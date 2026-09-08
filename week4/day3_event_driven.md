# Day 4.3 — Event-Driven & Event Mesh / Partner Directory

> **Goal of the day.** Subscribe the Resilient Order Hub to an SAP Event Mesh AMQP topic so that an `S/4HANA SalesOrder.Created` event triggers the same flow your `curl` triggered yesterday — and resolve the routing target through Partner Directory rather than hardcoded headers. By end of day, your Order Hub no longer requires a caller; it reacts to S/4 events.

## 1. Why event-driven matters in CI

Most of what you've built is **request-reply** — a caller hits an endpoint and waits. Event-driven flips the question: *"what should happen when something occurs in S/4HANA?"* The producer (S/4) doesn't know about you; you subscribe to the event you care about.

Pros:
- Loose coupling — S/4 doesn't have to know that Order Hub exists.
- Multiple consumers — finance, logistics, and Order Hub can all react to the same `SalesOrder.Created` event.
- Buffering for free — if Order Hub is down, events queue in Event Mesh and replay when it's up.
- Native fit for "do X when Y happens" business rules.

Cons:
- Harder to trace a single business transaction (callbacks to Day 4.1 correlation strategy).
- Idempotency is on you — events can be delivered more than once.
- Failures are async — an event consumer fails alone, no caller to surface the error to.

For the Order Hub: we'll make it react to `SalesOrder.Created` from S/4HANA Cloud. The same canonical-XML-and-OAuth-receive pipeline you've built since Week 1 will run, except triggered by an event instead of a `curl`.

## 2. CloudEvents — the spec your event payloads follow

SAP standardized on **CloudEvents** (the CNCF spec) as the envelope format for events flowing through Event Mesh, Intelligent Services, S/4HANA, and SuccessFactors event channels. Every event has a consistent header set:

| CloudEvents attribute | What it carries (typical S/4 example) |
|---|---|
| `id` | Event-instance ID — your dedup key |
| `source` | Producer URL — `https://my-s4-tenant.s4hana.cloud.sap` |
| `specversion` | CloudEvents spec version, e.g., `1.0` |
| `type` | Event type — `sap.s4.beh.salesorder.v1.SalesOrder.Created.v1` |
| `subject` | Affected business entity, often the order ID |
| `time` | ISO 8601 timestamp |
| `datacontenttype` | `application/json` |
| `data` | The actual payload — order header, partner, items refs |

In CI, the AMQP adapter exposes these as **headers** on the message. So `id` is available as a header, you can log `correlationId` from it, etc. The payload `data` becomes the message body.

**Project convention:** map `id` → `correlationId` if no correlation header was already present. This makes the event's own dedup key act as the cross-system trace ID.

## 3. AMQP — the protocol Event Mesh speaks

**AMQP 1.0** (Advanced Message Queuing Protocol) is the wire protocol Event Mesh exposes for subscribing. CI provides an **AMQP receiver/sender adapter** for it. The mental model: AMQP is to Event Mesh what JMS is to the CI broker — same idea (queues, topics, durable subscriptions), different protocol family.

Differences from the JMS adapter you used in Week 3:

| Aspect | JMS (CI broker) | AMQP (Event Mesh) |
|---|---|---|
| Broker | CI tenant-internal | External BTP service |
| Counted toward metering | No | Yes (sender), no (consumer) — check your plan |
| Auth | Internal | Client credentials via Security Material |
| Destination naming | `flat-queue-name` | `queue:my-queue` or `topic:my-topic` (the queue is durable, the topic is the routing target) |
| QoS | At-Least-Once / EO | At-Least-Once typically |
| Retry semantics | Configured on JMS adapter | Configured on AMQP adapter; broker also re-delivers |

For the lab: the AMQP adapter sender (subscriber) on the Order Hub subscribes to a queue `roi-orderhub-salesorder-created`. The queue is itself subscribed to a topic `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/Created/v1` — that wiring is done in the Event Mesh cockpit, not the CI iFlow.

## 4. Topic naming — the convention you'll see

Topic names are slash-separated paths. The default S/4HANA Cloud convention:

```
s4/sap/s4hanacloud/ce/<bounded-context>/v1/<EntityName>/<Verb>/v1
```

Examples:

- `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/Created/v1`
- `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/Changed/v1`
- `s4/sap/s4hanacloud/ce/finance/v1/InvoiceDocument/Posted/v1`
- `s4/sap/s4hanacloud/ce/master/v1/BusinessPartner/Created/v1`

