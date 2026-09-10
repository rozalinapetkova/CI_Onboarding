# Day 3.3 — ProcessDirect Modularization & Reusable Artifacts

> **Goal of the day.** Stop copy-pasting Groovy across iFlows. By end of day, the Order Hub calls the Week 2 Multi-format Order Translator over **ProcessDirect** with the right header allow-list, and a shared **Script Collection** `sc_<your_initials>_OrderHubHelpers` provides a logging helper and an error-formatting helper consumed by both the producer and consumer iFlows. You should be able to defend "subflow vs. ProcessDirect vs. Script Collection vs. Message Mapping reuse" in two sentences.

## 1. Why modularization matters in CI more than elsewhere

Cloud Integration projects rot fast. The reasons are structural:

- **iFlow XML is verbose** — even a small change touches multiple XML files inside the iFlow archive.
- **No native composition** — there is no equivalent of "include this file" in the iFlow editor. You compose by *calling* another iFlow.
- **Copy-paste is the path of least resistance** — when a colleague needs the same logging snippet, the easy thing is to copy the Groovy file. After 15 iFlows the snippet has 12 subtly different versions.
- **CTM ships *full iFlow archives*** between landscapes — there is no shared library mechanism baked into transports beyond what we cover today.

The four reuse mechanisms in CI, ranked by how much you'll use each on this tenant:

| Mechanism | Reuse what | Boundary | Versioning |
|---|---|---|---|
| **ProcessDirect** | Whole iFlow logic — composition at the iFlow level | Cross-iFlow, in-memory, sync or async | Per iFlow version |
| **Script Collection** | Groovy scripts, JARs, custom config files | Resource artifact referenced by N iFlows | Per Script Collection version |
| **Message Mapping artifact** | Shared mapping between iFlows | Resource artifact, referenced from Mapping step | Per Mapping version |
| **Subflow / Local Integration Process** | Logic chunks within one iFlow | In-iFlow only — does *not* cross iFlow boundaries | Same as containing iFlow |

You will use ProcessDirect and Script Collections today. Message Mapping reuse you already saw in Week 2. Subflows are a within-iFlow tool — useful, less critical for "Production-shaped flows" week.

## 2. ProcessDirect — what it is, what it isn't

**ProcessDirect** is an in-memory adapter that lets one iFlow call another *as if* it were a local function call. No network, no broker, no metering. From Week 1 Day 1.4: `ProcessDirect is not metered`.

What it does:

- Lets you split logic across iFlow boundaries — the *callee* iFlow can be reused by N *caller* iFlows.
- Provides per-call **isolation** — each call starts a fresh iFlow run on the callee with its own MPL entry.
- Supports **sync** (Request-Reply) and **async** (Send) semantics.
- Carries the **body** automatically.

What it does **not** do:

- **Headers do NOT propagate by default.** You must allow-list them. (This is the bit every cohort gets wrong once.)
- **Properties NEVER propagate.** ProcessDirect is a hard boundary for properties. If you need state on the other side, push it via headers or the body.
- **Persistence — none.** ProcessDirect is in-memory. If the callee throws, the caller sees the exception. If the JVM dies between caller and callee, the message is lost. Do not use ProcessDirect when you need durability — use JMS.
- **Cross-tenant — no.** ProcessDirect is intra-tenant only.

## 3. The header allow-list (the trap you only fall into once)

On the **caller** side, the ProcessDirect receiver adapter has an **Allowed Headers** field — a pipe-separated list of header names that *will* propagate to the callee. Default: empty. **Empty means no headers go through.**

On the **callee** side, the ProcessDirect sender adapter *also* has an Allowed Headers field — a filter applied on the way in. Default: empty. **Empty means no headers received.**

So: a default-configured ProcessDirect link transmits the body and *nothing else*. The most common newbie symptom — "my correlationId is missing in the callee iFlow" (Week 1 quiz B2) — is exactly this.

The fix:

