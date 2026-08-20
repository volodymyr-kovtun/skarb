# Low-balance alerts to Telegram

The scenario this was built for: a shared Monobank card that someone else tops up. When
the balance drops below the limit you set, the person responsible for it gets a Telegram
message — before the card goes empty at a checkout, and without anyone opening Skarb.

How it behaves:

- **One message per drop.** The alert fires when the balance crosses below the limit,
  then stays quiet. While the account stays low, a reminder goes out once a day. As soon
  as the balance recovers to the limit or above, the alert re-arms for the next drop.
- **Per account.** Every account gets its own limit (or none) in its own currency, and
  can send to its own chat — the shared card pings your partner, your own account pings
  you. Accounts without a chat of their own use the default chat from Settings.
- **As fast as your sync.** With the [Monobank webhook](BANKS.md) enabled, the alert
  lands seconds after the payment that crossed the line. Otherwise it goes out at the
  next background sync round.
- Sent and failed alerts show up in **Settings → Sync activity**, so "did it actually
  send?" has an answer.

Skarb talks to `api.telegram.org` directly from your machine; no third party sits in
between, and the bot token lives only in your local database.

## Setup (~3 minutes)

### 1. Create a bot

1. In Telegram, open **[@BotFather](https://t.me/BotFather)** and send `/newbot`.
2. Give it a name (e.g. *Skarb Alerts*) and a username (must end in `bot`).
3. Copy the token BotFather prints — it looks like `1234567890:AAF3xy…`.

The bot is yours alone. Anyone can *find* it by username, but it sends alerts only to
the chats you configure.

### 2. Connect it in Skarb

**Settings → Notifications** → paste the token. Skarb validates it and shows the bot's
@username.

### 3. Pick who gets the messages

A Telegram bot cannot start a conversation — the recipient has to make first contact:

1. The recipient (your partner, you, …) opens the bot by its @username and presses
   **Start** (any message works).
2. In Skarb, click **Find chats** — everyone who messaged the bot in the last day is
   listed. Click the right one and **Save**.
3. **Send test message** confirms the wiring end to end.

The *default chat* receives alerts for every account that doesn't name its own.

### 4. Set limits on accounts

**Accounts → pick an account → Low balance alert**: enter the limit in the account's
currency — e.g. `5000` on a UAH card. Optionally give the account its own chat ID
(step 3 shows the IDs) so this one account alerts someone else.

Leaving the limit empty turns the alert off for that account. Archived accounts never
alert — they stop syncing, so their balance means nothing.

## Notes

- If the balance is **already** below a limit you just set, the alert goes out right
  away — a fresh limit is judged immediately, not at the next sync.
- A limit of `0` means "tell me when the account goes negative" — useful with an
  overdraft.
- Group chats work too: add the bot to a group, have someone write in it, and **Find
  chats** will list the group (its ID is negative). Family channel instead of a DM.
- If sending fails (wrong chat ID, revoked token), the failure is logged in Sync
  activity and Skarb retries at the next balance change or sync round.
