# Day 1.2 — Anatomy of an iFlow

> **Goal of the day.** Build your first end-to-end iFlow ("Hello iFlow") and understand every part of the canvas: pools, participants, integration process, sender, receiver, message exchange pattern, content modifier, deployment, and runtime URL. By the end of the day you should also start scaffolding the *Customer Echo Service* you'll deliver Friday.

## 1. The canvas, top to bottom

When you create a new iFlow, you see a canvas with:

```
┌──────────────────────┐                                ┌──────────────────────┐
│   Sender (left      │ ──── message exchange ──── ▶ │  Integration Process │ ──── ▶ ┌──────────────────┐
│   participant pool) │                                │  (centre pool)       │       │   Receiver       │
└──────────────────────┘                                └──────────────────────┘       └──────────────────┘
```

- **Pools** are the boxes with a label on the left edge. They represent *participants*.
- **Participants** = roles in the message exchange. The leftmost participant is conventionally the *sender*, the rightmost the *receiver*.
- **Integration Process** = the centre pool. The actual sequence of flow steps lives inside it.
- **Sender adapter** sits on the connecting line *into* the Integration Process from the sender pool.
- **Receiver adapter** sits on the connecting line *from* the Integration Process to a receiver pool.
- **Flow steps** are the icons inside the Integration Process: Content Modifier, Mapping, Router, Splitter, Aggregator, Script, etc.

**Important mental model:** the *adapter* is the protocol/transport plug. A *participant* is the abstract role (e.g. "Customer Master System"). One participant can be wired to many iFlows over different adapters — and you do *not* configure participants once-per-tenant; they are scoped to the iFlow.

## 2. Integration Process and Local Integration Process

- **Integration Process (IP)** — there is exactly *one* main IP per iFlow. It owns the inbound connection point.
- **Local Integration Process (LIP)** — a sub-routine inside the same iFlow. Called from the main IP via a "Process Call" step. Lets you reuse logic *within* one iFlow.
- **Exception Subprocess** — a special pool that catches uncaught exceptions thrown anywhere in the main IP. We'll cover this in depth in Week 4. Note: **an Exception Subprocess cannot contain another Exception Subprocess, an Integration Process, a Local Integration Process, a Sender, a Receiver, Start/End events, a Router, or an Aggregator.** Memorize that constraint — it surprises everybody.

## 3. Message Exchange Patterns (MEP)

When you wire a sender to an Integration Process you choose:

| Pattern | Meaning | Common adapters |
|---|---|---|
| **Request-Reply** | Synchronous; the sender waits for a response. | HTTP (sync), SOAP (sync), OData, Process direct |
| **One-Way** | Fire-and-forget; sender doesn't wait. | SFTP, JMS, AMQP |

Sounds obvious, but get it wrong and you get cryptic errors at deploy time. The MEP must match what the protocol semantically supports.

## 4. The Message object — headers, properties, body

Every flow step receives and returns the same logical thing: a **Message** object with three compartments.

| Compartment | Lifetime | Visible to receiver? | Use for |
|---|---|---|---|
| **Headers** | Travel with the message *out* of the iFlow over most adapters. | Yes (HTTP headers, JMS headers, etc.) | External-facing metadata: `Content-Type`, `correlationId`, `customerId`. |
| **Properties** | Internal to the iFlow run; do *not* leave the iFlow. | No | Internal scratch state — counters, flags, intermediate values. |
| **Body** | The payload itself. | Yes | Whatever you're transmitting. |

**Project-style rule:** read headers via `message.getHeaders()`, set them via `message.setHeader(name, value)`. Same for properties. We'll write the Groovy in Week 2.

The body should be **read as a stream** when possible:

```groovy
import java.io.Reader;
Reader reader = message.getBody(java.io.Reader);
```

This avoids loading the whole payload into memory and is the project's required style. Detailed in Week 2.

## 5. The flow-step catalogue you'll meet this week

You won't use every step in Week 1, but the icons should be familiar.

| Step | What it does | Day you meet it |
|---|---|---|
| **Content Modifier** | Set headers / properties / body. The Swiss-army knife. | 1.2 (today) |
| **Message Mapping** | Visual XML/JSON transformation. | 2.1 |
| **Script** | Run Groovy v2 code. | 2.3 |
| **Router** | Conditional branching. | 1.3 |
| **Filter** | Drop messages that don't match a condition. | 2.2 (XSLT) |
| **Splitter** | Break a payload into multiple messages. | 1.4 |
| **Aggregator** | Combine split messages back together. | 3.4 |
| **Multicast** | Fan out to multiple branches. | 1.4 |
| **Request-Reply / Send** | Call a receiver. | 1.3 / 1.4 |
| **Process Call** | Call a Local Integration Process. | 3.3 |
| **Data Store Operations** | Write/Select/Get/Delete/Update. | 3.4 |
| **Write Variables** | Persist tenant-wide globals. | 3.4 |
| **Number Range** | Allocate a sequential counter. | 3.4 |
| **JMS / AMQP adapters** | Async, durable hops. | 3.2 / 4.3 |
| **ProcessDirect adapter** | Sync (Request-Reply) only, in-memory, intra-tenant. | 1.4 / 3.3 |
| **Exception Subprocess** | Error handling pool. | 4.4 |

