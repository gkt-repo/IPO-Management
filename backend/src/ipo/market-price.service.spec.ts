import { MarketPriceService } from './market-price.service';

describe('MarketPriceService', () => {
  let service: MarketPriceService;
  let mockPrisma: any;

  beforeEach(() => {
    mockPrisma = {
      iPO: {
        findMany: jest.fn(),
        update: jest.fn(),
      },
    };
    service = new MarketPriceService(mockPrisma);
  });

  describe('cleanCompanyName', () => {
    it('strips Limited, Ltd, (SME), and - IPO suffix cleanly', () => {
      expect(service.cleanCompanyName('Swiggy Limited')).toBe('Swiggy');
      expect(service.cleanCompanyName('Paras Healthcare Ltd.')).toBe('Paras Healthcare');
      expect(service.cleanCompanyName('TechNova Solutions (SME)')).toBe('TechNova Solutions');
      expect(service.cleanCompanyName('Ola Electric Mobility Limited - IPO')).toBe('Ola Electric Mobility');
      expect(service.cleanCompanyName('Tata Technologies Pvt. Ltd.')).toBe('Tata Technologies');
    });
  });

  describe('fetchMarketData', () => {
    it('handles network failure or missing data gracefully', async () => {
      const originalFetch = global.fetch;
      global.fetch = jest.fn().mockResolvedValue({
        ok: false,
        status: 404,
      }) as any;

      const result = await service.fetchMarketData('INVALID_TICKER.NS');
      expect(result).toBeNull();

      global.fetch = originalFetch;
    });

    it('extracts first trade opening price correctly from exchange chart', async () => {
      const originalFetch = global.fetch;
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          chart: {
            result: [
              {
                meta: {
                  regularMarketPrice: 456.0,
                  firstTradeDate: 1731469500,
                },
                indicators: {
                  quote: [
                    {
                      open: [null, 420.0, 425.0],
                    },
                  ],
                },
              },
            ],
          },
        }),
      }) as any;

      const result = await service.fetchMarketData('SWIGGY.NS');
      expect(result).not.toBeNull();
      expect(result?.listingPrice).toBe(420.0);
      expect(result?.currentPrice).toBe(456.0);
      expect(result?.symbol).toBe('SWIGGY.NS');

      global.fetch = originalFetch;
    });
  });

  describe('syncListingPrices', () => {
    it('skips updating if market data is unresolved', async () => {
      mockPrisma.iPO.findMany.mockResolvedValue([
        { id: 'ipo-1', name: 'Unknown Imaginary Corp', symbol: null, listingDate: new Date() },
      ]);
      jest.spyOn(service, 'fetchListingPriceForIpo').mockResolvedValue(null);

      const result = await service.syncListingPrices();
      expect(result.updated).toBe(0);
      expect(result.failed).toBe(1);
      expect(mockPrisma.iPO.update).not.toHaveBeenCalled();
    });

    it('updates IPO record when exchange price is resolved', async () => {
      mockPrisma.iPO.findMany.mockResolvedValue([
        { id: 'ipo-swiggy', name: 'Swiggy Limited', symbol: null, listingDate: new Date() },
      ]);
      jest.spyOn(service, 'fetchListingPriceForIpo').mockResolvedValue({
        symbol: 'SWIGGY.NS',
        listingPrice: 420.0,
        currentPrice: 456.0,
      });

      const result = await service.syncListingPrices();
      expect(result.updated).toBe(1);
      expect(result.failed).toBe(0);
      expect(mockPrisma.iPO.update).toHaveBeenCalledWith({
        where: { id: 'ipo-swiggy' },
        data: {
          symbol: 'SWIGGY.NS',
          listingPrice: 420.0,
          currentPrice: 456.0,
        },
      });
    });
  });
});
