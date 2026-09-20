# AfyaSmart on Supabase

Phase 1 of the Flutter + Supabase rewrite: move the data layer off Firebase
while the existing React Native app keeps running, so there is a working app at
every step.

Written for: whoever runs the migration (you, or another engineer picking this
up cold).

## What is here

| File | Purpose |
|---|---|
| `migrations/20260920000001_schema.sql` | Tables, enums, indexes — the Firestore collections as Postgres |
| `migrations/20260920000002_rls.sql` | Row Level Security + column grants — the port of `firestore.rules` |
| `migrations/20260920000003_functions.sql` | Business logic from `functions/index.js` as Postgres functions |
| `migrations/20260920000004_cron.sql` | pg_cron jobs replacing the two `onSchedule` Cloud Functions |
| `seed.sql` | Generated catalogue data — run `node scripts/build-supabase-seed.js` to regenerate |
| `functions/_shared/` | Auth, admin client, CORS and subscription helpers shared by all three functions |
| `functions/{chat,mpesa,symptoms}/` | Edge functions, now on Supabase Auth + Postgres |

## How Firestore concepts map

| Firestore | Postgres | Note |
|---|---|---|
| `users/{uid}` | `public.users` | PK is `auth.users(id)` (uuid) |
| `users/{uid}/chatMessages` | `chat_messages` | Subcollection becomes a FK |
| `users/{uid}/chatLogs` | `chat_logs` | Same |
| `doctors` / `drugs` / `pharmacies` | same names | Identity `bigint` ids — the client already coerced these to numbers |
| `paymentRequests` | `payment_requests` | Surrogate uuid PK; `checkout_request_id` is a nullable unique key |
| `affiliates` | `affiliates` | |
| `affiliateCodes` | *(gone)* | Became `affiliates.code` + the `resolve_referral_code()` function |
| `commissions` | `commissions` | |
| `payoutRequests` | `payout_requests` | |

Rules map to two mechanisms, not one: **which rows** a caller may touch is an
RLS policy; **which columns** they may write is a column `GRANT`. The
`isSafeUserUpdate()` whitelist is now `grant update (name, phone,
onboarding_completed)`, which is why a user still cannot make themselves a
subscriber. Anything neither can express (admin edits, marking a payment paid)
is not client-writable at all and goes through a `security definer` RPC — the
role the Admin SDK Cloud Functions played.

## Differences from the Firebase behaviour

These are deliberate, and each one is commented at its definition:

- **Double-credit guard.** `commissions_one_per_payment_idx` makes a repeated
  M-Pesa callback a no-op. Previously a callback and a status poll resolving the
  same STK push could each credit the referrer.
- **Double-refund guard.** `admin_resolve_payout` rejects an already-resolved
  payout. `rejectAffiliatePayout()` could be called twice and refund twice.
- **`paid` / `status` cannot disagree.** A check constraint replaces three
  separate code paths each setting both fields by hand.
- **Commission failure now rolls back the activation.** The original wrapped
  commission crediting in try/catch so it could not fail a subscription; here
  they share a transaction, because a half-applied payment is worse than a
  retryable error.
- **Self-referral is unrepresentable** rather than ignored at runtime.
- **The symptom quota can no longer be overrun.** It read the count, compared
  it, then wrote count+1; two concurrent requests both read the same value and
  both proceeded. Now one atomic `consume_symptom_quota()` call. It also fails
  closed — the quota exists for cost control, so an unavailable quota table
  must not become an open door.
- **Chat writes are atomic.** Four sequential Firestore writes (log, two
  messages, an increment) became one `record_chat_exchange()` call, so
  `chat_count` cannot drift out of step with the stored history.

## Edge functions

`firebaseAuth.ts` (91 lines of fetching Google's signing certs and verifying
RS256 by hand) and `firestore.ts` (a hand-rolled REST client, duplicated in
each function) are both gone — 5 files, ~715 lines, replaced by
`_shared/supabase.ts`. Auth is now `supabase.auth.getUser(token)`.

`verify_jwt` stays **off** for all three, and auth is enforced per-route:

| Function | Route | Auth |
|---|---|---|
| `chat` | `/send` | Supabase access token |
| `mpesa` | `/initiate`, `/status` | Supabase access token |
| `mpesa` | `/callback` | **None** — Safaricom cannot send one |
| `symptoms` | `/analyze`, `/clarify` | **None** — guest onboarding predates the account |

The M-Pesa callback is unauthenticated by necessity, and the
`CheckoutRequestID` it carries is also given to the paying client, so a forged
`{ ResultCode: 0 }` is trivially possible. It is therefore treated purely as a
"check now" trigger — the outcome always comes from our own authenticated
`stkQuery` to Safaricom, never from the request body. That design is carried
over unchanged, and it is the reason the callback can stay open.

Deploy with `verify_jwt` off:

```bash
supabase functions deploy chat     --no-verify-jwt
supabase functions deploy mpesa    --no-verify-jwt
supabase functions deploy symptoms --no-verify-jwt
```