Subscribe with a wildcard `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/+/v1` if you want all SalesOrder lifecycle events; subscribe specifically when you want one.

For the lab: subscribe specifically to `Created`. Adding `Changed` would be a one-line addition once the Created flow is solid.

## 5. Intelligent Services — the curated event catalog

**SAP Intelligent Services** is a curated event catalog inside Integration Suite — it lists the events SAP applications publish, with their schemas, and lets you subscribe an iFlow to one through a guided UI rather than figuring out the topic name yourself. Under the hood it's still Event Mesh + AMQP.

Use Intelligent Services when:
- The event is published by an SAP cloud application (S/4HANA Cloud, SuccessFactors, Field Service, Concur).
- You want SAP-managed schema docs and a "get me wired up" wizard.

Don't use Intelligent Services when:
- The producer is custom or third-party — you need a direct AMQP subscription.
- You need wildcard subscriptions or multi-tenant routing — Intelligent Services UI hides advanced AMQP options.

For the lab: we use direct AMQP subscription to keep the mechanics visible. In real life on this team, you'd use Intelligent Services for the SAP-published S/4 events and direct AMQP for everything else.

## 6. Durable subscriptions — what "durable" actually means

A subscription is **durable** when the broker holds events for the consumer even when the consumer is offline. AMQP supports both durable and non-durable; for any production iFlow, **always durable**.

Why: if your iFlow is undeployed for a transport, a tenant restart, or a scheduled maintenance window, events keep arriving at S/4. Without a durable subscription, those events are gone forever — silently. With a durable subscription, they pile up in the queue and drain when you come back online.

In the AMQP sender adapter on the Order Hub, the relevant settings:

- *Subscription Type*: **Durable**.
- *Subscription Name*: stable, e.g., `roi-orderhub-salesorder-v1`. This is the broker-side identifier; renaming creates a new durable subscription and abandons the old one's backlog. Choose carefully.
- *Acknowledgement Mode*: **Client Acknowledgement** (CI sends ACK only when the iFlow run completes successfully).
- *QoS*: **At-Least-Once** — your consumer must be idempotent (next section).

## 7. Idempotency — your most important defense

AMQP delivers **at-least-once**. If your iFlow processes an event, then crashes before acknowledging, the broker re-delivers. If the broker thinks the network glitched, it re-delivers. Real workloads see duplicates daily.

Your consumer must be **idempotent**: processing the same event twice produces the same outcome as processing it once.

The Order Hub already has the Data Store guard from Week 3 keyed on `orderId`. For the event subscription, key on the **CloudEvents `id`** instead — it's the canonical event-instance identifier, immutable across re-deliveries.

Pattern (recap from Week 3, applied to the event entrypoint):

1. Read `id` from the AMQP message headers.
2. Check if `id` is already in the Data Store under entity `roi_orderhub_event_dedup`.
3. If found → log a `MessageLog` attachment `duplicate-event`, set MPL status to **Discarded** by routing to a no-op end (or use the *Filter* step), `return message;` early.
4. If not found → write the `id` to the Data Store with a TTL of 7 days (long enough to cover broker re-delivery windows, short enough to avoid unbounded growth), then continue normal processing.
5. Commit only on successful end. If the iFlow fails before completion, the dedup entry shouldn't be written — otherwise a failed event becomes a permanent skip.

Pre-Week-3 trainees might be tempted to skip this. Don't. The first prod incident on an event subscription is always "we processed the same order three times". Today is the day to internalize idempotency as a habit, not a checkbox.

## 8. Partner Directory — what it is, what it isn't

**Partner Directory (PD)** is CI's tenant-scoped key-value store designed for **routing and partner configuration**. Think of it as a small operational database that operations can edit *without redeploying* iFlows.

What lives in PD:
- Partner-specific endpoint URLs.
- Per-partner certificate aliases.
- Routing rules — "for partner X, send to system Y".
- Configuration parameters that change weekly without an iFlow release.

What does *not* live in PD:
- Secrets (use Security Material).
- Large blobs (PD is for kilobytes, not megabytes).
- Application data (use Data Store / your downstream system).

The data model:

| PD object | What it represents |
|---|---|
| **Partner** | A logical partner identity, identified by an `id` like `ROI_ORDERHUB_ROUTING` |
| **Type System** | A grouping of types (commonly *AS2*, *AS4*, or custom strings) |
| **Authorized User** | A user/principal mapping to one or more partners |
| **Parameter** (string or binary) | Key-value data for the partner — `parameterId` + content |
| **Alternative Partner** | Mapping a partner to alternative IDs (e.g., DUNS) |
| **Authentication / Certificate** | TLS material for partner-specific connections |

