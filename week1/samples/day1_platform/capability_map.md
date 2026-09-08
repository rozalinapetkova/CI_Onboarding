# The 10 capabilities — "when would I reach for this?"

| # | Capability | Reach for it when… |
|---|---|---|
| 1 | **Cloud Integration** | You need to orchestrate, transform, route, or schedule a message flow between systems. The default starting point. |
| 2 | **API Management** | You want to expose iFlows publicly with rate limits, quotas, API keys, or a developer portal. |
| 3 | **Open Connectors** | You need Salesforce / HubSpot / Slack / 160+ SaaS connectors and don't want to build the auth + paging + retry yourself. |
| 4 | **Integration Advisor** | You're doing B2B / EDIFACT / X12 mappings and want ML-suggested field correspondences. |
| 5 | **Trading Partner Management** | You manage many B2B partners with distinct certs, agreements, and protocols. |
| 6 | **Event Mesh** | You want pub/sub decoupling — one producer, many subscribers, durable subscriptions. |
| 7 | **OData Provisioning** | You want to expose SAP data as a standards-compliant OData service. |
| 8 | **Data Space Integration** | You're in Catena-X / Manufacturing-X / sovereign-data-exchange scenarios. |
| 9 | **Integration Assessment** | You're planning a multi-quarter integration program and need governance tooling. |
| 10 | **Migration Assessment** | You're migrating from SAP PI/PO and need a readiness analysis of existing interfaces. |

## Whiteboard exercise — answer key

> *"A retailer wants their S/4HANA to publish order events. Salesforce and a third-party WMS should consume them. Partners exchange invoices over AS2."*

Expected answer:
- **Event Mesh** publishes the order event (decoupling).
- **Cloud Integration** subscribes for Salesforce (with mapping) and for the WMS (with auth + routing).
- **Trading Partner Management** + **Cloud Integration** handle the AS2 invoice channel.
- **API Management** fronts whatever the retailer exposes to partners externally.

Four capabilities working together. **Cloud Integration alone is rarely the whole answer.**
