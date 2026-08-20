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
- **Rules learned from corrections.** Changing a category by hand offers to turn that one
  correction into a keyword rule: Skarb derives the merchant keyword from the bank descriptor
  ("JMP S.A. BIEDRONKA 7184" → `biedronka`), shows how many transactions it matches and three
  of them as evidence, and files them all on one click. The keyword is editable and the counts
  follow it as you type, so a wrong guess costs a correction rather than a bad rule. The offer
  appears after the save, never before it, so dismissing it leaves the transaction corrected.
  When a rule already claims the keyword it offers to repoint that rule rather than stack a
  second one beside it for the two to disagree over. A bulk re-file can be undone from the
  toast that follows, rule and all.
- Transactions now record **which signal chose their category** — a keyword rule, the MCC map,
  one of the categorizer's fallbacks, or you. A bulk re-file rewrites the guesses and steps
  around the decisions; rows you sorted by hand are only touched if you ask for them by name,
  as are rows from before this was recorded. Transactions added by hand run through the rules
  too, which they previously did not.
- Hand-written rules now sort **ahead** of the ~200 seeded ones rather than behind them.
  Rules are evaluated lowest-priority-first, and a new rule used to be given a priority past
  the end of the table, so a keyword you added yourself silently lost to broad built-ins like
  `supermarket` or `fee`.
- A **Donations** category, routed primarily by MCC 8398 rather than by keyword: a Monobank
  jar top-up reads the same whether the jar belongs to a charity or to your own savings, and
  only the merchant code tells the two apart. Named funds and unambiguous words
  (`донат`, `charity`, `zrzutka`, …) are matched as well, for giving that arrives by card.
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
- **A start date for the ledger** (`Sync:StartDate`, unset by default), for opening the books
  on a chosen day rather than on whatever window a bank happens to offer. Connectors stop
  asking for anything older, and anything a bank volunteers regardless is dropped on the way
  in — from every source, full re-sync included — so deleting the earlier history once makes
  it stay deleted. The boundary is midnight UTC, like every other date boundary in Skarb.
- **Low-balance alerts to Telegram.** Any account can carry a limit (in its own currency);
  when the balance crosses below it, a Telegram message goes out — seconds after the
  payment when the Monobank webhook is on, otherwise at the next sync round. One message
  per drop with a daily reminder while it stays low, re-armed once the balance recovers,
  so a balance hovering at the limit cannot spam anyone. Each account can alert its own
  chat (the shared card pings whoever tops it up); everything else uses the default chat
  from Settings → Notifications, where the bot is connected, chats that messaged it can be
  picked by name, and a test message proves the wiring. Sent and failed alerts appear in
  Sync activity. Setup walkthrough: [docs/ALERTS.md](docs/ALERTS.md).
- PostgreSQL storage via Docker Compose, EF Core migrations, `make`-driven workflow.
- Building the API builds the SPA into `wwwroot` when the frontend changed, so running from
  an IDE or a bare `dotnet run` never serves a stale bundle (`-p:SkipSpa=true` opts out).
