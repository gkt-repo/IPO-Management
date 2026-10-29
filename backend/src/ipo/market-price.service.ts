import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface MarketPriceResult {
  symbol: string;
  listingPrice: number;
  currentPrice?: number;
  firstTradeDate?: Date;
}

@Injectable()
export class MarketPriceService {
  private readonly logger = new Logger(MarketPriceService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Clean company name to optimize search hit rate on stock exchanges (NSE / BSE).
   */
  cleanCompanyName(name: string): string {
    return name
      .replace(/\s*-\s*IPO$/i, '')
      .replace(/\s*\(SME\)/i, '')
      .replace(/\s+(Limited|Ltd\.?)/gi, '')
      .replace(/\s+(Private|Pvt\.?)/gi, '')
      .replace(/\s+India\b/gi, '')
      .replace(/[.\s]+$/, '')
      .trim();
  }

  /**
   * Resolves the stock exchange ticker symbol on NSE (.NS) or BSE (.BO).
   */
  async resolveSymbol(companyName: string): Promise<string | null> {
    const clean = this.cleanCompanyName(companyName);
    const searchUrl = `https://query1.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(clean)}&quotesCount=5&newsCount=0`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);

    try {
      const res = await fetch(searchUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
        signal: controller.signal,
      });

      if (!res.ok) {
        this.logger.debug(`Yahoo Finance symbol search failed with HTTP ${res.status} for ${companyName}`);
        return null;
      }

      const data = await res.json();
      const quotes = data?.quotes || [];

      // Prioritize NSE (.NS), then BSE (.BO)
      const nseQuote = quotes.find(
        (q: any) => q.symbol && (q.symbol.endsWith('.NS') || q.exchange === 'NSI'),
      );
      if (nseQuote?.symbol) return nseQuote.symbol;

      const bseQuote = quotes.find(
        (q: any) => q.symbol && (q.symbol.endsWith('.BO') || q.exchange === 'BSE'),
      );
      if (bseQuote?.symbol) return bseQuote.symbol;

      return null;
    } catch (err: any) {
      this.logger.debug(`Error resolving symbol for ${companyName}: ${err.message}`);
      return null;
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * Fetch listing day open price and current market price from exchange history.
   */
  async fetchMarketData(symbol: string): Promise<MarketPriceResult | null> {
    const chartUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=max&interval=1d`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);

    try {
      const res = await fetch(chartUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
        signal: controller.signal,
      });

      if (!res.ok) {
        this.logger.debug(`Yahoo chart query returned HTTP ${res.status} for ${symbol}`);
        return null;
      }

      const data = await res.json();
      const result = data?.chart?.result?.[0];
      if (!result) return null;

      const meta = result.meta || {};
      const quotes = result.indicators?.quote?.[0];
      const opens: (number | null)[] = quotes?.open || [];
      const volumes: (number | null)[] = quotes?.volume || [];

      // Find first trade candle with executed trade volume (> 0).
      // Indian exchanges put the base/issue price at the 9:15-9:20 pre-open reference with volume 0,
      // while the actual discovered listing price trades at the 9:45-10:00 opening auction with real volume.
      let firstOpen: number | null = null;
      for (let i = 0; i < opens.length; i++) {
        const o = opens[i];
        const v = volumes[i];
        if (o != null && o > 0 && v != null && v > 0) {
          firstOpen = o;
          break;
        }
      }

      // Fallback: check meta.chartPreviousClose or first non-null open
      if (!firstOpen) {
        if (meta.chartPreviousClose && meta.chartPreviousClose > 0) {
          firstOpen = meta.chartPreviousClose;
        } else {
          firstOpen = opens.find((o) => o != null && o > 0) || null;
        }
      }

      if (!firstOpen) {
        this.logger.debug(`No valid opening price candles found for ${symbol}`);
        return null;
      }

      const regularMarketPrice = meta.regularMarketPrice ?? undefined;
      const firstTradeDate = meta.firstTradeDate ? new Date(meta.firstTradeDate * 1000) : undefined;

      return {
        symbol,
        listingPrice: Math.round(firstOpen * 100) / 100,
        currentPrice: regularMarketPrice ? Math.round(regularMarketPrice * 100) / 100 : undefined,
        firstTradeDate,
      };
    } catch (err: any) {
      this.logger.debug(`Error fetching market data for ${symbol}: ${err.message}`);
      return null;
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * Scrapes / fetches live listing price from stock exchange for a specific IPO.
   */
  async fetchListingPriceForIpo(name: string, symbolHint?: string): Promise<MarketPriceResult | null> {
    const symbol = symbolHint || (await this.resolveSymbol(name));
    if (!symbol) return null;

    return this.fetchMarketData(symbol);
  }

  /**
   * Scans eligible IPOs (past listing date or missing listing price) and updates their
   * actual exchange listing prices from NSE/BSE into the database.
   */
  async syncListingPrices(): Promise<{ updated: number; failed: number }> {
    this.logger.log('Starting automated exchange listing price sync...');
    const now = new Date();

    const eligibleIpos = await this.prisma.iPO.findMany({
      where: {
        isActive: true,
        listingDate: { lte: now },
        closeDate: { lt: now },
      },
    });

    let updated = 0;
    let failed = 0;

    for (const ipo of eligibleIpos) {
      try {
        const data = await this.fetchListingPriceForIpo(ipo.name, ipo.symbol || undefined);
        if (data && data.listingPrice > 0) {
          await this.prisma.iPO.update({
            where: { id: ipo.id },
            data: {
              symbol: data.symbol,
              listingPrice: data.listingPrice,
              currentPrice: data.currentPrice ?? undefined,
            },
          });
          this.logger.log(`Updated IPO "${ipo.name}" with Exchange Listing Price: ₹${data.listingPrice} (${data.symbol})`);
          updated++;
        } else {
          failed++;
        }
      } catch (err: any) {
        this.logger.warn(`Could not sync listing price for "${ipo.name}": ${err.message}`);
        failed++;
      }
    }

    this.logger.log(`Listing price sync completed. Updated: ${updated}, Unresolved: ${failed}`);
    return { updated, failed };
  }
}
