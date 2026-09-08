# Day 1.1 — The SAP Integration Suite Landscape

> **Goal of the day.** By the end of today you should be able to draw, on a whiteboard, where Cloud Integration sits inside SAP Integration Suite, name the other 9 capabilities, explain the Camel-based runtime model, list the three QoS levels, and describe how messages are metered. You should also be comfortable navigating the cockpit.

## 1. The 10 capabilities of SAP Integration Suite

Most newcomers conflate *Cloud Integration* with *Integration Suite*. They are not the same thing. Integration Suite is the umbrella product; Cloud Integration is **one of its ten capabilities** — the iFlow process engine.

| # | Capability | What it does |
|---|---|---|
| 1 | **Cloud Integration** | iFlow process engine (Apache Camel-based). The capability you'll spend the entire month on. |
| 2 | API Management | Governance, security, developer portal — fronts your APIs with rate limiting, quotas, key management. |
| 3 | Open Connectors | 160+ pre-built SaaS connectors with normalized REST. Useful when you need Salesforce/HubSpot/etc. without writing the integration yourself. |
| 4 | Integration Advisor | ML-based mapping suggestions for B2B/EDI. |
| 5 | Trading Partner Management | Partner agreements and certificates for B2B. |
| 6 | Event Mesh | Event-driven pub/sub broker (CloudEvents, AMQP). You'll use this in Week 4. |
| 7 | OData Provisioning | Expose SAP data as OData services. |
| 8 | Data Space Integration | Sovereign data exchange (Catena-X, Manufacturing-X). |
| 9 | Integration Assessment | Strategic planning and governance. |
| 10 | Migration Assessment | PI/PO migration readiness analysis. |

**Why this matters in practice.** When you're asked "can SAP do X?", the answer is rarely "Cloud Integration" alone. A typical answer is "Cloud Integration handles the orchestration, API Management exposes it to partners, Event Mesh decouples the producers from the consumers." Knowing the 10 capabilities by name lets you have these conversations.

## 2. The four communication types Cloud Integration handles

| Type | Stands for | Examples |
|---|---|---|
| **A2X** | App-to-app inside SAP world | S/4HANA ↔ SuccessFactors, S/4HANA ↔ Ariba, S/4HANA ↔ CRM |
| **B2B** | Business-to-business with partners | EDIFACT, X12, AS2, AS4, Ariba Network |
| **B2G** | Business-to-government | Tax filing (ELSTER), e-invoicing (XRechnung, ZUGFeRD, FatturaPA, CFDI) |
| **B2C** | Business-to-consumer | REST APIs, webhooks, OAuth-secured customer portals |
| (M2M/IoT)| Machine-to-machine | MQTT, AMQP, Kafka — sensor and telemetry data |

These aren't formal product features — they're a vocabulary the integration community uses to scope conversations. Memorize them.

## 3. Cloud Integration's runtime engine

Cloud Integration is built on **Apache Camel** — an open-source enterprise integration framework. This is more than trivia: many of the patterns and limitations you'll see (the way headers and properties propagate, the way splitters work, the way exceptions bubble) are *Camel* behaviors that SAP wrapped a UI around.

Key facts about the runtime:

- **Multi-tenant** with logical isolation. Your tenant shares physical resources with others, but data is separated.
- **High availability** via load balancing and auto-recovery — messages can survive worker failures.
- **Transactional** processing where supported (JMS, JDBC, Data Store with caveats).
- **Parallel** processing supported (multicast, splitter parallel mode, multiple consumers per JMS queue).
- **SAP-managed scaling** — both vertical (more CPU/memory) and horizontal (more workers).

You don't operate the runtime. SAP does. Your job is to use it correctly.

## 4. Quality of Service (QoS) — three levels you must internalize

Every iFlow that talks to a remote system has a **Quality of Service** characteristic. Get this wrong and you either lose messages or duplicate them.

| QoS | What it guarantees | When to use |
|---|---|---|
| **At Least Once** *(default async)* | Guaranteed delivery; duplicates *are* possible if the network hiccups during ack. | Default for asynchronous flows. Pair with idempotency on the receiver side. |
| **Best Effort** | Synchronous, fire-and-forget. No retry. | Sync request-reply where the caller will retry if needed. |
| **Exactly Once** | Deduplicates by message ID. No duplicates. | Required for financial postings, idempotent-unsafe consumers. Costs latency. |

**Mental model:** "At Least Once + idempotent consumer" is the **bread and butter** of resilient async integrations. "Exactly Once" is expensive and is usually a sign you couldn't make the consumer idempotent — fix the consumer if you can.

## 5. Message metering — how SAP charges you

This becomes a real conversation when your tenant is busy. As of August 2025 (per the cookbook):