## 6. Deploying and calling an iFlow

The deploy lifecycle:

1. **Save** — persists in the design workspace; runtime unaffected.
2. **Save As Version** — explicit immutable version. Recommended before you deploy something you care about.
3. **Deploy** — pushes the artifact to the runtime cluster. Takes 10–60 seconds. Watch the *Deploy Status* on the artifact.
4. **Manage Integration Content** (Monitor workspace) — once deployed, you'll see the artifact with status "Started" and a generated **runtime endpoint URL** (for HTTP/SOAP/OData senders).

**Project-rule reminder (from auto-memory):** when uploading a Groovy script *into* an iFlow, always do it via the **Script step's own dialog**, not via the Resources tab. Doing it via Resources first causes stale metadata. We'll see this in Week 2 — but it's worth knowing now since you might be tempted to use Resources earlier.

## 7. Naming conventions you'll inherit

- Every Groovy script is prefixed `roiam_`. Reusable scripts should be part of script collections.
- New v2 scripts inside an iFlow live under `script/v2/` — **not** `script/`.
- Changelogs are a must and are stored in Sharepoint under `changelog/YYYYMMDD <description>/YYYYMMDD <description>.txt` 

You won't write any of these today.

---

## Hands-on lab — Build "Hello iFlow"

> Time: ~3 hours. Goal: make an HTTPS-callable iFlow that returns a static 200 OK with a JSON body containing your name.

### Steps

1. **Create the iFlow.**
   - Design → Training package → Create → Integration Flow → name it `roi_<your_initials>_HelloIFlow`.
   - You'll land on an empty canvas with a default Sender, Integration Process, and (no receiver — we'll add nothing).

2. **Configure the sender adapter.**
   - Click the Sender → Add Connection to the Integration Process.
   - Choose **HTTPS** sender adapter.
   - **Address:** `/roi/hello/<your-initials>` (must start with `/`).
   - **CSRF Protected:** un-check for this lab.
   - **Authorization:** "User Role" with role `ESBMessaging.send` (default for HTTP sender).
   - **Message Exchange Pattern:** Request-Reply.

3. **Add a Content Modifier.**
   - Drag a Content Modifier from the palette into the Integration Process between Start and End.
   - Tab *Message Header* → Add: `Content-Type` = `application/json` (Type: Constant).
   - Tab *Message Body* → Type: Constant → Body:
     ```json
     { "message": "hello from <your-name>", "version": 1 }
     ```

4. **Save and deploy.**
   - Save → Save as Version (1.0.0) → Deploy.
   - Wait for status "Started" in *Manage Integration Content*.
   - Copy the runtime URL (looks like `https://<tenant>-iflmap.hcisbt.<region>.hana.ondemand.com/http/roi/hello/<your-initials>`).

5. **Call it.**
   - From your local machine:
     ```bash
     curl -u <user>:<password> -X POST "<runtime-url>" -d '{}'
     ```
   - You should get back the JSON body. If you get 401, your role assignment is missing — flag the trainer.
   - **Postman works too, for this and every call from here on.** Basic Auth tab (same user/password), URL, body — whatever the `curl` example shows, set the equivalent fields in Postman. This course shows `curl` throughout because it's copy-pasteable in one line, not because Postman doesn't work; use whichever you're more comfortable with for the rest of the bootcamp.

6. **Find it in the monitor.**
   - Monitor → Message Processing → set time filter to "Last 30 minutes" → click your message.
   - Note: status `Completed`, the headers panel, the empty properties panel, the *Steps* tree showing Sender → Content Modifier → End.

### Stretch goal — start scaffolding the Customer Echo Service

If you have time:

- Create a second iFlow `roi_<your_initials>_CustomerEchoService`.
- Sender HTTPS at `/customer/<your_initials>/echo`, MEP Request-Reply, CSRF off for now.
- Content Modifier setting `Content-Type: application/json` and a placeholder body.
- Save, deploy, hit it with `curl`. Tomorrow we'll start replacing the placeholder with a real receiver call.

---

## Reference card excerpt — Day 1.2

- **Integration Process** = main; **Local Integration Process** = sub-routine; **Exception Subprocess** = error handler with hard constraints.
- **Headers travel with the message; properties stay inside the iFlow.**
- MEP must match what the adapter supports (Request-Reply for sync, One-Way for async).
- Always **stream the body** with `message.getBody(java.io.Reader)`.
- HTTP sender address always starts with `/`. Final URL is `https://<tenant-host>/http/<address>`.
- Default sender role for HTTP: `ESBMessaging.send`.
- Deploy → wait for "Started" in *Manage Integration Content* → call → check Monitor.
