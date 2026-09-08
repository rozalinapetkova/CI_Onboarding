# JMS misconfigurations — symptoms and causes

## Producer-side failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Producer returns 500 on POST | JMS receiver adapter can't reach broker; queue name invalid | Cockpit → *Manage Stores → Message Queues* — confirm queue exists; check adapter logs |
| Producer returns 200, not 202 | `CamelHttpResponseCode` header not set before End | Add Content Modifier setting `CamelHttpResponseCode = 202` |
| Producer succeeds but consumer never runs | Consumer iFlow not deployed, or its JMS sender pointing at wrong queue name | Cockpit → *Monitor → Message Queues* — confirm message is on the queue; check consumer's JMS sender Queue Name matches exactly |
| Producer's response body shows `${header.X-Order-Sequence}` literal | Header not actually set (Day 3.4 lab hasn't been done yet) | Hardcode to `ORD-PENDING` for the lab, or remove the field |
| Queue depth grows even though consumer is deployed | Consumer's JMS sender disabled, or Concurrent Processes = 0 | Re-deploy consumer; confirm `Concurrent Processes` ≥ 1 |

## Consumer-side failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Consumer run shows *Failed* with no Exception Subprocess detail | No exception subprocess attached, or attached but has no script step | Always attach an Exception Subprocess with `roiam_categorizeError.groovy` |
| Consumer retries 3 times on a 400 response, then DLQs | Categorization not running OR `errorCategory` defaults to Retry for 4xx | Verify Router branches: `Bypass = ${property.errorCategory} = 'Bypass'`. Verify categorization script sets Bypass on 400-499 (except 408, 429) |
| Same message appears in DLQ four times for one logical failure | Exception Subprocess uses `End Throw` for Bypass branch — rethrows after explicit DLQ enqueue. JMS then retries 3 more times | Bypass branch must end with regular `End` (swallow), not `End Throw` |
| Consumer iFlow stuck in *In Progress* state for >5 minutes | Lock Timeout shorter than worst-case processing → message reclaimed → duplicate in-flight | Raise Lock Timeout. Also: check downstream isn't deadlocking |
| `Concurrent Processes = 4` but only one worker draining | Access Type = `Exclusive` overrides Concurrent Processes | Pick one model. Exclusive = single-thread always; Non-Exclusive = N workers × Concurrent Processes |
| Random duplicate processing | A message was reclaimed mid-flight due to Lock Timeout, then both old and new worker completed | Raise Lock Timeout. Make consumer idempotent (Day 3.4 Data Store pattern) |

## DLQ failures

| Symptom | Likely cause | Fix |
|---|---|---|
| DLQ has messages but Alert Notification didn't fire | Alert rule not configured on this queue, or threshold set to >current depth | Week 4: configure Alert Notification on DLQ depth > 0 |
| DLQ messages don't show original error category | Categorization headers not preserved on enqueue, or DLQ envelope Content Modifier overwriting them | Set `X-Error-Category` and `X-DLQ-Reason` as outbound headers on the DLQ JMS receiver |
| Replay loop — same message in DLQ five times | Bypass-class message replayed without fixing root cause | Stop. Read `replay_dlq_runbook.md`. Fix the cause, then replay |
| DLQ name shows `<queue>.dlq` (auto-generated) instead of the configured one | DLQ Name field left blank on JMS sender adapter | Always set DLQ Name explicitly |

## Queue / broker / plan-limit failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Deploy fails with "queue limit exceeded" | Tenant has 30 queues (Standard plan); this deploy would create the 31st | Clean up old test queues — *Monitor → Message Queues → Delete*. Check trainer's cleanup list |
| Deploy fails with "queue name invalid" | Uppercase, spaces, or unsupported separator in queue name | All-lowercase, dots only: `roi.<flow>.<purpose>.<initials>` |
| `roi.orderhub.outbound` exists on tenant and trainee's `roi.orderhub.outbound.ab` also exists | Trainee forgot `<initials>` suffix and clashed with production queue, or production omitted suffix and trainee included it | Lab always uses `<initials>`. Production never does. Strip before transporting |
| Queue depth stuck at high number even though consumer reports completed runs | Worker hit a stuck consumer slot — broker holds messages with no live consumer | Restart the consumer iFlow's deployment; check 150-transaction tenant limit |

## "Looks fine but isn't" silent failures

1. **Producer returns 202 but the queue is empty.** The JMS receiver adapter's connection to the broker is misconfigured (rare) or there's a Content Modifier swallowing the body before enqueue. Look for *Monitor → Message Processing → producer run → Outbound* sub-step — if the JMS sub-step is missing, the iFlow ended before reaching JMS.

2. **Consumer iFlow deployed but never starts a run.** Concurrent Processes = `0`, or the JMS sender is disabled (Authentication mis-set, queue name mismatched). *Monitor → Started Integration Flows → consumer → Status: Started* — if it says *Idle* or *Stopped*, the consumer isn't polling.

3. **`X-Error-Category` header makes it into the DLQ message but the downstream alert says "unknown category".** Headers were renamed somewhere in the exception subprocess Content Modifier. Spell-check.

4. **EOIO appears to work in dev, fails under prod load.** Dev never had two messages with the same serialization key arrive close enough in time to interleave. Test EOIO with a load generator that hammers the *same* key, not random keys.

5. **Retry counter not visible in MPL.** Standard MPL view doesn't show JMS retry attempts as separate runs — each retry attempt is logged inside the same run's processing log. To see the retry sequence: *Monitor → Message Queues → message detail → Processing History*.

6. **"Working" consumer that silently drops messages.** End Throw never wired in the Retry branch — the subprocess ends normally on every failure → JMS thinks every message processed → no retry, no DLQ, no record. Look for a queue with high producer throughput and zero DLQ accumulation despite known-failing downstream — that's silent data loss. Always test failure paths.
