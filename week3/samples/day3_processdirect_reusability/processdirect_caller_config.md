# ProcessDirect — caller side (the iFlow that initiates the call)

On the **caller** iFlow you drop a *Request-Reply* flow step paired with a **ProcessDirect receiver** adapter. The "receiver" terminology: the iFlow *sends* the call to a downstream endpoint, the endpoint is the *receiver*. This is how `roi_<initials>_OrderHub` invokes `roi_<initials>_OrderTranslator`.

## Where it sits in the Order Hub producer

```
HTTPS sender ──► Content Modifier (X-Order-Format=json)
              ──► Script (roiam_logIncoming.groovy)
              ──► Request-Reply + ProcessDirect receiver ──► /orderTranslator/v1/translate/<initials>
              ──► (response body = canonical XML)
              ──► JMS receiver ──► roi.orderhub.outbound.<initials>
              ──► Content Modifier (response: 202 + JSON)
              ──► End
```

The ProcessDirect call sits **between** the input formatter and the JMS enqueue. By the time the body reaches the JMS receiver, it is the canonical XML returned from the translator.

## Adapter configuration

| Property | Lab value | Why |
|---|---|---|
| Address | `/orderTranslator/v1/translate/<your_initials>` | Versioned endpoint segment (`v1`). See `versioned_endpoint_pattern.md` |
| Message Exchange Pattern (MEP) | `Request-Reply` | The translator returns canonical XML; we need its body back |
| Allowed Headers | `correlationId,orderId,X-Order-Format,X-Idempotency-Key,X-Order-Sequence` | Comma-separated explicit list. **Empty = nothing propagates.** See `header_allowlist_reference.md` |
| Timeout | `60000` (ms) — default | The translator is fast; default is fine. Raise only if you measure a need |

The Address field is **not** a URL — no `https://`, no host. It's a logical path scoped to the tenant. Two iFlows on the same tenant can call each other across this address; cross-tenant ProcessDirect does not exist.

## What does and does NOT propagate

| What | Direction caller → callee | Direction callee → caller |
|---|---|---|
| **Body** | Yes (automatic) | Yes (automatic, Request-Reply only) |
| **Headers** | Only those in *Allowed Headers* | Only those the callee allow-lists on its sender adapter |
| **Properties** | **NEVER** | **NEVER** |
| **Attachments** | No (the MessageLog is per-run, not per-message) | No |

The properties rule trips people up. If `${property.errorCategory}` is set in the caller and the callee tries to read `${property.errorCategory}`, it will be **null**. Either:

- Lift it to a header before the ProcessDirect call: `X-Error-Category = ${property.errorCategory}`, allow-list it, read it back as `${header.X-Error-Category}` on the callee.
- Or push it into the body if it logically belongs there.

## Sync vs. async at the caller

| MEP | Caller behavior | When to use |
|---|---|---|
| Request-Reply | Caller waits for callee to return; body is replaced with callee's response body | Today's lab — translator returns canonical XML |
| One-Way (Send) | Caller fires-and-forgets; continues with the same body it had before the call | Fire-and-forget audit logging, downstream notifications |

**MEP must match between caller and callee.** Request-Reply on one side and One-Way on the other = deploy error.

## What the MPL shows

After a successful ProcessDirect call:

- The **caller's** MPL run shows a Request-Reply sub-step labeled with the Address.
- The **callee's** MPL is a **separate run** with its own correlationId/MPL entry — linked by `correlationId` only if you allow-listed it.
- Total wall-clock latency: typically 50–200 ms for an in-tenant ProcessDirect call. No network = no jitter.

## Common configuration mistakes

| Wrong | Symptom | Fix |
|---|---|---|
| Allowed Headers left empty | `correlationId` missing on the callee — cross-run tracing breaks | Set the comma-separated list explicitly |
| Address has `https://` or hostname | Deploy fails — Address is a path, not a URL | `/orderTranslator/v1/translate/<initials>` |
| MEP = One-Way but logic expects a response | Body unchanged after the call; downstream Mapping step sees the JSON not the XML | Match MEP. Request-Reply for translator-shaped uses |
| Calling a version that isn't deployed | Caller fails with "no consumer registered for endpoint" | Deploy callee first; verify the Address spelling |
