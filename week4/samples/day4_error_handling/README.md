# Day 4.4 samples — Error Handling End-to-End

Companion artifacts for `week4/day4_error_handling.md`. Each file maps to a section.

## Files

| File | Covers |
|---|---|
| `error_categories_reference.md` | Section 2 — taxonomy: transient, poison, business, configuration, runtime |
| `exception_subprocess_pattern.md` | Section 3 + 4 — what subprocess catches, the standard shape, things it can't do |
| `roiam_captureErrorContext.groovy` | Section 5 — capture-context script in project style |
| `roiam_buildDlqEnvelope.groovy` | Section 6 — JMS DLQ envelope builder |
| `roiam_buildAlertEvent.groovy` | Section 9 — Alert Notification event builder |
| `dlq_envelope_schema.md` | Section 6 — structured DLQ envelope, fields, sample payload |
| `sample_dlq_envelope.json` | Section 6 — realistic DLQ envelope from a poison failure |
| `jms_retry_policy_reference.md` | Section 7 — adapter retry config, redelivery counter, escalation |
| `retry_queue_pattern.md` | Section 8 — separate retry queue for "try again later" transient errors |
| `alert_categories_reference.md` | Section 9 — categories, severities, alert flood prevention |
| `replay_safety_pattern.md` | Section 10 — what makes a DLQ entry safely replayable; consumer-side idempotency |
| `final_orderhub_canvas.md` | Section 11 — the complete iFlow shape after Week 4 |
| `error_lab_failure_cases.md` | Lab failure-cases section — provoke each category and confirm classification |

## How to use

1. Read the module first.
2. Use `final_orderhub_canvas.md` as the canvas reference while building.
3. Upload the three Groovy scripts via the Script step dialog.
4. Keep `error_lab_failure_cases.md` open during the lab provocation exercises.
5. Use `dlq_envelope_schema.md` as the contract spec when designing the future replay iFlow.
