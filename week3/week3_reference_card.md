# Week 3 — Reference Card

> Cumulative through Weeks 1–2 plus Production-shaped flows: security, JMS, ProcessDirect & Script Collections, stateful helpers.

---

## Auth methods — pick the right one

| Method | Use when | Stored where |
|---|---|---|
| **Basic Auth** | Lab / intranet over TLS / legacy partners | Security Material → *User Credentials* |
| **OAuth2 Client Credentials** | Cloud-to-cloud, default for receivers in 2026 | Security Material → *OAuth2 Client Credentials* |
| **mTLS** | Banking, gov, hardware-token partners | **Keystore** (not Security Material) |
| **SAML 2.0 / SAML Bearer** | Corporate federation, SuccessFactors, on-prem via Principal Propagation | Keystore + Security Material |
| **JWT** | API Management front door, B2B token exchange | Keystore |

**Litmus test for "production-shaped":** rotating a secret is an operations task, not a deploy task. The iFlow holds a *reference name*; the runtime resolves the value at message time.

## Security Material vs. Keystore

| | Security Material | Keystore |
|---|---|---|
| Holds | user/pass, OAuth2 client_id+secret, cached tokens | X.509 certs, private keys, public keys |
| Adapter property | "Credential Name" | "Private Key Alias" |
| Rotated by | overwriting the entry | new entry + re-point alias |

**Putting an OAuth2 secret in the Keystore by mistake** = silent auth failure, no error message.

## OAuth2 — token cache surprise

Tokens cached **per-credential-name per-worker**. Rotate the secret → old workers keep working until token TTL expires. Operationally desired, but explains "I rotated and nothing changed."

## mTLS pitfalls

- **CN mismatch** → `SSLHandshakeException — peer not authenticated`. Verify CN with partner before generating.
- **Chain order** — SAP CI expects leaf-first.
- **Expiry is NOT automated.** Upload new key under new alias, re-point receiver, redeploy. The one credential-rotation case that needs a redeploy.

## Cloud Connector + Principal Propagation

On-prem downstream? Cloud Connector is the SSL tunnel. **Principal Propagation** forwards the original user identity end-to-end via X.509 short-lived certs — distinct from service-account OAuth.

---

## JMS — decoupling with durability

### Producer / consumer split

JMS-decoupled = **two iFlows**, not one with a JMS step in the middle.

- **JMS receiver** = producer side (iFlow → queue).
- **JMS sender** = consumer side (queue → iFlow).
- Deploy / monitor / version independently.

### Standard plan limits

- **30 queues** max tenant-wide.
- **9.3 GB** total queue storage.
- **150 transactions/consumers/providers** total adapter slots.
- Per-queue: **300 MB / 5 / 5 / 5**. Messages >5 MB auto-split (max 1280 MB).
- **JMS hops are not metered.**

### Naming

`roi.<flow>.<purpose>` — lower-case, dot-separated. Lab: suffix `<your_initials>`.

### DLQ — always set

| Without DLQ | With DLQ |
|---|---|
| Failed messages clog the source queue | Failed messages cleanly isolated |
| Operations can't distinguish "in retry" vs. "stuck" | Source queue clean, DLQ inspectable/replayable |
| No alerting hook on permanent failure | Alert Notification can watch DLQ depth |

**Always set DLQ Name explicitly.** Never leave default.

### Retry vs. Bypass — mandatory categorization

- **Retry** — transient (502/503/504, timeout, downstream maintenance). Rethrow → JMS retries with backoff → DLQ after N.
- **Bypass** — permanent (400, 401/403, 422, schema fail). Route directly to DLQ + **swallow** the exception. Never burn retry cycles on a 400.

Categorization Groovy lives in the consumer's Exception Subprocess:

```groovy
Integer httpCode = headers.get("CamelHttpResponseCode") as Integer;
String category = "Retry";
if (httpCode != null && httpCode >= 400 && httpCode < 500
    && httpCode != 408 && httpCode != 429) {
    category = "Bypass";
}
message.setProperty("errorCategory", category);
```

Router after script: `Retry` → throw; `Bypass` → JMS receiver to DLQ → End normally.

### Concurrency knobs

- **Concurrent Processes** — parallel threads per worker node. Scale throughput (multiplied by worker count when Access Type is Non-Exclusive).
- **Access Type = Exclusive** — single consumer across the whole tenant, ignoring worker count and Concurrent Processes entirely. Use for order-sensitive, downstream rate limits, shared-state atomicity. Otherwise caps throughput at one worker.
- **EOIO** — via serialization key (`customerId`). Same-key messages strictly in order, different keys can interleave. SOAP RM is the other EOIO option (90-day dedup).

### Queue health

Queue depth should hover near zero. Sustained non-zero = consumer slower than producer.

---

## ProcessDirect — in-memory composition

### What it is / isn't

- **In-memory, intra-tenant, sync or async, not metered, NOT durable.**
- For *composition*. Use **JMS** when you need decoupling-with-durability.

### Header allow-list — the trap

| Behavior | Default |
|---|---|
| Body propagates | always |
| Headers propagate | **only allow-listed on both sides** |
| Properties propagate | **never, period** |

Set Allowed Headers on **both** the receiver (caller) and sender (callee). Empty list = no headers cross.

Need state on the other side? Lift property → header before the call; rehydrate header → property at callee entry.

### Versioned endpoints

`/orderTranslator/v1/translate` — discipline, not feature. Ship v2 alongside v1; migrate callers; decommission v1 when telemetry says zero traffic.

