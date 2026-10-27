import { PeekService } from './peek.service';
import { AllotmentStatus } from '@prisma/client';

describe('PeekService', () => {
  let service: PeekService;

  beforeEach(() => {
    service = new PeekService();
    // Reset global.fetch
    jest.restoreAllMocks();
  });

  it('should map official registrar URLs properly', () => {
    expect(service.getOfficialRegistrarUrl('KFINTECH')).toBe('https://ipostatus.kfintech.com/');
    expect(service.getOfficialRegistrarUrl('MUFG_INTIME')).toBe('https://in.mpms.mufg.com/Initial_Offer/IPO.aspx');
    expect(service.getOfficialRegistrarUrl('BIGSHARE')).toBe('https://ipo.bigshareonline.com/IPO_Status.html');
  });

  it('should return LOOKUP_FAILED with CAPTCHA explanation for Bigshare without guessing allotment', async () => {
    const result = await service.checkAllotment('ABCDE1234F', 'Example IPO', 'BIGSHARE');
    expect(result.status).toBe(AllotmentStatus.LOOKUP_FAILED);
    expect(result.errorCode).toBe('CAPTCHA_REQUIRED');
    expect(result.message).toContain('interactive CAPTCHA');
  });

  it('should return NOT_SUPPORTED for unrecognized registrars', async () => {
    const result = await service.checkAllotment('ABCDE1234F', 'Example IPO', 'UNKNOWN_REGISTRAR');
    expect(result.status).toBe(AllotmentStatus.NOT_SUPPORTED);
    expect(result.errorCode).toBe('NOT_SUPPORTED');
  });

  it('should parse KFintech allotted response accurately', async () => {
    jest.spyOn(global, 'fetch').mockImplementationOnce(async () => {
      return {
        ok: true,
        json: async () => ({
          data: [
            {
              All_Shares: '50',
              App_Shares: '50',
            },
          ],
        }),
      } as any;
    });

    const result = await service.checkKFintechDirect('ABCDE1234F', '12345');
    expect(result.status).toBe(AllotmentStatus.ALLOTTED);
    expect(result.sharesAllotted).toBe(50);
  });

  it('should parse KFintech non-allotted response accurately', async () => {
    jest.spyOn(global, 'fetch').mockImplementationOnce(async () => {
      return {
        ok: true,
        json: async () => ({
          data: [
            {
              All_Shares: '0',
              App_Shares: '50',
            },
          ],
        }),
      } as any;
    });

    const result = await service.checkKFintechDirect('ABCDE1234F', '12345');
    expect(result.status).toBe(AllotmentStatus.NOT_ALLOTTED);
    expect(result.sharesAllotted).toBe(0);
  });

  it('should handle KFintech server error without reporting false non-allotment', async () => {
    jest.spyOn(global, 'fetch').mockImplementationOnce(async () => {
      return {
        ok: false,
        status: 502,
      } as any;
    });

    const result = await service.checkKFintechDirect('ABCDE1234F', '12345');
    expect(result.status).toBe(AllotmentStatus.LOOKUP_FAILED);
    expect(result.status).not.toBe(AllotmentStatus.NOT_ALLOTTED);
  });
});
