# Changelog

All notable changes to Skarb are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Initial public release.
- **Authentication.** Single-owner sign-in with password (PBKDF2-HMAC-SHA512) and mandatory
  TOTP two-factor, plus eight single-use recovery codes. First-run setup is gated by a setup
  token printed to the server log, so a deployed instance cannot be claimed by a stranger.
- Session cookies (`HttpOnly`, `Secure`, `SameSite=Lax`) backed by a persistable
  data-protection key ring; changing the password invalidates every other session.
- Deny-by-default API authorization: new endpoints are protected unless they opt out.
  Per-IP rate limiting and per-account lockout on the credential endpoints.
- Settings → Security: change password, view two-factor status, regenerate recovery codes.
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — deploying safely, and what the free Enable
  Banking tier does and does not permit.
- Dashboard: net worth across currencies, monthly earned / spent / invested / net,
  6-month cashflow chart, spending-by-category donut, recent activity.
- Dashboard currency switcher: every converted figure on the overview can be read in any
  account currency (plus EUR/USD), remembered between visits.
- Transactions: search, filters (account, category, uncategorized, internal transfers,
  investments), manual add / edit / delete, notes, tags.
- Internal transfer detection (own-IBAN match + opposite-amount pairs within 72 h) with
  manual override.
- Investment tracking via investment-kind categories (Brokerage, Crypto seeded; IBKR rules).
- Category management with emoji, color, kind and keyword auto-categorization rules;
  built-in MCC mapping for card transactions.
- Bank sync: Monobank (personal API + optional instant webhook), Enable Banking (PKO BP
  and 2,500+ European banks), CSV import with ZEN / PKO presets.
- Background auto-sync every 30 minutes and on-demand "Sync now".
- PostgreSQL storage via Docker Compose, EF Core migrations, `make`-driven workflow.
