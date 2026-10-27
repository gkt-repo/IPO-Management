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
