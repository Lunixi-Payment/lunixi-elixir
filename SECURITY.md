# Security policy

Report suspected vulnerabilities privately to **developer@lunixi.com** with an affected version, synthetic reproduction, impact and suggested mitigation. Do not post customer data, credentials or live exploits publicly. The latest 0.1.x patch receives fixes. Use a patched supported Elixir/OTP and dependency set. We investigate and coordinate disclosure without promising a response deadline.

Keep private credentials server-side, use separate TEST/LIVE keys and trusted deployment URLs/scopes. Inspect/JSON and OTP status redact credentials/bodies. Explicit data accessors, process state, traces and raw maps remain sensitive; do not log them or expose debugging to untrusted actors. Immutable BEAM binaries cannot guarantee memory zeroization.

Use HTTPS with certificate/hostname verification. Redirects and implicit Req retries are disabled. Local HTTP requires explicit loopback testing. Additional CA certificates are trusted deployment assets. The fixed checkout helper loads the official CDN bundle and escapes token JSON/CSP nonce. Authenticate the order's customer and use no-store before serving it.

Use integer minor units and saved per-attempt keys. Never fulfill from token/browser/HTTP success or authorization. Match authenticated merchant/order/payment/expected amount/currency/final capture and reconciliation state. Handle refund/void/dispute transitions separately.

Verify bounded exact webhook bytes before JSON middleware; preserve duplicate headers for rejection. HMAC uses OTP :crypto primitives and constant-time hash_equals. Freshness alone does not prevent replay. Commit marker, validated order transition and outbox together. Own each SQLite connection exclusively across its transaction, avoid long native busy waits, and return non-2xx on persistence failure. Retain markers for replay policy. Use only events returned by the verifier; local application code is a trusted boundary.

Run compile warnings-as-errors, tests, Credo warning/security checks, mix deps.audit and mix hex.audit. Synthetic fixtures are intentionally public. The runnable receipt example does not implement fulfillment and no default example collects raw card data. This SDK does not remove payment/privacy obligations.

References: [OTP crypto](https://www.erlang.org/doc/apps/crypto/crypto.html), [Req transport](https://req.hexdocs.pm/Req.html), [Exqlite](https://exqlite.hexdocs.pm/Exqlite.Sqlite3.html).
