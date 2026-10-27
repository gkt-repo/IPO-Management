import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EncryptionService } from '../common/encryption.service';
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

    const existingPan = await this.prisma.savedPan.findUnique({
      where: { userId },
    });

    if (existingPan) {
      if (!dto.confirmReplace) {
        throw new ConflictException({
          message: 'A PAN card is already linked to this account.',
          code: 'CONFIRM_REPLACE_REQUIRED',
          currentMaskedPan: existingPan.panMasked,
        });
      }

      // User confirmed replacing their PAN:
      // Update the existing record and wipe previous checks/history that belonged to the prior PAN
      return this.prisma.$transaction(async (tx) => {
        // Cascade delete old checks
        await tx.allotmentCheck.deleteMany({
          where: { savedPanId: existingPan.id },
        });
        await tx.allotmentHistory.deleteMany({
          where: { savedPanId: existingPan.id },
        });

        const updated = await tx.savedPan.update({
          where: { id: existingPan.id },
          data: {
            encryptedPan,
            panMasked,
            panFingerprint,
            consentGiven: true,
            consentTimestamp: new Date(),
          },
          select: {
            id: true,
            panMasked: true,
            consentGiven: true,
            consentTimestamp: true,
            createdAt: true,
            updatedAt: true,
          },
        });

        return {
          message: 'PAN updated successfully',
          pan: updated,
        };
      });
    }

    // Create new single PAN record
    const created = await this.prisma.savedPan.create({
      data: {
        userId,
        encryptedPan,
        panMasked,
        panFingerprint,
        consentGiven: true,
        consentTimestamp: new Date(),
      },
      select: {
        id: true,
        panMasked: true,
        consentGiven: true,
        consentTimestamp: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    return {
      message: 'PAN saved securely',
      pan: created,
    };
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
    const saved = await this.prisma.savedPan.findUnique({
      where: { userId },
    });

    if (!saved) {
      throw new NotFoundException('No PAN card found on your account');
    }

    await this.prisma.savedPan.delete({
      where: { id: saved.id },
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
  async getDecryptedPanForInternalJob(userId: string): Promise<{ id: string; rawPan: string; maskedPan: string } | null> {
    const record = await this.prisma.savedPan.findUnique({
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
