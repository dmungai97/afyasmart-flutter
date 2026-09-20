# AfyaSmart

A health companion app for the Kenyan market: AI symptom checking, a doctor and
pharmacy directory, a drug reference, M-Pesa subscriptions and an affiliate
referral programme.

**The app is mid-rewrite from Expo/React Native to Flutter.** Both clients talk
to the same Supabase backend, which is the source of truth for all business
logic.

| Directory | What it is |
|---|---|
| `supabase/` | Postgres schema, RLS policies, RPCs and edge functions — **the backend** |
| `flutter_app/` | The Flutter client (in progress; will replace the RN app at the repo root) |
| `app/`, `src/`, `admin/`, `affiliate/` | The Expo/React Native client (working, being retired) |
| `seed-data/` | Doctor, drug and pharmacy catalogue data, shared by both |

See [`supabase/README.md`](supabase/README.md) for the backend: schema, the
Firestore→Postgres mapping, deployment and the current migration status.

## Architecture

Business logic lives in the database, not in either client:

- **RLS policies + column grants** enforce who can read and write what. A user
  cannot make themselves a subscriber because `authenticated` holds an UPDATE
  grant on only three columns of `users`.
- **Security-definer RPCs** own everything money touches — `activate_subscription`,
  `request_payout`, `enroll_affiliate`, the `admin_*` family. Clients call them;
  they never write those rows directly.
- **Edge functions** (`chat`, `mpesa`, `symptoms`) hold the OpenAI and Safaricom
  credentials and are the only code that talks to those APIs.
- **pg_cron** runs the two scheduled jobs (expiring stale payments, releasing
  held affiliate commissions).

A client is therefore UI, state and thin service calls. That is what makes
running two clients against one backend practical during the rewrite.

### One thing to know before touching a paywalled read

Firestore rules **rejected** an unauthorised read. Postgres RLS **filters** —
an unsubscribed query succeeds and returns zero rows, which is
indistinguishable from an empty table. Every paywalled read therefore checks
subscription state explicitly before querying (`requireSubscription` in the RN
services, `_requireSubscription` in `CatalogueService`). Without it the paywall
silently stops working.

## Running the React Native app

```bash
npm install

export EXPO_PUBLIC_SUPABASE_URL=https://YOUR_REF.supabase.co
export EXPO_PUBLIC_SUPABASE_ANON_KEY=YOUR_ANON_KEY

npm run android   # or: npm run ios
```

The anon key is safe to ship — RLS is what protects the data. Google client IDs
live under `expo.extra.google` in `app.json`.

## Running the Flutter app

```bash
cd flutter_app
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

`GOOGLE_SERVER_CLIENT_ID` must be the **web** client id even on Android — it is
what Google audiences the ID token to, and Supabase validates that audience.

Screens not yet ported render a labelled placeholder, so the app is navigable
end to end while the port is in progress.

## Subscription plans

| Plan | Price (KES) | Duration |
|---|---|---|
| Daily | 20 | 1 day |
| Weekly | 100 | 7 days |
| Monthly | 200 | 1 month |

Unsubscribed users get 5 free AI chats and 3 free symptom checks per day. Both
limits are enforced server-side; the clients only pre-check them to avoid a
wasted round-trip.

Payment runs through M-Pesa STK push. The outcome is always re-derived from
Safaricom's own API rather than trusted from the callback body, because the
`CheckoutRequestID` in that callback is also handed to the paying client — so a
forged `{ ResultCode: 0 }` would otherwise be trivial.

## Affiliate programme

Referrers earn **30%** of each successful subscription by a user who signed up
with their code, held for **7 days** before becoming withdrawable. Minimum
withdrawal is KES 100. Balances are only ever moved by database functions, so a
retried M-Pesa callback cannot double-credit and a double-clicked rejection
cannot double-refund.
