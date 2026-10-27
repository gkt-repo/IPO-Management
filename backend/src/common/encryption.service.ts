import { Injectable, BadRequestException } from '@nestjs/common';
import * as crypto from 'crypto';

@Injectable()
export class EncryptionService {
  private readonly algorithm = 'aes-256-gcm';
  private readonly encryptionKey: Buffer;
  private readonly hmacKey: Buffer;

  constructor() {
    const rawKey = process.env.PAN_ENCRYPTION_KEY || 'default_secret_key_32_bytes_long_12345';
    // Ensure key is exactly 32 bytes for aes-256-gcm
    this.encryptionKey = crypto.createHash('sha256').update(rawKey).digest();

    const rawHmacKey = process.env.PAN_HMAC_KEY || 'default_hmac_secret_key_for_pan_indexing_32b';
    this.hmacKey = crypto.createHash('sha256').update(rawHmacKey).digest();
  }

  /**
   * Validate Indian Permanent Account Number (PAN) format.
   * Format: 5 uppercase letters, 4 digits, 1 uppercase letter (e.g. ABCDE1234F)
   */
  validatePanFormat(pan: string): boolean {
    if (!pan || typeof pan !== 'string') return false;
    const clean = pan.trim().toUpperCase();
    const panRegex = /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/;
    return panRegex.test(clean);
  }

  /**
   * Sanitize and format PAN to standard uppercase string.
   */
  sanitizePan(pan: string): string {
    const clean = (pan || '').trim().toUpperCase();
    if (!this.validatePanFormat(clean)) {
      throw new BadRequestException('Invalid PAN format. Expected format: ABCDE1234F');
    }
    return clean;
  }

  /**
   * Produce masked representation e.g. "ABCDE****F".
   */
  maskPan(pan: string): string {
    const clean = (pan || '').trim().toUpperCase();
    if (clean.length !== 10) {
      return '**********';
    }
    return `${clean.slice(0, 5)}****${clean.slice(9)}`;
  }

  /**
   * Generate a non-reversible keyed HMAC-SHA256 fingerprint for indexing/equality checks.
   */
  generateHmacFingerprint(pan: string): string {
    const clean = this.sanitizePan(pan);
    return crypto.createHmac('sha256', this.hmacKey).update(clean).digest('hex');
  }

  /**
   * Encrypt PAN using AES-256-GCM authenticated encryption.
   * Returns a compact string: iv:authTag:ciphertext (all in hex).
   */
  encryptPan(pan: string): string {
    const clean = this.sanitizePan(pan);
    const iv = crypto.randomBytes(12); // Standard 96-bit IV for AES-GCM
    const cipher = crypto.createCipheriv(this.algorithm, this.encryptionKey, iv);

    const encrypted = Buffer.concat([cipher.update(clean, 'utf8'), cipher.final()]);
    const authTag = cipher.getAuthTag();

    return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted.toString('hex')}`;
  }

  /**
   * Decrypt AES-256-GCM encrypted PAN payload.
   */
  decryptPan(encryptedPayload: string): string {
    if (!encryptedPayload || !encryptedPayload.includes(':')) {
      throw new Error('Invalid encrypted PAN payload structure');
    }

    const [ivHex, authTagHex, encryptedHex] = encryptedPayload.split(':');
    if (!ivHex || !authTagHex || !encryptedHex) {
      throw new Error('Malformed encrypted PAN payload');
    }

    const iv = Buffer.from(ivHex, 'hex');
    const authTag = Buffer.from(authTagHex, 'hex');
    const encrypted = Buffer.from(encryptedHex, 'hex');

    const decipher = crypto.createDecipheriv(this.algorithm, this.encryptionKey, iv);
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
    return decrypted.toString('utf8');
  }
}
