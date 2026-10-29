import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogueIssue, companyKey, enrichGroww, mergeIssues, parseGroww, parseNse } from './catalogue-parser';

const INTERVAL_MS = 15 * 60_000;
const DAY_MS = 86_400_000;

@Injectable()
export class CatalogueService implements OnModuleDestroy {
  private readonly logger = new Logger(CatalogueService.name);
  private timer?: ReturnType<typeof setInterval>;
  private inFlight?: Promise<void>;
  private lastAttempt = 0;
  private status: { lastSuccessAt: string | null; sources: string[]; errors: string[]; updated: number } = {
    lastSuccessAt: null, sources: [], errors: [], updated: 0,
  };

  constructor(private readonly prisma: PrismaService) {}

  start() {
    this.timer ??= setInterval(() => { void this.refreshIfDue(); }, INTERVAL_MS);
    this.timer.unref();
    return this.refreshIfDue();
  }

  onModuleDestroy() { if (this.timer) clearInterval(this.timer); }
  getStatus() { return { ...this.status, isRefreshing: !!this.inFlight }; }

  refreshIfDue(force = false): Promise<void> {
    if (this.inFlight) return this.inFlight;
    if (!force && Date.now() - this.lastAttempt < INTERVAL_MS) return Promise.resolve();
    this.lastAttempt = Date.now();
    this.inFlight = this.sync().catch((error) => {
      this.status.errors = [`Catalogue refresh failed: ${error.message}`];
      this.logger.warn(this.status.errors[0]);
    }).finally(() => { this.inFlight = undefined; });
    return this.inFlight;
  }

  private async text(url: string): Promise<string> {
    const response = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0', Accept: 'application/json,text/html', Referer: 'https://www.nseindia.com/' },
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const body = await response.text();
    if (body.length > 5_000_000) throw new Error('Unexpectedly large catalogue response');
    return body;
  }

