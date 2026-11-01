<p align="center">
  <a href="https://lunixi.com"><picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/lunixi-logo-dark.svg">
    <img src=".github/assets/lunixi-logo.svg" alt="Lunixi" height="64">
  </picture></a>
</p>

# Lunixi Elixir SDK

**Version 1.0.1 uses canonical minor-unit strings for money.** This is a breaking change from 0.x; update request and response handling together. See [migration](MIGRATION-1.0.md).

Historical release record: Verified Hex.pm release: **0.1.1**. The published archive was downloaded and its checksum verified on 2026-11-01.

The source patch adds a concrete merchant-site presentation example. **Embedded checkout is the default**: load only the official Lunixi bundle and mount the existing form; methods and multi-card choices stay in the Lunixi panel. Optional hosted mode uses the backend `paymentPageUrl` after exact HTTPS `pay.lunixi.com/payment/` validation. Its token may differ from the embedded token. Missing URLs keep embedded available and hosted on hold/reconciliation with the original attempt/key. Never derive a URL from the browser token. Authorize the customer/order and native browser CSRF before rendering, send `Cache-Control: private, no-store`, preserve the merchant CSP nonce and keep tokens/HTML/redirect URLs out of logs. Generic response data preserves `paymentPageUrl`; no new typed product parity is claimed.

