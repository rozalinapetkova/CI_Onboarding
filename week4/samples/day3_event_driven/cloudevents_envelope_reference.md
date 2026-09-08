# CloudEvents envelope — header reference

SAP standardized on the CNCF **CloudEvents** spec as the envelope for events flowing through Event Mesh, Intelligent Services, S/4HANA, and SuccessFactors event channels. Same shape everywhere.

## Required attributes (spec v1.0)

| Attribute | Type | Example |
|---|---|---|
| `id` | string | `e8a1bf57-0c52-4a35-b89c-abc123def456` |
| `source` | URI-ref | `https://my-s4-tenant.s4hana.cloud.sap` |
| `specversion` | string | `1.0` |
| `type` | string | `sap.s4.beh.salesorder.v1.SalesOrder.Created.v1` |

These four MUST be present on every event.

## Optional attributes (used in practice)

| Attribute | Type | Example |
|---|---|---|
| `subject` | string | Business entity ID, e.g. `0001234567` (the SalesOrder number) |
| `time` | RFC 3339 timestamp | `2026-06-22T14:31:09Z` |
| `datacontenttype` | media type | `application/json` |
| `dataschema` | URI | `https://my-s4-tenant.s4hana.cloud.sap/schemas/SalesOrder.Created.v1.json` |

## SAP extension attributes

SAP adds these to S/4 events. They appear as additional headers:

| Attribute | What it carries |
|---|---|
| `sapxsappname` | The S/4 tenant's XSUAA app name |
| `sapxstenantid` | S/4 tenant ID |
| `saplogicalsystem` | Logical system identifier (legacy ALE concept, carried for compat) |

## How CI's AMQP adapter exposes these

The AMQP adapter unpacks CloudEvents attributes into **message headers** prefixed `ce-`:

| In the event | In CI headers |
|---|---|
| `id` | `ce-id` |
| `source` | `ce-source` |
| `type` | `ce-type` |
| `subject` | `ce-subject` |
| `time` | `ce-time` |
| `datacontenttype` | `ce-datacontenttype` |
| (SAP extensions like `sapxsappname`) | `ce-sapxsappname` |

The `data` field becomes the message **body**.

So in your iFlow:
- Body access: standard `message.getBody(java.io.Reader)`.
- Event ID: `message.getHeaders().get("ce-id")`.
- Event type: `message.getHeaders().get("ce-type")`.

## Project convention — correlation mapping

Map `ce-id` → `correlationId` IF no `correlationId` header was already present. This makes the event's own dedup key act as the cross-system trace ID.

```groovy
String correlationId = headers.get("correlationId") as String;
if (correlationId == null || correlationId.trim().isEmpty()) {
    correlationId = headers.get("ce-id") as String;
}
if (correlationId == null || correlationId.trim().isEmpty()) {
    correlationId = UUID.randomUUID().toString();
}
```

See `roiam_setCorrelationId_event.groovy` for the full script.

## Why CloudEvents (and not custom envelopes)

| Concern | CloudEvents | Custom envelope |
|---|---|---|
| Subscribers can be polyglot (Java, Node, Python) | Standard parsers exist for every language | Each consumer writes its own parser |
| Tooling (event browsers, validators) | Standard tools work | Tooling is bespoke |
| Cross-vendor (SAP ↔ Microsoft ↔ Confluent ↔ AWS) | Same envelope flows everywhere | Each border requires translation |
| Schema evolution | `specversion`, `dataschema` fields | Bespoke versioning |
| Federation between SAP cloud products | Same shape across S/4, SuccessFactors, Field Service | Each product would be different |

The cost is verbose envelopes (eight required fields for a simple "something happened" message), but the cross-system fit makes it worth it.

## Common mistakes reading CloudEvents headers in CI

| Mistake | Symptom |
|---|---|
| Looking for header `id` (no prefix) | Returns null — header is `ce-id` |
| Looking for `eventId` or `event-id` | Wrong name; not how CI's AMQP adapter names them |
| Looking for `ce-data` | The data is in the body, not a header |
| Treating `ce-time` as a JVM `Date` object | It's a string in RFC 3339 format; parse with `java.time.OffsetDateTime.parse()` |
| Treating `ce-id` as a UUID | The spec only requires a unique string per source; could be any format |

## Differences between CloudEvents over HTTP and CloudEvents over AMQP

CloudEvents can be carried over multiple protocols. The two CI commonly uses:

| Aspect | HTTP transport | AMQP transport (Event Mesh) |
|---|---|---|
| Where attributes live | HTTP headers prefixed `ce-` OR JSON body in "structured mode" | AMQP application properties prefixed `cloudEvents:` (the adapter normalizes to `ce-`) |
| `data` field location | Body | Body |
| Content type when binary | `application/json` (or whatever) | `application/json` (or whatever) |
| Content type when structured | `application/cloudevents+json` | Less common over AMQP |

For the Order Hub we receive over AMQP. The headers are already normalized to `ce-*` by the adapter. You don't need to worry about structured vs binary mode.

## Sample event (S/4 SalesOrder.Created)

See `sample_cloudevents_payload.json` for a realistic example.

## Verifying CloudEvents headers landed correctly

In MPL → Run Steps → click the AMQP receive step → Headers panel. You should see:

```
ce-id: e8a1bf57-0c52-4a35-b89c-abc123def456
ce-source: https://my-s4-tenant.s4hana.cloud.sap
ce-specversion: 1.0
ce-type: sap.s4.beh.salesorder.v1.SalesOrder.Created.v1
ce-subject: 0001234567
ce-time: 2026-06-22T14:31:09Z
ce-datacontenttype: application/json
```

If any required attribute is missing, the producer published a malformed event. Route to error path; don't silently filter.
