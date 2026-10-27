import {
  Injectable,
  Logger,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { PanService } from '../pan/pan.service';
import { PeekService } from '../peek/peek.service';
import { AllotmentStatus, JobStatus } from '@prisma/client';

@Injectable()
export class RefreshService {
  private readonly logger = new Logger(RefreshService.name);
  private readonly COOLDOWN_MS = 5 * 60 * 1000; // 5 minutes cooldown

  constructor(
    private readonly prisma: PrismaService,
    private readonly panService: PanService,
    private readonly peekService: PeekService,
  ) {}

  /**
   * Trigger an allotment refresh job for the authenticated user.
   */
  async triggerRefresh(userId: string, force = false) {
    // 1. Verify user has a saved PAN
    const savedPan = await this.panService.getDecryptedPanForInternalJob(userId);
    if (!savedPan) {
      throw new BadRequestException('Please save your PAN card before running an allotment refresh');
    }

    // 2. Check for deduplication: any running or queued job for this user?
    const existingJob = await this.prisma.refreshJob.findFirst({
      where: {
        userId,
        status: { in: [JobStatus.QUEUED, JobStatus.IN_PROGRESS] },
      },
      orderBy: { startedAt: 'desc' },
    });

    if (existingJob) {
      return {
        jobId: existingJob.id,
        status: existingJob.status,
        message: 'A refresh job is already in progress.',
        isDuplicate: true,
      };
    }

    // 3. Check cooldown unless force is true
    if (!force) {
      const lastCompletedJob = await this.prisma.refreshJob.findFirst({
        where: {
          userId,
          status: JobStatus.COMPLETED,
        },
        orderBy: { completedAt: 'desc' },
      });

      if (lastCompletedJob && lastCompletedJob.completedAt) {
        const timeSince = Date.now() - new Date(lastCompletedJob.completedAt).getTime();
        if (timeSince < this.COOLDOWN_MS) {
          const remainingSec = Math.ceil((this.COOLDOWN_MS - timeSince) / 1000);
          return {
            jobId: lastCompletedJob.id,
            status: JobStatus.COMPLETED,
            message: `Recent refresh completed. Next automatic refresh available in ${remainingSec} seconds.`,
            cooldownRemainingSeconds: remainingSec,
          };
        }
      }
    }

    // 4. Fetch eligible IPOs
    const eligibleIpos = await this.prisma.iPO.findMany({
      where: { isActive: true },
      orderBy: { allotmentDate: 'desc' },
    });

    if (eligibleIpos.length === 0) {
      return {
        jobId: null,
        status: JobStatus.COMPLETED,
        message: 'No active IPOs to check at this time.',
      };
    }

    // 5. Create RefreshJob record
    const job = await this.prisma.refreshJob.create({
      data: {
        userId,
        status: JobStatus.QUEUED,
        totalIpos: eligibleIpos.length,
        processedIpos: 0,
        startedAt: new Date(),
      },
    });

    // 6. Launch background execution asynchronously (never block HTTP response)
    setImmediate(() => {
      this.executeRefreshJob(job.id, userId, savedPan.id, savedPan.rawPan, eligibleIpos)
        .catch((err) => {
          this.logger.error(`Error in refresh job ${job.id}: ${err.message}`, err.stack);
        });
    });

    return {
      jobId: job.id,
      status: JobStatus.QUEUED,
      totalIpos: eligibleIpos.length,
      message: 'Allotment refresh started in background.',
    };
  }

  /**
   * Retrieve progress and stats of a given refresh job.
   */
  async getJobProgress(jobId: string, userId: string) {
    const job = await this.prisma.refreshJob.findFirst({
      where: { id: jobId, userId },
    });

    if (!job) {
      throw new NotFoundException('Refresh job not found');
    }

    return {
      id: job.id,
      status: job.status,
      totalIpos: job.totalIpos,
      processedIpos: job.processedIpos,
      allottedCount: job.allottedCount,
      notAllottedCount: job.notAllottedCount,
      pendingCount: job.pendingCount,
      failedCount: job.failedCount,
      startedAt: job.startedAt,
      completedAt: job.completedAt,
      errorSummary: job.errorSummary,
    };
  }

  /**
   * Internal asynchronous worker for executing allotment checks across eligible IPOs.
   * Uses bounded concurrency (3 concurrent requests) to respect registrar limits.
   */
  private async executeRefreshJob(
    jobId: string,
    userId: string,
    savedPanId: string,
    rawPan: string,
    ipos: any[],
  ) {
    await this.prisma.refreshJob.update({
      where: { id: jobId },
      data: { status: JobStatus.IN_PROGRESS },
    });

    let processed = 0;
    let allottedCount = 0;
    let notAllottedCount = 0;
    let pendingCount = 0;
    let failedCount = 0;

    // Bounded concurrency batching: max 3 at a time
    const BATCH_SIZE = 3;
    for (let i = 0; i < ipos.length; i += BATCH_SIZE) {
      const batch = ipos.slice(i, i + BATCH_SIZE);

      await Promise.all(
        batch.map(async (ipo) => {
          try {
            // Check existing check record to avoid overwriting confirmed ALLOTTED
            const existingCheck = await this.prisma.allotmentCheck.findUnique({
              where: {
                savedPanId_ipoId: {
                  savedPanId,
                  ipoId: ipo.id,
                },
              },
            });

            // Perform check via PeekService
            const result = await this.peekService.checkAllotment(
              rawPan,
              ipo.name,
              ipo.registrar,
              ipo.externalId,
            );

            // Determine confirmed status:
            // CRITICAL RULE: If previous status was ALLOTTED, never degrade to LOOKUP_FAILED on network glitch!
            let newConfirmedStatus = result.status;
            let newAllottedQuantity = result.sharesAllotted;

            if (existingCheck && existingCheck.status === AllotmentStatus.ALLOTTED) {
              if (result.status === AllotmentStatus.LOOKUP_FAILED || result.status === AllotmentStatus.PENDING) {
                newConfirmedStatus = AllotmentStatus.ALLOTTED;
                newAllottedQuantity = existingCheck.allottedQuantity;
              }
            }

            // Upsert AllotmentCheck
            await this.prisma.allotmentCheck.upsert({
              where: {
                savedPanId_ipoId: {
                  savedPanId,
                  ipoId: ipo.id,
                },
              },
              update: {
                status: newConfirmedStatus,
                allottedQuantity: newAllottedQuantity,
                latestAttemptStatus: result.status,
                source: result.source,
                checkedAt: new Date(),
                errorCode: result.errorCode || null,
                diagnosticMessage: result.message,
              },
              create: {
                savedPanId,
                ipoId: ipo.id,
                status: newConfirmedStatus,
                allottedQuantity: newAllottedQuantity,
                latestAttemptStatus: result.status,
                source: result.source,
                checkedAt: new Date(),
                errorCode: result.errorCode || null,
                diagnosticMessage: result.message,
              },
            });

            // Record history item
            await this.prisma.allotmentHistory.create({
              data: {
                savedPanId,
                ipoId: ipo.id,
                status: result.status,
                allottedQuantity: result.sharesAllotted,
                source: result.source,
                errorCode: result.errorCode || null,
                diagnosticMessage: result.message,
                timestamp: new Date(),
              },
            });

            // Update local counters
            if (newConfirmedStatus === AllotmentStatus.ALLOTTED) allottedCount++;
            else if (newConfirmedStatus === AllotmentStatus.NOT_ALLOTTED) notAllottedCount++;
            else if (newConfirmedStatus === AllotmentStatus.PENDING) pendingCount++;
            else if (newConfirmedStatus === AllotmentStatus.LOOKUP_FAILED) failedCount++;
          } catch (err: any) {
            this.logger.warn(`Failed checking IPO ${ipo.name}: ${err.message}`);
            failedCount++;
          } finally {
            processed++;
          }
        }),
      );

      // Update progress in DB after each batch
      await this.prisma.refreshJob.update({
        where: { id: jobId },
        data: {
          processedIpos: processed,
          allottedCount,
          notAllottedCount,
          pendingCount,
          failedCount,
        },
      });
    }

    // Mark job as completed
    await this.prisma.refreshJob.update({
      where: { id: jobId },
      data: {
        status: JobStatus.COMPLETED,
        completedAt: new Date(),
        processedIpos: processed,
      },
    });

    this.logger.log(`Refresh job ${jobId} finished: ${processed}/${ipos.length} IPOs checked.`);
  }
}
