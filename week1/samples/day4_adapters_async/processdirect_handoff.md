# ProcessDirect handoff — main → CustomerLogger

ProcessDirect is the internal bus between two iFlows. **In-memory, single-tenant, not metered, no QoS guarantees.** Use it for composition; never for cross-tenant or cross-account communication.

## Address

`/ProcessDirect/<initials>_customerLog`

Conventions:
- Always start with `/ProcessDirect/`.
- The path after that is free-form but should be unique per consumer. Use the consumer iFlow's short name.

## Adapter — sender side (main iFlow)

ProcessDirect receiver step at the end of the happy path, after the country lookup and *before* the synchronous reply to the client.

| Setting | Value | Notes |
|---|---|---|
| Address | `/ProcessDirect/<initials>_customerLog` | Must match the consumer's listener exactly. |
| Allowed Headers | `correlationId\|customerId\|X-Logged` | **Critical** — only headers on this pipe-separated list cross the boundary. Everything else is dropped. |

> The headers field is an **allow-list**, not a filter. If you forget `customerId` here, the consumer's Data Store key will be null.

**`X-Logged` matters here specifically because this is the *return* trip.** The consumer sets `X-Logged: true` on its own response — but a header the callee sets only makes it back to the caller if it's on *this* list (the caller's own receiver-side Allowed Headers), not the callee's. Forget it here and `X-Logged` silently never comes back, even though the callee sent it.

## Adapter — consumer side (`roi_<initials>_CustomerLogger`)

ProcessDirect sender step as the start of the consumer iFlow.

| Setting | Value | Notes |
|---|---|---|
| Address | `/ProcessDirect/<initials>_customerLog` | Same string. |
| Allowed Headers | `X-Logged` | Doesn't govern the return trip (see above) — this list only filters what comes *in* from the caller. Set it anyway; keeping both sides' lists in sync is the project convention. |

That's it — no auth. MEP is Request-Reply (ProcessDirect's only option, set here too). The receiving iFlow just listens.

## Properties — the trap

**Exchange properties NEVER cross the ProcessDirect boundary**, regardless of any allow-list. If the main iFlow set `CustomerRequest` as a property and the consumer needs it, either:
- Promote it to a header (subject to the allow-list), or
- Put it in the body, or
- Re-derive it from the body in the consumer.

The cookbook's preferred pattern: **headers carry routing/identity, body carries data**. Properties stay local.

## What you'll see in MPL

Each ProcessDirect hop appears as a separate Message Processing Log entry. Two iFlows → two MPLs, correlated by `correlationId` header (which is why we put it on the allow-list).

## What you won't see

No metering hit. Verify on the Monitor → Usage tile: outbound count stays the same as before you split.
