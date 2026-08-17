# Security policy

Skarb handles bank access tokens and financial history, so security matters here even
though it is a self-hosted, single-user tool.

## Threat model in short

- Skarb is designed for a machine you control. It can be deployed behind HTTPS — see
  [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — but a private network (Tailscale) is safer than
  a public URL when you only need access from your own devices.
- **Access control is single-owner.** One account, claimed once via a setup token printed to
  the server log, protected by a password (PBKDF2-HMAC-SHA512) and a mandatory TOTP second
  factor, with single-use recovery codes. There is no signup and no password reset by email:
  recovery codes are the only fallback. Repeated failures lock the account; the credential
  endpoints are additionally rate-limited per IP.
- Every API endpoint requires a session by default. The exceptions are explicit: the SPA
  shell and its assets, the sign-in/setup endpoints, and the Monobank webhook.
- Sessions are `HttpOnly`, `Secure` (outside Development), `SameSite=Lax` cookies encrypted
  with an ASP.NET data-protection key ring. Changing the password rotates a security stamp
  that invalidates every other live session.
- **A TOTP secret is stored in the database unencrypted**, as are bank tokens. This is a
  deliberate trade: anyone who can read the database already holds your bank credentials, so
  encrypting the TOTP secret would add a permanent-lockout failure mode without changing the
  outcome of a database compromise.
- Bank tokens/keys are stored in your PostgreSQL database in plain text. Anyone with
  access to that database (or to the machine's Docker volume) can read them. Treat the
  database like a password vault: full-disk encryption, restricted user account, backups
  encrypted.
- The only endpoint that ever needs public reachability is the optional Monobank webhook.
  Use a tunnel (Cloudflare Tunnel / Tailscale Funnel) scoped to that path; never port-forward
  the whole app. The webhook URL embeds an unguessable connection id, and the handler only
  accepts statement items for accounts it already knows.
- Enable Banking access is read-only and expires with the PSD2 consent (~90 days); it can be
  revoked at the bank or in the Enable Banking portal at any time.
- Skarb never initiates payments or transfers.

## If a key or token leaks

Private keys and API tokens must never be committed. To check:

```bash
git log --all --diff-filter=A --name-only -- '*.pem' '*.key'
```

If one was committed, **rotate first, clean history second** — the key is public the moment
it is pushed, and rewriting history does not un-publish it:

1. Revoke it at the source (new key pair in the Enable Banking Control Panel; reissue the
   Monobank token at <https://api.monobank.ua/>).
2. Reconnect the affected bank in Skarb with the new credentials.
3. Remove it from the working tree and history:

   ```bash
   git rm --cached path/to/key.pem
   ```

   ```bash
   git filter-repo --invert-paths --path path/to/key.pem
   ```

   then force-push and ask GitHub Support to expire cached views of the old commits.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Email the maintainer (address on the GitHub profile) with:

- a description of the issue and its impact,
- steps to reproduce or a proof of concept,
- the commit or version affected.

You'll get an acknowledgement within a few days. Fixes for confirmed issues will be
released as soon as practical, and you'll be credited in the changelog if you wish.

## Supported versions

Only the latest commit on `main` is supported.
