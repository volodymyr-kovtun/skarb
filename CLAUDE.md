# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Skarb is a self-hosted, **single-owner** personal finance app: .NET 10 minimal-API backend
(`backend/Skarb.Api`), React 19 + Vite + Tailwind 4 SPA (`frontend`), PostgreSQL 17. The API
serves the built SPA from its own `wwwroot`, so there is one process and one Docker image.
README.md covers features and user-facing setup; `docs/` holds the bank, alert and deployment
guides; `docs/BACKLOG.md` is the list of unbuilt ideas; `CHANGELOG.md` follows Keep a Changelog.

## Commands

Everything goes through `make` (bare `make` lists targets). Prereqs: .NET 10 SDK, Node 22+, Docker.

| Command | Notes |
|---|---|
| `make install` | `dotnet restore` + `npm install` + trust the localhost HTTPS dev cert |
| `make dev` | Postgres in Docker + API on https://localhost:5179 / http://:5178 + Vite on http://localhost:5173 (proxies `/api` → :5178). Use this for frontend work. |
| `make run` | Builds the SPA into `wwwroot` and serves everything from the API on :5179 |
| `make dev-noauth` | API with `SKARB_DEV_AUTH_BYPASS=true` — every request is the signed-in owner. Development env only; the app refuses to start otherwise. |
| `make check` | CI-style: `tsc -b` + backend build + backend tests. Run before finishing a change. |
| `make test` | `dotnet test backend/Skarb.Api.Tests -v q` |
| `make migrate NAME=AddX` | `dotnet ef migrations add` — required whenever `Common/Domain/Entities.cs` changes; migrations apply on startup |
| `make deps-reset` | **Destroys** the local database |
| `make db-shell` | psql into the `skarb-postgres` container |

Not wrapped by make:

```bash
dotnet test backend/Skarb.Api.Tests --filter "FullyQualifiedName~ReportPeriodTests"   # one test class
dotnet test backend/Skarb.Api.Tests --filter "Name~Month_to_date"                      # tests by name fragment
cd frontend && npm run lint          # oxlint (react, typescript plugins) — runs in the deploy workflow, not in ci.yml
dotnet build backend/Skarb.Api -p:SkipSpa=true   # backend only; otherwise the csproj runs `npm run build` when frontend sources changed
```

`frontend/vite.config.ts` writes the bundle to `../backend/Skarb.Api/wwwroot` (gitignored). The
csproj's `BuildSpa` target rebuilds it on any backend build when `frontend/node_modules` exists.

## Backend architecture

Vertical slices over a small shared kernel. `Program.cs` is the only composition root.

- **Endpoint discovery.** Every `IEndpointGroup` in the assembly is found by reflection and
  instantiated with `Activator.CreateInstance` (`Common/Endpoints/EndpointGroupExtensions.cs`), so
  endpoint classes need a parameterless constructor; dependencies are handler parameters.
  One file per slice under `Features/<Slice>/<Slice>Endpoints.cs`, request records at the top.
- **Deny-by-default authorization.** The fallback policy requires an authenticated user, so a
  new endpoint is protected the moment it exists. Public routes opt out with `.AllowAnonymous()`
  and are deliberately few: `/api/auth/*` sign-in/setup (also `.RequireRateLimiting(RateLimitPolicies.Auth)`),
  `/api/webhooks/monobank/{connectionId}`, and the SPA fallback. Static files are served before
  auth on purpose. Sessions are a cookie (`skarb.session`) carrying a security stamp; changing
  credentials invalidates every other session.
- **Error contract.** `InvalidOperationException` is the "expected operational error" type
  (bank rejected the request, consent expired, bad input from a provider): the global handler
  turns it into `400 { error }` with the message. Anything else is a bug → `500`, message
  hidden outside Development. Validation failures in handlers return `Results.BadRequest(new { error })`.
