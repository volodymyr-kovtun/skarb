# Skarb for iPhone

A native SwiftUI client for the same Skarb API the web app talks to. Nothing is duplicated
server-side: the app signs in with the same password + TOTP, carries the same
`skarb.session` cookie, and reads the same endpoints — so the two clients can never
disagree about what your money did.

| | |
|---|---|
| Language | Swift 6, SwiftUI, Swift Charts |
| Minimum iOS | 26.0 — the tab bar, toolbars and toasts use Liquid Glass, which is iOS 26 only |
| Devices | iPhone, portrait |
| Bundle id | `app.subero.skarb` |

## Running it

```bash
open ios/Skarb.xcodeproj
```

Pick an iPhone simulator (or your own device) and hit Run. No packages to resolve, no
`pod install` — the project has no third-party dependencies.

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

## What's here, and what stayed on the web

Five tabs, mirroring the web's five pages:

- **Overview** — net worth with a currency switcher and a six-month trend, the report-window
  control (This month / Last month / 3M / 6M / YTD), earned / spent / invested / net, the
  spending ring broken down by category, account or tag, the in-and-out chart, accounts
  grouped by institution, and recent activity. Every slice of the ring opens the
  transactions behind it.
- **Activity** — search, filters (account, category, tag, uncategorized, internal,
  investments, hide-internal), day-grouped rows, add / edit / delete, and the rule offer that
  follows a hand-made category change, with undo.
- **Accounts** — grouped by institution, with the account editor: name, color, low-balance
  Telegram alert (including *Find chats* and a test message), *don't count*, archive, delete.
- **Categories** — spending / investments / income, tags, and the keyword rules behind them.
- **Settings** — connections (sync, full re-sync, rename, remove, restore deleted accounts),
  Monobank token connect, Telegram notifications, security (password, recovery codes),
  appearance, server address, sign out.

Two of the web's flows deliberately did **not** come across, because both are one-time
desktop errands that a phone makes worse:

- **Enable Banking onboarding** — pasting a PEM private key and completing an OAuth redirect.
- **CSV import** — column mapping against a statement file.

Settings says so, and points at the web app. First-run *setup* is the same story: claiming an
unclaimed instance needs the setup token from the server log, so the app explains that rather
than showing a form nobody can complete from a phone.

## Design

The palette, the radii and the color-normalization band are ported one-for-one from
`frontend/src/index.css` and `frontend/src/shared/color.ts` — see
[`Skarb/Design/Palette.swift`](Skarb/Design/Palette.swift) and
[`Skarb/Design/StoredColor.swift`](Skarb/Design/StoredColor.swift). Only those two files know
a hex code, so the two apps can only drift on purpose.

Type is the system face rather than the web's Bricolage Grotesque + Manrope: it keeps Dynamic
Type, the SF numeral set and the platform's own rhythm, which is the trade Apple's guidelines
ask for. Everything else that carries the brand — the ring mark, the paper background, the
card shapes, the hues — is the same.

The tab bar, toolbar buttons and toasts are the system's Liquid Glass, not a blur imitating
it: the app asks for the material and the behaviour (`.tabBarMinimizeBehavior(.onScrollDown)`,
`.glassEffect`) and lets the OS draw it.

## Shipping to TestFlight

[TESTFLIGHT.md](TESTFLIGHT.md) is the full walkthrough — enrolling in the Apple Developer
Program, creating the App Store Connect record, archiving, uploading, and adding testers —
plus the free seven-day route if you only want it on your own phone today.

The short version, once you're enrolled: set your team under **Signing & Capabilities**,
create the app record against `app.subero.skarb`, then **Product → Archive → Distribute App →
TestFlight & App Store → Upload**. Internal testing needs no App Review, so the build is
installable as soon as it finishes processing. Bump `CURRENT_PROJECT_VERSION` for every
upload — App Store Connect rejects a repeated build number.
