import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EncryptionService } from '../common/encryption.service';
import { Prisma } from '@prisma/client';
import { lockUser } from '../common/user-lock';
import { SavePanDto } from './dto/save-pan.dto';

@Injectable()
export class PanService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly encryptionService: EncryptionService,
  ) {}

  /**
   * Save or replace the single PAN for the authenticated user.
   */
  async savePan(userId: string, dto: SavePanDto) {
    if (!dto.consent) {
      throw new BadRequestException(
        'Explicit consent is mandatory to store and process your PAN for IPO allotment verification.',
      );
    }

    const cleanPan = this.encryptionService.sanitizePan(dto.pan);
    const encryptedPan = this.encryptionService.encryptPan(cleanPan);
    const panMasked = this.encryptionService.maskPan(cleanPan);
    const panFingerprint = this.encryptionService.generateHmacFingerprint(cleanPan);

    return this.prisma.$transaction(async (tx) => {
      await lockUser(tx, userId);
      const existingPan = await tx.savedPan.findUnique({ where: { userId } });
      if (existingPan && !dto.confirmReplace) {
        throw new ConflictException({
          message: 'A PAN card is already linked to this account.',
          code: 'CONFIRM_REPLACE_REQUIRED',
          currentMaskedPan: existingPan.panMasked,
        });
      }
      if (existingPan) {
        await this.cancelRefreshes(tx, userId);
        // A new identity prevents in-flight results for the previous PAN from
        // attaching to its replacement. Foreign keys cascade old history.
        await tx.savedPan.delete({ where: { id: existingPan.id } });
      }
      const pan = await tx.savedPan.create({
        data: {
          userId, encryptedPan, panMasked, panFingerprint,
          consentGiven: true, consentTimestamp: new Date(),
        },
        select: {
          id: true, panMasked: true, consentGiven: true, consentTimestamp: true,
          createdAt: true, updatedAt: true,
        },
      });
      return { message: existingPan ? 'PAN updated successfully' : 'PAN saved securely', pan };
    });
  }

  private async cancelRefreshes(tx: Prisma.TransactionClient, userId: string) {
    await tx.refreshJob.updateMany({
      where: { userId, status: { in: ['QUEUED', 'IN_PROGRESS'] } },
      data: { status: 'FAILED', completedAt: new Date(), errorSummary: 'Saved PAN changed. Start a new refresh.' },
    });
  }

  /**
   * Retrieve masked PAN for authenticated user. Decrypted PAN is NEVER returned.
   */
  async getSavedPan(userId: string) {
    const saved = await this.prisma.savedPan.findUnique({
      where: { userId },
      select: {
        id: true,
        panMasked: true,
        consentGiven: true,
        consentTimestamp: true,
        createdAt: true,
        updatedAt: true,
        _count: {
          select: {
            checks: true,
          },
        },
      },
    });

    if (!saved) {
      return {
        hasPan: false,
        pan: null,
      };
    }

    return {
      hasPan: true,
      pan: saved,
    };
  }

  /**
   * Delete the saved PAN and its associated allotment records.
   */
  async deleteSavedPan(userId: string) {
    await this.prisma.$transaction(async (tx) => {
      await lockUser(tx, userId);
      const saved = await tx.savedPan.findUnique({ where: { userId } });
      if (!saved) throw new NotFoundException('No PAN card found on your account');
      await this.cancelRefreshes(tx, userId);
      await tx.savedPan.delete({ where: { id: saved.id } });
    });

    return {
      success: true,
      message: 'Saved PAN and associated allotment history have been deleted permanently',
    };
  }

  /**
   * Internal helper for background allotment checks only:
   * Retrieves decrypted PAN into ephemeral memory. Never exposed in API responses or logs.
   */
  async getDecryptedPanForInternalJob(userId: string, db: Prisma.TransactionClient = this.prisma): Promise<{ id: string; rawPan: string; maskedPan: string } | null> {
    const record = await db.savedPan.findUnique({
      where: { userId },
    });

    if (!record) return null;

    const rawPan = this.encryptionService.decryptPan(record.encryptedPan);
    return {
      id: record.id,
      rawPan,
      maskedPan: record.panMasked,
    };
  }
}
