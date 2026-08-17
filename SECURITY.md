# Security policy

Skarb handles bank access tokens and financial history, so security matters here even
though it is a self-hosted, single-user tool.

## Threat model in short

- Skarb is meant to run on a machine you control, on `localhost`, behind no public port.
- Bank tokens/keys are stored in your local PostgreSQL database in plain text. Anyone with
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
