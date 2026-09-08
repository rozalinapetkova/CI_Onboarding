# Week 1 — Reference Card

> Cumulative cheat sheet for Foundations: Platform, iFlows, Adapters. Keep within arm's reach during the practical project.

---

## Platform vocabulary

- **Integration Suite** = umbrella product. **Cloud Integration** = one of its **10 capabilities** (the iFlow engine).
- The other 9: API Management, Open Connectors, Integration Advisor, Trading Partner Management, Event Mesh, OData Provisioning, Data Space Integration, Integration Assessment, Migration Assessment.
- Runtime: **Apache Camel**, multi-tenant, SAP-managed, HA. You don't operate it; you use it correctly.
- Communication types: **A2X** (SAP-to-SAP), **B2B** (partner), **B2G** (gov / e-invoice), **B2C** (REST/webhook), **M2M/IoT** (MQTT/Kafka).

## Quality of Service

| QoS | Guarantee | Use when |
|---|---|---|
| **At Least Once** | Delivered; duplicates possible | Default async — pair with idempotent consumer |
| **Best Effort** | Sync, no retry | Sync request-reply |
| **Exactly Once** | Deduplicated by message ID | Financial postings; non-idempotent consumers |

Rule of thumb: **At Least Once + idempotent consumer** is the bread and butter.

## Message metering

- Per **250 KB** of aggregated outgoing message size.
- **JMS** and **ProcessDirect** are **NOT counted** — internal hops are free.
- **Splitter multiplies** the count (1000 splits = 1000 messages).
- **Retries are counted** separately.

## Cockpit workspaces

- **Design** — author iFlows.
- **Monitor** — Message Processing, Manage Integration Content, Manage Stores, Manage Security.
- **Settings** — tenant configuration.
- **Discover** — SAP-shipped content; look here before building.

Default developer role: **`PI_Integration_Developer`**.

---

## iFlow anatomy

- **Integration Process (IP)** — one per iFlow, owns the inbound connection.
- **Local Integration Process (LIP)** — subroutine, called via *Process Call*.
- **Exception Subprocess** — error pool. **Cannot contain:** another Exception Subprocess, IP, LIP, Sender, Receiver, Start/End events, Router, or Aggregator.

## Message compartments

| Compartment | Leaves the iFlow? | Use for |
|---|---|---|
| **Headers** | Yes (HTTP/JMS headers) | External-facing metadata |
| **Properties** | **No** | Internal scratch state |
| **Body** | Yes | The payload |

Always stream the body: `Reader reader = message.getBody(java.io.Reader);`

## Deploy lifecycle

Save → Save as Version → Deploy → wait for **"Started"** in *Manage Integration Content* → call → check Monitor.

---

## Adapters — synchronous family

### HTTPS sender
- HTTPS only. Address starts with `/`. Runtime URL: `https://<tenant-host>/http/<address>`.
- **CSRF on by default** for state-changing methods.
- Default sender role: **`ESBMessaging.send`**.
- MEP: Request-Reply (sync) or One-Way.

### HTTP receiver
- Default timeout **60 s**; retry up to **3x**.
- **Uncheck "Throw Exception on Failure"** to route on `CamelHttpResponseCode` instead of failing.
- Methods: POST / GET / HEAD / PATCH / TRACE / Dynamic.

### SOAP
- Versions 1.1 and 1.2. WS-Addressing, WS-Security supported.
- **SOAP SAP RM** provides **EO / EOIO**. Dedup window: **90 days**.
- ID Determination modes: Generate / Reuse / Map.

### RFC
- **Receiver only**. **Requires Cloud Connector.** Synchronous.
- WSDL generated from `/sap/bc/soap/wsdl11?services=<FM>`.

### LDAP
- Receiver only. Returns LDIF — pair with Groovy to parse.

## Adapters — async / file / internal family

### SFTP sender (polling)
- **Read Lock Strategy:** *None* (unsafe) / *Content Change* (latency) / **Done File Expected** (safest) / *Rename*.
- **Post-Processing:** Delete (default) / Keep+Mark / Keep+Reprocess (dev only) / Move.
- **Idempotent Repository:** *Database* required for multi-node; *In-Memory* for dev.
- Max Messages per Poll: default 20, max 500.

### IDoc
- In CI, IDocs flow over **SOAP** (not tRFC like PI/PO). The XML payload is the IDoc.

### JDBC receiver
- Engines: SAP HANA, Oracle, SQL Server, PostgreSQL, MariaDB, DB2. Non-SAP needs driver upload.
- Payload is XML-shaped SQL.

### JMS
- **SAP-managed broker only.** Not metered. Deep dive Week 3.
- Standard plan limits: **30 queues, 9.3 GB, 150 tx/consumers/providers** total; per queue **300 MB / 5 / 5 / 5**. Messages >5 MB auto-split, max 1280 MB.

### ProcessDirect
- In-memory, single-tenant, **synchronous**. Not metered.
- **Headers NOT propagated by default** — configure *Allowed Headers*.
- **Properties NEVER propagated** — the called iFlow starts fresh.
- No durability — if consumer is undeployed, caller fails immediately.

---

## Authentication options (preview — Week 3 covers deeply)

| Method | Stored where |
|---|---|
| Basic Auth | Security Material → User Credentials |
| OAuth2 Client Credentials | Security Material → OAuth2 Client Credentials |
| Client Certificate (mTLS) | Keystore Entry |
| SAML 2.0 / SAML Bearer | Multiple |

**Secret rotation in Security Material does NOT require redeploy.**

---

## The "no native canonical format" gotcha

Unlike PI/PO, CI **does not auto-convert** payloads. JSON in = JSON in body. Before XPath / routing / mapping on non-XML, **explicitly convert** with the *JSON→XML Converter*, *CSV→XML Converter*, or a Groovy script.

---

## Custom header search

For a header to appear in Monitor → Message Processing custom-header search, it must be registered explicitly from a Groovy script:

```groovy
def messageLog = messageLogFactory.getMessageLog(message);
if (messageLog != null) {
    messageLog.addCustomHeaderProperty("<header name>", value);
}
```

---