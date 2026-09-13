# HTTP receiver — calling restcountries.com

This receiver hop calls `https://restcountries.com/v3.1/alpha/${property.customerCountry}`. It is the simplest possible *external* HTTPS call: no auth, no CSRF, no proxy.

**Before any of this works, `customerCountry` has to be allow-listed on the sender side** — canvas empty space → Integration Flow menu → Runtime Configuration → Allowed Header(s). Without that, the header is dropped before the Content Modifier ever sees it, the property this address reads is empty, and this call ends up malformed regardless of what the caller sent. See `day3_adapters_sync.md` Step 0.

## Adapter settings

| Setting | Value | Notes |
|---|---|---|
| Address | `https://restcountries.com/v3.1/alpha/${property.customerCountry}` | Dynamic URL using the property the Content Modifier stashed — not the raw header. Camel evaluates `${property.X}` at runtime. |
| HTTP Method | `GET` | restcountries only exposes GET. |
| Authentication | `None` | Public API. |
| Proxy Type | `Internet` | Out-of-the-box egress, no Cloud Connector. |
| Timeout | `60000` (default) | Override only if upstream is known-slow. |
| Throw Exception on Failure | **Day 1.3 step 1: ON** (validate the failure path), **step 2: OFF** (degrade gracefully via the script). | The whole point of this lesson. |
| Allowed Response Headers | leave empty | Defaults are fine. |

## What happens on each "Throw Exception on Failure" setting

| Setting | Upstream 200 | Upstream 404 | Upstream timeout |
|---|---|---|---|
| **ON** | iFlow continues with upstream body | iFlow throws `HttpResponseException`, MPL = FAILED | Same — `HttpHostConnectException` after 60s |
| **OFF** | iFlow continues with upstream body | iFlow continues; body is the plain-text error; script handles it | Same — script sees the timeout body / null |

> The cookbook rule: **leave it ON** unless you have explicit downgrade logic in a script step right after. Silent failures are the worst kind.

## Retry behavior

Defaults are 3 retries with exponential backoff between attempts.

| Setting | Default | When to change |
|---|---|---|
| Maximum Retries | 3 | Set to 0 for idempotency-sensitive POSTs without a dedup window. |
| Initial Retry Interval | 5000 ms | Increase to 30000 for flaky partners to avoid hammering. |
| Retry Backoff Multiplier | 2 | Leave. |

> Remember: each retry **costs 1 metered message** (see Day 1.1 `metering_examples.md`, example 4).
