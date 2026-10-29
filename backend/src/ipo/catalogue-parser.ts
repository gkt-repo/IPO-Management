import { IssueType } from '@prisma/client';

export interface CatalogueIssue {
  name: string;
  exchangeSymbol: string;
  issueType: IssueType;
  openDate: Date;
  closeDate: Date;
  listingDate?: Date;
  allotmentDate?: Date;
  priceBand?: string;
  issuePrice?: number;
  lotSize?: number;
  registrar?: string;
  officialVerificationUrl?: string;
  searchId?: string;
  source: string;
  exchangeVerified?: boolean;
  detailsCheckedAt?: string;
}

export function companyKey(name: string): string {
  return name.toLowerCase().replace(/&/g, 'and')
    .replace(/\b(limited|ltd|private|pvt|sme|ipo)\b/g, '')
    .replace(/[^a-z0-9]/g, '');
}

export function calendarDate(value: unknown): Date | undefined {
  if (typeof value !== 'string') return undefined;
  const iso = /^(\d{4})-(\d{2})-(\d{2})(?:T00:00:00)?$/.exec(value.trim());
  const text = /^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/.exec(value.trim());
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  const year = iso ? +iso[1] : text ? +text[3] : 0;
  const month = iso ? +iso[2] - 1 : text ? months.indexOf(text[2].toUpperCase()) : -1;
  const day = iso ? +iso[3] : text ? +text[1] : 0;
  if (year < 2000 || month < 0 || month > 11 || day < 1) return undefined;
  const date = new Date(Date.UTC(year, month, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month && date.getUTCDate() === day ? date : undefined;
}

function timestampDate(value: unknown): Date | undefined {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 946684800000) return undefined;
  // Feed timestamps are instants. Store their India calendar day, then apply
  // the shared exchange bidding cutoff, not a broker-specific pre-apply state.
  return calendarDate(new Date(value + 330 * 60_000).toISOString().slice(0, 10));
}

function positive(value: unknown): number | undefined {
  const n = typeof value === 'number' ? value : typeof value === 'string' ? Number(value.trim()) : NaN;
  return Number.isFinite(n) && n > 0 ? n : undefined;
}

function priceBand(min: unknown, max: unknown): string | undefined {
  const low = positive(min), high = positive(max);
  return low && high && high >= low ? `₹${low} - ₹${high}` : undefined;
}

export function registrarFromUrl(value: unknown): { registrar?: string; officialVerificationUrl?: string } {
  if (typeof value !== 'string') return {};
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:') return {};
    const hosts: Record<string, string> = {
      'ipostatus.kfintech.com': 'KFINTECH', 'ris.kfintech.com': 'KFINTECH',
      'in.mpms.mufg.com': 'MUFG_INTIME', 'linkintime.co.in': 'MUFG_INTIME',
      'ipo.bigshareonline.com': 'BIGSHARE', 'www.bigshareonline.com': 'BIGSHARE',
      'maashitla.com': 'MAASHITLA', 'www.skylinerta.com': 'SKYLINE',
      'www.masserv.com': 'MAS_SERVICES', 'www.purvashare.com': 'PURVA',
      'www.integratedregistry.in': 'INTEGRATED', 'www.cameoindia.com': 'CAMEO',
    };
    const registrar = hosts[url.hostname];
    return registrar ? { registrar, officialVerificationUrl: value } : {};
  } catch { return {}; }
}

export function parseNse(payload: unknown, source: string): CatalogueIssue[] {
  if (!Array.isArray(payload)) throw new Error('NSE catalogue must be an array');
  return payload.flatMap((row) => {
    const board = String(row.series ?? row.securityType ?? '').toUpperCase();
    if (!['EQ', 'BE', 'SME', 'SM', 'ST'].includes(board)) return []; // Exclude debt, rights, REITs, etc.
    const name = row.companyName ?? row.company;
    const symbol = row.symbol;
    const openDate = calendarDate(row.issueStartDate ?? row.ipoStartDate);
    const closeDate = calendarDate(row.issueEndDate ?? row.ipoEndDate);
    if (typeof name !== 'string' || typeof symbol !== 'string' || !openDate || !closeDate || closeDate < openDate) return [];
    const band = row.priceRange ?? row.priceBand ?? row.issuePrice;
    return [{
      name: name.trim(), exchangeSymbol: symbol, issueType: ['SME', 'SM', 'ST'].includes(board) ? IssueType.SME : IssueType.MAINBOARD,
      openDate, closeDate, listingDate: calendarDate(row.listingDate),
      priceBand: typeof band === 'string' && /\d/.test(band) ? band.trim().replace(/Rs\.?\s*/g, '₹').replace(/\s+to\s+/gi, ' - ') : undefined,
      issuePrice: positive(row.issuePrice), lotSize: positive(row.lotSize), source, exchangeVerified: true,
    }];
  });
}

