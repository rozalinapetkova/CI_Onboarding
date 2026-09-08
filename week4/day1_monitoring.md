# Day 4.1 — Monitoring & Logging

> **Goal of the day.** Stop treating "the message ran" as a binary outcome. By end of day, instrument the Resilient Order Hub so that a stranger reading the Monitor on a Saturday at 3am can answer four questions in under two minutes: *what happened, where, to which business entity, and is it still my problem?*

## 1. The 8 MPL statuses, what they mean, what they hide

Every iFlow execution produces one **Message Processing Log** (MPL) entry. The status is the first thing operations sees. Most teams know two of the eight statuses; the rest is where the bugs hide.

| Status | When you see it | Alerting? |
|---|---|---|
| **Pending** | Message accepted but not yet picked up — typically a stuck queue consumer or a sender adapter still buffering | Yes if it persists > expected SLA |
| **Processing** | Currently executing | No — but watch for ones stuck > timeout |
| **Completed** | Run finished without an exception bubbling up | **Be careful**: HTTP error suppression / receiver branch on 4xx looks like Completed |
| **Failed** | An exception reached the iFlow boundary | Yes, always |
| **Retry** | A retry policy is in effect (typically JMS / SFTP polling); next attempt scheduled | Maybe — alert on retry count, not on Retry status itself |
| **Escalated** | All retries exhausted; message moved on (e.g., to DLQ) | Yes, this is the human-attention status |
| **Discarded** | Message intentionally dropped (idempotency duplicate, filter step) | Usually no, but log the count |
| **Abandoned** | Tenant restart / runtime kill before completion | Yes — should be rare; investigate root cause |

The trap: **Completed does not mean "no error".** If you uncheck "Throw Exception on Failure" on an HTTP receiver and branch on `CamelHttpResponseCode`, a 500 from the backend looks like a successful run. Your alerting must look at what the iFlow *did*, not just at MPL status.

Today's lab will reproduce all 8 statuses on the Order Hub on purpose.

## 2. Log levels — Info / Error / Debug / Trace

Each iFlow has a deployable **Log Configuration** with four levels:

| Level | Captures | Use when | Cost |
|---|---|---|---|
| **None** | Nothing — `messageLogFactory.createMessageLog(message)` returns `null` | Never in production for the Order Hub | Free |
| **Error** | Default. Failed runs only | Default for stable iFlows | Low |
| **Info** | All runs, with attachments and properties you set | Production iFlows you actively monitor | Medium |
| **Debug** | Info + step-level traces | Investigating a specific issue, then revert | High |
| **Trace** | Debug + payload at every step boundary | Reproducing a hard bug; **never leave on** | Severe — payloads stored in tenant log store |

The `messageLog != null` guard you learned in Week 2 (Day 2.4) exists for the **None** case. It's mandatory because operations *can* set None on an iFlow you wrote, and your script must not crash because of it.

Rule for the Order Hub: **Info level in QA, Info in Prod, never Debug or Trace beyond an active investigation that is documented in changelog**.

## 3. The MessageLog API recap (callback to Week 2 Day 2.4)

```groovy
def messageLog = messageLogFactory.createMessageLog(message);
if (messageLog != null) {
    messageLog.addAttachmentAsString("incoming-payload", payloadString, "application/json");
    messageLog.setStringProperty("orderId", orderId);
    messageLog.setStringProperty("correlationId", correlationId);
}
```

Three things to remember:

1. **`addAttachmentAsString(name, content, mimeType)`** — visible in *Monitor → Message Processing → click message → Attachments*. Name them like log file lines: `incoming-payload`, `after-canonicalize`, `before-receiver-call`, `error-snapshot`.
2. **`setStringProperty(name, value)`** — adds an MPL-searchable key/value at the message level. This is what makes `orderId` and `correlationId` searchable in the Monitor.
3. Attachments and properties only show in the Monitor when log level is **Info or higher**. At **Error**, only failed runs see their attachments retained.

Don't log secrets. The tenant log store is read by operations and other developers — same rule as Week 2.

## 4. Custom header search — where business identifiers come from

