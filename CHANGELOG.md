# Changelog

## 1.0.0 — 2026-11-01

- Reject explicit null capture/refund amounts; full remaining operations use omission or the dedicated API described in MIGRATION-1.0.md.

- Breaking: public money request/response fields require canonical minor-unit strings; JSON numbers are rejected.
- Exact signed 64-bit fiat arithmetic and currency-aware decimal text conversion preserve values above JavaScript’s safe-integer limit.
- See [MIGRATION-1.0.md](MIGRATION-1.0.md) before upgrading.


## 0.1.1 - 2026-10-31

- Provide a concrete merchant-site renderer/example using the existing official Lunixi checkout form by default, with an explicit optional hosted presentation.
- Use only the validated backend paymentPageUrl for redirects; its opaque token is independent of the embedded token. Missing URL keeps embedded available and requires reconciliation for hosted mode without inventing another key.
- Preserve authentication, customer ownership/CSRF integration boundaries, no-store/token-redaction rules and raw response compatibility. Existing published tags are unchanged.

## 0.1.0 — 2026-10-31

- Initial Elixir/OTP SDK with supervised per-merchant token cache and concurrent protected requests.
- Native OTP Ed25519 PKCS8/seed authentication, canonical JavaScript-compatible JSON and strict integer money.
- Typed payments/fraud, split validation, bounded signed generic merchant transport and redacted diagnostics.
- Strict raw v2 HMAC verification and optional native SQLite transactional replay inbox.
- Safe existing checkout-form HTML helper with fixed official CDN origin and escaped token/CSP nonce.
- Runnable TEST checkout/durable receipt examples, cross-language/TLS/security/concurrency tests and EN/TR guides.
