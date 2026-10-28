import { IpoService } from './ipo.service';

describe('IPO listing filters and legacy data repair', () => {
  let prisma: any;
  let service: IpoService;
  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date('2026-10-28T08:00:00Z'));
    prisma = {
      savedPan: { findUnique: jest.fn().mockResolvedValue(null) },
      iPO: { findMany: jest.fn(), updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      allotmentCheck: { updateMany: jest.fn() },
    };
    service = new IpoService(prisma, { getOfficialRegistrarUrl: () => '' } as any, {} as any);
    const ipo = (id: string, open: string, close: string) => ({
      id, name: id, issueType: 'SME', openDate: new Date(open), closeDate: new Date(close),
      allotmentDate: new Date('2026-11-10'), listingDate: null, listingPrice: null,
    });
    prisma.iPO.findMany.mockResolvedValue([
      ipo('closed', '2026-10-20', '2026-10-23'),
      ipo('upcoming-later', '2026-11-05', '2026-11-08'),
      ipo('open', '2026-10-26', '2026-10-28'),
      ipo('upcoming-soon', '2026-11-01', '2026-11-04'),
    ]);
  });
  afterEach(() => jest.useRealTimers());

  it('filters lifecycle independently of board and preserves allotment status', async () => {
    const result = await service.listIpos('user', { issueType: 'SME', status: 'OPEN' });
    expect(prisma.iPO.findMany.mock.calls[0][0].where).toEqual({ isActive: true, issueType: 'SME' });
    expect(result.map((ipo) => ipo.id)).toEqual(['open']);
    expect(result[0]).toMatchObject({ lifecycleStatus: 'OPEN', status: 'NOT_APPLIED', isUpcoming: false });
  });
  it('legacy Upcoming excludes open and awaiting-allotment issues', async () => {
    const result = await service.listIpos('user', { issueType: 'UPCOMING' });
    expect(result.map((ipo) => ipo.id)).toEqual(['upcoming-soon', 'upcoming-later']);
  });
  it('corrects only exact known-bad seeds without recreating or overwriting the catalogue', async () => {
    await service.repairLegacySchedules();
    expect(prisma.iPO.updateMany).toHaveBeenCalledTimes(4);
    expect(prisma.iPO.updateMany).toHaveBeenCalledWith({
      where: { slug: 'ntpc-green-energy-limited', openDate: new Date('2026-11-04'), closeDate: new Date('2026-11-07') },
      data: { openDate: new Date('2024-11-19'), closeDate: new Date('2024-11-22'), allotmentDate: null, listingDate: null, listingPrice: null, currentPrice: null },
    });
  });
});