The Monitor's *Search* lets operations find messages by built-in fields (timestamp, status, integration flow) and by *custom* identifiers if you registered them. Two ways to register:

- **MPL custom header properties** — checkbox on Content Modifier "Message Header" tab. Headers checked here become searchable as message properties.
- **`messageLog.setStringProperty(name, value)`** — programmatic equivalent. Use this from a Groovy script when the searchable value is computed (e.g., parsed out of a payload).

For the Order Hub, register at minimum:

- `orderId` (business identifier — what operations searches by)
- `correlationId` (cross-iFlow trace ID)
- `customerId` (carried over from Week 1)
- `eventId` (from Day 4.3, when Event Mesh subscription is added)

If a value isn't searchable, it doesn't exist in operations' eyes.

## 5. Correlation ID strategy

Two IDs to know:

| Header | Source | Scope |
|---|---|---|
| `SAP_MessageProcessingLogID` | Auto-generated per MPL entry | Native MPL search; one per iFlow run |
| `correlationId` | Project convention — generated by us, propagated across hops | End-to-end business trace |

The project rule: **`SAP_MessageProcessingLogID` is per run; `correlationId` is per business transaction.** A single business order may produce 5 MPL entries (sender iFlow run → JMS producer iFlow run → JMS consumer iFlow run → receiver call → response handler). Each gets its own `SAP_MessageProcessingLogID`. They share one `correlationId`.

