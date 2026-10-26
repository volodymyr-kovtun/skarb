# Skarb for iPhone

A native SwiftUI client for the same Skarb API the web app talks to. Nothing is duplicated
server-side: the app signs in with the same password + TOTP, carries the same
`skarb.session` cookie, and reads the same endpoints — so the two clients can never
disagree about what your money did.

| | |
|---|---|
| Language | Swift 6 (strict concurrency, main-actor by default), SwiftUI, Swift Charts |
| Minimum iOS | 26.0 — the tab bar, toolbars, toasts and the bulk-edit bar use Liquid Glass |
| Devices | iPhone, portrait |
| Bundle id | `app.subero.skarb` |
| Dependencies | none — no packages to resolve, no `pod install` |

## Running it

```bash
open ios/Skarb.xcodeproj
```

Pick an iPhone simulator (or your own device) and hit Run. **⌘U** runs the unit tests.

The app points at `https://skarb.subero.app` out of the box. To aim it somewhere else, tap
the server address under the sign-in form, or **Settings → Server**. Changing the server
drops the session cookie of the one you left, which is why signing in again is expected.

### Against a local backend

`make dev` in the repo root serves the API on `http://localhost:5178`. The app is allowed to
talk to plain HTTP on the local network (`NSAllowsLocalNetworking`), so that address works
from the simulator as-is. `make run` serves HTTPS on `:5179` with the .NET `localhost`
development certificate — a **Debug** build trusts that certificate for loopback hosts only,
so that address works too. Release builds validate certificates normally.

To drive the UI against real data without a second factor in the loop, run the API with the
development bypass:

```bash
SKARB_DEV_AUTH_BYPASS=true ASPNETCORE_ENVIRONMENT=Development dotnet run --project backend/Skarb.Api
```

### Tests and CI

`SkarbTests` is a Swift Testing bundle hosted by the app. Like the backend's tests it covers
logic rather than pixels: the `Domain` layer (filters, deep links, cash corrections, bulk
selection, grouping, report slices, CSV decoding, rule-offer arithmetic) and the view models,
which run against the real services over a `StubHTTPClient` that records every request — so a
test checks the path, query and JSON body the app actually sends.

`.github/workflows/ios.yml` builds the app and runs the tests on a macOS runner with the newest
Xcode 26, for every push that touches `ios/`. It is the only place the app is compiled outside
someone's Mac, so a change that has not been through it has not been built.

## Everything the web does

The web's five pages are five tabs, and every feature on them is here:

- **Overview** — net worth (hidden until you tap the eye, as on the web) with a currency switcher
  and a six-month trend, the report window (This month / Last month / 3M / 6M / YTD), earned /
  spent / invested / net against the matching earlier window, the spending ring by category,
  account or tag — every slice opens the transactions behind it — the in-and-out chart, accounts
  by institution with their share of net worth, and recent activity.
- **Activity** — search, filters (account, category, tag, uncategorized, internal, investments,
  hide internal), day-grouped rows that load the next page as you reach it, add / edit / delete,
  and the rule offer that follows a hand-made category change, with undo.
  - **Bulk edit.** *Select* (or long-press a row) turns rows into checkboxes, with *Select day*
    per heading and *Select all N* for everything the filters match across every page. The
    selection survives filter and search changes on purpose. The tab bar gives way to a glass bar
    that files the selection under a category, adds or removes a tag (or a new one), marks it
    internal or not, and excludes it or counts it again — each on the tap, keeping the
    selection, with *Undo* on a category change.
  - **Cash withdrawals.** A withdrawal that moved to a cash wallet says so on its row
    (*to cash*, *to cash as €45.00*), and its editor has the *Cash you received* block: the
    currency and amount you were actually handed, with today's-rate estimate as the placeholder.
    The wallet side explains itself and points at the withdrawal.
  - Rows show what a payment abroad or a currency exchange was worth on the other side.
- **Accounts** — grouped by institution, balances behind the same eye; **cash wallets** as their
  own section, one per currency (*Add currency*, or make a manual account a wallet from its
  editor); the account editor with name, color, the low-balance Telegram alert (*Find chats*,
  test message), *don't count*, archive and delete.
