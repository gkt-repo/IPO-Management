import { Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { PeekService } from '../peek/peek.service';
import { AllotmentStatus, IssueType } from '@prisma/client';

@Injectable()
export class IpoService implements OnModuleInit {
  private readonly logger = new Logger(IpoService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly peekService: PeekService,
  ) {}

  async onModuleInit() {
    // Seed initial representative IPOs if table is empty, and sync dynamic catalogues
    await this.ensureSeedIpos();
    // Non-blocking dynamic discovery
    this.syncDynamicCatalogues().catch((err) => {
      this.logger.warn(`Initial catalogue discovery sync: ${err.message}`);
    });
  }

  /**
   * Ensure standard recent Mainboard and SME Indian IPOs exist in DB.
   */
  async ensureSeedIpos() {
    const count = await this.prisma.iPO.count();
    if (count > 0) return;

    this.logger.log('Seeding initial recent Indian IPOs...');
    const seedData = [
      {
        externalId: '11968',
        name: 'Paras Healthcare Limited',
        slug: 'paras-healthcare-limited',
        issueType: IssueType.MAINBOARD,
        priceBand: '₹650 - ₹693',
        lotSize: 21,
        openDate: new Date('2026-09-10'),
        closeDate: new Date('2026-09-12'),
        allotmentDate: new Date('2026-09-15'),
        listingDate: new Date('2026-09-18'),
        registrar: 'MUFG_INTIME',
        officialVerificationUrl: 'https://in.mpms.mufg.com/Initial_Offer/IPO.aspx',
      },
      {
        externalId: '78061126051',
        name: 'Jio Platforms Limited',
        slug: 'jio-platforms-limited',
        issueType: IssueType.MAINBOARD,
        priceBand: '₹450 - ₹475',
        lotSize: 30,
        openDate: new Date('2026-09-20'),
        closeDate: new Date('2026-09-24'),
        allotmentDate: new Date('2026-09-26'),
        listingDate: new Date('2026-09-30'),
        registrar: 'KFINTECH',
        officialVerificationUrl: 'https://ipostatus.kfintech.com/',
      },
      {
        externalId: '32261845640',
        name: 'Fusion CX Limited',
        slug: 'fusion-cx-limited',
        issueType: IssueType.MAINBOARD,
        priceBand: '₹280 - ₹295',
        lotSize: 50,
        openDate: new Date('2026-09-25'),
        closeDate: new Date('2026-09-27'),
        allotmentDate: new Date('2026-09-30'),
        listingDate: new Date('2026-10-04'),
        registrar: 'KFINTECH',
        officialVerificationUrl: 'https://ipostatus.kfintech.com/',
      },
      {
        externalId: 'BIG_SWIGGY_2026',
        name: 'Swiggy Limited',
        slug: 'swiggy-limited',
        issueType: IssueType.MAINBOARD,
        priceBand: '₹371 - ₹390',
        lotSize: 38,
        openDate: new Date('2026-10-01'),
        closeDate: new Date('2026-10-05'),
        allotmentDate: new Date('2026-10-07'),
        listingDate: new Date('2026-10-10'),
        registrar: 'BIGSHARE',
        officialVerificationUrl: 'https://ipo.bigshareonline.com/IPO_Status.html',
      },
      {
        externalId: '11966',
        name: 'TechNova Solutions (SME)',
        slug: 'technova-solutions-sme',
        issueType: IssueType.SME,
        priceBand: '₹115 - ₹122',
        lotSize: 1000,
        openDate: new Date('2026-10-10'),
        closeDate: new Date('2026-10-14'),
        allotmentDate: new Date('2026-10-16'),
        listingDate: new Date('2026-10-20'),
        registrar: 'MUFG_INTIME',
        officialVerificationUrl: 'https://in.mpms.mufg.com/Initial_Offer/IPO.aspx',
      },
      {
        externalId: '47651989560',
        name: 'Sollfege Smart Electronics',
        slug: 'sollfege-smart-electronics',
        issueType: IssueType.SME,
        priceBand: '₹84 - ₹90',
        lotSize: 1200,
        openDate: new Date('2026-10-15'),
        closeDate: new Date('2026-10-18'),
        allotmentDate: new Date('2026-10-21'),
        listingDate: new Date('2026-10-25'),
        registrar: 'KFINTECH',
        officialVerificationUrl: 'https://ipostatus.kfintech.com/',
      },
    ];

    for (const item of seedData) {
      await this.prisma.iPO.upsert({
        where: { slug: item.slug },
        update: {},
        create: item,
      });
    }
  }

  /**
   * Dynamically fetch live IPO catalogues from KFintech and MUFG Intime portals.
   */
  async syncDynamicCatalogues() {
    const [mufgIpos, kfinIpos] = await Promise.all([
      this.peekService.discoverMufgIpos(),
      this.peekService.discoverKFintechIpos(),
    ]);

    const allDiscovered = [...mufgIpos, ...kfinIpos];

    for (const item of allDiscovered) {
      const slug = item.name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');

      try {
        await this.prisma.iPO.upsert({
          where: { slug },
          update: {
            externalId: item.externalId,
            registrar: item.registrar,
            officialVerificationUrl: item.officialVerificationUrl,
            isActive: true,
          },
          create: {
            externalId: item.externalId,
            name: item.name,
            slug,
            issueType: item.issueType === 'SME' ? IssueType.SME : IssueType.MAINBOARD,
            registrar: item.registrar,
            officialVerificationUrl: item.officialVerificationUrl,
            isActive: true,
          },
        });
      } catch (err) {
        // Continue silently if single item conflicts
      }
    }
  }

  /**
   * List recent IPOs with the authenticated user's current allotment status for each.
   */
  async listIpos(userId: string, filter?: { status?: string; issueType?: string; search?: string }) {
    const savedPan = await this.prisma.savedPan.findUnique({
      where: { userId },
      select: { id: true },
    });

    const whereClause: any = { isActive: true };

    if (filter?.issueType && (filter.issueType === 'MAINBOARD' || filter.issueType === 'SME')) {
      whereClause.issueType = filter.issueType as IssueType;
    }

    if (filter?.search) {
      whereClause.name = { contains: filter.search.trim(), mode: 'insensitive' };
    }

    const ipos = await this.prisma.iPO.findMany({
      where: whereClause,
      orderBy: [
        { allotmentDate: 'desc' },
        { createdAt: 'desc' },
      ],
      include: savedPan
        ? {
            checks: {
              where: { savedPanId: savedPan.id },
              select: {
                id: true,
                status: true,
                allottedQuantity: true,
                latestAttemptStatus: true,
                source: true,
                checkedAt: true,
                errorCode: true,
                diagnosticMessage: true,
              },
            },
          }
        : undefined,
    });

    return ipos.map((ipo) => {
      const check = ipo.checks?.[0];
      return {
        id: ipo.id,
        externalId: ipo.externalId,
        name: ipo.name,
        slug: ipo.slug,
        issueType: ipo.issueType,
        openDate: ipo.openDate,
        closeDate: ipo.closeDate,
        priceBand: ipo.priceBand,
        lotSize: ipo.lotSize,
        allotmentDate: ipo.allotmentDate,
        listingDate: ipo.listingDate,
        registrar: ipo.registrar,
        officialVerificationUrl: ipo.officialVerificationUrl || this.peekService.getOfficialRegistrarUrl(ipo.registrar),
        status: check?.status || AllotmentStatus.PENDING,
        allottedQuantity: check?.allottedQuantity ?? null,
        latestAttemptStatus: check?.latestAttemptStatus || null,
        lastCheckedAt: check?.checkedAt || null,
        diagnosticMessage: check?.diagnosticMessage || null,
      };
    });
  }

  /**
   * Get single IPO details along with full allotment history for the authenticated user.
   */
  async getIpoDetails(id: string, userId: string) {
    const ipo = await this.prisma.iPO.findUnique({
      where: { id },
    });

    if (!ipo) {
      throw new NotFoundException('IPO not found');
    }

    const savedPan = await this.prisma.savedPan.findUnique({
      where: { userId },
      select: { id: true, panMasked: true },
    });

    let currentCheck = null;
    let history: any[] = [];

    if (savedPan) {
      currentCheck = await this.prisma.allotmentCheck.findUnique({
        where: {
          savedPanId_ipoId: {
            savedPanId: savedPan.id,
            ipoId: ipo.id,
          },
        },
      });

      history = await this.prisma.allotmentHistory.findMany({
        where: {
          savedPanId: savedPan.id,
          ipoId: ipo.id,
        },
        orderBy: { timestamp: 'desc' },
        take: 20,
      });
    }

    return {
      ipo: {
        ...ipo,
        officialVerificationUrl: ipo.officialVerificationUrl || this.peekService.getOfficialRegistrarUrl(ipo.registrar),
      },
      userPan: savedPan ? { id: savedPan.id, masked: savedPan.panMasked } : null,
      currentCheck,
      history,
    };
  }

  /**
   * Dashboard summary counts: ALLOTTED, NOT_ALLOTTED, PENDING, LOOKUP_FAILED, NOT_SUPPORTED,
   * last scan timestamp, active job metadata.
   */
  async getDashboardSummary(userId: string) {
    const savedPan = await this.prisma.savedPan.findUnique({
      where: { userId },
      select: { id: true, panMasked: true, updatedAt: true },
    });

    if (!savedPan) {
      return {
        hasPan: false,
        maskedPan: null,
        counts: {
          allotted: 0,
          notAllotted: 0,
          pending: 0,
          lookupFailed: 0,
          notSupported: 0,
          total: 0,
        },
        lastScanAt: null,
        activeJob: null,
      };
    }

    const [checks, activeJob, latestCheck] = await Promise.all([
      this.prisma.allotmentCheck.groupBy({
        by: ['status'],
        where: { savedPanId: savedPan.id },
        _count: { status: true },
      }),
      this.prisma.refreshJob.findFirst({
        where: {
          userId,
          status: { in: ['QUEUED', 'IN_PROGRESS'] },
        },
        orderBy: { startedAt: 'desc' },
      }),
      this.prisma.allotmentCheck.findFirst({
        where: { savedPanId: savedPan.id },
        orderBy: { checkedAt: 'desc' },
        select: { checkedAt: true },
      }),
    ]);

    const counts = {
      allotted: 0,
      notAllotted: 0,
      pending: 0,
      lookupFailed: 0,
      notSupported: 0,
      total: 0,
    };

    for (const group of checks) {
      const count = group._count.status;
      counts.total += count;
      switch (group.status) {
        case AllotmentStatus.ALLOTTED:
          counts.allotted += count;
          break;
        case AllotmentStatus.NOT_ALLOTTED:
          counts.notAllotted += count;
          break;
        case AllotmentStatus.PENDING:
          counts.pending += count;
          break;
        case AllotmentStatus.LOOKUP_FAILED:
          counts.lookupFailed += count;
          break;
        case AllotmentStatus.NOT_SUPPORTED:
          counts.notSupported += count;
          break;
      }
    }

    // Also account for unapplied/pending IPOs in catalogue
    const totalIpos = await this.prisma.iPO.count({ where: { isActive: true } });
    if (totalIpos > counts.total) {
      counts.pending += (totalIpos - counts.total);
      counts.total = totalIpos;
    }

    return {
      hasPan: true,
      maskedPan: savedPan.panMasked,
      counts,
      lastScanAt: latestCheck?.checkedAt || null,
      activeJob: activeJob
        ? {
            id: activeJob.id,
            status: activeJob.status,
            totalIpos: activeJob.totalIpos,
            processedIpos: activeJob.processedIpos,
            startedAt: activeJob.startedAt,
          }
        : null,
    };
  }
}
