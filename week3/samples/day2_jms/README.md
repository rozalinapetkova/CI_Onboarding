# Day 3.2 — JMS Producer / Queue / Consumer — sample artifacts

Maps to `week3/day2_jms.md`. Lab splits `roi_<initials>_OrderHub` into a producer iFlow + a consumer iFlow connected by `roi.orderhub.outbound.<initials>` with DLQ `roi.orderhub.dlq.<initials>`.

| File | Purpose | Mapped section |
|---|---|---|
| `jms_receiver_producer_config.md` | JMS receiver adapter (producer side) — fields, persistence, response-code wiring | §4 |
| `jms_sender_consumer_config.md` | JMS sender adapter (consumer side) — retry interval, backoff, and why the adapter's own Dead-Letter Queue checkbox isn't a real DLQ | §5, §8 |
| `queue_naming_reference.md` | `roi.<flow>.<purpose>.<initials>` convention + plan limits | §2, §10, §11 |
| `producer_response_body.json` | Sample 202-Accepted response body returned by the producer | Lab step 1 |
| `roiam_categorizeError.groovy` | v2 Groovy: classify exceptions as `Retry` or `Bypass`, set property + header + MessageLog | §9 |
| `exception_subprocess_wiring.md` | How the Retry/Bypass router branches translate to canvas elements | §9, Lab step 4 |
| `call_orderhub_async.sh` | Curl the producer endpoint; expect HTTP 202 + body with `orderSequence` | Lab step 3 |
| `provoke_failures.sh` | Trigger Retry-class (502/timeout) and Bypass-class (400) failures | Lab steps 5–6 |
| `replay_dlq_runbook.md` | Cockpit *Move To...* SOP for replaying DLQ messages, and why replay-without-fix is a loop | Lab step 7 |
| `eoio_serialization_key.md` | When a serialization key is the right answer (partitioned ordering) and when it isn't | §7 |
| `common_failures_cheatsheet.md` | Symptom → cause → fix table covering queue-depth growth, retry storms, mis-categorization | §6, §9, Failure cases |

Read `jms_receiver_producer_config.md` and `jms_sender_consumer_config.md` first — they anchor the producer/consumer split. Then `roiam_categorizeError.groovy` + `exception_subprocess_wiring.md` for the Retry/Bypass discipline. Save scripts as `roiam_*.groovy` under `script/v2/`.
