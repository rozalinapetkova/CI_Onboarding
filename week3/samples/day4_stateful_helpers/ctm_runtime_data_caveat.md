# CTM transports — definitions transport, runtime data does not

The most common Day-3-into-Week-4 gotcha: you transport `roi_<initials>_OrderHub` from Dev → QA, and the QA team gets the iFlow but the Number Range starts at whatever Dev was at, and the Data Store has either Dev's entries or none, and nobody's sure which.

This file clarifies what does and doesn't move with a CTM transport, and prescribes the post-transport runbook.

## What CTM packages contain

When you create a CTM transport for the *Training* package:

| Artifact | Transported? | What exactly moves |
|---|---|---|
| iFlow `roi_<initials>_OrderHub` | Yes | XML definition, all referenced scripts, current artifact version |
| Script Collection `sc_<initials>_OrderHubHelpers` | Yes | Scripts under `script/v2/`, current collection version |
| Data Store **definition** | Yes (as part of iFlow XML) | The reference; the runtime auto-creates the store on first deploy if missing |
| Data Store **entries** | **No** | Per-tenant runtime data |
| Number Range **definition** | Yes (if included in package) | Name, Min, Max, Format, Rotate, Field Length |
| Number Range **current value** | **No** | Per-tenant runtime data — starts at Min in destination |
| Global Variable **definition** | Yes (if defined in package) | The name |
| Global Variable **current value** | **No** | Per-tenant runtime data |
| Externalized Parameters | Definitions yes, **per-environment values no** | Each tenant has its own parameter values set in the cockpit |
| JMS queue **definition** | Per-tenant queues auto-provision on first deploy |
| JMS queue contents | **No** | In-flight messages stay on source tenant |
| User credentials (OAuth2, basic) | Definitions only | Secrets must be re-entered in destination |
| Keystore entries | **No** | Re-uploaded manually |

The shorthand: **anything an operator can edit in *Monitor → Manage Stores* is per-tenant runtime data** and doesn't transport.

This is correct behavior. You don't want production order numbers to bleed into Dev. You don't want Dev test PII in QA. You don't want a JMS queue's stale messages from Dev to start being processed by QA.

## Post-transport runbook

After a Dev → QA promotion of the Order Hub package, execute this checklist on the destination tenant.

### 1. Verify deployment

*Monitor → Started iFlows* — confirm:
- `roi_<initials>_OrderHub` — Started.
- `roi_<initials>_OrderHubConsumer` — Started.
- `roi_<initials>_OrderTranslator` — Started.
- `sc_<initials>_OrderHubHelpers` — Started.

### 2. Set Externalized Parameters

If the iFlow uses Externalized Parameters (downstream API URL, OAuth credential alias, queue name suffix), each must be configured in QA via *Manage Integration Content → iFlow → Configure*.

### 3. Reset Number Range current value

*Monitor → Manage Stores → Number Ranges → nr_<initials>_OrderSequence → Edit current value → 1*.

Reason: the transport carries the *definition* but the destination range starts at its Min (typically 1) regardless. Confirming this puts QA in a known state.

For a CTM into production, ops generally pre-seeds the Number Range to a value chosen by the business — e.g. `1000000` to leave the first million sequences as "test data" — to make business reports easier to filter.

### 4. Clear Data Store entries (or confirm empty)

*Monitor → Manage Stores → Data Stores → ds_<initials>_OrderIdempotency → Entries*.

Expected: empty (the store was auto-created on first QA deploy; no entries until first call).

If non-empty in QA after a fresh transport, someone has been running tests already — coordinate before clearing.

### 5. Re-enter secrets

*Manage Security → Security Material*:
- OAuth2 client credentials for downstream API — keep aliases identical to Dev, but enter QA-specific client IDs/secrets.
- Keystore entries — re-upload signing/encryption keys.

The iFlow references these by *alias*. The alias is in the transport; the secret value is not.

### 6. Smoke test

Run `call_orderhub_idempotent.sh` against the QA tenant. Confirm:
- Call 1 returns `orderSequence: ORD-0001` (QA's NR is at 1).
- Call 2 returns the cached envelope.
- Call 3 returns `orderSequence: ORD-0002`.

If sequences look different (e.g. `ORD-0042`), the NR wasn't reset. Go back to step 3.

### 7. Document the QA-specific values

In the deploy runbook for this iFlow, record:
- Date of transport.
- Source version (Dev artifact version).
- Destination version (QA artifact version after deploy).
- NR current value at smoke-test time.
- Anyone who needs to know about the deploy.

## Anti-patterns

| Anti-pattern | What goes wrong | What instead |
|---|---|---|
| Transporting an iFlow and assuming everything is "ready" | Ops finds half the params missing, NR at Dev's value, secrets blank | Always run the runbook |
| Skipping the NR reset in QA "because the values don't matter" | QA's first order number is some random number Dev was on; QA reports look weird | 30-second reset; do it every time |
| Running QA test with Dev's stored idempotency entries | False cache hits if the test reuses a Dev key | Empty the Data Store before testing |
| Copying Dev's OAuth credential secrets into QA | Dev's tokens may grant Dev's permissions — could let a QA test mutate production data on the downstream | Each environment has its own credentials. No copies |
| Forgetting to redeploy after Externalized Parameter changes | Parameter change saved but iFlow still runs old value | Always redeploy after parameter edit |

## Why the design is this way

The CI design philosophy: **iFlow artifacts (and their schema) are versioned, transported, and source-controlled. Runtime data is per-tenant and operationally managed.**

This separation is why:
- Test data never leaks into production accidentally.
- Production secrets never propagate to Dev / QA where they could be exposed.
- Each environment is independently reset/replayed without affecting others.

The cost is the post-transport runbook. Worth it.
