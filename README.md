# AfyaSmart

A health companion app for the Kenyan market: AI symptom checking, a doctor and
pharmacy directory, a drug reference, M-Pesa subscriptions and an affiliate
referral programme.

A Flutter app on a Supabase backend. The original Expo/React Native client
was removed once the Flutter port reached screen parity — see the history
before the "Remove the React Native app" commit if you need it.

| Directory | What it is |
|---|---|
| `lib/` | The Flutter app: `core/`, `models/`, `services/`, `state/`, `features/` |
| `supabase/` | Postgres schema, RLS policies, RPCs and edge functions |
| `assets/seed/` | Doctor, drug and pharmacy catalogue data |
| `assets/branding/` | App icon and splash source art |
| `scripts/` | `build-supabase-seed.js` regenerates `supabase/seed.sql` |

See [`supabase/README.md`](supabase/README.md) for the backend: schema, the
Firestore→Postgres mapping, deployment and migration status.

## Architecture

Business logic lives in the database, not in the client:

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

The client is therefore UI, state and thin service calls — which is what made
running the RN and Flutter apps against one backend practical during the
rewrite.

### One thing to know before touching a paywalled read

Firestore rules **rejected** an unauthorised read. Postgres RLS **filters** —
an unsubscribed query succeeds and returns zero rows, which is
indistinguishable from an empty table. Every paywalled read therefore checks
subscription state explicitly before querying (`_requireSubscription` in `CatalogueService`). Without it the paywall
silently stops working.

## Running the app

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

`GOOGLE_SERVER_CLIENT_ID` must be the **web** client id even on Android — it is
what Google audiences the ID token to, and Supabase validates that audience.

All 28 screens are ported. Nothing has yet been run against a live
Supabase project, so expect first-run defects.

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
