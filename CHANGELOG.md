# Changelog

All notable changes to Skarb are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Initial public release.
- Dashboard: net worth across currencies, monthly earned / spent / invested / net,
  6-month cashflow chart, spending-by-category donut, recent activity.
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