- **Ingestion pipeline** (the core invariant — keep it): every transaction source goes through
  `ITransactionIngestor`, never `db.Transactions.Add` directly.
  `IBankProvider.SyncAsync` / webhook / `CsvImportService` → `IncomingTransaction` →
  `TransactionIngestor` (drops rows before `Sync:StartDate`, dedupes on `(AccountId, ExternalId)`,
  refreshes mutable fields of known rows such as bank holds, runs `ICategorizer` on new ones).
  Sources without a provider id build one with `StableId.From(prefix, input)` — its format is the
  re-import dedupe contract, don't change it.
- **Sync orchestration** (`Features/Sync/SyncService.cs`): syncs run in the background per
  connection (Monobank rate limits make them minutes long; the UI polls `/api/sync/status`).
  `ITransferDetector` runs **once after the whole round**, not per connection, because pairing
  needs both legs; `ILowBalanceAlerter.CheckAsync` runs after that, even on an empty round.
  `BackgroundSyncService` triggers a round every `Sync:IntervalMinutes`.
- **Adding a bank** = `Infrastructure/Banking/<Bank>/` with a thin API client (HTTP/auth only,
  use `BankingHttp.ReadJsonAsync` for the shared error shape) + a provider implementing
  `IBankProvider` (`Key` must equal `BankConnection.Provider`), one `AddScoped<IBankProvider, …>()`
  in `Program.cs`, a connect flow in `Features/Connections` + Settings page, and a section in
  `docs/BANKS.md`. Providers must skip `BankConnection.IgnoredExternalIds` when discovering accounts.
- **Provenance fields are load-bearing.** `Transaction.CategorySource` (`CategorySources`) and
  `Transaction.InternalSource` (`InternalSources`) record *which signal* decided a category or an
  internal-transfer mark. `Manual` (and null, for pre-provenance rows) means the user decided;
  automated passes — rule re-application, transfer re-detection — only ever rewrite rows their own
  signal set. Preserve this when touching categorization or transfer code.
- **What counts.** Dashboard and transaction-list money is narrowed by
  `TransactionQueries.OnCountedAccounts()` (not archived, not `IsExcluded`) and then
  `!t.IsExcluded && !t.IsInternal`. Categories of kind `investment` are excluded from spending
  and reported in their own "Invested" figure. The Accounts page is the one place an excluded
  account still shows a balance. Any new aggregate should read through the same filters.
- **Dates are UTC everywhere**; every boundary (ledger start, report periods) is midnight UTC.
  `ReportPeriod.Resolve` defines the dashboard windows and their comparison windows.
- **Configuration.** Standard ASP.NET config; `__`-separated env vars in containers. Per-instance
  values (notably `Sync:StartDate`) must never land in the tracked `appsettings.json` — in
  development they go in user-secrets (`dotnet user-secrets set "Sync:StartDate" … --project backend/Skarb.Api`),
  elsewhere in the environment. `SKARB_DEV_AUTH_BYPASS` is read from the process environment
  only, never from `IConfiguration`, by design.
- **DTOs** live in `Common/Contracts/Dtos.cs` with `ToDto()` extension mappers; the frontend
  types in `frontend/src/shared/api.ts` mirror them by hand — change both.

## Frontend architecture

- `src/shared/api.ts` is the entire API surface: every endpoint, every response type, the
  `fetch` wrapper (`credentials: 'include'`, `{ error }` body → `Error`, 401 → `UnauthorizedError`).
  Add new endpoints there, not as ad-hoc `fetch` calls.
- Data via TanStack Query. After a mutation call `refreshAll(queryClient)` — the app invalidates
  *everything* on purpose; don't hand-maintain query keys. A `UnauthorizedError` anywhere
  re-checks `['session']`, which drops the app to the sign-in screen (`features/auth/AuthGate.tsx`).