For the Order Hub today: one partner (`ROI_ORDERHUB_ROUTING`), one binary parameter holding a JSON routing config — same shape as the existing `scripts/standalone/roiam_loadGrcProxyConfig.groovy`.

## 9. Partner Directory access from Groovy

The script API, by example, in the project's existing `roiam_loadGrcProxyConfig.groovy` style. The pattern:

```groovy
import com.sap.it.script.v2.api.Message;
import com.sap.it.api.pd.PartnerDirectoryService;
import com.sap.it.api.pd.BinaryData;
import com.sap.it.api.ITApiFactory;
import groovy.json.JsonSlurper;
import groovy.json.JsonOutput;
import java.io.Reader;
import java.io.ByteArrayInputStream;

def Message processData(Message message) {
    def headers = message.getHeaders();

    String pid = "ROI_ORDERHUB_ROUTING";
    String parameterId = headers.get("roiam_routing_destination") as String;
    String eventType = headers.get("ce-type") as String;

    if (parameterId == null || parameterId.trim().isEmpty()) {
        throw new RuntimeException("Header 'roiam_routing_destination' is missing or empty");
    }
    if (eventType == null || eventType.trim().isEmpty()) {
        throw new RuntimeException("Header 'ce-type' is missing or empty");
    }

    def pdService = ITApiFactory.getApi(PartnerDirectoryService.class, null);
    if (pdService == null) {
        throw new RuntimeException("Partner Directory service not available");
    }

    BinaryData binary = pdService.getParameter(parameterId, pid, BinaryData);
    if (binary == null) {
        throw new RuntimeException("Routing parameter not found for partnerId: '${pid}', parameterId: '${parameterId}'");
    }

    JsonSlurper jsonSlurper = new JsonSlurper();
    def config = jsonSlurper.parse(new ByteArrayInputStream(binary.getData()));
    if (!(config instanceof Map)) {
        throw new RuntimeException("Partner Directory parameter '${pid}/${parameterId}' is not a JSON object");
    }

    def routes = config.get("routes");
    if (!(routes instanceof Map)) {
        throw new RuntimeException("'routes' missing or not an object in '${pid}/${parameterId}'");
    }

    def matched = routes.get(eventType) ?: routes.get("default");
    if (matched == null) {
        throw new RuntimeException("No route for eventType '${eventType}' and no default in '${pid}/${parameterId}'");
    }

    String targetSystem = matched.get("targetSystem") as String;
    String targetPath = matched.get("targetPath") as String;

    message.setHeader("roiam_target_system", targetSystem);
    message.setHeader("roiam_target_path", targetPath);

    def messageLog = messageLogFactory.createMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("targetSystem", targetSystem);
        messageLog.addAttachmentAsString("resolved-route", JsonOutput.toJson(matched), "application/json");
    }

    return message;
}
```

Save as `roiam_resolveRoutingFromPd.groovy` under `scripts/collections/resilientOrderHub/`. Inside the iFlow project, place under `script/v2/`. Upload via the *Script step dialog*.

The shape mirrors the existing standalone script — same imports, same `ITApiFactory.getApi(PartnerDirectoryService.class, null)` pattern, same `BinaryData` JSON parsing, same null guards on every field. This is intentional: when in doubt, copy the shape of an existing project script.

The PD parameter (set up by the trainer in the cockpit before lab) is a JSON document like:

```json
{
  "routes": {
    "sap.s4.beh.salesorder.v1.SalesOrder.Created.v1": {
      "targetSystem": "OMS_PROD",
      "targetPath": "/orders/inbound"
    },
    "sap.s4.beh.salesorder.v1.SalesOrder.Changed.v1": {
      "targetSystem": "OMS_PROD",
      "targetPath": "/orders/update"
    },
    "default": {
      "targetSystem": "OMS_PROD",
      "targetPath": "/orders/inbound"
    }
  }
}
```

Operations can edit this in the PD cockpit and the change is picked up at the next message — no iFlow redeploy. That's the value.

## 10. Putting it together — the Order Hub event subscription flow

