import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { RefreshService } from './refresh.service';
import { PrismaService } from '../prisma/prisma.service';
import { PanService } from '../pan/pan.service';
import { PeekService } from '../peek/peek.service';
import { AllotmentStatus, JobStatus } from '@prisma/client';

describe('RefreshService', () => {
  let service: RefreshService;
  let mockPrisma: any;
  let mockPanService: any;
  let mockPeekService: any;

  beforeEach(async () => {
    mockPrisma = {
      refreshJob: {
        findFirst: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
      iPO: {
        findMany: jest.fn(),
      },
      allotmentCheck: {
        findUnique: jest.fn(),
        findMany: jest.fn(),
        upsert: jest.fn(),
      },
      allotmentHistory: {
        create: jest.fn(),
      },
    };

    mockPanService = {
      getDecryptedPanForInternalJob: jest.fn(),
    };

    mockPeekService = {
      checkAllotment: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        RefreshService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: PanService, useValue: mockPanService },
        { provide: PeekService, useValue: mockPeekService },
      ],
    }).compile();

    service = module.get<RefreshService>(RefreshService);
  });

  it('should throw BadRequestException if user has no saved PAN', async () => {
    mockPanService.getDecryptedPanForInternalJob.mockResolvedValue(null);
    await expect(service.triggerRefresh('user-1')).rejects.toThrow(BadRequestException);
  });

  it('should deduplicate and return existing job if one is already in progress', async () => {
    mockPanService.getDecryptedPanForInternalJob.mockResolvedValue({
      id: 'pan-1',
      rawPan: 'ABCDE1234F',
      maskedPan: 'ABCDE****F',
    });

    mockPrisma.refreshJob.findFirst.mockResolvedValue({
      id: 'job-in-progress',
      status: JobStatus.IN_PROGRESS,
    });

    const result = await service.triggerRefresh('user-1');
    expect(result.jobId).toBe('job-in-progress');
    expect(result.isDuplicate).toBe(true);
    expect(mockPrisma.refreshJob.create).not.toHaveBeenCalled();
  });

  it('should respect cooldown when last job completed recently', async () => {
    mockPanService.getDecryptedPanForInternalJob.mockResolvedValue({
      id: 'pan-1',
      rawPan: 'ABCDE1234F',
      maskedPan: 'ABCDE****F',
    });

    // No active job
    mockPrisma.refreshJob.findFirst
      .mockResolvedValueOnce(null)
      // Recent completed job (1 minute ago)
      .mockResolvedValueOnce({
        id: 'job-completed-recent',
        status: JobStatus.COMPLETED,
        completedAt: new Date(Date.now() - 60 * 1000),
      });

    const result = await service.triggerRefresh('user-1', false);
    expect(result.jobId).toBe('job-completed-recent');
    expect(result.cooldownRemainingSeconds).toBeGreaterThan(0);
    expect(mockPrisma.refreshJob.create).not.toHaveBeenCalled();
  });

  it('should create and start a new job when eligible and not in cooldown', async () => {
    mockPanService.getDecryptedPanForInternalJob.mockResolvedValue({
      id: 'pan-1',
      rawPan: 'ABCDE1234F',
      maskedPan: 'ABCDE****F',
    });

    mockPrisma.refreshJob.findFirst.mockResolvedValue(null);
    mockPrisma.allotmentCheck.findMany.mockResolvedValue([
      { hasApplied: true, status: AllotmentStatus.PENDING, ipo: { id: 'ipo-1', name: 'Test IPO', registrar: 'KFINTECH', externalId: '123', isActive: true } },
    ]);
    mockPrisma.refreshJob.create.mockResolvedValue({
      id: 'job-new',
      status: JobStatus.QUEUED,
    });

    const result = await service.triggerRefresh('user-1', true);
    expect(result.jobId).toBe('job-new');
    expect(result.status).toBe(JobStatus.QUEUED);
    expect(mockPrisma.refreshJob.create).toHaveBeenCalled();
  });
});
