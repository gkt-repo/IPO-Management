import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { PanService } from './pan.service';
import { PrismaService } from '../prisma/prisma.service';
import { EncryptionService } from '../common/encryption.service';

describe('PanService', () => {
  let service: PanService;
  let mockPrisma: any;

  beforeEach(async () => {
    mockPrisma = {
      $queryRaw: jest.fn(),
      refreshJob: { updateMany: jest.fn() },
      savedPan: {
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        delete: jest.fn(),
      },
      allotmentCheck: {
        deleteMany: jest.fn(),
      },
      allotmentHistory: {
        deleteMany: jest.fn(),
      },
      $transaction: jest.fn((callback) => callback(mockPrisma)),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PanService,
        EncryptionService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<PanService>(PanService);
  });

  it('should throw BadRequestException if explicit consent is false', async () => {
    await expect(
      service.savePan('user-1', { pan: 'ABCDE1234F', consent: false }),
    ).rejects.toThrow(BadRequestException);
  });

  it('should throw ConflictException if PAN already exists and confirmReplace is not provided', async () => {
    mockPrisma.savedPan.findUnique.mockResolvedValue({
      id: 'pan-1',
      userId: 'user-1',
      panMasked: 'ABCDE****F',
    });

    await expect(
      service.savePan('user-1', { pan: 'XYZPA5678Q', consent: true, confirmReplace: false }),
    ).rejects.toThrow(ConflictException);
  });

  it('should replace PAN when confirmReplace is true', async () => {
    mockPrisma.savedPan.findUnique.mockResolvedValue({
      id: 'pan-1',
      userId: 'user-1',
      panMasked: 'ABCDE****F',
    });

    mockPrisma.savedPan.create.mockResolvedValue({
      id: 'pan-new',
      panMasked: 'XYZPA****Q',
      consentGiven: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const result = await service.savePan('user-1', {
      pan: 'XYZPA5678Q',
      consent: true,
      confirmReplace: true,
    });

    expect(result.message).toBe('PAN updated successfully');
    expect(result.pan.panMasked).toBe('XYZPA****Q');
    expect(result.pan.id).toBe('pan-new');
    expect(mockPrisma.savedPan.delete).toHaveBeenCalledWith({ where: { id: 'pan-1' } });
    expect(mockPrisma.savedPan.update).not.toHaveBeenCalled();
    expect(mockPrisma.refreshJob.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ status: 'FAILED' }),
    }));
  });

  it('should create new PAN record if user has none', async () => {
    mockPrisma.savedPan.findUnique.mockResolvedValue(null);
    mockPrisma.savedPan.create.mockResolvedValue({
      id: 'pan-new',
      panMasked: 'ABCDE****F',
      consentGiven: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const result = await service.savePan('user-1', { pan: 'ABCDE1234F', consent: true });
    expect(result.pan.panMasked).toBe('ABCDE****F');
    expect(mockPrisma.savedPan.create).toHaveBeenCalled();
  });

  it('should delete saved PAN and associated records', async () => {
    mockPrisma.savedPan.findUnique.mockResolvedValue({ id: 'pan-1' });
    mockPrisma.savedPan.delete.mockResolvedValue({ id: 'pan-1' });

    const result = await service.deleteSavedPan('user-1');
    expect(result.success).toBe(true);
    expect(mockPrisma.savedPan.delete).toHaveBeenCalledWith({ where: { id: 'pan-1' } });
  });

  it('should throw NotFoundException when deleting if no PAN exists', async () => {
    mockPrisma.savedPan.findUnique.mockResolvedValue(null);
    await expect(service.deleteSavedPan('user-1')).rejects.toThrow(NotFoundException);
  });
});
