# Personal Indian IPO Allotment Tracker

A production-ready, full-stack application designed to securely track Mainboard and SME Indian IPO allotment results for an individual investor's single PAN card.

## Key Features

1. **Strict Single-PAN Security**:
   - Exactly one PAN card per user account enforced by PostgreSQL schema constraints.
   - Application-layer authenticated **AES-256-GCM encryption** with ephemeral decryption.
   - Non-reversible **HMAC-SHA256 fingerprint** for fast queries.
   - Decrypted PANs are never exposed in ordinary API responses or logged to disk.
   - Statutory explicit user consent enforcement.

2. **PEEK Microservice & Verified Registrar Adapters**:
   - Integrates live dynamic discovery and PAN allotment queries from PEEK (`crazydragonhacker/PEEK`).
   - Verified live adapters for **KFintech** and **MUFG Intime** (formerly Link Intime).
   - Safe status mapping: `ALLOTTED`, `NOT_ALLOTTED`, `PENDING`, `LOOKUP_FAILED`, and `NOT_SUPPORTED`.
   - Inconclusive or CAPTCHA-protected queries (e.g. Bigshare) are never falsely classified as "not allotted".
   - Confirmed `ALLOTTED` results are preserved across subsequent transient lookup failures.

3. **App-Open Automatic Asynchronous Refresh**:
   - Immediately renders cached dashboard metrics and IPO feed on launch.
   - Dispatches a non-blocking asynchronous refresh job in the background.
   - Configurable 5-minute cooldown and job deduplication to prevent redundant requests.
   - Bounded concurrency with retries and exponential backoff.
   - Real-time progress tracking via polling and manual Refresh button.

4. **Official Registrar Verification Links**:
   - One-tap button for every IPO directing users to the official registrar portal (KFintech, MUFG Intime, Bigshare, etc.) for independent verification.

5. **Production Architecture**:
   - **Frontend**: Flutter 3 (Riverpod, GoRouter, Dio, Material 3, Flutter Secure Storage).
   - **Backend**: NestJS 11, TypeScript, Prisma ORM, Passport JWT.
   - **Database**: PostgreSQL 16.
   - **Deployment**: Docker Compose side-by-side with NithConnect and MoneyGame on Oracle Cloud VM.

---

## Directory Structure

```text
IPO/
├── backend/                  # NestJS backend + Prisma ORM
│   ├── prisma/
│   │   ├── schema.prisma     # Relational schema (User, SavedPan, IPO, AllotmentCheck, RefreshJob)
│   │   └── migrations/
│   ├── src/
│   │   ├── auth/             # JWT auth & registration
│   │   ├── pan/              # Single PAN encryption & consent service
│   │   ├── ipo/              # IPO catalogue & dashboard summary
│   │   ├── refresh/          # Async job manager & cooldown engine
│   │   ├── peek/             # PEEK microservice client & native fallback
│   │   └── common/           # AES-256-GCM & HMAC security
│   └── Dockerfile
├── peek/                     # PEEK FastAPI Python microservice
│   ├── app/
│   │   ├── registrars/       # KFintech, MUFG, Bigshare, Skyline adapters
│   │   └── main.py
│   └── Dockerfile
├── frontend/                 # Flutter mobile & web client
│   ├── lib/
│   │   ├── core/             # API client, models, constants, theme
│   │   ├── providers/        # Riverpod notifiers (Auth, PAN, IPO, RefreshJob)
│   │   ├── screens/          # Dashboard, PAN Settings, IPO Detail, Login/Register
│   │   └── router/           # GoRouter configuration
│   └── test/
├── docker-compose.yml        # Production Docker Compose definition
├── deploy.sh                 # One-click deployment script
├── ORACLE_VM_SETUP.md        # Oracle Cloud VM guide
├── .env.example
└── .env.oracle.example
```

---

## Quickstart

### Running Backend Locally
```bash
cd backend
npm install
npm run prisma:generate
# Ensure PostgreSQL is running on port 5434 or configured in .env
npm run start:dev
```

### Running Flutter App
```bash
cd frontend
flutter pub get
flutter run -d chrome # or android / ios / linux
```

### Running Tests
```bash
# Backend unit & integration tests
cd backend && npm test

# Flutter analyzer & tests
cd frontend && flutter analyze && flutter test
```

## IPO listing schedules

The Mainboard/SME selector is independent of the Open, Closed and Upcoming tabs.
`GET /api/ipo?issueType=SME&status=OPEN` filters bidding status; the response's
`status` remains the user's allotment status and `lifecycleStatus` describes bidding.
Open issues sort by closing time, upcoming issues by opening time, and closed issues
by most recent closing date. Allotment dates never determine bidding status.

Legacy UTC-midnight `openDate`/`closeDate` values represent Indian calendar dates.
They use 10 AM IST opening and 5 PM IST Mainboard / 4 PM IST SME final closing.
Explicit non-midnight timestamps override these defaults (including extensions).
See [NSE bidding hours](https://www.nseindia.com/static/products-services/initial-public-offerings-book-building)
and [NSE SME closing rules](https://www.nseindia.com/static/trade/e-ipo-faqs).
These tabs describe the overall subscription period, not an intraday trading session;
broker/category deadlines can differ. The API also returns `biddingOpensAt` and
`biddingClosesAt`; clients recalculate status when these boundaries pass and on resume.

Registrar discovery currently provides names/identifiers, **not verified schedules**.
Incomplete schedules are shown separately as “Dates unavailable”, unless closing or
listing evidence establishes that bidding is closed. Populate verified board and
schedule data before expecting a newly discovered issue in a dated tab. Discovery's
name-based SME detection also needs verified issue-type data for names without “SME”.

Startup no longer inserts sample IPOs or overwrites all catalogue dates and quotes.
It repairs only exact matches for four known incorrect legacy seed schedules:

| IPO | Correct opening–closing dates | Source |
| --- | --- | --- |
| Swiggy | 6–8 November 2024 | [Issuer prospectus](https://www.swiggy.com/corporate/wp-content/uploads/2024/11/Swiggy-Limited-Prospectus_Final-filing-version.pdf) |
| Ola Electric | 2–6 August 2024 | [Issuer allotment notice](https://cdn.olaelectric.com/sites/evdp/pages/investor/basisofallotment_ola_approved_ad.pdf) |
| Tata Technologies | 22–24 November 2023 | [NSE issue information](https://www.nseindia.com/market-data/issue-information?series=EQ&symbol=TATATECH&type=Active) |
| NTPC Green Energy | 19–22 November 2024 | [Issuer prospectus](https://www.ngel.in/public/investors/Prospectus.pdf) |

For those exact legacy rows, unsourced seeded allotment/listing milestones and market
quotes are cleared; exchange price sync can repopulate quotes. Other imported rows,
IDs and user allotment history are preserved. Remaining catalogue dates still depend
on their source and have not been independently verified by this repair. Restart the
updated backend and refresh the client to apply the data corrections; no schema
migration is required.
