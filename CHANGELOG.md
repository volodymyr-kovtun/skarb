# Changelog

All notable changes to Skarb are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- **Switched-on filters on the Transactions page are readable again.** *Hide internal* and an
  active tag filter stacked an accent background on top of the pill's quiet one, and which of
  two background utilities wins is decided by their order in the stylesheet, not in the class
  list — the quiet one won, under text meant for the accent. The label all but disappeared in
  both themes. The on state is now a class of its own, so there is nothing left to conflict.
- **A typo in `Sync__IntervalMinutes` no longer takes the API down.** The value went straight
  to `Task.Delay`, which rejects anything past ~49 days, and a background service that throws
  stops the whole host by default — so `Sync__IntervalMinutes=100000` killed the app seconds
  after startup with no obvious link back to the setting. The interval is now clamped to
  1 minute–7 days and the out-of-range value is logged as a warning; `0` still means off.
  The other durations read from configuration (`Auth__SessionDays`, `Fx__CacheHours`,
  `Sync__TransferPairWindowHours`) are clamped the same way, since a large enough number
  overflows `TimeSpan` on its own.

### Changed
- **Balances are hidden until you ask for them.** Opening Skarb put the whole net worth on
  screen in 64px type before you had asked a question, which is the wrong thing to be handed
  when you came to check how the month is going. Balances — the net-worth hero, the
  institution totals on the overview, and every figure on the Accounts page — now read as
  dots, with an eye button next to the first of them that spells them out and remembers the
  choice. Only *balances* go through the toggle: earned, spent, invested, the net for the
  window and every transaction stay legible either way, and the net-worth curve keeps its
  shape because an unlabelled line says how the months went without saying what they came to.
- **The web app on a phone.** The five sections used to be a row of header pills that wrapped
  onto two lines and claimed the top third of a phone screen before any money was on it. Below
  `sm` they are now a bottom tab bar — an icon and a label per section, clear of the home
  indicator — and the header keeps only the mark and the sync / theme / sign-out controls.
  Card gutters, page titles, the transaction filter bar and every dialog tighten on narrow
  screens as well, so a phone shows the figures instead of the chrome. Tablet and desktop
  keep the header pills.

### Added
- **Cash wallets, and ATM withdrawals that move there instead of being spent.** Cash is now a
  built-in section of the Accounts page: one wallet per currency, enforced by the database, so
  a withdrawal always has exactly one place to go. A withdrawal — money out, filed under the
  seeded **Cash** category — becomes a transfer: the bank row is marked *internal* and Skarb
  writes the wallet side the bank never reports, so taking money out of an ATM stops counting
  as spending and the wallet's balance follows along. The wallet for a currency opens itself
  on the first withdrawal in it; **archiving a wallet is the off switch** for that currency.
  The category *is* the signal, which keeps it correctable with what you already know: file a
  missed ATM under Cash and it moves, file a false alarm anywhere else (or un-mark it as
  internal) and the wallet side goes away. Rows you excluded by hand before wallets existed
  are left alone until you include them again; rows you marked or un-marked as internal
  yourself are never touched. ATM detection itself got wider: MCC 6010/6011 (cash at a
  counter / from an ATM) now map to Cash rather than Fees, and `банкомат` / `зняття готівки`
  join the seeded keywords, so Monobank withdrawals are caught without a rule of your own.
  - **What you were actually handed.** A UAH card in an Italian ATM shows hryvnias on the
    statement and puts euros in your hand, and the machine's fee is in the bank's figure
    without ever reaching your wallet. The withdrawal's editor has a *Cash you received*
    block — currency and amount. Switching the currency shows today's-rate estimate as the
    placeholder (leave it empty to use it, frozen at save), and the cash moves to that
    currency's wallet. Without a correction the wallet follows the bank's amount, including
    when a hold settles differently.
  - **Upgrading.** Manual accounts filed under the institution `Cash` (what the account form
    used to suggest) become wallets on migration. Where two shared a currency they are
    **merged into one** — transactions moved to the older live account, balance recomputed,
    the emptied duplicate deleted. Any other manual account can be made a wallet from its
    editor. History already in the ledger is not re-read: past withdrawals move only when
    you edit them, which the new bulk edit makes a two-click job.
- **Select several transactions and edit them at once.** *Select* on the Transactions page
  turns rows into checkboxes — shift-click for a range, *Select day*, or *Select all N* for
  everything the current filters match across every page. The selection survives paging and
  filter changes on purpose: search one merchant, tick, search the next, tick, then file the
  lot. A bar at the bottom (above the tab bar on a phone) sets a **category**, adds or removes
  a **tag**, marks rows **internal** or not, and **excludes** them or counts them again. Each
  choice applies on the click and keeps the selection, so filing forty rows and then tagging
  the same forty is two clicks. Bulk edits stamp provenance exactly like single edits — they
  are your decisions, so rule re-files and transfer detection step around them — and a bulk
  category change comes back with an *Undo*.
- **Skarb for iPhone** ([ios/](ios/README.md)) — a native SwiftUI client on the same API,
  with the same password + TOTP sign-in and the same `skarb.session` cookie, so nothing is
  duplicated server-side. The web's five pages become five tabs behind an iOS 26 Liquid Glass
  tab bar: the overview (net worth, currency switcher, report window, the spending ring by
  category / account / tag, cashflow, accounts by institution, recent activity), the
  transaction list with every filter and the rule offer that follows a hand-made category
  change, the account editor including low-balance Telegram alerts, categories / tags / rules,
  and settings (connections, Monobank connect, notifications, security, appearance, server
  address). The palette and the per-theme color band are ported from `index.css` and
  `color.ts` rather than re-picked, so the two clients can only drift on purpose. Enable
  Banking onboarding and CSV import deliberately stay on the web, and the app points there.
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
  are grouped under its name, so the rename relabels them too — all of them, including any
  whose label had drifted from the connection's.
- Monobank accounts are grouped under their connection's name rather than a fixed
  "Monobank", and follow it on every sync. A card the bank started reporting after a rename
  used to arrive under the old name and sit in a group of its own.
- Removing a bank connection now deletes the accounts it created and their transactions,
  instead of leaving orphaned accounts behind. Manually created accounts are untouched, and
  the confirmation says exactly how much is going.
- Deleting a synced account makes it stay deleted. Sync rediscovers whatever the bank
  reports, so a deleted account used to reappear on the next round with its history
  re-fetched; the connection now remembers the provider-side id and skips it. Settings
  shows how many accounts a connection is skipping, and can bring them back.
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
  so a balance hovering at the limit cannot spam anyone. The bot is connected once in
  Settings → Notifications; the limit and the chat it pings live together on the account
  (the shared card alerts whoever tops it up) — chats that messaged the bot are picked by
  name, and a test message proves the wiring right where it is set. Sent and failed alerts
  appear in Sync activity. Setup walkthrough: [docs/ALERTS.md](docs/ALERTS.md).
- PostgreSQL storage via Docker Compose, EF Core migrations, `make`-driven workflow.
- Building the API builds the SPA into `wwwroot` when the frontend changed, so running from
  an IDE or a bare `dotnet run` never serves a stale bundle (`-p:SkipSpa=true` opts out).