Secrets (`supabase secrets set KEY=value`): `OPENAI_API_KEY`,
`MPESA_CONSUMER_KEY`, `MPESA_CONSUMER_SECRET`, `MPESA_PASSKEY`,
`MPESA_SHORTCODE`, `MPESA_CALLBACK_URL`, `MPESA_ENV`. `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

### Wire compatibility

Request and response shapes are unchanged, so a client needs only to send a
Supabase access token instead of a Firebase ID token. The symptoms endpoints
take the caller as `subject_id` — either a signed-in user's uuid or a
client-generated guest id, since onboarding runs before an account exists.

## Running it

Requires Docker + the Supabase CLI (`npm i -g supabase`). **None of this has
been executed yet** — see "Status" below.

```bash
supabase start                 # local stack
supabase db reset              # applies migrations/ then seed.sql
```

Against a hosted project:

```bash
supabase link --project-ref <ref>
supabase db push
psql "$DATABASE_URL" -f supabase/seed.sql
```

`pg_cron` must be enabled for the project (Dashboard → Database → Extensions)
before `20260920000004_cron.sql` will apply.

## Setting up a database

The live backend holds only test accounts, so there is nothing to migrate —
create the project, apply the migrations, run the seed, and register fresh
accounts. (A Firestore importer was written and then deleted once that was
confirmed — it was never committed, so it is not recoverable from git. If real
user data ever needs moving, note that Firebase scrypt password hashes cannot
be converted to Supabase bcrypt, so any such migration forces a password reset
for every account.)

Promote your first admin by hand, since role is not client-writable:

```sql
update public.users set role = 'super_admin' where email = 'you@example.com';
```


## The React Native client

The existing app now talks to Supabase. `firebase` is uninstalled and
`src/services/firebase.ts` / `functionsApi.ts` are deleted.

Set these before running — **`extra.supabase.anonKey` in `app.json` is
deliberately left empty**, since only you can read it from the dashboard:

```bash
EXPO_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=<anon key>
```

The anon key is safe to ship: RLS is what protects the data.

### The one behavioural trap

Firestore rules **rejected** an unauthorised read, so the catalogue services
detected `permission-denied` and let it propagate past their seed-data
fallback. Postgres RLS does not reject — **it filters**, so a non-subscriber's
query succeeds and returns zero rows, which is indistinguishable from an empty
table.

Left alone that silently defeats the paywall: the fallback would have served
the full doctor/pharmacy/drug directory to everyone. Each service therefore
checks subscription state explicitly and raises `PaywallError` before
querying. The RLS policies still enforce it server-side; the client check only
makes the failure look the way the screens already expect.

**If you add a new paywalled read, it needs that check too** — an empty result
will not tell you anything is wrong.

### Other client-side changes

- **Google sign-in** moves from `GoogleAuthProvider.credential()` to
  `supabase.auth.signInWithIdToken()`. The screens still fetch the Google ID
  token via `expo-auth-session` unchanged, but the client IDs moved from
  `extra.firebase` to `extra.google`, and **new OAuth credentials must be
  configured** in Supabase Auth → Providers → Google.
- **Registration** no longer writes the profile row. `referral_code` goes into
  user metadata and the `on_auth_user_created` trigger resolves it, so
  `referred_by_uid` is never client-writable and the second round-trip
  `resolveReferrerUid()` needed is gone.
- **Realtime** replaces `onSnapshot` in two places: `SubscriptionScreen`
  watches one payment by `checkout_request_id`, and `useAdminDashboard`
  refetches on changes to `users` / `payment_requests` (debounced 500ms, since
  one settlement touches both).
- **`useAdminDashboard` shrank from ~280 lines to ~110.** It carried a full
  second copy of the aggregation logic in `fetchAdminDashboardData()`, and the
  two had already drifted; it now calls that function.
- **Admin pagination** cursors are row offsets rather than `DocumentSnapshot`s,
  so `fetchUsersPage` / `fetchPaymentsPage` take a `number | null`.
- **A duplicate-write bug is fixed.** `ChatScreen` wrote both chat messages to
  Firestore *and* the chat function wrote the same two, so every exchange was
  stored twice and history replayed each line doubled. The client now holds no
  insert grant on `chat_messages`, making it impossible.
- **`rejectAffiliatePayout(id)`** no longer takes the uid and amount; the
  refund happens inside `admin_resolve_payout`, guarded against double-apply.

## Status

Phase 1 is **written but unverified** — no Docker, psql, Supabase CLI or Deno
was available in the environment where it was authored, so **none of the SQL
has been executed and none of the TypeScript has been typechecked**. Expect to
fix issues on the first `supabase db reset` and `supabase functions serve`.

The **React Native client, by contrast, is verified** as far as static analysis
goes: `npx tsc --noEmit` passes clean (exit 0) and `eslint` reports 0 errors
across `app/ src/ admin/ affiliate/` (16 warnings, all pre-existing).

Also checked: the two Node scripts pass `node --check`; the seed generator has
been run for real (22 doctors, 8 drugs, 21 pharmacies, quoting verified); and
every RPC name and parameter called from the edge functions and the client has
been confirmed against its SQL definition.

What that does **not** cover: nothing has been run against a real database.
Types passing says the calls are well-formed, not that the queries return what
the screens expect.

Still to do in Phase 1:

1. Create the Supabase project, run the migrations, fix what breaks.
2. Fill in `extra.supabase.anonKey` and configure Google OAuth.
3. Typecheck and smoke-test the edge functions (`deno check`,
   `supabase functions serve`).
4. Run the app end-to-end: register → onboarding → chat limit → subscribe via
   M-Pesa → catalogue unlocks → affiliate enroll/withdraw → admin console.
5. Migrate live data and send password resets.

Phase 2 (the Flutter client) starts once the app runs green against Supabase.