- Counted per **250 KB** of aggregated outgoing message size.
- **JMS** and **ProcessDirect** adapters are NOT counted — they are internal hops.
- **Splitter:** each split = a separate message count. A 1000-line file split per line = 1000 messages.
- **Retries** are counted separately.
- The current rule of thumb being applied today: every iFlow run with **≥ 1 receiver adapter = 1 message** — actual size-based metering wasn't yet live at time of writing.

**Practical consequence:** if you're worried about metering, prefer ProcessDirect for internal composition over re-calling iFlows over HTTP. We'll exploit this heavily in Week 3.

## 6. Key runtime components you should know exist

Even though you won't use all of these on day 1, you will hear them mentioned in standups all month.

1. **Keystore / Trust Store** — private keys, certificates, OAuth credentials live here. **Important:** rotating a secret in the Keystore does **NOT require redeploying the iFlow** that uses it. We rely on this in Week 3.
2. **Monitoring / Tracing** — Message Processing Log (MPL), system logs, trace mode, custom logging. We'll spend Day 4.1 here.
3. **Partner Directory** — centralized partner metadata (IDs, endpoints, certs, routing). Has an OData API. Lets you write *one generic* iFlow that serves *thousands* of partners — game-changing in B2B.
4. **Edge Integration Cell** — Kubernetes-based private runtime if regulation requires messages to stay on-premise. Design time stays in cloud, runtime stays local.

## 7. Security architecture in 30 seconds

You won't configure auth today, but you should know the shape:

- **Authentication** for cockpit users: Identity Authentication (SAML 2.0 / OIDC). For APIs: OAuth 2.0.
- **Authorization** is role-based: *Scope → Role Template → Role → Role Collection*.
- **Network**: TLS everywhere, IP whitelisting available, cert verification, tenant separation.
- **Compliance**: GDPR, audit logging via BTP cockpit or Cloud ALM.

Key role collections you should be able to recognize by name:

| Role collection | What it grants |
|---|---|
| `PI_Administrator` | Full admin access. |
| `PI_Business_Expert` | Business monitoring (read-only operations view). |
| `PI_Integration_Developer` | Design and deploy iFlows. **This is what you should have for the training.** |
| `TMS_LandscapeOperator_RC` | Transport landscape management. |
| `ImportOperator` | Approve and release transports. |

## 8. Cloud Connector — a quick mention

SAP Cloud Connector is the on-premise component that lets your tenant talk to systems behind your corporate firewall (S/4HANA on-premise, ECC, internal databases). Key properties:

- It is **outbound-only** from your network — no inbound firewall ports to open.
- It exposes only what you whitelist (specific ICF paths, services, RFC endpoints).
- Supports **Principal Propagation** — pass the calling user's identity through to the backend.
- Works via *Virtual Host / Virtual Port* addressing from the BTP side.

You won't install it in this training, but if your trainer's tenant uses it, they'll mention it on Day 1.3 when we cover RFC.

---

## Hands-on lab — Tenant tour

> Time: ~2 hours. No iFlow built yet — today is about *navigating*.

You will receive: a tenant URL, your user, the name of the shared "Training" integration package.

**Goals:**
1. Log in to the Integration Suite cockpit. Note that Cloud Integration is *one tile* on the home page.
2. Open the **Design** workspace. Find the "Training" integration package. Open it. Note the empty *Artifacts* tab — by Friday it will have your "Customer Echo Service".
3. Open the **Monitor** workspace. Click through:
   - *Message Processing* — empty for now.
   - *Manage Integration Content* — shows what is deployed.
   - *Manage Stores* — shows Data Stores, Number Ranges, Variables, Message Queues. You'll touch most of these in Week 3.
   - *Manage Security* — Security Material, Keystore, Connectivity Tests, User Roles. Don't change anything.
4. Open the **Settings** workspace.
5. Open the **Discover** workspace. Browse SAP-shipped content. Notice that there are *thousands* of pre-built iFlow templates — when in doubt at work, look here first; you might not need to build at all.
6. From the BTP cockpit (separate URL — your trainer will give it to you), find your **subaccount → Security → Role Collections**. Confirm that `PI_Integration_Developer` is assigned to your user.

**Deliverable.** Write three sentences in your daily journal:
- One thing that surprised you.
- One thing you couldn't find.
- One question you want answered before Day 1.5.

---

## Reference card excerpt — Day 1.1

- **Integration Suite** is the umbrella; **Cloud Integration** is one of its 10 capabilities.
- Runtime: Apache Camel, multi-tenant, SAP-managed, HA.
- QoS: **At Least Once** (default async) / **Best Effort** (sync) / **Exactly Once** (deduplicated).
- Metering: per 250 KB; **JMS and ProcessDirect not counted**; splitter multiplies count; retries counted.
- Workspaces: Design / Monitor / Settings / Discover.
- Default role for developers: `PI_Integration_Developer`.
