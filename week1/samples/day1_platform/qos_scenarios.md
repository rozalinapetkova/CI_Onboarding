# QoS — pick the right level

For each scenario, decide between **At Least Once**, **Best Effort**, **Exactly Once**.

| # | Scenario | Answer | Why |
|---|---|---|---|
| 1 | Frontend POSTs a quote-request, waits for a synchronous price response | **Best Effort** | Sync request-reply. If it fails, the caller retries. |
| 2 | Nightly batch of 50,000 customer master records from a CRM to S/4 | **At Least Once + idempotent consumer** | Default async. Duplicates handled by upserting on the consumer side. |
| 3 | Posting a payment journal entry to SAP Finance | **Exactly Once** | Non-idempotent — a duplicate posting is real money lost. Pay the latency cost. |
| 4 | Pushing inventory delta events to a downstream WMS that already deduplicates by event-id | **At Least Once** | Consumer is idempotent — let duplicates happen, save the EO overhead. |
| 5 | Webhook from a payment provider, retried 3× by the provider on non-2xx | **Best Effort** | The provider owns the retry. Just return 2xx fast. |
| 6 | EDIFACT invoices from a partner where regulatory rules forbid duplicate filings | **Exactly Once** | Compliance-driven. EO with 90-day dedup window via SOAP SAP RM. |

## Trap

If you find yourself writing **Exactly Once** more than twice in a system, look harder — usually the right move is to make the *consumer* idempotent and downgrade to At Least Once. EO is a tax on every message.
