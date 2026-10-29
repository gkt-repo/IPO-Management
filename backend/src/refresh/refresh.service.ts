import { Injectable, Logger, BadRequestException, NotFoundException, OnModuleInit } from '@nestjs/common';
import { AllotmentStatus, JobStatus, IPO } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PanService } from '../pan/pan.service';
import { PeekService, RegistrarCheckResult } from '../peek/peek.service';
import { lockUser } from '../common/user-lock';

const ACTIVE = [JobStatus.QUEUED, JobStatus.IN_PROGRESS];
const LEASE_MS = 2 * 60_000;

@Injectable()
export class RefreshService implements OnModuleInit {
  private readonly logger = new Logger(RefreshService.name);
  private readonly COOLDOWN_MS = 5 * 60_000;

  constructor(
    private readonly prisma: PrismaService,
    private readonly panService: PanService,
    private readonly peekService: PeekService,
  ) {}

  async onModuleInit() {
    // Only expire abandoned leases, so another backend's active work survives.
    try { await this.expireJobs(); }
    catch { this.logger.warn('Refresh recovery deferred until the database is available'); }
  }

  private expireJobs(userId?: string) {
    return this.prisma.refreshJob.updateMany({
      where: { userId, status: { in: ACTIVE }, heartbeatAt: { lt: new Date(Date.now() - LEASE_MS) } },
      data: { status: JobStatus.FAILED, completedAt: new Date(), errorSummary: 'Refresh interrupted or timed out. Please retry.' },
    });
  }

  async triggerRefresh(userId: string, force = false) {
    await this.expireJobs(userId);
    let work: { jobId: string; panId: string; rawPan: string; ipos: IPO[] } | undefined;
    const response = await this.prisma.$transaction(async (tx) => {
      await lockUser(tx, userId);
      const pan = await this.panService.getDecryptedPanForInternalJob(userId, tx);
      if (!pan) throw new BadRequestException('Please save your PAN card before running an allotment refresh');
      const existing = await tx.refreshJob.findFirst({
        where: { userId, status: { in: ACTIVE } }, orderBy: { startedAt: 'desc' },
      });
      if (existing) return {
        jobId: existing.id, status: existing.status, totalIpos: existing.totalIpos,
        message: 'A refresh job is already in progress.', isDuplicate: true,
      };
      const checks = await tx.allotmentCheck.findMany({
        where: { savedPanId: pan.id, hasApplied: true, status: { not: AllotmentStatus.ALLOTTED } },
        include: { ipo: true },
      });
      const ipos = checks.filter(c => c.ipo.isActive).map(c => c.ipo);
      const unresolved = checks.some(c => c.status === 'PENDING' || c.status === 'LOOKUP_FAILED');
      if (!force && !unresolved) {
        const last = await tx.refreshJob.findFirst({
          where: { userId, status: JobStatus.COMPLETED }, orderBy: { completedAt: 'desc' },
        });
        const remaining = last?.completedAt ? this.COOLDOWN_MS - (Date.now() - last.completedAt.getTime()) : 0;
        if (remaining > 0) return {
          jobId: last!.id, status: JobStatus.COMPLETED,
          message: 'Recent refresh completed.', cooldownRemainingSeconds: Math.ceil(remaining / 1000),
        };
      }
      const job = await tx.refreshJob.create({ data: {
        userId, status: ipos.length ? JobStatus.QUEUED : JobStatus.COMPLETED,
        totalIpos: ipos.length, heartbeatAt: new Date(),
        completedAt: ipos.length ? null : new Date(),
      } });
      if (ipos.length) work = { jobId: job.id, panId: pan.id, rawPan: pan.rawPan, ipos };
      return {
        jobId: job.id, status: job.status, totalIpos: ipos.length,
        message: ipos.length ? 'Allotment refresh started in background.' : 'All applied IPOs are up to date. No pending scans needed.',
      };
    });
    // Never dispatch work until the admission transaction has committed.
    if (work) {
      const { jobId, panId, rawPan, ipos } = work;
      setImmediate(() => { void this.executeRefreshJob(jobId, userId, panId, rawPan, ipos); });
    }
    return response;
  }

