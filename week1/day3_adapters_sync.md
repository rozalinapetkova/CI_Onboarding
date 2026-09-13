# Day 1.3 — Adapters Part 1: Sync / Request-Reply

> **Goal of the day.** Get comfortable with the synchronous adapter family — HTTP, SOAP, RFC, LDAP — by extending your Customer Echo Service to actually call an external API and reshape the result. Understand sender vs. receiver, CSRF, authentication options, timeouts, and retry semantics.

## 1. Sender vs. receiver — the most important distinction

| | Sender | Receiver |
|---|---|---|
| Where it sits | Left of the Integration Process | Right of the Integration Process |
| Direction of traffic | *Inbound* — external system calls *us* | *Outbound* — *we* call an external system |
| Role on iFlow side | Endpoint exposer | Client |
| Configured at | Connection from sender pool to IP | Connection from a Request-Reply / Send step to a receiver pool |

A common confusion: people say "I need an HTTP adapter" and don't specify which side. Always say **HTTP sender** (someone calls me) or **HTTP receiver** (I call someone).

## 2. The HTTP/HTTPS adapter

**HTTPS sender** — the one you used yesterday.
- HTTPS only. Plain HTTP not allowed.
- **CSRF Protection** on by default for state-changing methods. You disable it only for endpoints called by trusted internal clients or simple lab work; production webhooks usually keep it.
- Address must start with `/`. Runtime URL = `https://<tenant-host>/http/<address>`.
- Authorization options: User Role (basic auth + role check), Client Certificate (mTLS). OAuth via API Management when needed.

**HTTP receiver** — used inside the iFlow to call out.
- Methods: POST / GET / HEAD / PATCH / TRACE / Dynamic. ("Dynamic" = method comes from a header, useful for proxies.)
- Default timeout: **60 seconds**. Tunable.
- **Retry**: up to 3 attempts, retry-on error codes and intervals are configurable.
- **Error handling pattern (very important):** by default, the receiver throws an exception on any non-2xx response, which aborts the iFlow. To *route* on the response code instead, **uncheck "Throw Exception on Failure"** and branch on the `CamelHttpResponseCode` header. We'll use this in Week 4.

## 3. Authentication options at a glance

You'll go deep on auth in Week 3. For today, you should recognize:

| Method | When | Stored where |
|---|---|---|
| Basic Auth | Test, intranet over TLS | Security Material → User Credentials |
| OAuth 2.0 Client Credentials | Cloud-to-cloud, M2M | Security Material → OAuth2 Client Credentials |
| Client Certificate (mTLS) | High-security comms | Keystore Entry |
| SAML 2.0 / SAML Bearer | Corporate federation, SuccessFactors | Multiple |
| JWT | API management front-door | Token-based |

The **single most important property** of Security Material storage: **password/secret changes do NOT require redeploying the iFlow.** Treat secret rotation as an operational task, not a deploy task.

## 4. The SOAP adapter

SOAP is alive and well in the SAP world. You'll meet it whenever you talk to older S/4 systems, IDoc-over-SOAP scenarios, or partners who never moved off WS-* stacks.

- Supports **SOAP 1.1 and 1.2**, WS-Addressing, WS-Security (verify, decrypt, sign, encrypt).
- A special variant is **SOAP SAP RM** (Reliable Messaging) which provides **Exactly Once (EO)** and **Exactly Once In Order (EOIO)** delivery guarantees. Message IDs are stored for **90 days** for deduplication.
- Three Message ID Determination modes for SAP RM: *Generate* (new ID per message), *Reuse* (use upstream ID), *Map* (extract from a custom field).

SOAP sender or receiver is configured similarly to HTTP, but you usually upload a **WSDL** as an artifact and the adapter binds to it.

## 5. RFC adapter — talking to ABAP

If you need to call a remote-enabled function module on an ABAP system (S/4 on-premise, ECC, etc.):

- Receiver only — there is no "RFC sender" because ABAP doesn't push to CI; ABAP pushes via IDoc, OData, or HTTP.
- **Requires Cloud Connector** to reach the on-premise system.
- The adapter consumes the function module signature via a generated WSDL: `/sap/bc/soap/wsdl11?services=<function_module>`.
- Synchronous only.

You will not configure RFC today (no on-premise system in the lab) but you should be able to *describe* it.

## 6. LDAP adapter — directory lookups

- Receiver only.
- Use cases: user-info enrichment, group membership checks, certificate retrieval.
- Auth: anonymous or simple bind with credentials.
- Returns LDIF — usually paired with a Groovy script to parse.

Mentioned for completeness; you won't lab it.

## 7. The "no native standard format" gotcha

**This is the single biggest difference from SAP PI/PO and the source of many newcomer bugs.**

In PI/PO, every payload was auto-converted to the XI canonical XML on the way in. In Cloud Integration, **payloads are passed through unchanged**. If the inbound is JSON, your iFlow gets JSON in the body. If it's binary, it's binary. If it's flat-file CSV, it's CSV.

**Consequence:** before you can do XPath, content-based routing, or message mapping on a non-XML payload, you must **explicitly convert** it. Use:

- *JSON → XML Converter* step, or
- *CSV to XML Converter* step, or
- A Groovy script (Week 2).

Forgetting this is the #1 source of "why is my router not branching?" incidents in week 2 of someone's career.

---

## Hands-on lab — Customer Echo Service learns to call out

> Time: ~3 hours. Goal: extend your `roi_<your_initials>_CustomerEchoService` iFlow so that, after enriching the payload, it calls a public REST endpoint to *validate* the country code, and merges the response.

### Setup

