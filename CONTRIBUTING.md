# Contributing

Describe substantial changes in an issue first. Report vulnerabilities through [SECURITY.md](SECURITY.md).

Use Elixir1.20+/OTP29+ and centralize shared signing, transport, money and webhook logic. Framework adapters reuse the SDK. Add only verified public endpoints and preserve envelopes, pending/unknown/reconciliation states. Do not add raw-card defaults, customer/secret logs or arbitrary form script origins. Preserve original Lunixi branding.

Run `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `mix credo --strict --only warning`, `mix deps.audit`, `mix hex.audit` and `mix hex.build`. Tests use synthetic offline fixtures and generated local TLS certificates (OpenSSL CLI required), not merchant credentials. Replay tests must prove callback/marker rollback and durable deduplication. Keep native database connection ownership explicit.

Update English/Turkish guides, examples and changelog for public API changes. Explain the concrete behavior and actual checks in pull requests. Do not commit deps/_build output, secrets, customer data or database files. Hex.pm publication is a separate maintainer action and is not automated here.
