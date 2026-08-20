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
category: a visible count of what still needs one, and a fast way to work
through the list.

Turning each manual decision into a rule is done — correcting a category offers
the keyword, shows what it matches, and files the past on one click. What is
left is being *pointed at* the pile in the first place.

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
- Optionally a weekly digest over the Telegram channel that low-balance alerts
  already use ([docs/ALERTS.md](ALERTS.md)) — though a nudge about bookkeeping is
  easier to ignore than one about money running out, so in-app first still holds.

**Open questions.**

- What counts as needing attention? Internal transfers and excluded rows should
  not, and neither should a transaction that is minutes old and might still be
  a pending hold the bank will restate.
- Is there a point where a merchant with no obvious category should be allowed
  to stay uncategorized permanently, instead of being asked about forever?
- The review queue wants a category picker on the row itself rather than the
  edit modal, with the rule offer behind it. That is a second entry point into
  a flow that already works — worth confirming it should be the *only* one.

---

## Shared expenses and reimbursements

**What.** When you front a bill and people pay you back, Skarb should count what you
actually spent. You pay $500 for dinner, friend A sends $100 and friend B sends $150 —
the restaurant cost you $250, and that is the number every chart should show.

**Why.** Today it shows $500, and the $250 coming back is counted as income on top. The
outgoing lands in Eating out at its full size; the two repayments are recognised as P2P
transfers and filed under *Transfers from people*, which is an income-kind category. So a
single dinner inflates the month twice: spending by $250 and earnings by $250. The
spending donut then says restaurants cost double what they did, which is exactly the
number you would use to decide whether to eat out less.

Neither existing escape hatch fixes it. Excluding the two repayments stops the phantom
income but leaves the $500 standing. Excluding the dinner hides $250 of real spending. And
the amount cannot simply be edited down, deliberately — on a synced transaction it is the
bank's number, and the ledger is worth more when it matches the statement.

**How, roughly.**

- A link from a repayment to the expense it repays. This is structurally what
  `TransferGroupId` already does for the two legs of an internal transfer, so both the
  data shape and the "these belong together" affordance have a precedent to follow.
- The expense reports **net of what came back**, while still showing the bank's amount —
  `−$500, $250 settled`. The repayments stop counting as income, because they never were:
  that money was always yours.
- Suggest the link rather than requiring it. An incoming P2P transfer, smaller than an
  expense from the last few days, is nearly always a repayment — and P2P is already
  detected (`transfers-in`). Internal-transfer detection sets the pattern: propose the
  match, mark it, let the user un-mark it.
- Optionally mark an expense as shared when it lands, with the share you expect back, so
  the outstanding amount is visible before anyone has paid.

**Open questions.**

- **Which month absorbs it?** Dinner in August, repaid in September. Netting it into
  August silently rewrites a month you have already read and reasoned about; netting it
  into September can push a category below zero. Accounting has argued about this for
  centuries and neither answer is free — pick one deliberately and say which it is.
- What if only one friend pays, or nobody does? The unsettled part has to stay your
  spending, which argues for netting as money arrives rather than promising a share
  up front.
- Should a repayment inherit the expense's category, so the netting happens inside
  *Eating out* rather than as a separate line that has to be mentally subtracted?
- Cash never shows up in a bank feed. Does this need a manual "settled in cash" that
  writes down part of the expense with no matching transaction?
- Where does it stop? Tracking what each person owes you over time is Splitwise's job.
  The line worth holding is that Skarb reports **your** money honestly — it is not a
  ledger of other people's debts.
