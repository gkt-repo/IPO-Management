import { PeekService } from './peek.service';
import { AllotmentStatus } from '@prisma/client';

describe('PeekService', () => {
  let service: PeekService;

  beforeEach(() => {
    service = new PeekService();
    // Reset global.fetch
    jest.restoreAllMocks();
    jest.spyOn(global, 'fetch').mockRejectedValue(new Error('offline'));
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

describe('registrar response validation', () => {
  const fetchOriginal = global.fetch;
  afterEach(() => { global.fetch = fetchOriginal; });
  it.each([
    { error: 'Temporarily unavailable' }, { data: null }, { data: [{}] },
    { data: [{ All_Shares: 'pending' }] }, { data: [{ All_Shares: '-1' }] },
    { data: [{ All_Shares: '12oops' }] }, { data: [{ All_Shares: null, App_Shares: '50' }] },
  ])('rejects incomplete KFintech results: %j', async payload => {
    global.fetch = jest.fn(async () => ({ ok: true, json: async () => payload })) as any;
    const result = await new PeekService().checkKFintechDirect('ABCDE1234F', '123');
    expect(result.status).toBe('LOOKUP_FAILED');
    expect(result.sharesAllotted).toBeNull();
  });
  it('does not treat an HTML 404 as a confirmed negative', async () => {
    global.fetch = jest.fn(async () => ({ ok: false, status: 404, json: async () => { throw new Error('HTML'); } })) as any;
    expect((await new PeekService().checkKFintechDirect('ABCDE1234F', '123')).status).toBe('LOOKUP_FAILED');
  });
  it.each([
    {}, { d: 'Maintenance' }, { d: '<NewDataSet><Table><NAME>Test</NAME></Table></NewDataSet>' },
    { d: '<NewDataSet><Table><ALLOT>pending</ALLOT></Table></NewDataSet>' },
    { d: '<NewDataSet><Table><ALLOT>0</ALLOT></NewDataSet>' },
  ])('rejects incomplete MUFG results: %j', async payload => {
    global.fetch = jest.fn(async () => ({ ok: true, json: async () => payload })) as any;
    expect((await new PeekService().checkMufgDirect('ABCDE1234F', '123')).status).toBe('LOOKUP_FAILED');
  });
  it.each([['0', 'NOT_ALLOTTED', 0], ['1,000', 'ALLOTTED', 1000]])('accepts explicit MUFG count %s', async (count, status, quantity) => {
    global.fetch = jest.fn(async () => ({ ok: true, json: async () => ({ d: `<NewDataSet><Table><ALLOT>${count}</ALLOT></Table></NewDataSet>` }) })) as any;
    const result = await new PeekService().checkMufgDirect('ABCDE1234F', '123');
    expect(result.status).toBe(status);
    expect(result.sharesAllotted).toBe(quantity);
  });
});
