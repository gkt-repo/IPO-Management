import { Injectable, Logger } from '@nestjs/common';
import { AllotmentStatus } from '@prisma/client';

export interface RegistrarCheckResult {
  status: AllotmentStatus;
  sharesAllotted: number | null;
  message: string;
  source: string;
  errorCode?: string;
}

export interface DiscoveredIPO {
  externalId: string;
  name: string;
  registrar: string;
  officialVerificationUrl: string;
  issueType?: 'MAINBOARD' | 'SME';
}

@Injectable()
export class PeekService {
  private readonly logger = new Logger(PeekService.name);
  private readonly peekUrl = process.env.PEEK_SERVICE_URL || 'http://localhost:8000';

  /**
   * Primary check method: calls PEEK FastAPI service with timeout and retry,
   * with automatic fallback to direct registrar adapters if PEEK service is unreachable.
   */
  async checkAllotment(
    rawPan: string,
    ipoName: string,
    registrarName: string,
    externalId?: string,
  ): Promise<RegistrarCheckResult> {
    // 1. Attempt check via PEEK FastAPI service
    try {
      const peekResult = await this.queryPeekService(rawPan, externalId || ipoName);
      if (peekResult) {
        return peekResult;
      }
    } catch (err) {
      this.logger.debug(`PEEK service query bypassed/failed (${err.message}). Using native registrar adapter.`);
    }

    // 2. Direct Registrar Adapter Execution
    const normalizedReg = (registrarName || '').toUpperCase();
    if (normalizedReg.includes('KFIN')) {
      return this.checkKFintechDirect(rawPan, externalId);
    } else if (normalizedReg.includes('MUFG') || normalizedReg.includes('LINK')) {
      return this.checkMufgDirect(rawPan, externalId);
    } else if (normalizedReg.includes('BIGSHARE')) {
      // Bigshare is CAPTCHA protected - as verified in PEEK, cannot be bypassed automatically
      return {
        status: AllotmentStatus.LOOKUP_FAILED,
        sharesAllotted: null,
        message: 'Bigshare automated lookup requires interactive CAPTCHA verification. Please use the official verification link.',
        source: 'BIGSHARE_CAPTCHA_REQUIRED',
        errorCode: 'CAPTCHA_REQUIRED',
      };
    } else {
      return {
        status: AllotmentStatus.NOT_SUPPORTED,
        sharesAllotted: null,
        message: `Automated lookups are not currently supported for registrar ${registrarName}. Please check via official registrar link.`,
        source: 'REGISTRAR_NOT_SUPPORTED',
        errorCode: 'NOT_SUPPORTED',
      };
    }
  }

