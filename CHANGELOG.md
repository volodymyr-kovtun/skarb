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
- [docs/BACKLOG.md](docs/BACKLOG.md) — features worth building that are not built yet.
- Dashboard: net worth across currencies, monthly earned / spent / invested / net,
  6-month cashflow chart, spending-by-category donut, recent activity.
- Dashboard currency switcher: every converted figure on the overview can be read in any
  account currency (plus EUR/USD), remembered between visits.
- Dashboard net-worth trend: a six-month line under the headline figure, walked backwards
  from today's total through each month's net. It follows money in and out, not what
  holdings did on the market, since Skarb keeps no historical balances.
- **Light and dark themes.** The theme follows the system by default and can be pinned
  either way from the header; the choice is remembered and applied before first paint, so
  a dark-mode instance never flashes white. Colors you pick for a category, tag or account
  are normalized into a lightness band per theme, so a hue chosen on paper stays legible
  on a dark surface without being re-picked.
- Accounts are grouped by institution on the overview (each group showing its share of
  net worth, expandable to the accounts underneath) and on the Accounts page, so the
  layout holds up with many accounts instead of growing a row of pills.
- Transactions: search, filters (account, category, tag, uncategorized, internal transfers,
  investments), manual add / edit / delete, notes, tags. The tag filter takes several tags
  at once and matches transactions carrying any of them.
- Spending by tag: the overview's spending donut can break the month down by tag, with the
  untagged remainder as its own slice and each tag linking to the transactions behind it.
  Tags are renamed, recolored and deleted on the Categories page.
- Spending by account: the same donut also breaks the month down by the account the money
  left from, each slice linking to that account's transactions. It cuts the same month the
  category breakdown does, so internal transfers, investments, manually excluded
  transactions and accounts marked *don't count* stay out of it.
- Accounts can be marked *don't count*: the account still syncs and the Accounts tab still
  reports its balance, but it contributes nothing to net worth, the month tiles, the cashflow
  chart, the spending breakdowns or recent activity, and its transactions drop out of the
  transaction list. Selecting it in the account filter still shows them. Archived accounts are
  now held to the same rule — previously they were dropped from net worth but their spending
  still reached the overview's charts and the transaction list.
- Internal transfer detection (own-IBAN match, bank-issued shared reference, and
  opposite-amount pairs within 72 h) with manual override. Pairing settles the closest
  match in time first, so a distant leg cannot claim a credit that another leg matches to
  the second — the case that left one half of a transfer counted as income when the second
  bank was connected later. Connecting that bank now re-examines the pairings made without
  it. An override records that you made it, in both directions, so a pair you un-mark stays
  un-marked instead of being re-detected on the next sync.
- Investment tracking via investment-kind categories (Brokerage, Crypto seeded; IBKR rules).
- Category management with emoji, color, kind and keyword auto-categorization rules;
  built-in MCC mapping for card transactions.
- Auto-categorization rules are searchable (by keyword or category) and load a page at a
  time behind a *Show more* button, so the ~190 seeded rules no longer stretch the
  Categories page. Adding a rule jumps the search to it, so it is visible straight away.
- Bank sync: Monobank (personal API + optional instant webhook), Enable Banking (PKO BP
  and 2,500+ European banks), CSV import with ZEN / PKO presets.
- Bank connections can be renamed from Settings. The accounts synced through a connection
  are grouped under its name, so the rename relabels them too.
- Removing a bank connection now deletes the accounts it created and their transactions,
  instead of leaving orphaned accounts behind. Manually created accounts are untouched, and
  the confirmation says exactly how much is going.
- Background auto-sync every hour and on-demand "Sync now".
- PostgreSQL storage via Docker Compose, EF Core migrations, `make`-driven workflow.
- Building the API builds the SPA into `wwwroot` when the frontend changed, so running from
  an IDE or a bare `dotnet run` never serves a stale bundle (`-p:SkipSpa=true` opts out).
