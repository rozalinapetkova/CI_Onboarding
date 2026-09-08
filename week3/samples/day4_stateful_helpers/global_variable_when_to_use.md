# Global Variables — when to use, when to refuse

A Global Variable is a tenant-scoped name → string slot. There's exactly **one** pattern it's right for. Everything else that feels like it wants a Global is actually one of: Data Store, Number Range, Value Mapping, Externalized Parameter, or "no, the runtime already handles that for you."

## The one right pattern: high-water mark / last-success marker

A polling iFlow that runs on a timer, pulls "all records changed since X", and needs to remember the X for next time.

```
Timer (every 5 min)
    │
    ▼
Read Variable (Global) → property.lastSuccessTimestamp
    │
    ▼
HTTP receiver: GET /api/orders?changedSince=${property.lastSuccessTimestamp}
    │
    ▼
process records...
    │
    ▼
on success:
Write Variables (Global) → lastSuccessTimestamp = (now or max(changedAt) over batch)
```

Why this works:
- **Single writer.** The timer iFlow has Exclusive Consumer / single-instance semantics. No concurrent writers. The "not atomic" caveat doesn't bite.
- **Idempotent if missed.** If a write fails, the next run picks the same window. At-least-once polling is fine.
- **Tiny.** Single ISO timestamp string. Within the variable size limits.
- **Per-tenant.** Survives iFlow redeploy. Reset by ops only if intentional.

The day-module calls this the "high-water mark" pattern. It's the canonical Global-variable use case.

## The wrong patterns

| Want to use it for | Why it's wrong | What to use instead |
|---|---|---|
| **Counter** of messages processed | Read-modify-write isn't atomic — concurrent writes lose updates silently | Number Range (atomic) or external counter (Splunk, Prometheus, downstream system) |
| **Current configuration value** that "operations might change at runtime" | Not versioned, not transport-aware, no audit trail of changes | Externalized Parameter (versioned with iFlow, settable per environment) or Value Mapping (versioned cockpit artifact) |
| **Cached OAuth2 access token** | The runtime's OAuth2 client already caches tokens with proper expiry handling. Re-implementing it gives you stale tokens and concurrent refresh storms | Use the *OAuth2 Client Credentials* receiver / *OAuth2 Authorization Code* in the adapter; the runtime caches per credential alias |
| **Shared state between iFlow A and iFlow B** during a single workflow | Brittle coupling. Either iFlow's redeploy may catch the other mid-state. No transactional boundary | Pass via JMS, ProcessDirect headers, or a Data Store entry with a deliberate key |
| **Feature flag / kill switch** | Same as "current configuration value" — but worse, because operators expect a kill switch to be reliable | Externalized Parameter, or a dedicated config iFlow with a Data Store that ops can flip |
| **Last-seen ID for de-duplication** | Read-modify-write race; under load, duplicates slip through | Data Store with the message ID as the key |
| **Per-customer setting that varies by customer** | One name = one value globally; you'll end up with `cust_123_setting`, `cust_124_setting`, ... — proliferation | Data Store keyed by customer ID |

## How to read and write

### Read (in a Content Modifier)

| Field | Value |
|---|---|
| Type | *Expression* |
| Source | `${global.<variable-name>}` |
| Target | Property `lastSuccessTimestamp` (or whatever) |

### Read (in Groovy)

```groovy
import com.sap.it.script.v2.api.Message;
import com.sap.it.api.ITApiFactory;
import com.sap.it.api.variable.VariableAccessor;

def Message processData(Message message) {
    VariableAccessor accessor = ITApiFactory.getApi(VariableAccessor.class, null);
    String lastSuccess = accessor.getVariable("lastSuccessTimestamp");
    message.setProperty("lastSuccessTimestamp", lastSuccess ?: "1970-01-01T00:00:00Z");
    return message;
}
```

### Write

The *Write Variables* flow step:

| Field | Value |
|---|---|
| Name | `lastSuccessTimestamp` |
| Value | `${header.lastBatchTimestamp}` (or however you computed it) |
| Type | *Global* (vs. *Local* — Local is per-message, not what we want here) |
| Expires at | leave empty for permanent |

## Defensive review questions when someone proposes a Global

When a colleague suggests a Global Variable, ask:

1. **Will two iFlow runs ever write to this concurrently?** If yes, you need atomicity — pick something else.
2. **Does the value carry over to QA / Prod after a CTM transport?** Globals are tenant-local. Definitions transport; values don't. Will the destination tenant know to set it?
3. **What's the failure mode if the variable doesn't exist?** Globals can be deleted by ops. Read code should default gracefully.
4. **Why isn't this an Externalized Parameter?** If the answer is "because ops needs to change it at runtime without redeploying" — *that's* a Global use case (kind of). If the answer is "because we didn't know about parameters" — refactor.
5. **Is there a transactional boundary you're trying to maintain?** Globals don't provide one. JMS does, with proper ack/nack semantics.

If a colleague proposes a Global for the lab's Order Hub, push back. The Order Hub doesn't have a polling pattern. Idempotency is Data Store. Sequence is Number Range. There's no slot in this iFlow that wants a Global.

## Cockpit operations

*Monitor → Manage Stores → Variables*:

- List, view, edit, delete.
- Edit history (audit).
- Filter by name prefix.

Production-only access should require ops role. Dev/QA: any developer can edit.
