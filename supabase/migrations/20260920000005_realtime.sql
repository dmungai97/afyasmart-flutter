-- Realtime replication for the payment flow.
--
-- SubscriptionScreen watched the paying user's paymentRequests document with
-- Firestore's onSnapshot so the UI could react the moment the M-Pesa callback
-- landed, rather than waiting for the next poll. Postgres changes reach the
-- client through a replication publication instead, and the subscription is
-- filtered to a single checkout_request_id.
--
-- Realtime honours RLS, so payment_requests_select is what stops a client
-- subscribing to someone else's payment: the filter narrows the stream, the
-- policy is what secures it.

alter publication supabase_realtime add table public.payment_requests;

-- The admin dashboard also watches users, so a new registration or a
-- settled subscription refreshes its counts without a manual reload.
alter publication supabase_realtime add table public.users;

-- REPLICA IDENTITY FULL makes the previous row available on UPDATE events.
-- Without it Postgres sends only the primary key for unchanged columns, and
-- the screen reads status/result off the new row — which would arrive mostly
-- empty.
alter table public.payment_requests replica identity full;
