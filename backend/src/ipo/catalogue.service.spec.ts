import { CatalogueService } from './catalogue.service';
import { ipoLifecycle } from './ipo-lifecycle';
const nse = [
  { company: 'Zetwerk Manufacturing Businesses Limited', symbol: 'ZETWERK', securityType: 'EQ', ipoStartDate: '15-OCT-2026', ipoEndDate: '19-OCT-2026', listingDate: '23-OCT-2026', issuePrice: '151' },
  { companyName: 'BLS Polymers Limited', symbol: 'BLSPOLY', series: 'EQ', issueStartDate: '27-Oct-2026', issueEndDate: '29-Oct-2026', issuePrice: 'Rs.142 to Rs.150' },
];
const html = `<script id="__NEXT_DATA__">${JSON.stringify({ props: { pageProps: {
  closedDataList: [{ companyName: 'Zetwerk', symbol: 'ZETWERK', isSme: false, openingDate: '2026-10-15', closingDate: '2026-10-19', allotmentDate: '2026-10-21', rtaLink: 'https://ipostatus.kfintech.com/' }],
  openDataList: [{ companyName: 'Carver Roboweld', symbol: 'CARVER', isSme: true, bidStartTimestamp: Date.parse('2026-10-28T04:30:00Z'), bidEndTimestamp: Date.parse('2026-10-30T11:30:00Z') }],
} } })}</script>`;

describe('Catalogue synchronization', () => {
  let service: CatalogueService, prisma: any, records: any[];
  const originalFetch = global.fetch;
  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date('2026-10-28T14:00:00Z'));
    records = [{ id: 'existing-zetwerk', name: nse[0].company, slug: 'zetwerk-manufacturing-businesses-limited', externalId: 'registrar-id', registrar: 'KFINTECH', openDate: new Date('2026-11-10'), closeDate: new Date('2026-11-14'), lotSize: 44, metadata: { keep: 'existing metadata' } }];
    prisma = { iPO: {
      findMany: jest.fn(async () => [...records]),
      update: jest.fn(async ({ where, data }) => { const old = records.find((r) => r.id === where.id); Object.assign(old, Object.fromEntries(Object.entries(data).filter(([, v]) => v !== undefined))); return old; }),
      create: jest.fn(async ({ data }) => { const created = { id: `new-${records.length}`, ...data }; records.push(created); return created; }),
      updateMany: jest.fn(),
    } };
    service = new CatalogueService(prisma);
    global.fetch = jest.fn(async (url: string) => ({ ok: true, text: async () => url.includes('groww') ? html : JSON.stringify(nse) })) as any;
  });
  afterEach(() => { service.onModuleDestroy(); global.fetch = originalFetch; jest.useRealTimers(); });
  it('repairs original rows preserving identity and discovers open issues idempotently', async () => {
    await service.refreshIfDue();
    const original = records.find((r) => r.id === 'existing-zetwerk');
    expect(original.externalId).toBe('registrar-id');
    expect(original.metadata.keep).toBe('existing metadata');
    expect(original.allotmentDate.toISOString()).toBe('2026-10-21T00:00:00.000Z');
    expect(ipoLifecycle(original)).toBe('CLOSED');
    expect(records.filter((r) => r.name.includes('Zetwerk'))).toHaveLength(1);
    expect(records.filter((r) => ipoLifecycle(r) === 'OPEN').map((r) => r.name).sort()).toEqual(['BLS Polymers Limited', 'Carver Roboweld']);
    expect(service.getStatus().updated).toBe(3);
    await service.refreshIfDue(true);
    expect(prisma.iPO.create).toHaveBeenCalledTimes(2);
  });
  it('retains data if all feeds fail and reports the failure', async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error('offline'));
    await service.refreshIfDue();
    expect(prisma.iPO.update).not.toHaveBeenCalled();
    expect(prisma.iPO.create).not.toHaveBeenCalled();
    expect(prisma.iPO.updateMany).not.toHaveBeenCalled();
    expect(service.getStatus().errors[0]).toContain('offline');
    expect(service.getStatus().lastSuccessAt).toBeNull();
  });
  it('uses available sources when another fails', async () => {
    global.fetch = jest.fn(async (url: string) => {
      if (url.includes('nseindia')) throw new Error('timeout');
      return { ok: true, text: async () => html };
    }) as any;
    await service.refreshIfDue();
    expect(service.getStatus().sources).toEqual(['https://groww.in/ipo']);
    expect(service.getStatus().errors).toHaveLength(3);
    expect(records.some((r) => r.name === 'Carver Roboweld')).toBe(true);
  });
  it('coalesces concurrent requests and respects refresh interval', async () => {
    await Promise.all([service.refreshIfDue(), service.refreshIfDue(), service.refreshIfDue()]);
    expect(global.fetch).toHaveBeenCalledTimes(4);
    await service.refreshIfDue();
    expect(global.fetch).toHaveBeenCalledTimes(4);
    jest.setSystemTime(new Date('2026-10-28T14:16:00Z'));
    await service.refreshIfDue();
    expect(global.fetch).toHaveBeenCalledTimes(8);
  });
});

describe('catalogue authority across refresh cycles', () => {
  const originalFetch = global.fetch;
  afterEach(() => { global.fetch = originalFetch; });
  it('keeps exchange dates, board and verification time during an exchange outage, then accepts a newer exchange schedule', async () => {
    const old: any = { id: 'issue', name: 'Example Limited', symbol: 'EXAMPLE.NS', issueType: 'MAINBOARD',
      openDate: new Date('2026-10-28'), closeDate: new Date('2026-10-30'), listingDate: new Date('2026-11-03'),
      metadata: { catalogue: { source: 'https://www.nseindia.com/api/ipo-current-issue', verifiedAt: '2026-10-28T00:00:00Z' } } };
    const prisma: any = { iPO: { findMany: async () => [old], updateMany: async () => ({}),
      update: async ({ data }) => Object.assign(old, Object.fromEntries(Object.entries(data).filter(([,v]) => v !== undefined))) } };
    const groww = `<script id="__NEXT_DATA__">${JSON.stringify({ props: { pageProps: { openDataList: [{
      companyName: 'Example', symbol: 'EXAMPLE', isSme: true, openingDate: '2026-11-01', closingDate: '2026-11-03',
    }] } } })}</script>`;
    let nseDown = true;
    global.fetch = jest.fn(async (url: string) => {
      if (url.includes('groww')) return { ok: true, text: async () => groww };
      if (nseDown) throw new Error('offline');
      return { ok: true, text: async () => JSON.stringify([{ companyName: 'Example Limited', symbol: 'EXAMPLE',
        series: 'EQ', issueStartDate: '28-Oct-2026', issueEndDate: '31-Oct-2026' }]) };
    }) as any;
    const service = new CatalogueService(prisma);
    await service.refreshIfDue(true);
    expect(old.issueType).toBe('MAINBOARD');
    expect(old.openDate.toISOString()).toBe('2026-10-28T00:00:00.000Z');
    expect(old.closeDate.toISOString()).toBe('2026-10-30T00:00:00.000Z');
    expect(old.metadata.catalogue.verifiedAt).toBe('2026-10-28T00:00:00Z');
    expect(old.metadata.catalogue.exchangeVerified).toBe(true);
    nseDown = false;
    await service.refreshIfDue(true);
    expect(old.closeDate.toISOString()).toBe('2026-10-31T00:00:00.000Z');
  });
});
