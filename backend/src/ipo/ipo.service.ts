import { Injectable, Logger, NotFoundException, BadRequestException, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { PeekService } from '../peek/peek.service';
import { MarketPriceService } from './market-price.service';
import { AllotmentStatus, IssueType } from '@prisma/client';
import { biddingTime, ipoLifecycle } from './ipo-lifecycle';
import { CatalogueService } from './catalogue.service';
import { companyKey } from './catalogue-parser';

@Injectable()
export class IpoService implements OnModuleInit {
  private readonly logger = new Logger(IpoService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly peekService: PeekService,
    private readonly marketPriceService: MarketPriceService,
    private readonly catalogueService: CatalogueService,
  ) {}

  async onModuleInit() {
    try {
      await this.repairLegacySchedules();
    } catch (err: any) {
      this.logger.warn(`Legacy schedule repair deferred: ${err.message}`);
    }

    // Start schedule refresh independently of registrar availability. Identity
    // discovery follows it to avoid duplicate records; then sync listed prices.
    this.catalogueService.start()
      .then(() => this.syncDynamicCatalogues())
      .then(() => this.marketPriceService.syncListingPrices())
      .catch((err) => this.logger.warn(`Initial catalogue sync: ${err.message}`));
  }

  getCatalogueStatus() { return this.catalogueService.getStatus(); }

  /** Repair only exact legacy seed schedules; never overwrite imported schedules. */
  async repairLegacySchedules() {
    // Sources and the date-only timestamp convention are documented in README.md.
    const corrections = [
      ['swiggy-limited', '2026-10-01', '2026-10-05', '2024-11-06', '2024-11-08'],
      ['ola-electric-mobility-limited', '2026-08-02', '2026-08-06', '2024-08-02', '2024-08-06'],
      ['tata-technologies-limited', '2026-05-10', '2026-05-14', '2023-11-22', '2023-11-24'],
      ['ntpc-green-energy-limited', '2026-11-04', '2026-11-07', '2024-11-19', '2024-11-22'],
    ];
    for (const [slug, oldOpen, oldClose, open, close] of corrections) {
      await this.prisma.iPO.updateMany({
        where: { slug, openDate: new Date(oldOpen), closeDate: new Date(oldClose) },
        data: {
          openDate: new Date(open), closeDate: new Date(close),
          // Old seeded milestones and quotes were not sourced from an exchange.
          allotmentDate: null, listingDate: null, listingPrice: null, currentPrice: null,
        },
      });
    }
    await this.prisma.allotmentCheck.updateMany({
      where: { status: AllotmentStatus.ALLOTTED },
      data: { hasApplied: true },
    });
  }

  private extractIssuePrice(priceBand?: string | null): number | null {
    if (!priceBand) return null;
    const matches = priceBand.replace(/,/g, '').match(/(\d+(?:\.\d+)?)/g);
    if (!matches || matches.length === 0) return null;
    const nums = matches.map(Number);
    return Math.max(...nums);
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
    const existing = await this.prisma.iPO.findMany();

    for (const item of allDiscovered) {
      const slug = item.name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');

      try {
        const match = existing.find((ipo) =>
          ipo.externalId === item.externalId || companyKey(ipo.name) === companyKey(item.name),
        );
        const identity = {
          externalId: item.externalId,
          registrar: item.registrar,
          officialVerificationUrl: item.officialVerificationUrl,
        };
        if (match) {
          await this.prisma.iPO.update({ where: { id: match.id }, data: identity });
        } else {
          const created = await this.prisma.iPO.create({ data: {
            ...identity, name: item.name, slug,
            issueType: item.issueType === 'SME' ? IssueType.SME : IssueType.MAINBOARD,
            isActive: true,
          } });
          existing.push(created);
        }
      } catch (err) {
        this.logger.warn(`Registrar identity sync failed for ${item.name}`);
      }
    }
  }

  /**
   * List recent IPOs with the authenticated user's current allotment status for each.
   */
  async listIpos(userId: string, filter?: { status?: string; issueType?: string; search?: string }) {
    void this.catalogueService.refreshIfDue();
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
                hasApplied: true,
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

    const now = new Date();
    // Keep the legacy query parameter working, but with strict upcoming semantics.
    const lifecycle = filter?.issueType === 'UPCOMING' ? 'UPCOMING' : filter?.status;
    const matching = ipos.filter((ipo) =>
      !['OPEN', 'CLOSED', 'UPCOMING'].includes(lifecycle ?? '') || ipoLifecycle(ipo, now) === lifecycle,
    );
    matching.sort((a, b) => {
      const date = (ipo: typeof a) => lifecycle === 'UPCOMING'
        ? biddingTime(ipo.openDate, 10)?.getTime()
        : biddingTime(ipo.closeDate, ipo.issueType === 'SME' ? 16 : 17)?.getTime()
          ?? ipo.listingDate?.getTime();
      const ascending = lifecycle === 'OPEN' || lifecycle === 'UPCOMING';
      const aTime = date(a) ?? (ascending ? Number.MAX_SAFE_INTEGER : 0);
      const bTime = date(b) ?? (ascending ? Number.MAX_SAFE_INTEGER : 0);
      return (ascending ? aTime - bTime : bTime - aTime) || a.name.localeCompare(b.name);
    });

    return matching.map((ipo) => {
      const check = ipo.checks?.[0];
      const isAllotted = check?.status === AllotmentStatus.ALLOTTED;
      const hasApplied = isAllotted || (check?.hasApplied ?? false);
      const lifecycleStatus = ipoLifecycle(ipo, now);

      return {
        id: ipo.id,
        externalId: ipo.externalId,
        name: ipo.name,
        slug: ipo.slug,
        issueType: ipo.issueType,
        isUpcoming: lifecycleStatus === 'UPCOMING',
        lifecycleStatus,
        biddingOpensAt: biddingTime(ipo.openDate, 10),
        biddingClosesAt: biddingTime(ipo.closeDate, ipo.issueType === 'SME' ? 16 : 17),
        openDate: ipo.openDate,
        closeDate: ipo.closeDate,
        priceBand: ipo.priceBand,
        issuePrice: ipo.issuePrice ?? this.extractIssuePrice(ipo.priceBand),
        listingPrice: ipo.listingPrice ?? null,
        currentPrice: ipo.currentPrice ?? null,
        symbol: ipo.symbol ?? null,
        lotSize: ipo.lotSize,
        allotmentDate: ipo.allotmentDate,
        listingDate: ipo.listingDate,
        registrar: ipo.registrar,
        officialVerificationUrl: ipo.officialVerificationUrl || this.peekService.getOfficialRegistrarUrl(ipo.registrar),
        hasApplied,
        status: isAllotted
          ? AllotmentStatus.ALLOTTED
          : hasApplied
            ? (check?.status || AllotmentStatus.PENDING)
            : 'NOT_APPLIED',
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

    const isAllotted = currentCheck?.status === AllotmentStatus.ALLOTTED;
    const hasApplied = isAllotted || (currentCheck?.hasApplied ?? false);

    return {
      ipo: {
        ...ipo,
        lifecycleStatus: ipoLifecycle(ipo),
        biddingOpensAt: biddingTime(ipo.openDate, 10),
        biddingClosesAt: biddingTime(ipo.closeDate, ipo.issueType === 'SME' ? 16 : 17),
        issuePrice: ipo.issuePrice ?? this.extractIssuePrice(ipo.priceBand),
        listingPrice: ipo.listingPrice ?? null,
        currentPrice: ipo.currentPrice ?? null,
        symbol: ipo.symbol ?? null,
        officialVerificationUrl: ipo.officialVerificationUrl || this.peekService.getOfficialRegistrarUrl(ipo.registrar),
      },
      userPan: savedPan ? { id: savedPan.id, masked: savedPan.panMasked } : null,
      currentCheck: currentCheck
        ? {
            ...currentCheck,
            hasApplied,
            status: isAllotted
              ? AllotmentStatus.ALLOTTED
              : hasApplied
                ? currentCheck.status
                : 'NOT_APPLIED',
          }
        : null,
      hasApplied,
      history,
    };
  }

  /**
   * Toggles whether the user has marked "I have applied" for an IPO.
   * If already ALLOTTED, it cannot be un-applied.
   */
  async toggleApplied(ipoId: string, userId: string) {
    const ipo = await this.prisma.iPO.findUnique({
      where: { id: ipoId },
    });
    if (!ipo) {
      throw new NotFoundException('IPO not found');
    }

    const savedPan = await this.prisma.savedPan.findUnique({
      where: { userId },
    });
    if (!savedPan) {
      throw new BadRequestException('Please link your PAN before marking applied IPOs');
    }

    const existingCheck = await this.prisma.allotmentCheck.findUnique({
      where: {
        savedPanId_ipoId: {
          savedPanId: savedPan.id,
          ipoId: ipo.id,
        },
      },
    });

    if (existingCheck && existingCheck.status === AllotmentStatus.ALLOTTED) {
      return {
        success: true,
        hasApplied: true,
        status: AllotmentStatus.ALLOTTED,
        message: 'This IPO is confirmed ALLOTTED and will always remain applied.',
      };
    }

    const nextApplied = existingCheck ? !existingCheck.hasApplied : true;

    const check = await this.prisma.allotmentCheck.upsert({
      where: {
        savedPanId_ipoId: {
          savedPanId: savedPan.id,
          ipoId: ipo.id,
        },
      },
      update: {
        hasApplied: nextApplied,
        status: nextApplied
          ? (existingCheck?.status === AllotmentStatus.NOT_ALLOTTED ? AllotmentStatus.PENDING : (existingCheck?.status || AllotmentStatus.PENDING))
          : AllotmentStatus.PENDING,
      },
      create: {
        savedPanId: savedPan.id,
        ipoId: ipo.id,
        hasApplied: true,
        status: AllotmentStatus.PENDING,
        source: 'MANUAL_APPLIED',
      },
    });

    return {
      success: true,
      hasApplied: check.hasApplied,
      status: check.hasApplied ? check.status : 'NOT_APPLIED',
    };
  }

  /**
   * Triggers background sync of stock exchange listing prices for all active IPOs.
   */
  async syncListingPrices() {
    return this.marketPriceService.syncListingPrices();
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

    const [allottedCount, pendingCount, activeJob, latestCheck] = await Promise.all([
      this.prisma.allotmentCheck.count({
        where: { savedPanId: savedPan.id, status: AllotmentStatus.ALLOTTED },
      }),
      this.prisma.allotmentCheck.count({
        where: {
          savedPanId: savedPan.id,
          hasApplied: true,
          status: { not: AllotmentStatus.ALLOTTED },
        },
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
      allotted: allottedCount,
      notAllotted: 0,
      pending: pendingCount,
      lookupFailed: 0,
      notSupported: 0,
      total: allottedCount + pendingCount,
    };

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