[![CI](https://github.com/Lunixi-Payment/lunixi-elixir/actions/workflows/ci.yml/badge.svg)](https://github.com/Lunixi-Payment/lunixi-elixir/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**[Documentation](https://docs.lunixi.com/sdks/elixir) · [Türkçe](docs/README.tr.md) · [Changelog](CHANGELOG.md) · [Security](SECURITY.md)**

Server-side Elixir SDK for Lunixi payments and merchant APIs. Uses OTP's vetted Ed25519/HMAC primitives and Req's verified TLS transport. Works with Phoenix, Plug, LiveView server processes and ordinary supervised OTP applications. Requires Elixir 1.20+ and Erlang/OTP 29+.

## Installation

After version 1.0.1 is available on Hex.pm, add the dependency to `deps/0`, then run `mix deps.get`:

```elixir
{:lunixi, "~> 1.0.1"}
```

For the optional native SQLite inbox, also add `{:exqlite, "~> 0.43.0"}` to your application dependencies. Exqlite provides a native SQLite driver; a C compiler is required if a precompiled NIF is unavailable. No database driver is required for payments, signing or webhook verification.

## Supervise one client per merchant key

```elixir
config = %Lunixi.Config{
  base_url: "https://api-gateway.lunixi.com",
  key_id: System.fetch_env!("LUNIXI_KEY_ID"),
  private_key: System.fetch_env!("LUNIXI_PRIVATE_KEY_PEM"),
  max_retries: 2
}

children = [{Lunixi.Client, name: MyApp.Lunixi, config: config}]
Supervisor.start_link(children, strategy: :one_for_one)
```

Register the Ed25519 public key in the dashboard; keep the private key on your server/secret manager. PKCS8 PEM, base64 PKCS8 DER, base64 32-byte seed and validated base64 64-byte keypair encodings are supported. The key selects TEST/LIVE; there is no environment flag. Never send private credentials to the browser.

Each supervised client owns exactly one merchant credential and token cache. Use distinct names or Registry entries for separate merchants. Token acquisition is lazy, coalesced and renewed before expiry. Signing/token refresh run in the client process; protected HTTP calls run concurrently in caller processes. A supervised restart discards the token and safely reacquires it. Access tokens are never persisted.

Config `Inspect`/JSON, response `Inspect`/JSON and OTP client status redact credentials/bodies; client crash status also redacts state/message fields. Raw maps, explicit response data and event raw accessors can contain sensitive information. Do not log them or expose process state/debugging to untrusted callers. BEAM immutable memory is garbage-collected; the SDK does not promise memory zeroization.

| Configuration | Default | Bounds / behavior |
|---|---|---|
| `timeout` | 30,000 ms | Positive, up to 120,000 ms; connect is at most 10 seconds |
| `max_retries` | 0 | 0–5; GET or caller-persisted key only |
| `max_response_bytes` | 8 MiB | Up to 32 MiB; streaming accumulation stops at this bound |
| `allow_insecure_localhost` | false | Explicit HTTP tests on localhost/literal loopback only |
| `additional_ca_certificates` | empty | Trusted DER CA certificates; verification stays enabled |

BaseURL is a trusted HTTPS origin without path, credentials or query. Redirects and Req automatic retries are disabled. Certificate and hostname verification remain enabled; caller-supplied transport options cannot disable them. Use an application-level deadline for an overall workflow containing authentication/retries. Client process unavailability returns a redacted error.

## Checkout: embedded by default, optional hosted mode

Read the order and basket from your server-side records. Persist the attempt key before the call and reuse the same key/body after an uncertain result.

```elixir
alias Lunixi.Payment.{Intent, BasketItem}

intent = %Intent{
  amount: "10050",
  currency: "TRY",
  order_id: "ORD-1001",
  callback_url: "https://merchant.example/payment/return",
  basket_items: [
    %BasketItem{id: "line-1", name: "Example product", item_type: "PHYSICAL", price: "10050"}
  ]
}

with {:ok, response} <- Lunixi.Payments.create_intent(MyApp.Lunixi, intent, persisted_attempt_key),
     %{"token" => token} when is_binary(token) and token != "" <- response.data do
  Lunixi.CheckoutHTML.render(token, nonce: server_generated_csp_nonce)
end
```

Authenticate the order's customer before returning the HTML/token and send `Cache-Control: no-store`. `CheckoutHTML` loads only `https://cdn.lunixi.com/lunixi-checkout.min.js`, mounts the existing Lunixi form, HTML-escapes token JSON and validates an optional CSP nonce. Serve the fragment within your merchant page; never construct custom script URLs or echo arbitrary returned HTML. The form handles enabled card/alternative methods. No default sample collects PAN/CVV.

Money is positive canonical minor-unit strings up to `9223372036854775807`: `10050` = 100.50 TRY. Basket `price` is the line total and must sum to intent `amount`. Removed root fields `price`, `paidPrice`, `autoCapture` fail locally, including through generic requests. Intent installments are not accepted; selection/fees belong to the form. Buyer/address and documented insurance basket details are passed as public string-keyed gateway schemas. `preauth`/`force_3d` preserve explicit boolean false. Method restrictions only narrow methods already enabled in the Lunixi panel.

A token, browser completion, HTTP success or `AUTHORIZED` status is **not proof of capture**. Fulfill only after authenticating the gateway result and matching stored merchant/order/payment ID, expected amount/currency and final capture/reconciliation state. Handle refund, void and dispute transitions separately.

## API coverage

| Module | Methods |
|---|---|
| `Lunixi.Payments` | `create_intent`, `get`, `list`, `methods`, `capture`, `capture_remaining`, `refund`, `refund_remaining`, `void` |
| `Lunixi.Payments` split | `split`, `get_split`, `refund_split` |
| `Lunixi.Fraud` | `evaluate`, `record_event`, `decisions`, `decision` |
| `Lunixi.request` | Signed access to other documented `/api/v1/` merchant APIs |
| `Lunixi.Webhook` | Raw v2 verification, rotation, freshness and ID/type binding |
| `Lunixi.SqliteInbox` | Optional transactional durable replay processing |

```elixir
Lunixi.Payments.get(MyApp.Lunixi, payment_id)
Lunixi.Payments.refund(MyApp.Lunixi, payment_id, "2500", "Customer return", persisted_refund_key)
Lunixi.Payments.capture_remaining(MyApp.Lunixi, payment_id, persisted_capture_key)
Lunixi.Payments.refund_remaining(MyApp.Lunixi, payment_id, "Customer return", persisted_refund_key)
# Explicit nil amounts are invalid. void releases an authorization.
```

Split validates integer total/leg amounts, 1–5 legs and exact balance; method-specific schema validation stays in the gateway. Pending split states can return a response with HTTP 400 and must remain unpaid. Compensation, partial refunds and reconciliation-required states need explicit handling.

Responses preserve `envelope`, `data`, `page_info`, content type, request ID and binary `bytes`. JSON money amounts remain canonical minor-unit strings and unknown fields/states remain available. `{:error, %Lunixi.Error{}}` retains safe kind/code/status/request ID without upstream messages, bodies, URLs or credentials. Do not log returned data/raw bodies.

Version 1.0.1 does not have separate typed wallet, bank-connect, links, insurance, marketplace, subscriptions or identity modules. Use their documented REST schemas with the generic signed transport; no typed parity is claimed:

```elixir
Lunixi.request(MyApp.Lunixi, :get, "/api/v1/payments", query: [{"limit", "20"}])
```

Canonical bodies match JavaScript numeric-index key order, UTF-8 escaping and ECMAScript-style shortest number formatting. Duplicate keys, excessive nesting and unsafe integer numbers fail locally. Queries are encoded separately and included in the signature. Authentication has no body/Digest header.

Known payment mutations and financial helpers require a saved 16–128 character non-space printable ASCII idempotency key. GET/keyed requests may retry bounded transient transport/read failures or 429/500/502/503/504, preserving body/key with fresh nonce. Safe calls may refresh a rejected token once. Unkeyed mutations never automatically retry. Reconcile an unknown outcome before opening another payment attempt.

## Raw webhooks and durable processing

Read the bounded raw bytes before JSON middleware. Keep all delivery header pairs so duplicates can be rejected:

```elixir
{:ok, event} = Lunixi.Webhook.verify(raw_body, request_headers,
  secrets: [System.fetch_env!("LUNIXI_WEBHOOK_SECRET")])
```

The v2 HMAC binds event ID, exact ISO timestamp and raw bytes; OTP `:crypto.hash_equals` compares fixed-length MACs in constant time. Timestamp tolerance defaults to five minutes, can be 1–900 seconds and cannot be disabled. `:now` is a trusted test-clock option, never the caller's timestamp. A signed body `type` is required; an unsigned type header cannot authorize an action. Duplicate JSON/header fields and ID/type mismatches fail closed. Up to three current/previous secrets support rotation.

Verification does not consume an event ID. With optional Exqlite:

```elixir
:ok = Lunixi.SqliteInbox.ensure_schema(connection) # startup/migration only
{:ok, applied} = Lunixi.SqliteInbox.process(connection, merchant_scope, event, fn transaction ->
  apply_verified_order_transition(transaction, event)
end)
```

`apply_verified_order_transition` is your application adapter that matches financial fields and uses the supplied connection for order/outbox updates. The connection must be exclusively owned for the whole transaction; independent processes use separate connections. Keep native busy timeouts modest (the sample uses 100 ms) and return a retryable HTTP failure on storage/lock errors. Do not block all NIF workers with long SQLite busy waits.

Marker and state commit together. Duplicates skip the callback; reused IDs with changed payload fail closed. Callback/commit/storage failure rolls back the marker for safe retry. Scope by merchant, retain markers for your replay policy and send external effects through an outbox. Do not acknowledge failed persistence with 2xx. For another database implement the same unique event/hash + financial update transaction contract. Use only authenticated events returned by `verify`.

The [durable receipt example](examples/durable_webhook.exs) consumes authentic stdin/header data and records only event IDs/types; it does not fulfill orders. The [TEST checkout example](examples/checkout.exs) omits tokens from console output. Request a fresh dashboard replay for old deliveries rather than disabling freshness.

## Examples and verification

```sh
mix run examples/checkout.exs
mix run examples/durable_webhook.exs < raw-webhook.json
```

Checkout requires `LUNIXI_BASE_URL`, TEST-only `LUNIXI_KEY_ID`, `LUNIXI_PRIVATE_KEY_PEM`, and saved `LUNIXI_ORDER_ID` / `LUNIXI_ATTEMPT_KEY`. The receipt requires `LUNIXI_WEBHOOK_SECRET`, `LUNIXI_EVENT_ID`, `LUNIXI_SIGNATURE_TIMESTAMP`, `LUNIXI_SIGNATURE` from an authentic delivery. Supply secrets securely; `.env` is not loaded automatically.

```sh
mix deps.get --check-locked
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict --only warning
mix deps.audit
mix hex.audit
mix hex.build
```

Tests use real TLS with a generated synthetic CA, Node.js JSON/Ed25519/HMAC golden vectors, concurrent token acquisition, malicious form data and persistent SQLite rollback/restart/concurrency. OpenSSL CLI is used only to generate test certificates. Fixture credentials are deliberately synthetic; no live payment calls are needed. Credo runs its warning/security checks; this is not a Dialyzer type proof. [Contributing](CONTRIBUTING.md) · [MIT](LICENSE).

## Merchant-page integration example

The source [CheckoutPresentation adapter](https://github.com/Lunixi-Payment/lunixi-elixir/blob/main/examples/checkout_presentation.exs) calls the existing `Lunixi.CheckoutHTML.render/2`. `present(response.data, nonce: nonce)` defaults to `{:ok, {:html, fragment}}`; explicit `mode: :hosted` returns only a validated `{:ok, {:redirect, url}}`. Require this example from your authorized merchant controller and enforce native CSRF/no-store there. The existing client response already preserves `paymentPageUrl`; its browser and hosted tokens are independent.

Before upgrading from 0.x, follow [the money-string migration](MIGRATION-1.0.md).