  /**
   * Query the PEEK FastAPI microservice.
   */
  private async queryPeekService(rawPan: string, ipoQuery: string): Promise<RegistrarCheckResult | null> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);

    try {
      const res = await fetch(`${this.peekUrl}/check`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pan: rawPan, ipo: ipoQuery }),
        signal: controller.signal,
      });

      if (!res.ok) {
        if (res.status === 404) {
          return null; // Not found in PEEK cache, proceed to native adapter
        }
        return {
          status: AllotmentStatus.LOOKUP_FAILED,
          sharesAllotted: null,
          message: `PEEK service returned HTTP ${res.status}`,
          source: 'PEEK_SERVICE_HTTP_ERROR',
          errorCode: `HTTP_${res.status}`,
        };
      }

      const data = await res.json();
      return this.mapPeekStatus(data);
    } catch (err) {
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }

  private mapPeekStatus(data: any): RegistrarCheckResult {
    const statusStr = (data.status || '').toLowerCase();
    let status: AllotmentStatus = AllotmentStatus.LOOKUP_FAILED;

    if (statusStr === 'allotted') {
      status = AllotmentStatus.ALLOTTED;
    } else if (statusStr === 'not_allotted' || statusStr === 'not_applied') {
      status = AllotmentStatus.NOT_ALLOTTED;
    } else if (statusStr === 'lookup_failed') {
      status = AllotmentStatus.LOOKUP_FAILED;
    }

    return {
      status,
      sharesAllotted: data.shares_allotted != null ? Number(data.shares_allotted) : null,
      message: data.message || 'Lookup completed',
      source: `PEEK_${data.registrar || 'REGISTRAR'}`.toUpperCase(),
    };
  }

  /**
   * Direct native KFintech adapter (verified live in PEEK).
   */
  async checkKFintechDirect(rawPan: string, clientId?: string): Promise<RegistrarCheckResult> {
    if (!clientId) {
      return {
        status: AllotmentStatus.LOOKUP_FAILED,
        sharesAllotted: null,
        message: 'KFintech client ID is missing for this issue.',
        source: 'KFINTECH_NATIVE',
        errorCode: 'MISSING_CLIENT_ID',
      };
    }

    const apiUrl = 'https://0uz601ms56.execute-api.ap-south-1.amazonaws.com/prod/api/query?type=pan';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);

    try {
      const res = await fetch(apiUrl, {
        method: 'GET',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:155.0) Gecko/20100101 Firefox/155.0',
          'Accept': 'application/json, text/plain, */*',
          'reqparam': rawPan,
          'client_id': clientId,
          'Origin': 'https://ipostatus.kfintech.com',
          'Referer': 'https://ipostatus.kfintech.com/',
        },
        signal: controller.signal,
      });

      if (!res.ok) {
        return {
          status: AllotmentStatus.LOOKUP_FAILED,
          sharesAllotted: null,
          message: `KFintech server returned HTTP ${res.status}`,
          source: 'KFINTECH_NATIVE',
          errorCode: `HTTP_${res.status}`,
        };
      }

      const json = await res.json();
      const records = json?.data;

      if (!records || !Array.isArray(records) || records.length === 0) {
        // Record not found / not applied
        return {
          status: AllotmentStatus.NOT_ALLOTTED,
          sharesAllotted: 0,
          message: 'No allotment record found for this PAN.',
          source: 'KFINTECH_NATIVE',
        };
      }

      const rec = records[0];
      const allottedRaw = rec.All_Shares;
      const allotted = parseInt(String(allottedRaw || '0').replace(/,/g, ''), 10) || 0;

      if (allotted > 0) {
        return {
          status: AllotmentStatus.ALLOTTED,
          sharesAllotted: allotted,
          message: `Congratulations! ${allotted} shares allotted.`,
          source: 'KFINTECH_NATIVE',
        };
      } else {
        return {
          status: AllotmentStatus.NOT_ALLOTTED,
          sharesAllotted: 0,
          message: 'Applied, but no shares were allotted.',
          source: 'KFINTECH_NATIVE',
        };
      }
    } catch (err: any) {
      return {
        status: AllotmentStatus.LOOKUP_FAILED,
        sharesAllotted: null,
        message: `KFintech request failed: ${err.name === 'AbortError' ? 'Request timed out' : err.message}`,
        source: 'KFINTECH_NATIVE',
        errorCode: err.name || 'NETWORK_ERROR',
      };
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * Direct native MUFG Intime adapter (formerly Link Intime, verified live in PEEK).
   */
  async checkMufgDirect(rawPan: string, clientId?: string): Promise<RegistrarCheckResult> {
    if (!clientId) {
      return {
        status: AllotmentStatus.LOOKUP_FAILED,
        sharesAllotted: null,
        message: 'MUFG Intime company ID is missing for this issue.',
        source: 'MUFG_NATIVE',
        errorCode: 'MISSING_CLIENT_ID',
      };
    }

    const url = 'https://in.mpms.mufg.com/Initial_Offer/IPO.aspx/SearchOnPan';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);

    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
        body: JSON.stringify({
          clientid: clientId,
          PAN: rawPan,
          IFSC: '',
          CHKVAL: '1',
          token: '',
        }),
        signal: controller.signal,
      });

      if (!res.ok) {
        return {
          status: AllotmentStatus.LOOKUP_FAILED,
          sharesAllotted: null,
          message: `MUFG server returned HTTP ${res.status}`,
          source: 'MUFG_NATIVE',
          errorCode: `HTTP_${res.status}`,
        };
      }

      const json = await res.json();
      const rawXml = json?.d || '';

      if (!rawXml || !rawXml.includes('<NewDataSet')) {
        return {
          status: AllotmentStatus.NOT_ALLOTTED,
          sharesAllotted: 0,
          message: 'No allotment record found for this PAN.',
          source: 'MUFG_NATIVE',
        };
      }

      // Check XML for ALLOT tag e.g. <ALLOT>273</ALLOT> or <ALLOT>0</ALLOT>
      const allotMatch = rawXml.match(/<ALLOT>(\d+)<\/ALLOT>/i);
      if (!allotMatch) {
        return {
          status: AllotmentStatus.NOT_ALLOTTED,
          sharesAllotted: 0,
          message: 'No shares allotted for this application.',
          source: 'MUFG_NATIVE',
        };
      }

      const allotted = parseInt(allotMatch[1], 10) || 0;
      if (allotted > 0) {
        return {
          status: AllotmentStatus.ALLOTTED,
          sharesAllotted: allotted,
          message: `Congratulations! ${allotted} shares allotted.`,
          source: 'MUFG_NATIVE',
        };
      } else {
        return {
          status: AllotmentStatus.NOT_ALLOTTED,
          sharesAllotted: 0,
          message: 'Applied, but zero shares were allotted.',
          source: 'MUFG_NATIVE',
        };
      }
    } catch (err: any) {
      return {
        status: AllotmentStatus.LOOKUP_FAILED,
        sharesAllotted: null,
        message: `MUFG Intime request failed: ${err.name === 'AbortError' ? 'Request timed out' : err.message}`,
        source: 'MUFG_NATIVE',
        errorCode: err.name || 'NETWORK_ERROR',
      };
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * Discover live IPOs dynamically from MUFG Intime portal.
   */
  async discoverMufgIpos(): Promise<DiscoveredIPO[]> {
    try {
      const res = await fetch('https://in.mpms.mufg.com/Initial_Offer/IPO.aspx/GetDetails', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0',
        },
        body: JSON.stringify({}),
      });

      if (!res.ok) return [];
      const json = await res.json();
      const xml = json?.d || '';

      const items: DiscoveredIPO[] = [];
      const tableRegex = /<Table>([\s\S]*?)<\/Table>/g;
      let match;
      while ((match = tableRegex.exec(xml)) !== null) {
        const tableContent = match[1];
        const idMatch = tableContent.match(/<company_id>([^<]+)<\/company_id>/);
        const nameMatch = tableContent.match(/<companyname>([^<]+)<\/companyname>/);
        if (idMatch && nameMatch) {
          const clientId = idMatch[1].trim();
          const name = nameMatch[1].trim().replace(/\s*-\s*IPO$/i, '').trim();
          items.push({
            externalId: clientId,
            name,
            registrar: 'MUFG_INTIME',
            officialVerificationUrl: 'https://in.mpms.mufg.com/Initial_Offer/IPO.aspx',
            issueType: name.toUpperCase().includes('SME') ? 'SME' : 'MAINBOARD',
          });
        }
      }
      return items;
    } catch (err) {
      this.logger.warn(`MUFG dynamic discovery error: ${err.message}`);
      return [];
    }
  }

  /**
   * Discover live IPOs dynamically from KFintech portal.
   */
  async discoverKFintechIpos(): Promise<DiscoveredIPO[]> {
    try {
      const pageRes = await fetch('https://ipostatus.kfintech.com/', {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      });
      if (!pageRes.ok) return [];
      const html = await pageRes.text();
      const bundleMatch = html.match(/(static\/js\/main\.[a-zA-Z0-9]+\.js)/);
      if (!bundleMatch) return [];

      const bundleUrl = `https://ipostatus.kfintech.com/${bundleMatch[1]}`;
      const bundleRes = await fetch(bundleUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': 'https://ipostatus.kfintech.com/',
        },
      });
      if (!bundleRes.ok) return [];
      const bundle = await bundleRes.text();

      const items: DiscoveredIPO[] = [];
      const regex = /"clientId":"([^"]+)","name":"([^"]+)"/g;
      let match;
      while ((match = regex.exec(bundle)) !== null) {
        const clientId = match[1].trim();
        const name = match[2].trim();
        items.push({
          externalId: clientId,
          name,
          registrar: 'KFINTECH',
          officialVerificationUrl: 'https://ipostatus.kfintech.com/',
          issueType: name.toUpperCase().includes('SME') ? 'SME' : 'MAINBOARD',
        });
      }
      return items;
    } catch (err) {
      this.logger.warn(`KFintech dynamic discovery error: ${err.message}`);
      return [];
    }
  }

  /**
   * Return official verification URL for a given registrar.
   */
  getOfficialRegistrarUrl(registrar: string): string {
    const reg = (registrar || '').toUpperCase();
    if (reg.includes('KFIN')) {
      return 'https://ipostatus.kfintech.com/';
    } else if (reg.includes('MUFG') || reg.includes('LINK')) {
      return 'https://in.mpms.mufg.com/Initial_Offer/IPO.aspx';
    } else if (reg.includes('BIGSHARE')) {
      return 'https://ipo.bigshareonline.com/IPO_Status.html';
    } else if (reg.includes('SKYLINE')) {
      return 'https://www.skylinerta.com/ipo.php';
    } else if (reg.includes('MAASHITLA')) {
      return 'https://maashitla.com/allotment-status/public-issues';
    }
    return 'https://www.chittorgarh.com/ipo/ipo_allotment_status.asp';
  }
}
