# Contributing to Skarb

Thanks for your interest. Skarb is a small personal project, but contributions — bug
reports, bank-format presets, new bank providers, UI polish — are welcome.

## Getting set up

Prerequisites: .NET 10 SDK, Node 22+, Docker.

```bash
git clone git@github.com:volodymyr-kovtun/skarb.git
cd skarb
make install     # dotnet restore + npm install
make dev         # Postgres in Docker, API on :5178, Vite hot reload on :5173
```

Run bare `make` to see every target. `make check` typechecks the frontend and builds the
backend — run it before opening a PR.

## Project layout in one minute

- `backend/Skarb.Api/Common` — domain, persistence, abstractions and shared services.
- `backend/Skarb.Api/Features/*` — one folder per vertical slice; endpoints implement
  `IEndpointGroup` and are auto-discovered.
- `backend/Skarb.Api/Infrastructure/Banking/*` — bank integrations. Each is a thin API
  client (HTTP/auth only) plus a provider implementing `IBankProvider`.
- `frontend/src/features/*` and `frontend/src/shared` mirror the same split.

See the README's *Architecture* section for the key seams.

## Adding a bank provider

1. Create `Infrastructure/Banking/<Bank>/` with an API client and a class implementing
   `IBankProvider` (`Key` + `SyncAsync`).
2. Map incoming data to `IncomingTransaction` and hand it to `ITransactionIngestor` —
   never write to `db.Transactions` directly, so dedupe/categorization stay uniform.
3. Register it in `Program.cs` with `AddScoped<IBankProvider, YourProvider>()`.
4. Add the connect flow to `Features/Connections` and the Settings page.
5. Document the user-facing steps in `docs/BANKS.md`.

## Adding a CSV preset

Presets live in `frontend/src/features/settings/SettingsPage.tsx` (`CSV_PRESETS`). Add
an entry with the column indices, date format and delimiter of the bank's export, and note
the export path from that bank's app in the `hint`.

## Database changes

Entities live in `Common/Domain/Entities.cs`. After changing them:

```bash
make migrate NAME=DescribeYourChange
```

Commit the generated files under `Migrations/`. Migrations apply automatically on startup.

## Pull requests

- Keep PRs focused; one change per PR.
- Match the existing style (the code is `dotnet format` / default Vite ESLint clean).
- Never commit real bank credentials, tokens, keys or statements — not even in tests.
  Use synthetic data.
- Describe how you verified the change.

## Reporting bugs / requesting features

Open an issue using the templates. For anything security-related, please follow
[SECURITY.md](SECURITY.md) instead of a public issue.
