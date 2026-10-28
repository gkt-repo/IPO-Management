import { biddingTime, ipoLifecycle } from './ipo-lifecycle';

const schedule = {
  openDate: new Date('2026-10-26'),
  closeDate: new Date('2026-10-28'),
  issueType: 'MAINBOARD',
};

describe('IPO bidding lifecycle in IST', () => {
  it.each([
    ['2026-10-26T04:29:59.999Z', 'UPCOMING'],
    ['2026-10-26T04:30:00.000Z', 'OPEN'],
    ['2026-10-27T20:00:00.000Z', 'OPEN'],
    ['2026-10-28T11:29:59.999Z', 'OPEN'],
    ['2026-10-28T11:30:00.000Z', 'CLOSED'],
    ['2026-10-29T00:00:00.000Z', 'CLOSED'],
  ])('classifies %s as %s', (now, expected) => {
    expect(ipoLifecycle(schedule, new Date(now))).toBe(expected);
  });

  it('closes SME bidding at 4 PM IST', () => {
    const sme = { ...schedule, issueType: 'SME' };
    expect(ipoLifecycle(sme, new Date('2026-10-28T10:29:59Z'))).toBe('OPEN');
    expect(ipoLifecycle(sme, new Date('2026-10-28T10:30:00Z'))).toBe('CLOSED');
  });

  it('honors explicit issue timestamps, including extended bidding', () => {
    const extended = { ...schedule, closeDate: new Date('2026-10-28T19:00:00+05:30') };
    expect(ipoLifecycle(extended, new Date('2026-10-28T12:30:00Z'))).toBe('OPEN');
    expect(ipoLifecycle(extended, new Date('2026-10-28T13:30:00Z'))).toBe('CLOSED');
  });

  it('never infers open or upcoming from absent or invalid dates', () => {
    const now = new Date('2026-10-28T08:00:00Z');
    expect(ipoLifecycle({}, now)).toBe('UNKNOWN');
    expect(ipoLifecycle({ closeDate: schedule.closeDate }, now)).toBe('UNKNOWN');
    expect(ipoLifecycle({ openDate: schedule.openDate }, now)).toBe('UNKNOWN');
    expect(ipoLifecycle({ ...schedule, closeDate: new Date('2026-10-25') }, now)).toBe('UNKNOWN');
    expect(biddingTime(new Date('invalid'), 10)).toBeNull();
  });

  it('keeps listed issues and closed issues out of Upcoming', () => {
    const now = new Date('2026-10-29T08:00:00Z');
    expect(ipoLifecycle(schedule, now)).toBe('CLOSED');
    expect(ipoLifecycle({ listingDate: new Date('2024-11-27') }, now)).toBe('CLOSED');
    expect(ipoLifecycle({ listingPrice: 100, openDate: new Date('2026-11-05') }, now)).toBe('CLOSED');
  });
});