1. **On the caller's ProcessDirect receiver**, set Allowed Headers to a pipe-separated list, e.g. `correlationId|orderId|X-Order-Format|X-Idempotency-Key|X-Order-Sequence`.
2. **On the callee's ProcessDirect sender**, set the same list (or a superset) so the callee will accept them.
3. Verify in the Monitor — open the callee's MPL run, *Headers* tab, confirm your allow-listed headers are visible.

**Properties never propagate, period.** If you need a piece of state on the other side, lift it to a header at the caller's last step before the ProcessDirect call, and push it back to a property on the callee's first step.

## 4. ProcessDirect is Request-Reply only

There's no fire-and-forget option here. **ProcessDirect only supports Request-Reply** — the caller always waits for the callee to finish and gets a body back, even for calls that are logically "just" a side effect (logging, audit, fan-out notifications). There's no "One-Way" or "Send" MEP to pick instead, and so no MEP-mismatch failure mode between caller and callee to worry about — there's only one option, on both sides.

If you genuinely want fire-and-forget semantics between two iFlows, that's what JMS is for (Day 3.2) — ProcessDirect is synchronous, in-memory, intra-tenant composition, not a queue.

Today's lab uses ProcessDirect because the Order Translator returns the canonical XML and we need that body back — which happens to be the only mode ProcessDirect has anyway.

## 5. Versioned endpoints — the discipline that saves your future self

ProcessDirect addresses are URI-like: `/orderTranslator/translate`. There is **no automatic versioning** — if you change the callee's contract (input format, output format, allowed headers), every caller breaks.

Project pattern: include a **version segment** in the endpoint:

- `/orderTranslator/v1/translate` — original.
- `/orderTranslator/v2/translate` — breaking-change version.

When you ship v2, you keep v1 deployed for the migration window. Callers migrate one at a time. You decommission v1 when telemetry shows zero traffic.

This is more discipline than tooling — there is no SAP feature that enforces it. But on a multi-team tenant where 5 iFlows depend on `/orderTranslator/translate`, this discipline is the difference between "ship a change Tuesday" and "explain why every queue is in DLQ on Wednesday".

For today's lab, use `/orderTranslator/v1/translate/<your-initials>`.

## 6. Subflows / Local Integration Processes

A **Local Integration Process** is a *within-iFlow* subflow. It's not reuse across iFlows — it's organization within one iFlow. You use them when:

- The main flow is so large the editor canvas becomes hard to read.
- You want to share logic between two branches of the same iFlow (e.g. happy path + retry path both call `validateOrder`).
- You need a "function" with its own steps for clarity.