- `src/shared/ui.tsx` holds the primitives (`Card`, `Modal`, `Segmented`, `Money`, `TxRow`,
  `btnPrimary`/`inputCls` class strings, color palettes). Reuse them before adding new ones.
- Theming: `src/index.css` is the only file that knows a hex code — raw `--sk-*` values swap
  with `[data-theme]`, Tailwind tokens point at them. Charts read colors via `useChartColors()`;
  user-picked colors go through `swatch()/tint()` in `shared/color.ts` so they stay legible in
  both themes. Don't hardcode colors in components.
- Pages are one file per feature under `src/features/<feature>/`. CSV presets live in
  `SettingsPage.tsx` (`CSV_PRESETS`). Report periods and display currency are shared hooks
  (`shared/period.ts`, `shared/currency.ts`) persisted in localStorage.
- TypeScript is strict-ish (`noUnusedLocals`, `noUnusedParameters`, `verbatimModuleSyntax`):
  `tsc -b` failing is a CI failure.

## Tests

`backend/Skarb.Api.Tests` is xUnit and tests **pure logic only** — no database, no HTTP.
The pattern is to lift the decision into a static function (`TransferDetector.PairLegs`,
`LowBalanceAlerter.Evaluate`, `ReportPeriod.Resolve`, `MerchantKeyword.For`) and test that;
`InternalsVisibleTo("Skarb.Api.Tests")` is set, so `internal static` is fine. Test names are
snake-case sentences (`Closest_match_wins_the_credit_over_an_earlier_debit`). Synthetic data
only — never real IBANs, tokens or statements, even in tests.

## Driving the UI against real data

The owner normally has `make dev` running (API :5178/:5179, Postgres :5432 with their real local
ledger). For screenshots, layout work or automated click-throughs, don't bind those ports or seed
into that database: start a throwaway Postgres on another port, point `ConnectionStrings__Default`
at it, run the API with `SKARB_DEV_AUTH_BYPASS=true ASPNETCORE_ENVIRONMENT=Development` on a
spare `--urls`, and claim the instance via `POST /api/auth/setup` + `/setup/confirm` (TOTP from
the returned secret) — otherwise `setupRequired` keeps every client on the setup screen even
with the bypass on. `.claude/launch.json` defines a `skarb-web` Vite preview on :5273.

## Conventions

- **Config lives where it's used.** Per-entity settings (an account's alert limit and
  recipient, a category's kind) belong in that entity's editor; the Settings page holds only
  instance-wide plumbing (tokens, connections, bot). Don't add per-thing pickers to Settings.
- **Commits**: imperative subject, then a prose body that explains the *why* and the reasoning
  behind non-obvious choices (see `git log`). No `Co-Authored-By` or other AI-attribution
  trailers, and no generated-with footers in PR bodies.
- When behaviour or setup changes, update the matching doc in the same change: `CHANGELOG.md`
  (Unreleased), `README.md`, `docs/BANKS.md` / `docs/ALERTS.md` / `docs/DEPLOYMENT.md`. Shipped
  backlog items move from `docs/BACKLOG.md` to the changelog.
- Comments in this codebase explain *why* a decision was made, often with the bug it prevents;
  match that register rather than restating what the code does.

## Deployment

`docker/Dockerfile` builds one image (SPA stage + `dotnet publish -p:SkipSpa=true`);
`compose.production.yml` + `compose.ghcr.yml` run it with Postgres, a daily `pg_dump` sidecar and
a persistent data-protection key ring, joined to a shared external `web` network for a reverse
proxy. `.github/workflows/manual-deploy.yml` (workflow_dispatch) lints/tests, pushes to GHCR and
rolls out over SSH. Production runs at https://skarb.subero.app on a shared droplet; server-side
specifics (Caddy, `/opt/skarb`, secrets) are in the `droplet` skill and the Infra folder, not this
repo. See `docs/DEPLOYMENT.md` for the env vars and the Enable Banking free-tier constraint
(one instance, one owner, own accounts only).
