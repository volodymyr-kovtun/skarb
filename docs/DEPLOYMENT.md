# Deploying Skarb

Skarb was built to run on `localhost`. Putting it on a public address changes the threat
model completely: the database holds live bank tokens and your full transaction history,
and anyone who can reach the URL is one bug away from all of it.

This guide covers what changes when you deploy, and the one licensing question that
catches people out.

---

## 1. Can I even deploy this? (Enable Banking, free tier)

**Yes — for yourself. Not for other people.**

Enable Banking's free "restricted production" mode is what Skarb's PKO BP / European bank
connector runs on. Their [Terms of Service](https://enablebanking.com/terms/) say two
things that matter here:

| Rule | What it means for you |
|---|---|
| API use in Production is **limited to Linked Accounts** | Only the accounts you personally authenticated in the Enable Banking portal are reachable. A stranger signing up could not connect their bank even if they wanted to. |
| Production access is for **"evaluation purposes or the personal use of private individuals"**, free of charge | Running your own instance for your own accounts is exactly this. |
| You may not "make accessible to any third party" the API | Opening Skarb up for other people to use — even free, even friends — is outside the free tier and needs a commercial agreement with Enable Banking. |

So the deployment that is fine is: **one instance, one owner, your own linked accounts,
reachable from your phone.** That is precisely what the single-owner auth in Skarb
enforces — there is no signup, and the instance can only ever have one account.

What would *not* be fine: turning Skarb into a service other people sign into with their
own banks. That needs a licensed-TPP arrangement (or Enable Banking's paid tier), not a
code change.

Two practical notes:

- **The number of linked accounts per application may be limited.** If you add many
  accounts, check the portal.
- **Consent still expires every ~90 days.** Deploying does not change that; you re-authorize
  from the Settings page as before.

**Monobank** is separate and simpler: their personal API explicitly allows self-hosted
personal use. Running a service for other people would require their corporate API.

---

## 2. Before the first public deploy: rotate your keys

If your Enable Banking private key has ever been committed to a repository — check with
`git log --all --diff-filter=A -- '*.pem'` — treat it as compromised:

1. Register a **new** key pair in the Enable Banking Control Panel and remove the old one.
2. Reconnect the bank in Skarb with the new key.
3. Purge the old key from git history (see [SECURITY.md](../SECURITY.md)).

The same applies to a Monobank token that has leaked: reissue it at
<https://api.monobank.ua/>.

---

## 3. Claiming the instance

Skarb starts unowned. On first boot with no owner it prints a **setup token**:

```
┌───────────────────────────────────────────────────────────────┐
│  Skarb has no owner yet — open the app to claim it.           │
│  Setup token:  ABCD1234...                                    │
└───────────────────────────────────────────────────────────────┘
```

Read it from the server log (`docker logs skarb`, `journalctl -u skarb`), open the app, and
complete the three-step setup: credentials → authenticator app → recovery codes.

The token exists so that a deployed-but-unclaimed instance cannot be taken over by whoever
loads the URL first. Set your own instead of using the generated one with
`Auth__SetupToken`. Once setup completes, the token stops working.

**Save the recovery codes.** They are shown once and are the only way back in if you lose
your authenticator.

---

## 4. Configuration

Everything is standard ASP.NET configuration — `appsettings.json`, or `__`-separated
environment variables, which is what you want in a container.

| Variable | Why it matters |
|---|---|
| `ConnectionStrings__Default` | Point at your real database. **Change the default `skarb/skarb` password.** |
| `Auth__SetupToken` | Choose your own first-run token instead of reading it from logs. |
| `Auth__KeyRingPath` | **Mount this as a volume.** These keys encrypt the session cookie; if they vanish on restart, every session dies. Defaults to `<contentroot>/keys`. |
| `Auth__SessionDays` | How long a session lasts (default 14, sliding). |
| `Auth__MaxFailedAttempts` / `Auth__LockoutMinutes` | Lockout policy (default 5 attempts → 15 minutes). |
| `Auth__AllowedOrigins__0` | Only needed if you serve the SPA from a different origin than the API. |
| `ASPNETCORE_ENVIRONMENT` | Must **not** be `Development` in production — that is what switches cookies to `Secure`-always and stops unexpected exception messages reaching the client. |

Example:

```bash
docker run -d --name skarb \
  -e ASPNETCORE_ENVIRONMENT=Production \
  -e ConnectionStrings__Default="Host=db;Database=skarb;Username=skarb;Password=<strong>" \
  -e Auth__SetupToken="$(openssl rand -hex 16)" \
  -e Auth__KeyRingPath=/keys \
  -v skarb_keys:/keys \
  -p 127.0.0.1:5178:8080 \
  skarb
```

Note the `127.0.0.1:` binding — the app should sit behind a reverse proxy, not face the
internet directly.

---

## 5. HTTPS and the reverse proxy

Skarb must be served over HTTPS in production. Cookies are marked `Secure` outside
Development, so **the session simply will not work over plain HTTP.**

Put Caddy, nginx or Cloudflare Tunnel in front and make sure it forwards the standard
headers — the app reads `X-Forwarded-Proto` to know the request was HTTPS:

```
skarb.example.com {
    reverse_proxy 127.0.0.1:5178
}
```

Caddy sets `X-Forwarded-Proto` and `X-Forwarded-For` by default. For nginx, set them
explicitly.

If your proxy is not on the same host as the app, also configure
`ForwardedHeadersOptions.KnownProxies` — otherwise ASP.NET ignores headers from an
untrusted hop.

---

## 6. Update the Enable Banking redirect URL

The redirect URL Skarb sends must match one registered in your Enable Banking application
exactly. Moving from `https://localhost:5179/settings` to a real domain means adding:

```
https://skarb.example.com/settings
```

in **Control Panel → API Applications → your app**. Keep the localhost entry too if you
still develop locally.

The session cookie uses `SameSite=Lax` specifically so it survives the bank's redirect back
to `/settings` — a stricter setting would silently sign you out at the last step of linking
a bank.

---

## 7. What is exposed, and what is not

| Path | Access |
|---|---|
| `/`, `/assets/*` | Public — the SPA shell and bundle. No data. |
| `/api/auth/session`, `/api/auth/login`, `/api/auth/setup*` | Public by necessity; rate-limited per IP. |
| `/api/webhooks/monobank/{connectionId}` | Public — Monobank calls it, not a browser. Guarded by the unguessable connection id; only accepts items for accounts already known to that connection. |
| **Everything else under `/api`** | Requires a session. This is enforced by a deny-by-default authorization policy, so new endpoints are protected automatically. |
| `/openapi/*` | Development only. |

---

## 8. Backups

The database is the whole app: transactions, categories, and your bank tokens.

```bash
docker exec skarb-postgres pg_dump -U skarb skarb | gzip > skarb-$(date +%F).sql.gz
```

Encrypt the dump — it contains live bank credentials. Back up the data-protection key ring
volume too if you would rather not sign in again after a restore.

---

## 9. A realistic alternative

If the only thing you want is to reach Skarb from your phone, you do not have to expose it
to the internet at all. **Tailscale** puts the app on a private network shared only by your
own devices:

```bash
tailscale serve 5178
```

That removes the public attack surface entirely, and the auth in this app then acts as a
second layer rather than the only one. It is the setup I would recommend unless you
specifically need a public URL.
