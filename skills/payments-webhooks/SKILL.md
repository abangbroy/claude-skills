---
name: payments-webhooks
description: Build payment and money logic that survives real gateways - integer money, a gateway adapter with an offline fake, signed webhooks processed in one idempotent transaction, status precedence for late and out-of-order events, a credit/wallet ledger that can't go negative or double-grant, reconciliation when webhooks go missing, refunds on failed fulfilment, and the tests that prove it. Use whenever the task involves checkout, a payment gateway (Stripe, CHIP, Billplz, Xendit, PayPal, ToyyibPay…), webhooks or callbacks, credits, wallets, top-ups, subscriptions, refunds, invoices, or any code that moves money - even a "small" pricing change.
---

# Payments and webhooks

Webhooks arrive late, out of order, more than once, or never. The browser's
return URL proves nothing. Two deliveries can run at the same moment. Each of
these has cost real products money; the design below makes all of them
harmless by construction rather than by luck.

## Money in code

- Integer minor units (sen, cents) everywhere in code, in one `money.ts` with
  parse/format helpers. Convert to `numeric(12,2)` (or keep integers) only at
  the database boundary. Floats never touch money.
- Prices, totals, discounts and tiers are computed by the app on the server,
  never by the client and never by an LLM. The client sends a plan id, not an
  amount.
- Rounding happens once, at a documented step, and has a unit test.

## Gateway adapter

- A `PaymentGateway` interface: `createPurchase`, `getPurchase`,
  `verifyWebhook(rawBody, headers)`, `refund`. The real implementation and a
  **fake gateway** (a dev-only page that "pays") for local runs, E2E and CI.
  The env loader refuses the fake in production.
- Mark every vendor detail you haven't confirmed against their sandbox with
  `// VERIFY:` (method ids, amount field names, status names, base URLs per
  environment). Before launch, one real sandbox purchase clears them.
- Checkout asks for the payment method you want first via whatever the
  gateway offers (a `preferred` parameter); don't assume it can reorder.

## One processing path, one transaction

The webhook, the admin "re-process payment" button and the reconciliation job
all call the same `processPaymentEvent`:

1. **Verify the signature over the raw body** before parsing (RSA/HMAC as the
   gateway specifies). Support several keys if the gateway rotates or uses
   per-webhook keys.
2. Parse with a whitelist schema. Store only what you need (status, amounts,
   ids); drop the payer's name, email, phone and card details.
3. In one transaction: lock the payment row by the gateway's purchase id
   (`select … for update`); check amount, currency and your reference match
   what you created; apply the status change; on the **first** `paid`, grant
   what was bought, spend it on what it was bought for, mark it unlocked, and
   queue follow-up work (generation, receipt email). All or nothing.
4. Respond with codes the gateway retries correctly: 200 for applied,
   replayed or unknown purchases; 401 bad signature; 400 malformed; 422
   amount/currency/reference mismatch (apply nothing, alert); 500 for your own
   errors so the gateway retries — replays are safe.

**Status precedence**: `paid` may follow created/failed/expired (the payer
retried on the same checkout). A late `failed` or `expired` never downgrades
`paid`. `refunded`/chargeback is recorded, final, and flagged for a human;
don't silently claw back credits.

## Idempotency comes from the schema

Don't rely on "we check first, then insert" — two deliveries both pass the
check. Put the guarantee in unique constraints and let the second insert fail
or no-op:

- `unique (payment_id, reason)` on ledger grants: a payment grants once.
- `unique (reverses_id)` on refunds: a spend is refunded once.
- `dedupe_key unique` on jobs and on the email log: follow-up work and
  receipts are queued and sent once.

## Credits and wallets: a ledger, not a balance column

- Append-only `credit_ledger` rows: grants (+n, with `expires_at`), spends
  (−1 each), refunds (reverse a specific spend). Balance = sum over unexpired
  grants of what remains.
- **Spends reference the grant they draw from**, earliest expiry first. With a
  plain sum, an expired grant's earlier spends keep counting and balances go
  negative. Refunds return the credit to the same grant (keeping its expiry).
- Serialize spends per customer (`select … from customers where id = $1 for
  update`) so two tabs can't spend the last credit twice.
- A paid customer always gets what they paid for: if the wallet came up short
  between checkout and webhook, issue a logged admin grant to cover it and
  alert — never leave a payment without its product.

## When the webhook never comes

Gateway outage, host deployment protection blocking the route, a wrong
webhook key, a deploy that broke the handler: the customer paid and sees
"confirming" forever, and nothing errors. Queue a **reconciliation job** with
every checkout (same transaction as the payment row) that asks the gateway
for the purchase at growing intervals (5 min, 15 min, 1 h, 6 h, 24 h) and runs
it through `processPaymentEvent`. Stop once settled. Finding a purchase paid
before its webhook is reported as `webhook_missed`: one is a late webhook, a
run of them means webhooks are broken.

## Work after payment

Fulfilment (generation, provisioning, emails) runs as jobs on a queue
(Postgres `for update skip locked` is enough at small scale): idempotent
enqueue, retries with backoff, `dead` after max attempts, and an `onDead`
hook that **refunds** the customer. Retry `onDead` itself until it succeeds,
so a refund can't be lost. Ignore status updates from a late worker once a
newer attempt owns the job. Details in
[references/job-queue.md](references/job-queue.md).

## Tests that prove it

Unit/DB tests (on a real database, see postgres-migrations-release):

- Same webhook twice → granted once. Two deliveries concurrently → granted once.
- `failed` after `paid` → still paid. `paid` after `failed` → paid.
- Amount, currency or reference mismatch → nothing applied, 422, alert.
- Bad signature → 401, nothing read. Unknown purchase → 200, nothing applied.
- Spend across two grants with different expiries; expiry of a partly used
  grant; refund returns to the original grant; two concurrent spends of the
  last credit → one succeeds.
- Fulfilment job dies → credit refunded exactly once, even if `onDead` failed
  the first time.
- Reconciliation racing the webhook → granted once.

E2E: the full journey with the fake gateway, plus a declined payment.

## Before launch

- One real sandbox purchase per payment method; clear the `VERIFY:` markers.
- Webhook URL reachable from the internet (deployment protection off for it).
- Alerts on: rejected webhooks, mismatches, `webhook_missed`, dead fulfilment
  jobs, failed refunds. A runbook for "customer paid but has nothing".