  async sync(): Promise<void> {
    const sources = [
      { url: 'https://groww.in/ipo', parse: parseGroww },
      { url: 'https://www.nseindia.com/api/public-past-issues', parse: (s: string, u: string) => parseNse(JSON.parse(s), u) },
      { url: 'https://www.nseindia.com/api/ipo-current-issue', parse: (s: string, u: string) => parseNse(JSON.parse(s), u) },
      { url: 'https://www.nseindia.com/api/all-upcoming-issues?category=ipo', parse: (s: string, u: string) => parseNse(JSON.parse(s), u) },
    ];
    const results = await Promise.allSettled(sources.map(async ({ url, parse }) => parse(await this.text(url), url)));
    const issues: CatalogueIssue[] = [];
    const succeeded: string[] = [], errors: string[] = [];
    results.forEach((result, index) => {
      if (result.status === 'fulfilled') { issues.push(...result.value); succeeded.push(sources[index].url); }
      else errors.push(`${sources[index].url}: ${result.reason.message}`);
    });
    if (!issues.length) throw new Error(errors.join('; ') || 'Sources returned no valid schedules');

    const existing = await this.prisma.iPO.findMany();
    const byName = new Map(existing.map((ipo) => [companyKey(ipo.name), ipo]));
    const bySymbol = new Map<string, typeof existing[number]>();
    for (const ipo of existing) {
      const meta = ipo.metadata as any;
      if (meta?.catalogue?.exchangeSymbol) bySymbol.set(meta.catalogue.exchangeSymbol, ipo);
      if (ipo.symbol) bySymbol.set(ipo.symbol.replace(/\.(NS|BO)$/, ''), ipo);
    }
    const candidates = mergeIssues(issues).filter((issue) =>
      issue.closeDate.getTime() >= Date.now() - 120 * DAY_MS || byName.has(companyKey(issue.name)) || bySymbol.has(issue.exchangeSymbol),
    );
    // Refresh a bounded number of detail pages. Existing wrong schedules and
    // current issues go first; successful details are reused for one day.
    candidates.sort((a, b) => Number(byName.has(companyKey(b.name))) - Number(byName.has(companyKey(a.name))) || b.closeDate.getTime() - a.closeDate.getTime());
    let detailRequests = 0, updated = 0;
    for (let issue of candidates) {
      let old = byName.get(companyKey(issue.name)) ?? bySymbol.get(issue.exchangeSymbol);
      const metadata = (old?.metadata && typeof old.metadata === 'object' && !Array.isArray(old.metadata) ? old.metadata : {}) as any;
      if (issue.searchId && /^[a-z0-9-]+$/.test(issue.searchId) && detailRequests < 24 &&
          (!metadata.catalogue?.detailsCheckedAt || Date.now() - Date.parse(metadata.catalogue.detailsCheckedAt) > DAY_MS)) {
        detailRequests++;
        try { issue = enrichGroww(issue, await this.text(`https://groww.in/ipo/${issue.searchId}`)); }
        catch (error) { errors.push(`Details ${issue.exchangeSymbol}: ${error.message}`); }
      }
      old ??= byName.get(companyKey(issue.name));
      const previousCatalogue = metadata.catalogue;
      const preserveExchangeSchedule = !issue.exchangeVerified && old?.openDate && old?.closeDate &&
        (previousCatalogue?.exchangeVerified === true ||
          /^https:\/\/www\.nseindia\.com\//.test(previousCatalogue?.source ?? ''));
      if (preserveExchangeSchedule) {
        issue = { ...issue, issueType: old.issueType, openDate: old.openDate!, closeDate: old.closeDate!,
          listingDate: old.listingDate ?? issue.listingDate,
          allotmentDate: old.allotmentDate ?? issue.allotmentDate };
      }
      const changedSchedule = old && (old.openDate?.getTime() !== issue.openDate.getTime() || old.closeDate?.getTime() !== issue.closeDate.getTime());
      const data = {
        issueType: issue.issueType, openDate: issue.openDate, closeDate: issue.closeDate,
        listingDate: issue.listingDate ?? (changedSchedule ? null : undefined),
        allotmentDate: issue.allotmentDate ?? (changedSchedule ? null : undefined),
        priceBand: issue.priceBand ?? (issue.issuePrice ? `₹${issue.issuePrice}` : undefined),
        issuePrice: issue.issuePrice, lotSize: issue.lotSize ?? (changedSchedule ? null : undefined),
        registrar: issue.registrar ?? old?.registrar ?? 'UNKNOWN',
        officialVerificationUrl: issue.officialVerificationUrl ?? old?.officialVerificationUrl ?? '',
        symbol: issue.exchangeVerified ? `${issue.exchangeSymbol}.NS` : undefined,
        // A confirmed future listing cannot have a traded listing price yet.
        ...(issue.listingDate && issue.listingDate > new Date() ? { listingPrice: null, currentPrice: null } : {}),
        metadata: {
          ...metadata,
          catalogue: {
            ...metadata.catalogue,
            source: preserveExchangeSchedule ? previousCatalogue.source : issue.source,
            exchangeVerified: !!(issue.exchangeVerified || preserveExchangeSchedule),
            supplementalSource: preserveExchangeSchedule ? issue.source : null,
            exchangeSymbol: issue.exchangeSymbol,
            verifiedAt: preserveExchangeSchedule ? previousCatalogue.verifiedAt ?? null : new Date().toISOString(),
            detailsCheckedAt: issue.detailsCheckedAt ?? metadata.catalogue?.detailsCheckedAt ?? null,
            searchId: issue.searchId ?? metadata.catalogue?.searchId ?? null,
          },
        },
      };
      try {
        if (old) {
          await this.prisma.iPO.update({ where: { id: old.id }, data });
        } else {
          const slug = issue.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
          const created = await this.prisma.iPO.create({ data: { ...data, name: issue.name, slug, isActive: true } });
          byName.set(companyKey(issue.name), created);
          bySymbol.set(issue.exchangeSymbol, created);
        }
        updated++;
      } catch (error) {
        errors.push(`Save ${issue.exchangeSymbol}: ${error.code ?? 'database error'}`);
      }
    }
    // This exact record was a fabricated seed with a fake registrar identifier.
    // Archive it, retaining all relationships and any existing user history.
    await this.prisma.iPO.updateMany({
      where: { slug: 'apex-cloud-automation-sme-limited', externalId: 'MUFG_APEXSME', openDate: new Date('2026-11-15'), closeDate: new Date('2026-11-18') },
      data: { isActive: false },
    });
    this.status = { lastSuccessAt: updated ? new Date().toISOString() : this.status.lastSuccessAt, sources: succeeded, errors, updated };
    this.logger.log(`Catalogue refreshed: ${updated} issues, ${succeeded.length} sources, ${errors.length} errors`);
    for (const error of errors) this.logger.warn(error);
  }
}
