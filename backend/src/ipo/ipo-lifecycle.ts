export type IpoLifecycle = 'OPEN' | 'CLOSED' | 'UPCOMING' | 'UNKNOWN';

interface Schedule {
  openDate?: Date | null;
  closeDate?: Date | null;
  listingDate?: Date | null;
  listingPrice?: number | null;
  issueType?: string;
}

// Legacy date-only values are stored at UTC midnight. Interpret those as
// Indian calendar dates; preserve an explicitly supplied intraday timestamp.
export function biddingTime(date: Date | null | undefined, hour: number): Date | null {
  if (!date || !Number.isFinite(date.getTime())) return null;
  if (date.getUTCHours() || date.getUTCMinutes() || date.getUTCSeconds() || date.getUTCMilliseconds()) {
    return date;
  }
  return new Date(date.getTime() + (hour * 60 - 330) * 60_000);
}

export function ipoLifecycle(ipo: Schedule, now = new Date()): IpoLifecycle {
  const opens = biddingTime(ipo.openDate, 10);
  const closes = biddingTime(ipo.closeDate, ipo.issueType === 'SME' ? 16 : 17);
  if (opens && closes && closes <= opens) return 'UNKNOWN';
  // Closing takes precedence over a later allotment or listing date.
  if (closes && now >= closes) return 'CLOSED';
  if (ipo.listingPrice != null || (ipo.listingDate && ipo.listingDate <= now)) return 'CLOSED';
  if (opens && now < opens) return 'UPCOMING';
  if (opens && closes && now >= opens && now < closes) return 'OPEN';
  return 'UNKNOWN';
}
