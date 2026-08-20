# Connecting your banks to Skarb

Verified August 2026. Three banks, three different realities:

| Bank | Method | Auto-sync | Effort |
|---|---|---|---|
| **Monobank** 🇺🇦 | Official personal API, direct | ✅ hourly, **instant with webhook** | 2 minutes |
| **PKO Bank Polski** 🇵🇱 | Enable Banking (licensed PSD2 aggregator, free personal tier) | ✅ hourly | ~20 minutes, once |
| **ZEN.com** | CSV statement import | ❌ manual (monthly file) | 1 minute per import |

---

## 1. Monobank — direct API (easiest)

Monobank publishes an official personal API and explicitly allows self-hosted personal
use (running a *service* for other people requires their corporate API — a family app
for yourself is fine).

### Get a token

1. Open **https://api.monobank.ua/** in a browser.
2. Scan the QR code with the Monobank app and confirm.
3. Copy the token from the page.
4. In Skarb: **Settings → Connect Monobank** → paste → **Connect & sync**.

Accounts (including jars) and the last 31 days of statements appear automatically.
The token can be revoked/re-issued on the same page at any time.

### What to expect

- **Rate limits are real:** 1 statement request per 60 seconds, max 31 days + 500
  transactions per request. Skarb queues and paces requests automatically, so the *first*
  sync takes about a minute per account — later syncs only fetch what's new.
- Amounts arrive in minor units with credit limit baked into the balance; Skarb already
  corrects for both and shows own funds.
- Skarb refreshes `hold` (pending) transactions on later syncs, deduplicating by
  transaction id.

### Instant sync (webhook) — "I paid → it's in Skarb"

Monobank can push every statement item to Skarb the moment it happens. It needs a public
HTTPS URL that reaches your machine. For personal use, a tunnel is the safe way:

```bash
# Option A: Cloudflare Tunnel (free)
brew install cloudflared
cloudflared tunnel --url http://localhost:5178
```

```bash
# Option B: Tailscale Funnel
tailscale funnel 5178
```

Both print a public `https://…` URL. Then in Skarb: **Settings → (Monobank connection) →
webhook icon** → paste that base URL → **Enable**. Skarb registers
`<your-url>/api/webhooks/monobank/<connection-id>` with Monobank and answers the
validation ping automatically.

Notes:
- Monobank retries failed deliveries after 60 s and 600 s, then **disables the webhook** —
  if your tunnel was down for a while, just enable it again from the same dialog.
- The URL contains an unguessable connection id (Monobank sends no signature for
  personal webhooks); the endpoint only accepts statement items for known accounts.
- Webhook or not, the 30-minute background sync still runs as a safety net.

---

## 2. PKO Bank Polski — via Enable Banking

### Why not…

- **PKO's own PSD2 / PolishAPI** (developers.pkobp.pl): production access requires a
  licensed TPP (AISP registration with a regulator + eIDAS QWAC/QSealC certificates).
  Not realistic for an individual.
- **GoCardless Bank Account Data (ex-Nordigen)** — the old community favourite —
  **stopped accepting new signups in July 2025**. If you happen to have an old account it
  still works (institution `PKO_BPKOPLPW`, 50 free connections), but you can't register today.
- **Salt Edge / Tink / Plaid**: B2B contracts only, no personal tier.

**Enable Banking** (enablebanking.com) is a licensed Finnish AISP with 2,500+ European
banks including PKO BP, and its **"restricted production" mode is free**: you link your own
bank accounts in their portal and your app can access exactly those accounts — perfect for
personal finance.

### One-time setup (~20 minutes)

1. **Register** at https://enablebanking.com (personal account is fine).
2. **Generate an RSA key pair** on your machine:

   ```bash
   openssl genrsa -out skarb_eb_private.pem 2048
   openssl rsa -in skarb_eb_private.pem -pubout -out skarb_eb_public.pem
   ```

3. In the Enable Banking **Control Panel → API Applications → Register new application**:
   - Environment: **Production**
   - Upload `skarb_eb_public.pem` (the public key)
   - Redirect URL: `https://localhost:5179/settings` — must be **https** (Enable Banking rejects
     plain http) and match exactly what Skarb sends; add `https://localhost:5173/settings` too if you
     use `make dev`
   - Copy the generated **Application ID**
4. The app activates in **restricted mode** ("linked accounts"): in the portal, follow
   *linked accounts* and authenticate to **your own PKO BP** account there once, so the API
   is allowed to serve it.
5. In Skarb: **Settings → Connect PKO / other bank**:
   - Name: `PKO Bank Polski`
   - Application ID: from step 3
   - Private key: paste the contents of `skarb_eb_private.pem`
   - **Continue** → pick *PKO Bank Polski* from the PL list → you're redirected to PKO,
     confirm with the IKO app → you land back in Skarb and the first sync starts.

### What to expect

- Consent is PSD2-standard: **~90 days**, then the bank asks you to re-authorize
  (Skarb shows the expiry date on the connection card — just click the bank again when it lapses).
- SCA happens in the IKO mobile app during authorization.
- First sync pulls up to 90 days of history; PSD2 rate limits (typically 4 unattended
  calls/day per account) are far above Skarb's 30-minute cycle needs.
- The same connector works for **any other Enable Banking bank** — the picker in Skarb can
  list every supported institution across Europe (choose "All countries") or filter per
  country. Revolut, Wise, Pekao, mBank, ING, Millennium, … Add each as a separate connection.

### Fallback: iPKO CSV export

