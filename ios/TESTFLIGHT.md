# Getting Skarb onto your iPhone

Everything between "it builds in the simulator" and "it's on my phone", in order.

There are two routes. The first is free and takes ten minutes; the second costs $99/year and
is what you want if the app is going to stay on your phone.

| | Free personal team | Apple Developer Program |
|---|---|---|
| Cost | nothing | $99 / year |
| How the app arrives | Xcode, over a cable or Wi-Fi | TestFlight |
| How long it keeps working | **7 days**, then it stops launching | 90 days per build, refreshed on every upload |
| Needs a Mac each time | yes — rebuild weekly | no |
| Other people can install it | no | yes, up to 100 internal / 10,000 external |

Start with the free route today to confirm the app works on your actual phone, then enrol and
move to TestFlight. The steps overlap, so nothing is wasted.

---

## Route A — free, on your own phone, in ten minutes

Signing in to Xcode with an ordinary Apple Account (no paid membership) gives you what Apple
calls a **Personal Team**. It can sign apps for your own devices, with limits: profiles expire
after 7 days, at most 10 App IDs, and at most 3 registered devices.

1. **Xcode → Settings → Accounts → +** → Apple Account. Sign in with your Apple ID.
2. Open `ios/Skarb.xcodeproj`, select the **Skarb** target → **Signing & Capabilities**.
3. Tick **Automatically manage signing**, and set **Team** to `<your name> (Personal Team)`.
4. Change the **Bundle Identifier** to something unique to you — a free team can't always
   claim `app.subero.skarb`. Anything like `app.subero.skarb.<yourname>` works. (You'll set it
   back to `app.subero.skarb` for the real thing.)
5. Plug the iPhone in, unlock it, and pick it in Xcode's destination menu.
6. Press **Run**. The first attempt fails with "Untrusted Developer" — on the phone, go to
   **Settings → General → VPN & Device Management**, tap your Apple ID, and **Trust**.
7. Run again. The app installs and launches.

Seven days later the profile expires and the icon stops responding. Plug in and press Run
again to refresh it. That's the deal with a free team, and it's the reason Route B exists.

---

## Route B — Apple Developer Program and TestFlight

### 1. Before you start

Have these ready, or enrolment stalls:

- An **Apple Account with two-factor authentication turned on**. Use the one you want to own
  the app long-term — moving an app between accounts later is a support ticket, not a setting.
- Your **legal name** as it appears on official documents. Apple checks it against payment
  details, and a nickname is the most common cause of a delayed approval.
- A real postal address (**no P.O. boxes**) and a phone number.
- A payment card for the $99/year fee (charged in your local currency).

Enrol as an **Individual / Sole Proprietor** unless you have a specific reason not to. Your
legal name becomes the seller name on the App Store, which is irrelevant for a private app you
never publish. Enrolling as an **Organization** additionally requires a
[D-U-N-S number](https://developer.apple.com/enroll/duns-lookup/), a legal entity (no trade
names), a work email on your own domain, and a public website — weeks of extra process for
nothing you need here.

### 2. Enrol

1. Go to [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/),
   or use the **Apple Developer** app on your iPhone — the app route is usually faster because
   it can verify your identity with the device you already hold.
2. Sign in, choose **Individual / Sole Proprietor**, and fill in your legal name and address.
3. Accept the Apple Developer Program License Agreement and pay.
4. Wait. Approval is often same-day and sometimes takes a couple of days; if Apple needs to
   verify something they email you. You cannot upload builds until it clears.

### 3. Point Xcode at your new team

Once you're approved:

