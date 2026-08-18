# Skarb

[![CI](https://github.com/volodymyr-kovtun/skarb/actions/workflows/ci.yml/badge.svg)](https://github.com/volodymyr-kovtun/skarb/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Skarb** (Polish & Ukrainian for *treasure*) is a self-hosted personal finance app in the spirit
of Copilot Money and Bilance: one clean dashboard for all your accounts, automatic bank sync,
categories, tags and investment tracking — running entirely on your own machine.

Built for a PKO BP + ZEN + Monobank setup, but works with 2,500+ European banks.

| | |
|---|---|
| Backend | .NET 10, ASP.NET Core minimal APIs, vertical-slice architecture, EF Core + PostgreSQL |
| Frontend | React 19, TypeScript, Vite, Tailwind CSS 4, Recharts, TanStack Query |
| Storage | PostgreSQL 17 (bundled `docker-compose.yml`) — your data never leaves your machine |

## Features

- **Single-owner sign-in** — password + TOTP two-factor, single-use recovery codes,
  session cookies and a deny-by-default API. The instance is claimed once, through a
  setup token printed to the server log; there is no signup.
- **Overview dashboard** — net worth across all currencies, monthly
  earned / spent / **invested** / net, 6-month cashflow chart, and a spending donut that
  flips between **categories and tags** — so "what did the renovation cost this month"
  is one click, and each tag opens the transactions behind it. A switcher re-reports the
  whole page in any of your account currencies (or EUR/USD), converted at today's rates.
- **Internal transfer detection** — moving money between your own accounts (e.g. between two
  PKO accounts) is detected automatically, marked *internal* and never counted in any metric.
  Detection uses two signals: the counterparty IBAN matching one of your accounts, and
  opposite-amount pairs landing on two accounts within 72 hours. Manual override in the
  transaction editor un-marks both legs at once.
- **Investment tracking** — categories have a kind (*spending / income / investment*).
  Transfers to your broker (IB is pre-wired via `ibkr` / `interactive brokers` rules) count
  toward "Invested" — this month and all time — and never inflate your spending.
- **Transactions** — search, filters (account, category, tag, plus *internal* and
  *investments* views), day grouping, manual add/edit/delete, notes, tags
- **Category management** — full CRUD with emoji, color and kind, usage counts, plus
  keyword auto-categorization rules, built-in MCC mapping for Monobank, and the tags
  themselves (rename, recolor, delete)
- **Bank sync**
  - **Monobank** — direct personal API; instant push sync via webhook (optional)
  - **PKO BP + any Enable Banking bank** — the picker lists every supported institution
    across Europe (or per country), free for personal use
  - **ZEN** — CSV statement import (ZEN has no API; see the guide)
  - background auto-sync every 30 minutes + "Sync now" button
- **CSV import** — presets for ZEN and PKO iPKO, configurable column mapping, duplicate-safe re-imports

## Quick start

Everything runs through `make` (run bare `make` to list all targets):

```bash
make run
```

That starts PostgreSQL in Docker (waits until healthy), builds the SPA into the API's
`wwwroot`, applies EF migrations, seeds default categories and serves everything on
**https://localhost:5179** (and plain http on :5178). HTTPS uses the standard .NET
`localhost` dev certificate — run `make https-trust` once if your browser warns about it.
Open-banking providers require an `https://` redirect URL, which is why HTTPS is the default.

| Command | What it does |
|---|---|
| `make run` | Run the full app on https://localhost:5179 (deps + SPA build included) |
| `make dev` | Dev mode: API :5178 + Vite hot reload :5173, Ctrl+C stops both |
| `make deps-up` / `deps-down` | Start / stop PostgreSQL (data kept) |
| `make deps-reset` | **Destroy** the database and start fresh |
| `make build` / `make check` | Build everything / CI-style typecheck + build |
| `make migrate NAME=AddX` | Create an EF Core migration |
| `make db-shell` | psql shell into the database |
| `make install` | dotnet restore + npm install + trust the HTTPS dev cert |
| `make https-trust` | (Re)trust the localhost HTTPS certificate |

Building the API builds the SPA into `wwwroot` first — and only when the frontend actually
changed — so Rider's Run button, `dotnet run` and `make run` all serve the current UI instead
of whatever was built last. `-p:SkipSpa=true` skips it when you want the backend alone, and a
missing `frontend/node_modules` skips it with a message rather than failing the build.

While working on the frontend, prefer `make dev` and http://localhost:5173: Vite hot-reloads
and proxies `/api` to the backend, so nothing has to be rebuilt at all.

### Database

- Connection string lives in `backend/Skarb.Api/appsettings.json`
  (`Host=localhost;Port=5432;Database=skarb;Username=skarb;Password=skarb`, matching `docker-compose.yml`).
- Schema is managed with EF Core migrations (`Migrations/`), applied automatically on startup.
  After changing entities: `make migrate NAME=<Name>` and restart.
- Full reset: `make deps-reset`.

## Connecting your banks

**Read [docs/BANKS.md](docs/BANKS.md)** — step-by-step for Monobank (token + instant webhook),
PKO BP / any European bank (Enable Banking, free personal tier) and ZEN (CSV import), including
the research on why each path was chosen.

## Architecture

Vertical slices + a small shared kernel; SOLID-oriented seams throughout:

```
backend/Skarb.Api/
  Common/
    Domain/           entities (Account, Transaction, Category, …)
    Persistence/      SkarbDbContext + seed
    Abstractions/     IBankProvider, ITransactionIngestor, ICategorizer,
                      ITransferDetector, IExchangeRateService, ISyncService, IEndpointGroup
    Services/         TransactionIngestor, RuleBasedCategorizer, TransferDetector
    Security/         IPasswordHasher, ITotpAuthenticator, IRecoveryCodeService,
                      IOwnerStore, IOwnerAuthenticator, IOwnerSetup + cookie/authz wiring
  Infrastructure/
    Banking/Monobank/       MonobankApiClient (HTTP) + MonobankProvider (IBankProvider)
    Banking/EnableBanking/  EnableBankingApiClient (HTTP+JWT) + EnableBankingProvider
    Fx/                     OpenErApiExchangeRateService
  Features/           one folder per slice, endpoints implement IEndpointGroup
    Auth/ Accounts/ Transactions/ Categories/ Tags/ Dashboard/
    Connections/ Sync/ Import/ Webhooks/ Meta/
  Migrations/         EF Core migrations
frontend/src/
  shared/             typed api client, UI primitives, Layout
  features/           dashboard/ transactions/ accounts/ categories/ settings/
```

Key seams:

- **`IBankProvider`** — adding a bank = one class + one DI registration; the sync
  orchestrator never changes (OCP/DIP).
- **`ITransactionIngestor`** — the single door into the ledger for sync, webhook and CSV
  import: dedupe by external id, refresh of bank holds, auto-categorization. All sources
  behave identically.
- **`ITransferDetector` / `ICategorizer`** — isolated policies, replaceable without touching
  ingestion or providers.
- **`IOwnerAuthenticator` and friends** — the sign-in decision is one policy composed of small
  ones (`IPasswordHasher`, `ITotpAuthenticator`, `IRecoveryCodeService`, `IOwnerStore`), none
  of which knows about HTTP or EF. Authorization is a **deny-by-default fallback policy**, so
  a new endpoint slice is protected the moment it exists — the handful of public routes opt
  out explicitly and visibly.

## Signing in

On first start Skarb has no owner and prints a **setup token** to the log:

```
┌───────────────────────────────────────────────────────────────┐
│  Skarb has no owner yet — open the app to claim it.           │
│  Setup token:  ABCD1234…                                      │
└───────────────────────────────────────────────────────────────┘
```

Open the app and complete setup: email + password → scan the QR with any TOTP app
(1Password, Aegis, Bitwarden, Google Authenticator) → save the recovery codes. After that
the whole API requires a session; only the SPA shell, the sign-in endpoints and the
Monobank webhook are reachable without one.

Password, recovery codes and two-factor status live under **Settings → Security**.
Set `Auth__SetupToken` to choose your own token instead of the generated one.

## Deploying

Running Skarb anywhere other than `localhost` needs a few deliberate choices — a persistent
data-protection key ring, HTTPS with forwarded headers, an updated Enable Banking redirect
URL, and an honest look at whether the free open-banking tier permits what you have in mind
(short version: yes for your own accounts, no for other people's).

**Read [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).**

## Security notes

- Bank tokens/keys are stored in the PostgreSQL database in plain text. Treat the database
  like a password vault — encrypted backups, restricted access.
- Never expose port 5432, and put the app behind a reverse proxy rather than facing the
  internet directly. Reaching it over Tailscale instead of a public URL is the safer default.
- The Monobank webhook path is the only API endpoint that is public by design; it embeds an
  unguessable connection id and only accepts items for accounts it already knows.
- Exchange rates come from open.er-api.com (no key needed) and are cached for 12 h;
  everything else talks only to your banks' official APIs.

See [SECURITY.md](SECURITY.md) for the threat model and how to report vulnerabilities.

## Contributing

What is planned but not built yet lives in [docs/BACKLOG.md](docs/BACKLOG.md).

Bug reports, bank presets and new providers are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © Volodymyr Kovtun. Skarb is not affiliated with any bank or with
Enable Banking; it accesses only accounts you own, with your consent, read-only.
See [docs/PRIVACY.md](docs/PRIVACY.md) and [docs/TERMS.md](docs/TERMS.md).