Pattern in the Order Hub inbound script (call back to Week 2's `processData` style):

```groovy
import com.sap.it.script.v2.api.Message;
import java.io.Reader;
import java.util.UUID;

def Message processData(Message message) {
    def headers = message.getHeaders();

    String correlationId = headers.get("correlationId") as String;
    if (correlationId == null || correlationId.trim().isEmpty()) {
        correlationId = UUID.randomUUID().toString();
    }
    message.setHeader("correlationId", correlationId);

    def messageLog = messageLogFactory.createMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("correlationId", correlationId);
    }

    return message;
}
```

Save as `roiam_setCorrelationId.groovy` under the iFlow's `script/v2/` folder. Place this script as the **first** step after the sender adapter, every time, on every iFlow.

ProcessDirect callee tip: remember from Week 1 Day 1.4 that ProcessDirect doesn't propagate headers by default. **Add `correlationId` to the Allowed Headers list** on every ProcessDirect adapter or your trace breaks at the boundary.

## 6. Simulation — the only way to test step-by-step without a tenant

The iFlow editor's **Simulation** mode lets you run the iFlow against a sample payload with breakpoints at each step. It uses a local Camel runtime, not the tenant — so it won't talk to JMS, OAuth receivers, ProcessDirect to other iFlows, etc. (anything stateful or out-of-process is a no-op).

Use simulation when:
- You're debugging a Content Modifier expression and don't want a deploy round-trip.
- You want to inspect the body / headers / properties at each step.
- You're stepping through a Groovy script with `messageLog` attachments.

Don't rely on simulation for: anything that touches JMS, ProcessDirect to a different iFlow, OAuth receivers, Data Store. Those need the tenant.

## 7. Alert Notification — the bridge to operations

SAP **Alert Notification Service** (ANS) is a separate BTP service that turns events into actions. It is the recommended integration between Cloud Integration's MPL and your operations channels.

### Concepts

- **Producer**: anything that sends an event to ANS (CI tenant emits MPL events automatically; you can also send custom events from a script).
- **Action**: the delivery channel — email, webhook, MS Teams, Slack, ServiceNow, PagerDuty, OpenAPI.
- **Subscription**: the binding between event filters and actions. Filters can match on event category, severity, integration flow name, etc.

### Action types you'll wire up

| Action type | Use for |
|---|---|
| **Email** | Cohort distribution list during training; on-call mailbox in production |
| **Webhook** | Custom alerting integration (e.g., feeding into your incident-management tool) |
| **MS Teams** | Operations team's channel; typically the first action on Sev-2 alerts |
| **Slack** | Same role as Teams on Slack-shop tenants |

### Project naming convention for ANS event categories

Categories follow `roi.<iflow-stem>.<reason>`:

- `roi.orderhub.dlq` — message went to DLQ
- `roi.orderhub.poison` — malformed payload, won't retry
- `roi.orderhub.transport` — CTM-related events
- `roi.orderhub.subscription-down` — Event Mesh subscription lost connection

Categorizing this way lets the operations team write **one subscription per category** and route them to different action sets independently.

## 8. Cloud ALM — when to use it instead of (or alongside) ANS

**Cloud ALM** is SAP's Application Lifecycle Management product. For integration, it offers:

- Synthetic monitoring (scheduled `curl`-style checks against your iFlow endpoints).
- Real user monitoring across the BTP estate.
- Change tracking (tied to CTM transports — see Day 4.2).
- Long-term metric storage (90+ days vs. ANS's short-window event store).

When to choose what:

| Need | Tool |
|---|---|
| "Wake somebody up *right now*" | Alert Notification |
| "Was this iFlow up at 02:14 last Tuesday?" | Cloud ALM |
| "Catch deploys that broke a downstream consumer" | Cloud ALM (change tracking) + ANS (immediate) |
| "Track end-of-quarter SLA report" | Cloud ALM |

For the Order Hub: ANS is required (for the lab); Cloud ALM is the trainer's *guided tour* — show the cohort the cockpit, the synthetic monitoring screen, the change events. Don't ask them to wire it up this week.

## 9. Reproducing the 8 statuses on demand

This is the lab's centerpiece. Knowing how to *cause* each status makes you trust the alerting that watches for them.

| Status | How to provoke it | Notes |
|---|---|---|
| Pending | Undeploy the JMS consumer iFlow, send a message → producer Completes, queue holds the message | Visible in *Monitor → Messages → Queues* |
| Processing | Send a message into a step with a deliberate `sleep(30000) { }` and look quickly | Closes once the run completes |
| Completed | Happy-path `curl` | Trivial |
| Failed | Send malformed JSON, no exception subprocess yet | Day 4.4 will catch this with the subprocess |
| Retry | JMS consumer raises exception → max-occurrence not yet reached | Configure 3 retries with 30s backoff |
| Escalated | Same as Retry but exhaust attempts → DLQ | Day 4.4 wires this together |
| Discarded | Hit the idempotency Data Store guard (replay same `orderId`) → message intentionally dropped | Day 4.4 |
| Abandoned | Trainer restarts the tenant worker mid-run | Trainer demos this once, don't try at home |

---

## Hands-on lab — Instrument the Resilient Order Hub

> Time: ~3 hours. Goal: take the Week 3 Resilient Order Hub and make it observable to a stranger in operations. Reproduce all 8 MPL statuses by end of session.

### Setup

- Resilient Order Hub deployed from Week 3 (OAuth2 receiver, JMS producer/consumer, idempotent via Data Store, sequence number, Script Collection wired in).
- Log Configuration on the iFlow set to **Info**.
- Alert Notification entitlement available (cohort-shared instance) with one *Email* action pre-wired by the trainer.
- A test JMS DLQ already exists from Week 3 (`roi.orderhub.dlq`).

### Steps

1. **Add `roiam_setCorrelationId.groovy`** as the first script step after the inbound HTTP sender. Place it under `script/v2/` inside the iFlow project. Upload via the *Script step dialog* — never the Resources tab (Week 2 Day 2.4 rule).
2. **Register the searchable headers.** There's no Content Modifier checkbox for this — it's script-only. In the script step that already has each value on hand, call `messageLog.addCustomHeaderProperty(name, value)` (with the null-guard) for `orderId`, `correlationId`, and `customerId`.
3. **Add MessageLog attachments** at four boundaries:
   - After inbound canonicalization → `incoming-canonical`
   - Before JMS send → `pre-jms`
   - After JMS receive (consumer side) → `post-jms`
   - Before receiver call → `pre-receiver`
   Each attachment uses the project null-guard pattern and `application/xml` (or `application/json`) MIME type.
4. **Deploy**, send one happy-path `curl`, open *Monitor → Message Processing*. Confirm:
   - All four attachments are visible.
   - `correlationId` is searchable.
   - `SAP_MessageProcessingLogID` is auto-populated and unique per iFlow run; `correlationId` is shared across the producer and consumer runs.
5. **Provoke 8 statuses** in this order — one trainee's tenant is enough; the cohort gathers around:
   - **Completed** — happy `curl`.
   - **Processing** — temporarily add a `sleep(20000) { interrupted -> /* */ }` in a script step, send a message, refresh quickly. Remove the sleep afterwards.
   - **Failed** — send malformed JSON, no exception subprocess yet.
   - **Retry** — undeploy the OAuth2 receiver target, send a message → JMS consumer raises → first retry visible.
   - **Escalated** — let the retries exhaust → message moves to DLQ.
   - **Pending** — undeploy the JMS consumer iFlow itself, send a message → producer Completes, queue depth shows in *Monitor → Messages → Queues*.
   - **Discarded** — re-deploy everything, send the *same* `orderId` twice; the second one hits the idempotency guard and is intentionally discarded.
   - **Abandoned** — trainer-only. Trainer restarts the tenant worker mid-run; cohort observes one Abandoned message.
6. **Wire the Alert Notification subscription.** Trainer demonstrates the cockpit; trainees create one subscription with category filter `roi.orderhub.dlq`, action *Email* to their training distribution list. Verify the email arrives by replaying the Escalated scenario above. (The actual emit step happens in Day 4.4 — for now, generate a synthetic event from the ANS cockpit's *Test Event* button just to prove the wiring.)
7. **Cloud ALM tour** (~15 min, trainer-driven). Trainer screen-shares the Cloud ALM cockpit, walks through synthetic monitoring config, change-tracking page, and the "Last 30 days" availability report.

### Failure cases to provoke

- Forget the `messageLog != null` guard, set Log Level to None on the iFlow → the script crashes the run with NPE. *Lesson:* the guard is mandatory.
- Skip the `messageLog.addCustomHeaderProperty(...)` call → `orderId` is set but not searchable. Operations cannot find the message by business identifier. *Lesson:* setting the header isn't enough — it has to be explicitly registered from script.
- Forget to add `correlationId` to the ProcessDirect Allowed Headers list (if your Order Hub uses ProcessDirect anywhere) → trace breaks at the hop. *Lesson:* every ProcessDirect needs an explicit allow-list (Week 1 callback).

---

## Reference card excerpt — Day 4.1

- **8 MPL statuses:** Pending, Processing, Completed, Failed, Retry, Escalated, Discarded, Abandoned. Alert on Failed + Escalated + (sometimes) Pending; never on Completed alone.
- **"Completed" is not "successful"** — HTTP error suppression hides 4xx/5xx behind a green status.
- **Log levels:** Info in QA + Prod, Debug only during active investigation, Trace never beyond a documented incident.
- **MessageLog pattern:** `def messageLog = messageLogFactory.getMessageLog(message); if (messageLog != null) { messageLog.addAttachmentAsString("name", content, mimeType); messageLog.setStringProperty("key", value); }`. Null guard is mandatory.
- **Correlation:** generate or accept `correlationId` on the inbound step, set as header, register as MPL searchable property. `SAP_MessageProcessingLogID` is per run, `correlationId` is per business transaction.
- **Custom header search:** call `messageLog.addCustomHeaderProperty(name, value)` from script — the only mechanism that makes a value searchable Monitor-wide. `setStringProperty` is not equivalent: it only shows up in that one script step's own Properties subsection (Debug/Trace level only), never in Search. There's no Content Modifier checkbox for this.
- **Alert Notification categories** follow `roi.<iflow-stem>.<reason>` (e.g., `roi.orderhub.dlq`).
- **Cloud ALM** for long-term + synthetic + change tracking; **ANS** for "wake somebody up now". Use both.
- **Simulation** is local-only — no JMS, no ProcessDirect-cross-iFlow, no OAuth.
- **Don't log secrets.** Tenant log store is multi-developer.
