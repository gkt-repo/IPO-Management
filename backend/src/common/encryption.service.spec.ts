import { EncryptionService } from './encryption.service';
import { BadRequestException } from '@nestjs/common';

describe('EncryptionService', () => {
  let service: EncryptionService;

  beforeEach(() => {
    service = new EncryptionService();
  });

  it('should validate standard PAN formats correctly', () => {
    expect(service.validatePanFormat('ABCDE1234F')).toBe(true);
    expect(service.validatePanFormat('abcde1234f')).toBe(true);
    expect(service.validatePanFormat('ABCDE12345')).toBe(false);
    expect(service.validatePanFormat('ABCD12345F')).toBe(false);
    expect(service.validatePanFormat('12345ABCDE')).toBe(false);
    expect(service.validatePanFormat('')).toBe(false);
  });

  it('should mask PAN correctly showing only first 5 and last character', () => {
    expect(service.maskPan('ABCDE1234F')).toBe('ABCDE****F');
    expect(service.maskPan('BNZPS9999K')).toBe('BNZPS****K');
  });

  it('should generate consistent HMAC fingerprint without exposing raw PAN', () => {
    const fp1 = service.generateHmacFingerprint('ABCDE1234F');
    const fp2 = service.generateHmacFingerprint('abcde1234f');
    const fp3 = service.generateHmacFingerprint('XYZPA5678Q');

    expect(fp1).toEqual(fp2);
    expect(fp1).not.toEqual(fp3);
    expect(fp1).toHaveLength(64); // SHA-256 hex
  });

  it('should encrypt and decrypt PAN accurately using AES-256-GCM', () => {
    const pan = 'ABCDE1234F';
    const encrypted = service.encryptPan(pan);

    expect(encrypted).not.toContain(pan);
    expect(encrypted.split(':')).toHaveLength(3); // iv:authTag:ciphertext

    const decrypted = service.decryptPan(encrypted);
    expect(decrypted).toBe(pan);
  });

  it('should reject invalid PAN during sanitization', () => {
    expect(() => service.sanitizePan('INVALID_PAN')).toThrow(BadRequestException);
  });
});
