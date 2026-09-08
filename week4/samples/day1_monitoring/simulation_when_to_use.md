# Simulation mode — what works, what doesn't

The iFlow editor's **Simulation** lets you step through an iFlow with a sample payload, inspect body / headers / properties at each boundary, and set breakpoints. It runs against a local Camel runtime in the browser — not the tenant.

## What it's good for

| Use case | Works in simulation? |
|---|---|
| Debugging a Content Modifier expression | Yes |
| Stepping through a Groovy script | Yes, including breakpoints |
| Inspecting body/header transitions at each step | Yes — the *Variables* panel is the killer feature |
| Verifying an XPath / JSONPath extraction | Yes |
| Testing a Filter step's predicate | Yes |
| Verifying a Router's branch selection | Yes |
| Testing a Mapping step | Yes |

If your bug is "what's the body after this Content Modifier?", simulation answers it in 20 seconds without a deploy round-trip.

## What it does NOT do

| Won't work | Why |
|---|---|
| **JMS Sender / Receiver** | No JMS broker in the local runtime — these steps no-op or throw |
| **ProcessDirect to a different iFlow** | Other iFlow isn't running; the call falls into the void |
| **OAuth2 Receiver** | No token endpoint reachable; auth fails |
| **HTTPS Receiver to a real backend** | Browser can't reach internet hosts directly |
| **Data Store Get/Write** | No backing store; reads return empty, writes are dropped |
| **Number Range Increment** | No backing artifact; returns null or throws |
| **Global Variable read/write** | No backing store |
| **Anything stateful or out-of-process** | Simulation is single-message, in-browser |

## The principle

Simulation is **a calculator for transformations**, not **a test environment for integrations**. If your iFlow is "compute → call → compute", you can simulate the two compute steps but you'll see no call.

## How to start a simulation

1. Open the iFlow in the editor.
2. Click *Simulate* (top toolbar, top-right area).
3. Choose start step (defaults to first sender step's output).
4. Choose end step (defaults to last receiver step's input).
5. Provide sample body, headers, properties.
6. Click *Run*.

The canvas highlights the executed path; the right-hand panel shows variables at each boundary.

## Setting up a sample payload

For the Order Hub, a useful sample:

```json
{
  "orderId": "C-3001",
  "customer": "Acme GmbH",
  "totalAmount": 1500,
  "lines": [
    { "sku": "S-1", "quantity": 2, "unitPrice": 750 }
  ]
}
```

Headers to provide:

| Header | Sample value |
|---|---|
| `X-Idempotency-Key` | `abc-123-test` |
| `correlationId` | `sim-trace-1` |
| `Content-Type` | `application/json` |

Save your sample payloads under a `simulation/` folder next to the iFlow. The cohort reuses each other's; project convention is filename = scenario name (`happy-path.json`, `missing-customer.json`).

## Breakpoints in Groovy scripts

In a Groovy script step:

1. Click the line gutter to set a breakpoint.
2. Start simulation; execution pauses at the breakpoint.
3. Inspect locals via the *Variables* panel.
4. Step over (F10), step into (F11), continue (F5).

This is faster than `messageLog.addAttachmentAsString` + deploy + send + read.

## Limitations on Groovy scripts

- `messageLogFactory.createMessageLog(message)` returns a stub in simulation — attachments and properties go to a panel, not a real MPL.
- `httpClient` calls (custom HTTP from a script) fail in simulation.
- Class loading is the same as runtime — most v2 APIs work.

## When to fall back to a deploy

If your bug involves:
- JMS, ProcessDirect, OAuth, or anything stateful
- Multi-iFlow choreography
- Real backend responses

…deploy and run a curl. Simulation won't help.

## Workflow recommendation

1. **Develop with simulation** while you build the transformation logic.
2. **Deploy and curl** once the transformation is right, to verify the integration steps.
3. **Re-enter simulation** if you find a new transformation bug.

Avoid the trap of deploying-every-change. A simulation cycle is ~5 seconds; a deploy cycle is ~30. Save the long ones for what only deploy can answer.

## Limitations to remember

- Simulation runs against the iFlow's **current saved state**, not its current deployed state. If you've made unsaved changes, simulate them. If you've deployed something old, only deploy + curl tests it.
- Simulation does not exercise externalized parameters — you provide values in the simulation dialog manually.
- Performance characteristics differ from runtime — don't measure timing in simulation.