The local integration process appears as a separate pool on the same iFlow canvas. You invoke it via a **Process Call** flow step. Headers and properties **do** propagate (it's the same iFlow run).

You will not lab a Local Integration Process today, but you will see one tomorrow when the Data Store / Number Range lab gets long.

## 7. Script Collections — the right way to share Groovy

A **Script Collection** is a deployable artifact that holds Groovy scripts (and optionally JARs, configuration files). Multiple iFlows reference the *same* Script Collection by name. When you update a script in the collection and redeploy the collection, **every iFlow that references it picks up the change** at the next message.

Anatomy:

```
sc_<your_initials>_OrderHubHelpers/              ← Script Collection artifact
└── src/main/resources/script/v2/
    ├── roiam_logIncoming.groovy
    └── roiam_formatError.groovy
```

Then in **each iFlow**, you add the Script Collection as a **Reference** in *iFlow → References → Script Collection*. The iFlow's Script steps can now select scripts from the collection by their `roiam_*` filename.

Versioning: Script Collections are versioned independently. When the cookbook changes `roiam_logIncoming.groovy` and you bump the collection from v1.0 to v1.1, deploy v1.1 of the collection. Every iFlow that references "the latest version" picks it up. iFlows that pin a specific version (rare but possible) need a redeploy with the new pin.

**Project naming convention:** `sc_<your_initials>_<purpose>` — `sc_<your_initials>_OrderHubHelpers`, `sc_<your_initials>_LoggingCommon`, `sc_<your_initials>_PartnerDirectoryAccess`. Same `roiam_*` prefix for the scripts inside.

## 8. What goes in a Script Collection vs. inside the iFlow

Decision matrix:

| Script logic | Where |
|---|---|
| Used by **one iFlow only**, tightly coupled to its message contract | Inside the iFlow at `script/v2/` — `scripts/collections/<iflow>/` in this repo |
| Used by **2+ iFlows**, generic enough to be reused | Script Collection — `scripts/standalone/` in this repo, plus an actual `sc_*` artifact on the tenant |
| Used by **2+ iFlows but with different contracts** | Probably 2 different scripts. Don't force shared abstractions; copy is fine if drift is small. |
| Used by **1 iFlow today, 2 iFlows tomorrow** | Start in the iFlow. Promote to Script Collection when the second consumer arrives. **Do not pre-emptively share.** |

The "do not pre-emptively share" rule is project wisdom: shared scripts grow speculative parameters that no caller actually uses. Wait for the second consumer; let the abstraction emerge from real use.

## 9. Reusable Message Mappings

A standalone **Message Mapping** artifact (separate from any iFlow) is referenced by N iFlows from their Mapping flow steps. The shape is the same as the inline Mapping you built in Week 2 — but the artifact lives in the package, not the iFlow.

When to extract:

- A vendor → canonical mapping shared between an inbound flow (today's translator) and a regression-test flow (you'll see this in Week 4).
- A canonical → partner-specific mapping shared between every outbound iFlow.

When **not** to extract:

- A one-off field rename used in a single iFlow. Inline.
- A mapping that needs slightly different value-mapping tables per consumer. Either pass the table name as a parameter or keep two mappings.

Today you'll see the Order Translator iFlow being called over ProcessDirect — that's reuse at the iFlow level. We'll skip extracting its inner mapping into a separate artifact; that level of reuse hasn't paid for itself yet.

## 10. The compound pattern — Order Hub → ProcessDirect → Order Translator

The full flow you'll wire up today:

```
Caller ─► roi_<your_initials>_OrderHub (producer)
            │
            ├─► [Day 3.4 will add: Idempotency check via Data Store]
            ├─► [Day 3.4 will add: Number Range pull]
            │
            ├─► ProcessDirect call ──► roi_<your_initials>_OrderTranslator (Week 2)
            │   Allowed Headers:           │
            │   correlationId,orderId,     ▼
            │   X-Order-Format,        Returns canonical XML
            │   X-Idempotency-Key,         │
            │   X-Order-Sequence           │
            │   ◄──────────────────────────┘
            │
            └─► JMS receiver ──► roi.orderhub.outbound.<your_initials>
                                       │
                                       ▼
                                 roi_<your_initials>_OrderHubConsumer
                                       │
                                       ▼
                                 OAuth2 receiver → downstream API
```

Both `roi_<your_initials>_OrderHub` and `roi_<your_initials>_OrderHubConsumer` reference `sc_<your_initials>_OrderHubHelpers` for shared logging + error formatting.

## 11. Common mistakes

- **Forgetting the header allow-list** — the #1 ProcessDirect bug. Always allow-list explicitly; don't rely on defaults.
- **Trying to propagate properties via ProcessDirect.** Doesn't work, never has, never will. Lift to a header.
- **Endpoint without a version segment** — `/orderTranslator/translate` works fine until the day it doesn't. `/v1/` from the start.
- **Putting too much in a Script Collection too early** — the abstraction should emerge from at least two real consumers, not from speculation.
- **Editing a Script Collection without bumping its version** — operations sees the same version number with new behavior. Bump the version. Every. Time.
- **Script Collection upload via Resources tab on each iFlow** — wrong; the Script Collection is added as a *Reference* on the iFlow, and the script files live in the *Script Collection's* own resources, not in each iFlow's. Same project memory rule as Week 2: scripts upload through the Script step dialog, never via Resources.

---

## Hands-on lab — Add ProcessDirect + Script Collection to the Order Hub

> Time: ~3 hours. Goal: refactor the Order Hub producer to call the Week 2 Order Translator over ProcessDirect, and extract a logging helper + error-formatter into `sc_<your_initials>_OrderHubHelpers` consumed by both the producer and the consumer.

### Setup

- Yesterday's `roi_<your_initials>_OrderHub` producer + `roi_<your_initials>_OrderHubConsumer` deployed and working with JMS.
- The canonical-transformation logic built across Week 2 Days 2.1–2.3 (Router on `X-Order-Format`, the Message Mapping branch, both Groovy branches, the XSLT enrichment) still lives **inline inside `roi_<your_initials>_OrderHub`** — today's first step pulls it out into its own iFlow.
- Permission to create Script Collection artifacts (granted by `PI_Integration_Developer`).

### Steps

1. **Extract the translator logic into its own iFlow.** Everything from Week 2 Days 2.1–2.3 currently sits between the input Content Modifier and the End of `OrderHub`. Pull it out:
   - **Create a new iFlow**: Design → Training package → New Integration Flow → `roi_<your_initials>_OrderTranslator`.
   - **Add an HTTPS Sender** to it — e.g. `/http/ordertranslator/translate/<your_initials>`, MEP Request-Reply. This gives you something to test standalone before ProcessDirect is wired up in step 3.
   - **Move each of these steps** from `OrderHub`'s canvas onto `OrderTranslator`'s canvas, right after the Sender, in the same order: the **Router** (branches on `X-Order-Format`: `xml` / `json` / `csv` / default-error), the **Message Mapping** step (references `mm_<your_initials>_VendorOrderToCanonical` — it's a shared artifact, just reference it from the new iFlow too, no changes needed to the mapping itself), the two **Script** steps (`roiam_jsonOrderToCanonical.groovy`, `roiam_csvOrderToCanonical.groovy` — re-upload via the Script step dialog on the new iFlow, then click *Upgrade*, same rule as always), and the **XSLT enrichment** step (references `xslt_<your_initials>_EnrichCanonicalOrder.xsl`, same artifact, no changes).
   - **Remove those same steps from `OrderHub`.** Router, Message Mapping, both Script steps, XSLT enrichment — all gone from `OrderHub`'s canvas. It doesn't do any of this anymore; from here on it calls `OrderTranslator` for it instead.
   - **Save → version → deploy `OrderTranslator`**, then re-run the three `curl` calls from Week 2 Days 2.1 and 2.3 against *its own* endpoint, to confirm the extraction didn't break anything before you touch `OrderHub`.

2. **Add a ProcessDirect sender to `roi_<your_initials>_OrderTranslator`.**
   - Open `roi_<your_initials>_OrderTranslator`.
   - Add a *ProcessDirect sender* adapter alongside the HTTPS sender from step 1 (keep both so you can still test the translator standalone via curl; in production you'd pick one).
   - **Address**: `/orderTranslator/v1/translate/<your-initials>`
   - **MEP** (or "Pattern"): `Request-Reply`
   - **Allowed Headers**: `correlationId,orderId,X-Order-Format,X-Idempotency-Key,X-Order-Sequence`
   - Save → version → deploy.

3. **Refactor `roi_<your_initials>_OrderHub` to call the translator over ProcessDirect.**
   - Open `roi_<your_initials>_OrderHub`.
   - Insert a *Request-Reply* step + *ProcessDirect receiver* adapter between the input Content Modifier and the JMS receiver.
   - **Address**: `/orderTranslator/v1/translate/<your-initials>`
   - **MEP**: `Request-Reply`
   - **Allowed Headers**: `correlationId,orderId,X-Order-Format,X-Idempotency-Key,X-Order-Sequence`
   - Before the ProcessDirect call, set `X-Order-Format: json` (or read from the inbound — your Order Hub accepts JSON only for now).
   - The body returned from the translator is the canonical XML. Pass that to the JMS receiver downstream.
   - Save → version → deploy.

3. **Test the chained call.**
   ```bash
   curl -X POST "<runtime-url>/http/orderhub/orders/<your-initials>" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{ "orderId": "C-3001", "customer": "Acme GmbH", "totalAmount": 1500, "lines": [{"sku": "S-1", "quantity": 2, "unitPrice": 750}] }'
   ```
   - Confirm **202 Accepted** at the producer.
   - Open *Monitor → Message Processing*. You should see **three** runs:
     - `roi_<your_initials>_OrderHub` — Completed.
     - `roi_<your_initials>_OrderTranslator` — Completed (called via ProcessDirect).
     - `roi_<your_initials>_OrderHubConsumer` — Completed (drained the JMS queue).
   - In the `roi_<your_initials>_OrderTranslator` MPL run, *Headers* tab — confirm `correlationId` and `orderId` are visible. If not, your allow-list is missing — fix and redeploy.

4. **Create the `sc_<your_initials>_OrderHubHelpers` Script Collection.**
   - In your *Training* package, *Add → Script Collection*.
   - Name: `sc_<your_initials>_OrderHubHelpers`.
   - Description: `Shared logging and error-formatting helpers for the Order Hub iFlows.`

5. **Add `roiam_logIncoming.groovy` to the Script Collection.**
   - Open `sc_<your_initials>_OrderHubHelpers` → *Resources → Add → Script*.
   - **Important (project memory): create the script via the Script Collection's own dialog, not by uploading a file to a Resources tab.**
   - Path inside the collection: `script/v2/roiam_logIncoming.groovy`.
   - Content:

   ```groovy
   import com.sap.it.script.v2.api.Message;
   import java.io.Reader;

   def Message processData(Message message) {
       def headers = message.getHeaders();
       String correlationId = headers.get("correlationId") as String;
       String orderId       = headers.get("orderId") as String;

       Reader reader = message.getBody(java.io.Reader);
       StringBuilder sb = new StringBuilder();
       char[] buf = new char[4096];
       int n;
       while ((n = reader.read(buf)) != -1) {
           sb.append(buf, 0, n);
       }
       String bodyString = sb.toString();

       def messageLog = messageLogFactory.getMessageLog(message);
       if (messageLog != null) {
           if (correlationId != null) {
               messageLog.addCustomHeaderProperty("correlationId", correlationId);
           }
           if (orderId != null) {
               messageLog.addCustomHeaderProperty("orderId", orderId);
           }
           messageLog.addAttachmentAsString("incoming", bodyString, "application/json");
       }

       message.setBody(bodyString);
       return message;
   }
   ```

   Note: yes, this materializes the body to a String — deliberate, since this script *is* the logging step and we need the full body to attach. Documented exception to the streaming rule. Downstream steps see the body as a String, which they can re-parse.

6. **Add `roiam_formatError.groovy` to the Script Collection.**
   - Same Script Collection, same `script/v2/` path.
   - Content:

   ```groovy
   import com.sap.it.script.v2.api.Message;
   import groovy.json.JsonOutput;

   def Message processData(Message message) {
       def headers = message.getHeaders();
       def properties = message.getProperties();

       Object exObj = properties.get("CamelExceptionCaught");
       String exMessage = exObj != null ? (exObj as Throwable).getMessage() : "Unknown error";
       String exClass   = exObj != null ? exObj.getClass().getName() : "";

       String correlationId = headers.get("correlationId") as String;
       String orderId       = headers.get("orderId") as String;
       String category      = (properties.get("errorCategory") ?: "Unknown") as String;

       Map<String,Object> err = new LinkedHashMap<>(6);
       err.put("status", "failed");
       err.put("category", category);
       err.put("correlationId", correlationId);
       err.put("orderId", orderId);
       err.put("error", exMessage);
       err.put("exceptionClass", exClass);

       String body = JsonOutput.toJson(err);

       def messageLog = messageLogFactory.getMessageLog(message);
       if (messageLog != null) {
           messageLog.setStringProperty("errorCategory", category);
           messageLog.addAttachmentAsString("error-context", body, "application/json");
       }

       message.setHeader("Content-Type", "application/json");
       message.setBody(body);
       return message;
   }
   ```

   Notice the explicit `LinkedHashMap` with capacity 6 — small detail, project style. The use of `JsonOutput` on a Map preserves insertion order in the output JSON.

7. **Deploy `sc_<your_initials>_OrderHubHelpers`.**

8. **Reference the Script Collection from `roi_<your_initials>_OrderHub`.**
   - Open `roi_<your_initials>_OrderHub` → *References → Add → Script Collection → sc_<your_initials>_OrderHubHelpers*.
   - Drop a *Script* flow step at the very start of the iFlow (right after the sender's first Content Modifier).
   - In the Script step's properties, *Browse* → choose `roiam_logIncoming.groovy` from the now-available collection.
   - Save → version → deploy.

9. **Reference the Script Collection from `roi_<your_initials>_OrderHubConsumer`.**
   - Same — *References → Add → sc_<your_initials>_OrderHubHelpers*.
   - Drop a *Script* step at the start, point it to `roiam_logIncoming.groovy`.
   - In the existing *Exception Subprocess*, replace the inline error-handling Content Modifier with a *Script* step pointing to `roiam_formatError.groovy`.
   - Save → version → deploy.

10. **Test end-to-end.**
    - Send a happy-path order.
    - Open *Monitor → Message Processing → roi_<your_initials>_OrderHub run → Attachments* — confirm an `incoming` attachment with the full JSON body.
    - Open *roi_<your_initials>_OrderHubConsumer run → Attachments* — confirm an `incoming` attachment with the canonical XML body. (Same script, different iFlow, different content. Reuse confirmed.)
    - Search by `orderId=C-3001` in the MPL custom search — both runs should appear.

11. **Demonstrate Script Collection reuse update.**
    - Edit `roiam_logIncoming.groovy` in the Script Collection — add a new attachment, e.g. `headers-snapshot`:
      ```groovy
      messageLog.addAttachmentAsString("headers-snapshot",
          headers.toString(), "text/plain");
      ```
    - Bump the Script Collection's version to **v1.1**.
    - Deploy `sc_<your_initials>_OrderHubHelpers`.
    - Send a fresh order — *without* redeploying either iFlow.
    - Confirm both `roi_<your_initials>_OrderHub` and `roi_<your_initials>_OrderHubConsumer` runs show the new `headers-snapshot` attachment.
    - Lesson: one collection deploy, both iFlows updated. **This is the reuse value.**

### Failure cases to provoke

- **Empty Allowed Headers list** on the ProcessDirect adapter — call the iFlow, inspect translator MPL, see no `correlationId`. Fix.
- **Wrong endpoint** — caller points at `/orderTranslator/v2/translate` but only v1 exists. Caller fails fast with "no consumer". Lesson: deploy callee first.
- **Script Collection deployed but iFlow doesn't see new behavior.** Likely: iFlow is pinned to v1.0; you deployed v1.1 of the collection. Either bump pin or use "latest" reference. Confirm the iFlow's Script Collection reference version.
- **Script Collection edited but not redeployed** — you saved in the editor but didn't hit Deploy. Same old behavior. Always deploy after edit.

---

## Reference card excerpt — Day 3.3

- **ProcessDirect** = in-memory, intra-tenant, not metered, not durable. Use for composition; use JMS for decoupling-with-durability.
- **Header allow-list is mandatory** on both sides of the ProcessDirect link. Default empty = no headers. **Properties never propagate.**
- **Versioned endpoints** — `/foo/v1/bar`. Discipline, not feature.
- **ProcessDirect is Request-Reply only** — no fire-and-forget MEP exists. Want fire-and-forget between iFlows? Use JMS instead.
- **Subflow / Local Integration Process** = within one iFlow. **ProcessDirect** = across iFlows. Don't confuse.
- **Script Collection naming**: `sc_<purpose>`. Scripts inside still `roiam_*`. Path: `script/v2/`.
- **Reference, don't embed** — iFlow lists the Script Collection as a *Reference*; the script files live in the collection only.
- **Bump the collection version** every time you edit. Operations needs to know what changed.
- **Don't pre-emptively share** — promote to Script Collection on the *second* real consumer, not the first.