1. **Xcode → Settings → Accounts**, select your Apple Account, and confirm the new team
   appears (it's your name, not "Personal Team").
2. In the **Skarb** target → **Signing & Capabilities**: **Automatically manage signing** on,
   **Team** set to your paid team, **Bundle Identifier** back to `app.subero.skarb`.

Xcode registers the App ID, creates the signing certificate and builds the provisioning
profile for you. Skarb uses no push notifications, no iCloud, no App Groups — nothing that
needs a capability enabled — so there is nothing else to configure.

### 4. Create the app record in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** →
   **New App**.
2. Fill in:
   - **Platforms**: iOS
   - **Name**: this must be unique across the entire App Store, so plain "Skarb" may be
     taken. It's only a label until you publish — `Skarb Finance` or `Skarb Ledger` is fine,
     and you can change it before any public release.
   - **Primary language**: English (or whatever you prefer)
   - **Bundle ID**: pick `app.subero.skarb` from the dropdown. If it isn't there, Xcode hasn't
     registered it yet — build once with your team selected and reload the page.
   - **SKU**: any private string you like, e.g. `skarb-ios`. Nobody sees it.
   - **User Access**: Full Access
3. **Create**. You now have an app record with no builds, which is exactly what you want —
   you are **not** submitting to the App Store, only using TestFlight.

### 5. Archive and upload

1. In Xcode, set the destination to **Any iOS Device (arm64)** — you cannot archive while a
   simulator is selected.
2. **Product → Archive**. This does a Release build and can take a couple of minutes.
3. The Organizer opens when it finishes. Select the archive → **Distribute App** →
   **TestFlight & App Store** → **Upload**.
4. Accept the defaults on the signing screens (automatic signing, upload symbols) and let it
   go. Upload takes a few minutes.
5. The build appears in App Store Connect under **TestFlight** within 5–15 minutes, first as
   "Processing", then ready.

Skarb declares `ITSAppUsesNonExemptEncryption = false` in its `Info.plist` — it uses nothing
beyond standard HTTPS — so the export-compliance question is already answered and won't hold
the build up.

### 6. Install it on your phone (internal testing)

Internal testing needs **no App Review**, so this works the moment the build finishes
processing.

1. App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** next to
   Testers.
2. Add yourself. Internal testers must be App Store Connect users on your team holding the
   **Account Holder, Admin, App Manager, Developer or Marketing** role — as the account
   holder you already qualify. Up to 100 people.
3. Assign the build to that group.
4. On the iPhone: install **TestFlight** from the App Store, sign in with the same Apple
   Account, and Skarb is waiting there. Tap **Install**.

That's it. Builds stay installable for **90 days**; every new upload resets the clock.

### 7. Other people (external testing) — only if you need it

If you want someone outside your App Store Connect team to test it:

1. **TestFlight → External Testing → +** to create a group and add testers by email, or use a
   public link. Up to 10,000 testers.
2. The **first build you put in front of external testers goes to Beta App Review.** Later
   builds usually don't. Expect a day or so.
3. You'll need to fill in **Test Information**: what to test, a contact email, and — because
   Skarb sits behind a sign-in — **demo account credentials**, or the reviewer will reject it
   for being untestable. Give them a throwaway Skarb instance, not your real ledger.

For a private finance app, internal testing is almost certainly all you want.

---

## Shipping an update

```bash
# 1. deploy the server first — an old app against a new API is harmless; the reverse is not
gh workflow run manual-deploy.yml -f branch=main
```

Then, in Xcode:

2. Bump **`CURRENT_PROJECT_VERSION`** in the Skarb target's build settings. App Store Connect
   rejects a build number it has already seen. Bump **`MARKETING_VERSION`** too when the
   change is worth a new version number (1.0 → 1.1).
3. **Product → Archive → Distribute App → TestFlight & App Store → Upload.**
4. Once it finishes processing, assign it to your internal group. Testers get a notification.

## When something goes wrong

**"No account for team" / "Failed to register bundle identifier"**
Xcode isn't signed in, or the bundle id is taken by someone else. Check
Settings → Accounts, then try a more specific id.

**"Untrusted Developer" on the phone (free team only)**
Settings → General → VPN & Device Management → tap your Apple ID → Trust.

**The app icon does nothing after a week (free team only)**
The 7-day profile expired. Plug in, press Run. This is why Route B exists.

**Archive is greyed out**
A simulator is selected as the destination. Switch to Any iOS Device (arm64).

**Build stuck on "Processing" for over an hour**
Usually a missing icon or an invalid `Info.plist`. Check your email — Apple sends a rejection
notice with the specific reason.

**The app says the server is running an older Skarb**
Exactly what it says: the API is behind the app. Deploy the server, then pull to refresh.

**Sign-in fails with "Couldn't reach that server"**
Check the address under the sign-in form (**Settings → Server**). Production is
`https://skarb.subero.app`. Plain HTTP only works for hosts on your local network.

## What this costs to keep running

$99/year for the developer account. TestFlight is included. There is no App Store review to
pass and nothing to publish — the app can live in TestFlight indefinitely, as long as you
upload a fresh build every 90 days.