We'll use the trial endpoint `https://restcountries.com/v3.1/alpha/{code}` (returns a JSON array describing a country given a 2-letter code). No auth required. If your tenant blocks that endpoint, the trainer will substitute `https://httpbin.org/get` and adjust the lab.

### Steps

0. **Allow-list `customerCountry` before anything else.** An inbound custom header isn't visible inside the iFlow just because the caller sent it — it has to be explicitly whitelisted first, or it's silently dropped at the sender boundary with no error.
   - Click the empty canvas behind the flow (not on any shape) — an **Integration Flow** menu appears.
   - Go to **Runtime Configuration** → **Allowed Header(s)**.
   - Add `customerCountry`. Multiple names are pipe-separated (`headerOne|headerTwo`) — same convention as ProcessDirect's allow-list, Day 1.4. `*` accepts everything, but don't use it: explicit names only, same rule as everywhere else in this project.
   - Save the iFlow.

1. **Open `roi_<your_initials>_CustomerEchoService`.** Confirm it has the HTTPS sender at `/customer/<your_initials>/echo` and a Content Modifier.

2. **Replace the placeholder with a real flow:**

   ```
   Sender ─▶ Content Modifier (set props) ─▶ Request-Reply ─▶ End
                                                  │
                                                  ▼
                                            HTTP receiver
                                            (restcountries)
   ```

3. **Content Modifier — extract input and stash properties.**
   - *Message Header*:
     - `correlationId` — Type: *Expression* → `${date:now:yyyyMMddHHmmssSSS}-${exchangeId}` (we'll switch to a UUID via Groovy in Week 2).
     - `Content-Type` — Constant → `application/json`.
   - *Exchange Property*:
     - `customerCountry` — Type: *XPath* won't work on JSON. Use **Type: Header** with name `customerCountry` and have the caller provide it as a header (cleaner for today). Document this in your iFlow comments. **This property is what Step 4's receiver address actually reads — not the raw header** (see Step 4).
     - **Before this header is readable at all, it has to be allow-listed — see the Step 0 below.** Without that, `customerCountry` never reaches this Content Modifier no matter what the caller sends.

   *(Tomorrow we'll learn the JSON-to-XML converter trick to extract `country` from the body without a header.)*

4. **Add a Request-Reply step**, then drop an **HTTP receiver adapter** on its outbound line.
   - **Address**: `https://restcountries.com/v3.1/alpha/${property.customerCountry}` — the property Step 3 stashed, not the raw header. This is the point of extracting it into a property: the value is available for the rest of *this* iFlow run without depending on the header still being around unchanged.
   - **Method**: GET
   - **Authentication**: None
   - **Throw Exception on Failure**: leave checked for now.

5. **After the Request-Reply**, add a second Content Modifier to merge:
   - The *received* body (now the country JSON) is placed into a property named `countryDetails`.
   - Then set the body to a synthesized JSON like:
     ```
     { "customerId": "...", "name": "...", "country": "...", "countryDetails": { ... } }
     ```
   We'll do this properly with Groovy in Week 2; for today, build it with the Content Modifier *Message Body → Type: Expression* using Camel Simple expressions, or accept a half-merged result and clean up with Groovy next week. The point today is the *call*, not the merge.

6. **Save → version → deploy.**

7. **Test it.**
   ```bash
   curl -u <user>:<pwd> -X POST "<runtime-url>" \
        -H "customerCountry: DE" \
        -H "Content-Type: application/json" \
        -d '{ "customerId": "C-1001", "name": "Acme GmbH" }'
   ```

8. **Inspect in the Monitor.**
   - Find the message in *Message Processing*.
   - Click into *Steps* — note that the Request-Reply has its own sub-step showing the HTTP receiver call, with the response code visible.
   - Try filtering by `correlationId=<value>` in Custom Headers search — it won't find anything yet. Setting a header (as this Content Modifier did) isn't the same as registering it as a searchable MPL property; that's a separate, explicit step you'll do with a script on Day 1.4.

### Failure injection — the most useful part

After the happy path works, try:

- Send `customerCountry: ZZ` — RestCountries returns 404. Your iFlow will *fail*. Look at the message in the Monitor; status will be **Failed** with `CamelHttpOperationFailedException` in the error details. This is the default behavior we mentioned.
- Now in the HTTP receiver, **uncheck "Throw Exception on Failure"**. Add a Router after the Request-Reply that branches on `${header.CamelHttpResponseCode}` — `2xx` → success, anything else → set body to `{ "error": "country not found" }` and continue. Redeploy and retry.
- Inspect the monitor. Status will now be **Completed** even when the upstream returned 404. **This is the HTTP error suppression pattern** — useful when 404 is a known business outcome, dangerous when it lets real errors slip past your alerting (we revisit this in Week 4).

---

## Reference card excerpt — Day 1.3

- HTTPS sender = inbound; HTTP receiver = outbound.
- **Inbound custom headers must be allow-listed** — canvas empty space → Integration Flow menu → Runtime Configuration → Allowed Header(s), pipe-separated. Not on the list = silently dropped, even though the caller sent it.
- HTTP receiver default timeout 60 s, retry up to 3x.
- **Uncheck "Throw Exception on Failure"** to route on `CamelHttpResponseCode` instead of failing.
- SOAP SAP RM provides **EO / EOIO** with 90-day message-ID dedup.
- RFC requires Cloud Connector and is receiver-only.
- **Cloud Integration has no native canonical format** — convert JSON/CSV/flat to XML before XPath/routing/mapping.
- Security Material storage means **secret rotation does NOT need a redeploy**.