  async getJobProgress(jobId: string, userId: string) {
    await this.expireJobs(userId);
    const job = await this.prisma.refreshJob.findFirst({ where: { id: jobId, userId } });
    if (!job) throw new NotFoundException('Refresh job not found');
    return job;
  }

  private async persistResult(jobId: string, userId: string, savedPanId: string, ipoId: string, result: RegistrarCheckResult) {
    return this.prisma.$transaction(async (tx) => {
      await lockUser(tx, userId);
      // Fence expired/cancelled workers before they can write any results.
      const active = await tx.refreshJob.updateMany({
        where: { id: jobId, status: JobStatus.IN_PROGRESS, heartbeatAt: { gte: new Date(Date.now() - LEASE_MS) } },
        data: { heartbeatAt: new Date() },
      });
      if (!active.count) return false;
      const pan = await tx.savedPan.findUnique({ where: { userId }, select: { id: true } });
      if (pan?.id !== savedPanId) return false;
      const changed = await tx.allotmentCheck.updateMany({
        where: { savedPanId, ipoId, hasApplied: true, status: { not: AllotmentStatus.ALLOTTED } },
        data: {
          status: result.status, allottedQuantity: result.sharesAllotted,
          latestAttemptStatus: result.status, source: result.source, checkedAt: new Date(),
          errorCode: result.errorCode ?? null, diagnosticMessage: result.message,
        },
      });
      if (!changed.count) return false;
      await tx.allotmentHistory.create({ data: {
        savedPanId, ipoId, status: result.status, allottedQuantity: result.sharesAllotted,
        source: result.source, errorCode: result.errorCode ?? null, diagnosticMessage: result.message,
      } });
      return true;
    });
  }

  private async executeRefreshJob(jobId: string, userId: string, savedPanId: string, rawPan: string, ipos: IPO[]) {
    try {
      const claimed = await this.prisma.refreshJob.updateMany({
        where: { id: jobId, status: JobStatus.QUEUED, heartbeatAt: { gte: new Date(Date.now() - LEASE_MS) } },
        data: { status: JobStatus.IN_PROGRESS, heartbeatAt: new Date() },
      });
      if (!claimed.count) return;
      let processedIpos = 0, allottedCount = 0, notAllottedCount = 0, pendingCount = 0, failedCount = 0;
      for (let i = 0; i < ipos.length; i += 3) {
        await Promise.all(ipos.slice(i, i + 3).map(async ipo => {
          try {
            const check = await this.prisma.allotmentCheck.findUnique({
              where: { savedPanId_ipoId: { savedPanId, ipoId: ipo.id } },
            });
            if (!check?.hasApplied) return;
            if (check.status === AllotmentStatus.ALLOTTED) { allottedCount++; return; }
            const result = await this.peekService.checkAllotment(rawPan, ipo.name, ipo.registrar, ipo.externalId ?? undefined);
            if (!await this.persistResult(jobId, userId, savedPanId, ipo.id, result)) return;
            if (result.status === AllotmentStatus.ALLOTTED) allottedCount++;
            else if (result.status === AllotmentStatus.NOT_ALLOTTED) notAllottedCount++;
            else if (result.status === AllotmentStatus.PENDING) pendingCount++;
            else failedCount++;
          } catch {
            failedCount++;
          } finally { processedIpos++; }
        }));
        const progress = await this.prisma.refreshJob.updateMany({
          where: { id: jobId, status: JobStatus.IN_PROGRESS, heartbeatAt: { gte: new Date(Date.now() - LEASE_MS) } },
          data: { processedIpos, allottedCount, notAllottedCount, pendingCount, failedCount, heartbeatAt: new Date() },
        });
        if (!progress.count) return;
      }
      await this.prisma.refreshJob.updateMany({
        where: { id: jobId, status: JobStatus.IN_PROGRESS },
        data: { status: JobStatus.COMPLETED, completedAt: new Date() },
      });
    } catch {
      try {
        await this.prisma.refreshJob.updateMany({
          where: { id: jobId, status: { in: ACTIVE } },
          data: { status: JobStatus.FAILED, completedAt: new Date(), errorSummary: 'Refresh interrupted. Please retry.' },
        });
      } catch {
        // If the database is down, lease expiry makes the next request recoverable.
        this.logger.warn(`Refresh job ${jobId} will be recovered when its lease expires`);
      }
    }
  }
}