export function nextPageProps(html: string): any {
  const match = /<script\b(?=[^>]*\bid=["']__NEXT_DATA__["'])[^>]*>([\s\S]*?)<\/script>/i.exec(html);
  if (!match) throw new Error('Catalogue page is missing structured data');
  const props = JSON.parse(match[1])?.props?.pageProps;
  if (!props || typeof props !== 'object') throw new Error('Catalogue page props are invalid');
  return props;
}

export function parseGroww(html: string, source: string): CatalogueIssue[] {
  const props = nextPageProps(html);
  if (![props.openDataList, props.closedDataList, props.upcomingDataList].some(Array.isArray)) {
    throw new Error('Catalogue page has no IPO lists');
  }
  return [props.closedDataList, props.upcomingDataList, props.openDataList].flatMap((rows) =>
    (Array.isArray(rows) ? rows : []).flatMap((row) => {
      const openDate = calendarDate(row.openingDate) ?? timestampDate(row.bidStartTimestamp);
      const closeDate = calendarDate(row.closingDate) ?? timestampDate(row.bidEndTimestamp);
      if (typeof row.companyName !== 'string' || typeof row.symbol !== 'string' || typeof row.isSme !== 'boolean' || !openDate || !closeDate || closeDate < openDate) return [];
      const category = row.categories?.find((c) => c.category === 'IND') ?? row.categories?.[0];
      return [{
        name: row.companyName, exchangeSymbol: row.symbol, issueType: row.isSme ? IssueType.SME : IssueType.MAINBOARD,
        openDate, closeDate, listingDate: timestampDate(row.listingTimestamp), allotmentDate: calendarDate(row.allotmentDate),
        issuePrice: positive(row.issuePrice), priceBand: priceBand(category?.minPrice, category?.maxPrice),
        lotSize: positive(category?.lotSize), searchId: typeof row.searchId === 'string' ? row.searchId : undefined,
        ...registrarFromUrl(row.rtaLink), source,
      }];
    }),
  );
}

export function enrichGroww(issue: CatalogueIssue, html: string): CatalogueIssue {
  const data = nextPageProps(html).ipoData;
  if (!data || data.symbol !== issue.exchangeSymbol) throw new Error('IPO detail identity mismatch');
  // Schedule remains authoritative from the exchange when available.
  return {
    ...issue,
    name: !issue.exchangeVerified && typeof data.companyName === 'string' ? data.companyName : issue.name,
    lotSize: positive(data.lotSize) ?? issue.lotSize,
    priceBand: issue.priceBand ?? priceBand(data.minPrice, data.maxPrice),
    issuePrice: issue.issuePrice ?? positive(data.issuePrice),
    allotmentDate: calendarDate(data.allotmentDate) ?? issue.allotmentDate,
    listingDate: issue.listingDate ?? calendarDate(data.listingDate),
    ...registrarFromUrl(data.rtaLink),
    detailsCheckedAt: new Date().toISOString(),
  };
}

export function mergeIssues(issues: CatalogueIssue[]): CatalogueIssue[] {
  const merged = new Map<string, CatalogueIssue>();
  for (const issue of issues) {
    const old = merged.get(issue.exchangeSymbol);
    if (!old) { merged.set(issue.exchangeSymbol, issue); continue; }
    const preferred = issue.exchangeVerified ? issue : old;
    const other = issue.exchangeVerified ? old : issue;
    const defined = Object.fromEntries(Object.entries(preferred).filter(([, value]) => value !== undefined));
    merged.set(issue.exchangeSymbol, { ...other, ...defined } as CatalogueIssue);
  }
  return [...merged.values()];
}