```
[AMQP Sender Adapter]                       (subscribes to roi-orderhub-salesorder-created)
        |
        v
[Script: roiam_setCorrelationId]            (correlationId from CloudEvents 'id', or fresh UUID)
        |
        v
[Router: Idempotency Check via Data Store]  (key = CloudEvents 'id', entity = roi_orderhub_event_dedup)
   |              |
   discarded   not yet seen
   v              v
   end       [Script: roiam_resolveRoutingFromPd]
                  |
                  v
            [JSON → Canonical XML]          (re-uses the canonical mapping from Week 2)
                  |
                  v
            [JMS Producer]                  (puts onto roi.orderhub.queue, same as the HTTP path)
                  |
                  v
                  end
```

The clever bit: **the JMS queue is shared with the HTTP entry path**. Whether an order arrives via `curl` or via S/4 event, the same downstream consumer (Week 3 design) processes it. One iFlow change benefits both entry points.

## 11. Failure modes specific to event-driven

You haven't seen these in the request-reply world:

| Failure | Symptom | Mitigation |
|---|---|---|
| Subscription disconnects (broker glitch, credential rotation) | No messages arrive; queue depth grows on Event Mesh side | Alert on subscription connection state (Day 4.1 ANS category `roi.orderhub.subscription-down`); auto-reconnect on AMQP adapter |
| Poison message blocks the queue | Same message redelivered forever; nothing else processes | Maximum redelivery count + DLQ (Day 4.4 will wire this in) |
| Out-of-order delivery | `Changed` event arrives before `Created` | Either subscribe with EOIO (limits throughput) or design idempotent merging on the consumer side |
| Duplicate floods | Same `id` thousands of times due to producer bug | Dedup table grows unbounded; TTL on dedup entries (7 days here) bounds it |
| Schema drift | S/4 changes the event payload, your mapping breaks | Validate against schema at the entry script; route validation failures to the error path |

---

## Hands-on lab — Subscribe the Order Hub to Event Mesh

> Time: ~3 hours. Goal: the Order Hub, currently triggered only by HTTP, also reacts to `SalesOrder.Created` events on Event Mesh, deduplicates by CloudEvents `id`, and resolves the routing target through Partner Directory.

### Setup

- Order Hub deployed on Dev tenant with monitoring (Day 4.1) and recently transported to QA (Day 4.2).
- Event Mesh service instance bound to Dev tenant. AMQP credentials in Security Material as `event_mesh_amqp`.
- Trainer pre-created in Event Mesh cockpit:
  - Queue `roi-orderhub-salesorder-created`.
  - Subscription binding the queue to topic `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/Created/v1`.
- Trainer pre-created in Partner Directory:
  - Partner `ROI_ORDERHUB_ROUTING`.
  - Binary parameter `default` with the JSON routing config above.
- A test event publisher: trainer has a small "send fake S/4 event" helper iFlow that emits CloudEvents-shaped messages to the topic. Trainees use this to test without needing an actual S/4 tenant.

### Steps

1. **Add the AMQP entry branch** to the Order Hub. Drag a new sender adapter onto the canvas, type AMQP, configured for the Event Mesh credentials. Set:
   - *Address Type*: Queue.
   - *Address Name*: `roi-orderhub-salesorder-created`.
   - *Subscription Name*: `roi-orderhub-salesorder-v1`.
   - *Subscription Type*: Durable.
   - *Acknowledgement*: Client Acknowledgement.
2. **First step after the AMQP sender:** the existing `roiam_setCorrelationId.groovy` from Day 4.1, modified to pick up CloudEvents `id` if no `correlationId` header is present:

   ```groovy
   String correlationId = headers.get("correlationId") as String;
   if (correlationId == null || correlationId.trim().isEmpty()) {
       correlationId = headers.get("ce-id") as String;
   }
   if (correlationId == null || correlationId.trim().isEmpty()) {
       correlationId = UUID.randomUUID().toString();
   }
   ```

   Save the updated script via the *Script step dialog → Upgrade*.
3. **Idempotency guard.** Add a Data Store *Get* step keyed on `${header.ce-id}`, entity `roi_orderhub_event_dedup`. Branch:
   - If found → script that adds `MessageLog` attachment `duplicate-event` and routes to a no-op end.
   - If not found → continue.
4. **Add the routing-resolution script.** Save `roiam_resolveRoutingFromPd.groovy` from section 9. Place under `scripts/collections/resilientOrderHub/`. Inside the iFlow project, under `script/v2/`. Upload via Script step dialog. Place after the idempotency check.

   The script expects a header `roiam_routing_destination` — set this with a Content Modifier before the script call. Fixed value `default` for the lab; in real life this could be derived from the event's `subject` or another header.
