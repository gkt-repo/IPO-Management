import { calendarDate, companyKey, enrichGroww, mergeIssues, parseGroww, parseNse } from './catalogue-parser';
import { ipoLifecycle } from './ipo-lifecycle';
const page = (props: object) => `<script id="__NEXT_DATA__">${JSON.stringify({ props: { pageProps: props } })}</script>`;
const row = { company: 'Zetwerk Manufacturing Businesses Limited', symbol: 'ZETWERK', securityType: 'EQ', ipoStartDate: '15-OCT-2026', ipoEndDate: '19-OCT-2026', listingDate: '23-OCT-2026', issuePrice: '151', priceRange: 'Rs.143 to Rs.151' };

describe('Catalogue parsing', () => {
  it('reads exchange schedules and excludes debt and invalid dates', () => {
    const issues = parseNse([row, { ...row, securityType: 'DEBT' }, { ...row, ipoEndDate: '31-FEB-2026' }], 'nse');
    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({ issueType: 'MAINBOARD', priceBand: '₹143 - ₹151', issuePrice: 151 });
    expect(ipoLifecycle(issues[0], new Date('2026-10-28T14:00:00Z'))).toBe('CLOSED');
    expect(calendarDate('31-FEB-2026')).toBeUndefined();
    expect(calendarDate('2026-13-01')).toBeUndefined();
    expect(calendarDate('2026-10-21T00:00:00')?.toISOString()).toBe('2026-10-21T00:00:00.000Z');
  });
  it('classifies pre-apply by dates and imports SME without name guessing', () => {
    const issues = parseGroww(page({ openDataList: [
      { companyName: 'Bombay Coated', symbol: 'BCSSL', isSme: false, bidStartTimestamp: Date.parse('2026-10-29T04:30:00Z'), bidEndTimestamp: Date.parse('2026-11-02T11:30:00Z'), isPreApply: true },
      { companyName: 'Carver Roboweld', symbol: 'CARVER', isSme: true, bidStartTimestamp: Date.parse('2026-10-28T04:30:00Z'), bidEndTimestamp: Date.parse('2026-10-30T11:30:00Z'), categories: [{ category: 'IND', lotSize: 1600, minPrice: 76, maxPrice: 80 }] },
    ], upcomingDataList: [{ companyName: 'Undated', symbol: 'TEMP', isSme: false }] }), 'groww');
    expect(issues).toHaveLength(2);
    expect(ipoLifecycle(issues[0], new Date('2026-10-28T14:00:00Z'))).toBe('UPCOMING');
    expect(ipoLifecycle(issues[1], new Date('2026-10-28T14:00:00Z'))).toBe('OPEN');
    expect(issues[1]).toMatchObject({ issueType: 'SME', lotSize: 1600 });
  });
  it('prefers exchange dates and retains supplemental details when matching symbols', () => {
    const exchange = parseNse([row], 'nse')[0];
    const broker = { ...exchange, name: 'Zetwerk', openDate: new Date('2026-11-10'), lotSize: 99, exchangeVerified: false, searchId: 'zetwerk-ipo', source: 'groww' };
    const [merged] = mergeIssues([broker, exchange]);
    expect(merged.openDate.toISOString()).toBe('2026-10-15T00:00:00.000Z');
    expect(merged.name).toBe(row.company);
    expect(merged.lotSize).toBe(99);
    expect(merged.searchId).toBe('zetwerk-ipo');
    expect(companyKey('Ravita Engineering Services Limited - SME IPO')).toBe(companyKey('Ravita Engineering Services Ltd.'));
  });
  it('validates detail identity, response shape and registrar URLs', () => {
    const issue = parseNse([row], 'nse')[0];
    expect(() => enrichGroww(issue, page({ ipoData: { symbol: 'OTHER' } }))).toThrow('identity mismatch');
    const result = enrichGroww(issue, page({ ipoData: { symbol: 'ZETWERK', lotSize: 99, allotmentDate: '2026-10-21T00:00:00', rtaLink: 'https://untrusted.example/ipo' } }));
    expect(result.lotSize).toBe(99);
    expect(result.registrar).toBeUndefined();
    expect(result.allotmentDate?.toISOString()).toBe('2026-10-21T00:00:00.000Z');
    expect(() => parseGroww('<html>unavailable</html>', 'groww')).toThrow();
  });
});
