# Error categories — taxonomy and strategy

The project's five-category taxonomy. Memorize this before building the Exception Subprocess; the entire error-handling strategy depends on classifying correctly.

## The five categories

| Category | Definition | Examples in the Order Hub |
|---|---|---|
| **Transient** | Will succeed on retry without human intervention | OAuth token expired (no auto-refresh); network blip; downstream 502/503; JMS broker connection drop |
| **Poison** | Will never succeed without changing the message itself | Malformed JSON; schema validation failure; missing required field; PD parameter not found because of typo in header |
| **Business** | Downstream rejected the message for valid business reasons | Order rejected for "credit hold"; duplicate orderId on a non-idempotent path; SKU not orderable |
| **Configuration** | iFlow is misconfigured; no message will succeed until ops fixes it | Wrong receiver URL; missing Security Material; missing PD parameter (because the parameter genuinely doesn't exist) |
| **Runtime** | Tenant or infrastructure problem outside iFlow control | Tenant restart (Abandoned MPL status); JVM out-of-memory; ten-minute timeout exceeded |

## Why the distinction matters

Different categories need different responses:

| Category | Retry? | Alert? | Severity | Destination |
|---|---|---|---|---|
| Transient (under retry limit) | Yes (auto) | No | — | None (transparent retry) |
| Transient (retry exhausted) | Yes (manual / scheduled) | Yes | Sev-3 | Retry queue |
| Poison | No | Yes | Sev-2 | DLQ |
| Business | No | No (or warn) | Sev-4 | Reject queue |
| Configuration | No | **Loudly** | Sev-1 | DLQ + immediate page |
| Runtime | Maybe (operator decides) | Yes | Sev-2 | Operator queue |

Treat them the same and you get either alert fatigue (everything pages) or silent failures (nothing pages).

## How to classify in script

The capture-context script (`roiam_captureErrorContext.groovy`) uses heuristics on the exception class and message:

```groovy
String classify(Throwable cause) {
    if (cause == null) {
        return "unknown";
    }
    String name = cause.getClass().getName();
    if (name.contains("JsonException") || name.contains("XmlException") || name.contains("SAXParseException")) {
        return "poison";
    }
    if (name.contains("javax.net") || name.contains("ConnectException") || name.contains("SocketTimeout")) {
        return "transient";
    }
    if (name.contains("PartnerDirectory") || name.contains("SecurityMaterial")) {
        return "configuration";
    }
    if (cause.getMessage() != null && cause.getMessage().toLowerCase().contains("credit hold")) {
        return "business";
    }
    return "unknown";
}
```

This is a starting point. As production runs reveal new failure modes, add cases. **Never remove cases without checking what failure mode they covered.** The classification heuristic is the team's shared understanding of what to do; don't quietly weaken it.

## Decision matrix — concrete examples

| Symptom | Cause | Category | Why |
|---|---|---|---|
| `JsonException: Unexpected character 'x' at line 3` | Producer sent broken JSON | Poison | Won't fix on retry |
| `ConnectException: connection refused to api.oms.acme.com` | OMS is down | Transient | Will likely succeed when OMS comes back |
| HTTP 401 from OMS | OAuth token expired | Transient (this iFlow has no auto-refresh) | Refresh handled at next message; retry will succeed |
| HTTP 401 from OMS, persistent | Credentials wrong (rotated, not updated in Security Material) | Configuration | Won't fix without ops |
| HTTP 422 from OMS, body "Customer is on credit hold" | Customer is on credit hold | Business | Working as designed — order rightly rejected |
| HTTP 500 from OMS | OMS bug | Transient (could also be Runtime depending on cause) | OMS team will fix; retries during the window may eventually catch a healthy node |
| `RuntimeException: Routing parameter not found` | PD parameter deleted or typo'd | Configuration | Won't fix until ops restores PD |
| `SAXParseException: cvc-complex-type` | Vendor sent XML that doesn't match canonical XSD | Poison | Schema mismatch is structural |
| `OutOfMemoryError` | iFlow processed a 1 GB body | Runtime | Operator must investigate; possibly plan upgrade |
| MPL Abandoned | Tenant restarted mid-run | Runtime | Will not auto-retry; depends on adapter (JMS adapters re-queue; HTTP doesn't) |

## The "unknown" classification

The default. Routes to DLQ + alert at the standard severity. Treat it as a flag that the classification heuristic needs an update.

| Unknown frequency | Action |
|---|---|
| Zero or one per month | Healthy. Heuristic covers production reality. |
| Multiple per week with the same exception class | Update `classify()` to recognize this exception class explicitly. |
| Surge of unknowns | New failure mode in production. Investigate before tuning the classifier. |

Don't bias unknowns toward "transient" (silently retried) or "poison" (loud alert). Keep "unknown" routing the same as poison until you understand it.

## What "Business" really means

The trickiest category. A business rejection means the upstream/downstream contract is intact but the *content* doesn't qualify for the next step. Examples:

- Customer on credit hold → OMS legitimately won't accept the order.
- SKU obsolete → can't fulfill from stock.
- Shipping address country not in the partner's serviced list.
- Order amount exceeds the partner's risk threshold.

The Order Hub's job is to **route business rejections back to the originating system** (or to a reject queue), not to retry, not to alert oncall. The user-facing reason should be preserved so the originating system can take appropriate action (notify the customer, escalate to credit team, etc.).

Common mistake: treating business rejections as poison. Triggers Sev-2 alerts for events that are actually *working as designed*. Within a month, oncall starts ignoring all `roi.orderhub.dlq` alerts. Now you've broken alerting.

Distinguish carefully. Add a business-classification branch even if your first iteration has only one case (`credit hold`); the alternative is alert fatigue.

## What "Runtime" rarely is in cohort training

In production, runtime failures account for 1–5% of incidents. On the training tenants, they're almost zero — the tenants are small and quiet. You'll see Abandoned MPL status if the trainer restarts the tenant; that's the one realistic provocation.

In production, runtime failures are typically the responsibility of the platform team (tenant capacity, JVM tuning, scheduled maintenance). The iFlow developer's job is to ensure runtime failures *result in retries* on adapters that support them (JMS), and *result in alerts* on those that don't (HTTP).

## Cross-reference

| Category | Capture-context script field | Router branch | Alert category |
|---|---|---|---|
| transient | `errorClassification = "transient"` | "transient-retrying" (let JMS auto-retry) | None until exhausted |
| transient-exhausted | `errorClassification = "transient"` + `redeliveryCounter >= 3` | "transient-exhausted" | `roi.orderhub.retry-stuck` |
| poison | `errorClassification = "poison"` | "poison" → DLQ | `roi.orderhub.dlq` |
| business | `errorClassification = "business"` | "business" → reject queue | None (log only) |
| configuration | `errorClassification = "configuration"` | "configuration" → DLQ | `roi.orderhub.dlq` at highest sev |
| unknown | `errorClassification = "unknown"` | default → DLQ (safe default) | `roi.orderhub.dlq` |
