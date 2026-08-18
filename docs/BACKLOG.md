# Backlog

Things worth building that are not built yet. Nothing here is a commitment or a
schedule — it is the list to pick the next thing from, and somewhere to put an
idea before it evaporates.

Shipped features move to [CHANGELOG.md](../CHANGELOG.md) and leave this file.

Each entry says **what** it is, **why** it is worth doing, and what is already
known about **how** — including the questions that have to be answered before
any code is written. An entry with no open questions is usually one that has
not been thought about hard enough.

---

## Family support

**What.** More than one person using the same Skarb instance: a household sees
its shared money together, while each person keeps their own accounts private
unless they say otherwise.

**Why.** Household money is the case the current design cannot express at all.
Today Skarb is single-owner by construction — one `OwnerAccount` row, claimed
once through the setup token, and a deny-by-default policy that knows only
"signed in" or "not". A couple running one instance today shares one password
and one undivided ledger, which is both a privacy problem and a reporting one:
"our spending" and "my spending" are different questions and the app can only
answer one of them.

**How, roughly.**

- `OwnerAccount` becomes a small user table with an invite flow instead of a
  one-shot setup token. Sign-in, TOTP, recovery codes and the lockout policy
  stay exactly as they are — they already sit behind interfaces that do not know
  about HTTP or EF, so this is mostly about which row they load.
- Accounts get a visibility: private to one person, or shared with the
  household. Transactions inherit it from their account. Every report then takes
  a scope — mine or ours — instead of assuming there is only one.
- Bank connections stay personal. Enable Banking's free tier covers accounts you
  own, so a second person links their own consent under their own login rather
  than being added to someone else's.
- Categories, tags and auto-categorization rules are probably household-wide;
  splitting them per person would double the upkeep for little gain. Worth
  confirming before building.

**Open questions.**

- Does a partner see the *balance* of a private account, or nothing at all?
- Internal-transfer detection currently means "between my own accounts". Money
  moving between two people in the same household is internal to the household
  but real income and real spending to each person. Which one wins depends on
  the scope being viewed — that logic needs designing before it is coded.
- Can a household member be read-only (a teenager, an accountant)?

---

## Unrecognized transaction reminder

**What.** A steady nudge toward the goal that **every** transaction carries a
category: a visible count of what still needs one, a fast way to work through
the list, and an offer to turn each manual decision into a rule so the same
merchant never has to be sorted twice.

**Why.** Auto-categorization gets most rows right — keyword rules first, then
MCC for card payments — and quietly leaves the rest uncategorized. Nothing ever
points at them. They surface only as a grey "Uncategorized" wedge in the
spending donut and a filter you have to remember to check, so the pile grows and
every number on the overview gets a little less true.

**How, roughly.**

- A count where it will actually be seen: on the overview, and next to
  Transactions in the sidebar. It disappears at zero, which makes zero the
  visible goal.
- A review queue that opens the oldest uncategorized transaction, takes one
  keystroke per category, and moves to the next. Grouping by merchant first, so
  eleven Żabka rows are one decision rather than eleven.
- After a manual categorization, offer the rule: *"always file BIEDRONKA under
  Groceries?"*. The rule engine and `POST /api/rules` already exist; this is the
  missing prompt that would make them accumulate on their own.
- Optionally a weekly digest once notifications exist at all — Skarb sends
  nothing today, and that is a feature, so any reminder should be in-app first.

**Open questions.**

- What counts as needing attention? Internal transfers and excluded rows should
  not, and neither should a transaction that is minutes old and might still be
  a pending hold the bank will restate.
- Should a rule created from one transaction be applied backwards to matching
  older ones? "Apply to uncategorized" already exists as a manual action —
  perhaps the offer is simply to run it.
- Is there a point where a merchant with no obvious category should be allowed
  to stay uncategorized permanently, instead of being asked about forever?