5. **Map CloudEvents payload → canonical XML.** Re-use the canonical mapping from Week 2 (`vendor XML → canonical`) but feed the JSON-shaped CloudEvents `data` through the JSON-branch path instead. The output should be identical to the HTTP-triggered path's canonical XML — that's the point.
6. **Send to JMS.** The same JMS producer step that the HTTP path uses. Both entry points converge here.
7. **Idempotency commit.** On the success branch, *after* JMS send completes, write the CloudEvents `id` into the dedup Data Store with a 7-day TTL. (Don't write earlier — failed events should not be marked as seen.)
8. **Deploy.** Test with the trainer's helper iFlow:
   - Send a fake `SalesOrder.Created` event with `id = evt-001`. Verify Order Hub MPL Completed, JMS message visible, downstream OMS receives.
   - Replay the same event with `id = evt-001`. Verify MPL Discarded (or your equivalent), `duplicate-event` attachment present.
   - Send `evt-002` with a malformed payload. Verify MPL Failed (Day 4.4 will tighten this).
9. **Edit the PD parameter live.** While the iFlow is running, change `routes.default.targetPath` in the Partner Directory cockpit. Send another event. Verify the new path is picked up *without* redeploying the iFlow. Operations magic — this is why PD exists.
10. **Changelog entry.** Write `changelog/roi_ResilientOrderHub/<YYYY-MM-DD>_event_subscription_added.txt`. Note the topic, the queue, the subscription name, the PD partner+parameter used, and the test event IDs you fired.

### Failure cases to provoke

- **Forget the durable flag.** Undeploy the iFlow for 60 seconds, send an event, redeploy → event is *gone*. Re-mark Durable, try again, event survives. *Lesson:* always durable.
- **Skip the idempotency check.** Replay the same event 10 times; OMS gets the order 10 times. *Lesson:* dedup at the entry point, not on the OMS side.
- **Wrong `pid`/`parameterId` in the PD script.** Script throws "parameter not found"; iFlow fails; alerting fires. *Lesson:* PD lookup failures must produce loud errors, not silent skips.
- **Edit PD parameter to invalid JSON.** Script throws on `JsonSlurper.parse`; iFlow fails. *Lesson:* PD changes need the same review discipline as iFlow changes — a second pair of eyes before saving.
- **Subscription name change.** Change `roi-orderhub-salesorder-v1` → `roi-orderhub-salesorder-v2`, redeploy. The old subscription's backlog is orphaned on the broker. *Lesson:* subscription names are stable identity.

---

## Reference card excerpt — Day 4.3

- **CloudEvents** is the envelope spec; key attributes `id`, `source`, `type`, `subject`, `time`. Map `id` → `correlationId` when no other correlation is present.
- **AMQP 1.0** is the wire protocol Event Mesh exposes. CI's AMQP adapter is the subscriber; topic-to-queue routing is configured in Event Mesh, not in CI.
- **Topic naming** for S/4HANA Cloud: `s4/sap/s4hanacloud/ce/<context>/v1/<Entity>/<Verb>/v1`.
- **Intelligent Services** is the curated catalog of SAP-published events with a wizard; under the hood it's still Event Mesh + AMQP. Use direct AMQP for non-SAP or advanced subscriptions.
- **Always durable** subscriptions. Subscription Name is stable identity — renaming abandons the backlog.
- **Idempotency** is the consumer's job. Key on CloudEvents `id`; Data Store dedup with bounded TTL (7 days for the Order Hub).
- **Partner Directory** is for *operational routing config* that changes without redeploy. Not for secrets, not for blobs, not for application data.
- **PD Groovy access:** `ITApiFactory.getApi(PartnerDirectoryService.class, null)` → `getParameter(parameterId, pid, BinaryData)` → `JsonSlurper().parse(new ByteArrayInputStream(binary.getData()))`. Same shape as `scripts/standalone/roiam_loadGrcProxyConfig.groovy`.
- **Script naming** for Order Hub event additions: `roiam_resolveRoutingFromPd.groovy` under `scripts/collections/resilientOrderHub/`, in iFlow under `script/v2/`. Upload via Script step dialog only.
- **Failure modes specific to events:** subscription disconnect, poison messages, out-of-order, duplicate floods, schema drift. Day 4.4 ties most of these to error handling.
