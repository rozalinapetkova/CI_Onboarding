# ProcessDirect — callee side (the iFlow that handles the call)

On the **callee** iFlow you replace (or add alongside) the HTTPS sender with a **ProcessDirect sender** adapter. The "sender" terminology: the iFlow *receives* messages from this entry point, treating ProcessDirect as the *sender* of messages into the iFlow. This is `roi_<initials>_OrderTranslator` accepting calls from the Order Hub.

## Where it sits in the Order Translator

```
ProcessDirect sender   ──► Router (by X-Order-Format)
  /orderTranslator/v1/    ├─► JSON branch: JsonSlurper → canonical XML
  translate/<initials>    ├─► XML branch:  XmlSlurper → canonical XML
                          └─► CSV branch:  custom parser → canonical XML
                                                        │
                                                        ▼
                                                  End (returns canonical XML)
```

During the lab you can **keep the HTTPS sender alongside** the ProcessDirect sender so the Week 2 caller still works. Two senders on one iFlow = two entry points; either can start a run.

## Adapter configuration

| Property | Lab value | Why |
|---|---|---|
| Address | `/orderTranslator/v1/translate/<your_initials>` | **Must match the caller's Address exactly.** Including the `<initials>` suffix |
| Message Exchange Pattern (MEP) | `Request-Reply` | The only MEP ProcessDirect has — nothing else to set |
| Allowed Headers | `correlationId\|orderId\|X-Order-Format\|X-Idempotency-Key\|X-Order-Sequence` | Filter on the way *in*. Same list or a superset of the caller's |

## Allowed Headers — caller list vs callee list

The two adapters each have their own Allowed Headers field. Both must include a header for it to make it across.

| Caller allows | Callee allows | Result |
|---|---|---|
| `correlationId\|orderId` | `correlationId\|orderId` | Both propagate |
| `correlationId\|orderId` | `correlationId` | Only `correlationId` reaches callee; `orderId` filtered |
| `correlationId\|orderId` | *(empty)* | Nothing reaches callee — most common bug |
| *(empty)* | `correlationId\|orderId` | Nothing leaves caller — also common |

**Project convention: keep the two lists identical.** Manage drift with a comment in the iFlow XML rather than asymmetric lists.

## What the callee sees in its MPL run

- A **separate run** from the caller's, with its own MPL entry.
- The body is whatever the caller sent.
- The headers are the intersection of caller-allowlist and callee-allowlist.
- The properties are **the callee's own** — no properties from the caller cross the ProcessDirect boundary.

## How the response flows back

For Request-Reply MEP:

1. Callee runs through its steps.
2. The body at the callee's End event is what the caller sees as the response body.
3. **Headers set by the callee** are subject to the *caller-side* receiver's Allowed Headers — for return propagation, the caller adapter's allow-list also applies on the inbound direction. Project pattern: keep both sides symmetric to avoid asymmetric debugging.

## Multiple ProcessDirect senders on one iFlow

You can have several ProcessDirect sender adapters on a single iFlow, each with its own Address. Common pattern:

- `/orderTranslator/v1/translate/<initials>` — main entry (current contract)
- `/orderTranslator/v2/translate/<initials>` — breaking-change new contract
- `/orderTranslator/v1/healthCheck/<initials>` — diagnostic ping

Each address starts a run in its own branch (you'd use a Router right after the entry to dispatch). See `versioned_endpoint_pattern.md` for the v1+v2 coexistence rollout.

## Common configuration mistakes

| Wrong | Symptom | Fix |
|---|---|---|
| Address typo (different from caller's) | Caller fails with "no consumer registered for endpoint" | Match the strings exactly. Copy-paste, don't re-type |
| Callee Allowed Headers does not include `correlationId` | Tracing breaks despite caller setting it | Symmetric lists |
| Caller deployed before callee | Caller deploys fine, runtime fails on first call: "no consumer" | Deploy callee first, then caller |
| Two callees registered on the *same* Address | Deploy error: "duplicate endpoint" | One Address = one callee. Use different versions for the same logical endpoint |