iPKO web banking exports history as CSV: *Historia rachunku → Eksport danych → CSV*.
Import it via **Settings → Import CSV** with the **PKO iPKO** preset (verify the column
numbers against your file — PKO has changed the layout over the years).

---

## 3. ZEN.com — CSV import (no API exists)

The honest result of the research: **ZEN has no path to automatic sync today.**

- ZEN's only developer API is the merchant payment gateway (docs.zen.com) — it accepts
  payments for shops; it cannot read your personal account.
- As an EMI, ZEN (UAB ZEN.COM, Lithuania) is absent from every aggregator's coverage:
  GoCardless Bank Account Data, Enable Banking (checked against their live ASPSP feed —
  2,664 institutions, no ZEN) and Salt Edge, checked August 2026.
- No community/reverse-engineered client exists either (and using one would risk your account).

### Monthly routine (about a minute)

1. ZEN app → **Wallet → pick a currency → ⋯ (top right) → Statements → Generate Statement**
   → format **CSV**, period e.g. *this month*. Statements are **per currency** — export one
   file per currency you use.
2. In Skarb, create a manual account per ZEN currency once (**Accounts → Add manual
   account**, bank "ZEN").
3. **Settings → Import CSV (ZEN, …)** → choose the ZEN account, preset **ZEN.com
   statement**, pick the file, check the column mapping against the file's header
   (first column = 0), **Import**.

Re-importing an overlapping period is safe — Skarb deduplicates rows it has already seen.

Worth re-checking twice a year: if ZEN ever shows up in Enable Banking's coverage
(https://enablebanking.com/api/aspsps), the PKO connector above will work for ZEN too,
no code changes needed.

---

## How syncing works inside Skarb

- A background service syncs every linked connection every **hour**
  (`Sync:IntervalMinutes` in `appsettings.json`; `0` disables it).
- **`Sync:StartDate` is where the ledger opens** — unset by default, so out of the box you
  get whatever history each bank offers. Give it a date and nothing older ever enters Skarb:
  connectors stop asking their banks for it, and anything a bank volunteers anyway is dropped
  on the way in, including on a full re-sync. Deleting the earlier transactions once therefore
  makes them stay deleted. The boundary is midnight **UTC**, like every other date boundary
  in Skarb. It is a per-instance choice, so keep it out of the tracked `appsettings.json`:

  ```bash
  dotnet user-secrets set "Sync:StartDate" "2026-08-01" --project backend/Skarb.Api
  ```

  User secrets are read in Development only; elsewhere set `Sync__StartDate=2026-08-01` in
  the environment (see [DEPLOYMENT.md](DEPLOYMENT.md)).
- **Sync now** in the sidebar (or per connection in Settings) triggers the same thing
  on demand; progress and results appear under **Settings → Sync activity**.
- New transactions are auto-categorized: your keyword rules first
  (**Categories → Auto-categorization rules**), then Monobank MCC codes, then a few
  heuristics (person-to-person rails → "Transfers to/from people", small anonymous credits →
  cashback). ~190 rules for the Polish market and common global merchants are seeded; edit or
  delete any of them. Rules are **direction-aware** (an income category only matches money
  in) and match **whole words** on transfers/notes, plain substrings on glued card descriptors.
  Everything can be recategorized by clicking the transaction.
- **PKO sends no MCC codes** through Enable Banking, so for PKO only rules and the bank's
  type codes (`CARD-ATM`, `MOBILE-PAYMENT-C2C`, `FEE`, …) drive categorization. Card
  descriptors arrive as `CITY+MERCHANT+COUNTRY` glued together; Skarb cleans them
  (`WARSZAWAJMP S.A. BIEDRONKA 7184PL` → `JMP S.A. BIEDRONKA 7184`) and keeps the raw text
  in the note for search.
- After adding rules, **Categories → Apply to uncategorized** runs them over existing
  transactions without touching anything you categorized by hand. After a mapping
  improvement, the ⟲ **Full re-sync** button on a connection re-fetches the whole history and
  refreshes existing rows.
- Currency exchanges between your own accounts (PKO `FX… EUR/PLN` legs) are paired by the
  bank's shared reference and marked internal, even though the two legs have different
  amounts and currencies.
- After every sync/import Skarb runs **internal-transfer detection**: counter-IBANs matching
  your own accounts, and opposite-amount pairs on two accounts within 72 hours, are marked
  *internal* and excluded from all metrics. Cross-currency transfers (e.g. PLN→EUR top-ups)
  can't be matched reliably — tick "Internal transfer" on the transaction to mark those.
- Transactions in **investment-kind categories** (Brokerage, Crypto — `ibkr`/`interactive
  brokers` rules are pre-seeded) count as "Invested" on the dashboard, not as spending.
- Balances in foreign currencies are converted to PLN for the dashboard using daily
  ECB-sourced rates (open.er-api.com, cached 12 h); per-account balances always stay in
  the account's own currency.

## Security checklist

- The PostgreSQL database holds your bank tokens and transactions — it stays on your machine
  (Docker volume `skarb_pgdata`). Back it up like you'd back up a password database.
- Never expose ports 5178/5432 directly to the internet. The Monobank webhook is the only
  feature that needs public reachability, and a Cloudflare/Tailscale tunnel to that one
  path is enough.
- Monobank token = read access to all your statements. Revoke it at https://api.monobank.ua/
  if you ever suspect a leak; Enable Banking access dies with the 90-day consent and can be
  revoked in their portal or at the bank.
