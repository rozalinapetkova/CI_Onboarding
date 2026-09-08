# Day 4.3 samples — Event-Driven & Event Mesh / Partner Directory

Companion artifacts for `week4/day3_event_driven.md`. Each file maps to a section.

## Files

| File | Covers |
|---|---|
| `cloudevents_envelope_reference.md` | Section 2 — CloudEvents spec, header conventions, `id → correlationId` mapping |
| `amqp_vs_jms_reference.md` | Section 3 — protocol comparison, when to use which |
| `topic_naming_reference.md` | Section 4 — S/4HANA topic conventions, wildcard subscription patterns |
| `intelligent_services_vs_amqp.md` | Section 5 — when to use the wizard, when to wire directly |
| `durable_subscription_config.md` | Section 6 — adapter settings, subscription-name stability, recovery semantics |
| `roiam_resolveRoutingFromPd.groovy` | Section 9 — Partner Directory lookup script, project-style |
| `roiam_setCorrelationId_event.groovy` | Section 10 — updated correlation script for the event entry path |
| `pd_routing_parameter.json` | Section 8/9 — sample binary parameter JSON content |
| `event_subscription_flow_diagram.md` | Section 10 — the full event-entry flow with branch decisions |
| `sample_cloudevents_payload.json` | Section 2 — a realistic `SalesOrder.Created` event |
| `event_failure_modes_cheatsheet.md` | Section 11 — subscription disconnect, poison, out-of-order, dup floods, schema drift |
| `pd_vs_security_material_vs_data_store.md` | Section 8 — what belongs where |

## How to use

1. Read the module first.
2. Use `event_subscription_flow_diagram.md` as the canvas reference while building.
3. Upload the two Groovy scripts via the Script step dialog (not Resources tab).
4. Keep `event_failure_modes_cheatsheet.md` open while testing.