### MEP

- **Request-Reply** — need callee's body back.
- **One-Way (Send)** — fire-and-forget side effects.

MEP mismatch between caller and callee = cryptic deploy error.

### Subflow vs. ProcessDirect

- **Subflow / Local Integration Process** = within one iFlow. Headers + properties DO propagate.
- **ProcessDirect** = across iFlows. Header allow-list, no property propagation.

---

## Script Collections — sharing Groovy

### Anatomy

```
sc_<your_initials>_OrderHubHelpers/
└── src/main/resources/script/v2/
    ├── roiam_logIncoming.groovy
    └── roiam_formatError.groovy
```

### Rules

- **Naming**: `sc_<your_initials>_<purpose>`. Scripts inside still `roiam_*`. Path `script/v2/`.
- **Reference, don't embed.** iFlow adds the collection under *References → Script Collection*; script files live in the collection only.
- **Bump version every edit.** Operations needs to know what changed.
- **Don't pre-emptively share.** Promote on the *second* real consumer, not the first.
- **Edit + Deploy.** Saving in the editor without deploying = no behavior change at runtime.

### Reuse decision matrix

| Logic used by | Where |
|---|---|
| 1 iFlow only, tightly coupled | Inside iFlow at `script/v2/` |
| 2+ iFlows, generic | Script Collection (`sc_*` artifact) |
| 2+ iFlows, different contracts | Don't force shared abstraction — copy is fine |
| 1 today, 2 tomorrow | Start inside; promote when consumer #2 arrives |

---

## Stateful helpers

### Three stores at a glance

| Artifact | Stores | Key | Lifetime | Concurrency |
|---|---|---|---|---|
| **Data Store** | Payloads | String key per entry | TTL | Per-entry lock; safe |
| **Number Range** | Monotonic integer | NR name | Permanent | Atomic next-value |
| **Global Variable** | Small string | Variable name | Permanent | **Last writer wins — NOT atomic** |

### Data Store

- Flow steps: **Write** / **Get** / **Select** / **Delete**.
- **Set TTL on every entry.** No exceptions. Default for idempotency keys: 7 days.
- **Deterministic keys.** Using `${exchangeId}` = always-miss, store grows forever.
- **Don't store secrets** — operations can browse entries.
- Per-entry hard limit 25 MB; aim < 1 MB. Tenant quota ~32 GB.

### Idempotency pattern

```
Get (key=X-Idempotency-Key, Throw on Failure=NO)
  → Router on found
       ├ true  → return cached body → End
       └ false → Number Range → ProcessDirect → ...
                 → Write to Data Store (TTL=604800)
                 → JMS receiver → End
```

**Cache the response AFTER success**, never before. If ProcessDirect throws, no Write happens, the next retry reprocesses correctly.

### Number Range

- Naming: `nr_<your_initials>_<purpose>`. Format `ORD-{nnnn}`.
- **Rotate=No** for business references. Yes = eventual duplicates.
- Pick a generous field width — `{nn}` truncates beyond 99.
- **Atomic next-value** at runtime.
- Transports carry **the artifact AND the current value** — reset in QA after Dev→QA promotion. Operational runbook item.

### Global Variables — usually wrong

| Use case | Verdict |
|---|---|
| Last-success marker for polling iFlow | **Right** — what Globals are for |
| Counter | Wrong — not atomic, use Number Range |
| Current config value | Wrong — use Value Mapping / Externalized Parameter |
| Cached token | Wrong — runtime handles it |
| Shared state between iFlows | Wrong — use Data Store / JMS / ProcessDirect headers |

### Read-modify-write atomicity

- Data Store: per-key lock, safe for *different* keys in parallel; **not** safe for same-key Get→modify→Write under concurrency.
- Number Range: fully atomic.
- Global Variable: not atomic; concurrent writes silently lost.

For high-concurrency idempotency, push de-dup to the downstream's atomic upsert; for low-volume APIs, accept the race and document it.

---

## The Order Hub state model (end of Week 3)

```
Inbound POST
  → roiam_logIncoming                       [from sc_<initials>_OrderHubHelpers]
  → Reject if X-Idempotency-Key missing → 400
  → Get Data Store (key=X-Idempotency-Key)
       ├ found → return cached → 202
       └ miss  ↓
  → Number Range → header X-Order-Sequence = ORD-NNNN
  → ProcessDirect → roi_<initials>_OrderTranslator   [v1, allow-list 5 headers]
  → Write Data Store (envelope, TTL=7d)
  → JMS receiver → roi.orderhub.outbound.<initials>
  → 202 + envelope body
                                                ┊
                  ── consumer iFlow ─────────────┘
  roi_<initials>_OrderHubConsumer
  ← JMS sender (3 retries, 60s+exp backoff, DLQ enabled)
  → Request-Reply → HTTP receiver (OAuth2)
  Exception subprocess: roiam_categorizeError → Router (Retry/Bypass)
```

---

## Project conventions update — Week 3

- **`sc_<your_initials>_*`** — Script Collection artifact names.
- **`nr_<your_initials>_*`** — Number Range artifact names.
- **`ds_<your_initials>_*`** — Data Store artifact names.
- **Allowed Headers list** on ProcessDirect adapters always explicit, never default-empty.
- **DLQ Name** on JMS sender always explicit.
- **TTL** on Data Store Write always explicit.
- Script files inside Script Collections live under `src/main/resources/script/v2/`, same `roiam_*` prefix.
- After Dev→QA transport: reset Number Ranges, clear test Data Store entries. Runbook task.