- **Categories** — spending / investments / income, tags, and the keyword rules behind them.
- **Settings** — connections (sync, full re-sync, rename, remove, restore deleted accounts),
  **Monobank** by token and its **instant-sync webhook**, **any Enable Banking bank** (and
  *Renew bank access* when the ~90-day consent runs out), **CSV import** from Files with the ZEN,
  PKO and generic presets, sync activity, Telegram notifications, security (password, recovery
  codes), appearance, server address, sign out.
- **First-run setup** — claiming an unclaimed instance with the setup token from the server log,
  enrolling the authenticator (a link that opens one on this iPhone, or a QR code for another
  device) and saving the recovery codes.

### Linking a bank from the phone

Enable Banking only redirects to the https URLs registered on your application, and the one you
registered for the web app — `https://<your server>/settings` — is the one the app uses too.
The bank opens in a private browser sheet; when it sends you back, the web page recognizes an
authorization the app started (the server marks those in the OAuth state) and hands it straight
to `skarb://enablebanking`, and the app finishes the link with its own session. Nothing extra to
register. See [docs/BANKS.md](../docs/BANKS.md).

## Architecture

```
Skarb/
  App/         composition root (AppContainer), router, root and tab views
  Core/
    Networking/  APIRequest values, the HTTPClient protocol and its URLSession implementation
    Models/      the API's DTOs, mirrored by hand from frontend/src/shared/api.ts
    Services/    one protocol per area (auth, ledger, transactions, accounts, categories,
                 tags, rules, connections, Enable Banking, sync, notifications, import)
                 and its live implementation over HTTPClient
    State/       shared observable stores: session, ledger, sync monitor, toasts
  Domain/      pure, nonisolated decisions — no SwiftUI, no networking — and the tests' main target
  Design/      palette, color normalization and the shared components
  Features/    one folder per tab: views, and an @Observable view model per screen or sheet
SkarbTests/    Swift Testing: Domain and view models over StubHTTPClient
```

The rules that keep it that way:

- **Nothing reaches for a singleton.** `AppContainer` is the only place an implementation is
  chosen; everything else receives protocols through its initializer. Views get the container
  from the environment only to build the view models of the sheets they present, through the
  `make…` factories that sit next to each feature.
- **Views render, view models decide, Domain knows.** A view model owns a screen's state and
  talks to services; anything that is a rule rather than plumbing — what a filter sends, when a
  cash correction is sent, how slices roll up, what a delete warning says — lives in `Domain` as
  a pure function with a test.
- **One answer to "is anyone home?"** Every 401 goes to `SessionStore.revalidate()`, which asks
  the server before signing anyone out — a wrong *current* password is a 401 too.
- **Everything reloads after a mutation.** `LedgerStore.invalidate()` re-reads the shared lists
  and bumps `revision`, which every screen's load is keyed on — the web's `refreshAll`.
- **Two apps, one contract.** Models mirror `api.ts` by hand; change both. The palette and the
  color-normalization band are ported from `index.css` and `color.ts` (see
  [`Design/Palette.swift`](Skarb/Design/Palette.swift) and
  [`Design/StoredColor.swift`](Skarb/Design/StoredColor.swift)), so the clients only drift on purpose.
  A CSV picked in the app is decoded exactly as a browser decodes it, because re-import dedupe
  is keyed on the text.

## Design

Type is the system face rather than the web's Bricolage Grotesque + Manrope: it keeps Dynamic
Type, the SF numeral set and the platform's own rhythm, which is the trade Apple's guidelines
ask for. Everything else that carries the brand — the ring mark, the paper background, the
card shapes, the hues — is the same.

The tab bar, toolbar buttons, toasts and the bulk-edit bar are the system's Liquid Glass, not a
blur imitating it: the app asks for the material and the behaviour
(`.tabBarMinimizeBehavior(.onScrollDown)`, `.glassEffect`) and lets the OS draw it.

## Shipping to TestFlight

[TESTFLIGHT.md](TESTFLIGHT.md) is the full walkthrough — enrolling in the Apple Developer
Program, creating the App Store Connect record, archiving, uploading, and adding testers —
plus the free seven-day route if you only want it on your own phone today.

The short version, once you're enrolled: set your team under **Signing & Capabilities**,
create the app record against `app.subero.skarb`, then **Product → Archive → Distribute App →
TestFlight & App Store → Upload**. Internal testing needs no App Review, so the build is
installable as soon as it finishes processing. Bump `CURRENT_PROJECT_VERSION` for every
upload — App Store Connect rejects a repeated build number.
