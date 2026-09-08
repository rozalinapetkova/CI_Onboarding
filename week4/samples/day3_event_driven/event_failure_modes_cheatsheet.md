# Event-driven failure modes — symptom-to-cause cheatsheet

Keep this open during the Day 4.3 hands-on lab and any time you're debugging the event subscription. Symptoms are listed; causes and fixes follow.

## Subscription / connection failures

| Symptom | Cause | Fix |
|---|---|---|
| iFlow deployed but no events ever arrive | AMQP credentials wrong; adapter can't authenticate | Check Security Material alias `event_mesh_amqp`; test connection in adapter config |
| Events arrive on partner team's iFlow but not on yours | Queue binding to topic missing in Event Mesh cockpit | Open Event Mesh cockpit → Queues → your queue → Subscriptions → verify topic binding |
| Events stop arriving after running for hours | Broker connection dropped, adapter not reconnecting | Verify `Reconnect: Yes` on adapter; check tenant network event logs |
| Adapter logs "AMQP link detached" repeatedly | Credential rotated on Event Mesh side but old creds still in Security Material | Update Security Material with new client id/secret |
| First event after re-deployment of iFlow doesn't arrive | Subscription Name was changed inadvertently | Compare current adapter config's Subscription Name to git history; revert if changed |
| Queue depth climbing on broker, MPL on iFlow shows nothing recent | AMQP adapter in started state but not consuming (rare adapter bug; restart needed) | Undeploy / redeploy the iFlow |

## Poison message / DLQ failures

| Symptom | Cause | Fix |
|---|---|---|
| Same `ce-id` appears in failed MPL runs repeatedly | Message is malformed (schema drift, parse error) and being re-delivered indefinitely | Verify Maximum Retries is finite (e.g., 5); verify DLQ is configured in Event Mesh; manually move the message to DLQ if it's stuck |
| Queue depth high but processing rate is zero | Poison message at head of queue blocking new deliveries (rare — most brokers re-deliver out of order under retry) | Check broker docs for "skip" or "side-line" capabilities; move the problematic message to DLQ |
| DLQ is filling up but no alert fires | Cloud ALM alert on DLQ depth not configured | Add alert on DLQ depth > 0 → page oncall |
| Event lost: appears nowhere in MPL or DLQ | Producer-side error before publish, OR retention purge cleaned it before consumption | Check Event Mesh metrics for "messages dropped"; check producer-side logs |
| DLQ has messages but no consumer is reading them | DLQ consumer iFlow not deployed (Day 4.4) | Deploy the DLQ-reader iFlow; review accumulated DLQ entries |

## Out-of-order / sequencing failures

| Symptom | Cause | Fix |
|---|---|---|
| `Changed` event for order `0001234567` processed before `Created` for the same order | Different producer threads, no per-key ordering guarantee | Either: (a) subscribe with EOIO (limits throughput); (b) design idempotent merge on the consumer side; (c) detect-and-buffer ("hold Changed if no Created seen yet") |
| Discount applied before order header exists in downstream | Same as above | Idempotent merge: downstream Upsert logic that tolerates events arriving in any order |
| Order Hub processes order create then immediate cancel correctly, but on replay the cancel comes first | Replay doesn't preserve original ordering | Replay logic should apply only deltas, not re-process the whole timeline |

## Duplicate / idempotency failures

| Symptom | Cause | Fix |
|---|---|---|
| Same order appears 2+ times in OMS | Dedup check was skipped or dedup store empty (cleared, deleted, TTL expired prematurely) | Check Data Store `roi_orderhub_event_dedup` exists with correct entity name; check TTL config; check that dedup write is at end of flow |
| Duplicate processed despite dedup check | Dedup write happens BEFORE downstream success — re-delivery on partial failure caused a permanent skip on retry; OR dedup key isn't `ce-id` | Move dedup write to end of flow; key on `ce-id` exactly, not on a derived field |
| Thousands of duplicates flood the queue in minutes | Producer-side bug: retry loop without idempotency on the producer side | Alert on Inbound message rate spike (Day 4.1); contact producer team; raise short-term Maximum Retries on iFlow to absorb the flood; the dedup catches them in script |
| Dedup store growing unboundedly | TTL not set or set too long | Verify TTL = 7 days on writes; review entries older than TTL — they should be auto-purged |

## Schema drift failures

| Symptom | Cause | Fix |
|---|---|---|
| iFlow runs fine for weeks, suddenly all events fail at the mapping step | Producer rolled out a schema change without notification | Compare current event payload to `sample_cloudevents_payload.json`; update mapping; route old payloads via legacy branch during transition |
| Mapping succeeds but downstream rejects the canonical XML | Schema drift didn't break the iFlow's parsing but moved a field that downstream relies on | Re-validate downstream contract; either tighten iFlow's schema validation (route mismatches to error path) or coordinate with downstream |
| New required field added on producer side, your mapping silently writes empty value | Permissive mapping doesn't fail on missing fields | Tighten input validation: explicitly check that critical fields are present at script entry |
| Event type `sap.s4.beh.salesorder.v1.SalesOrder.Created.v2` arrives, your subscription expects `.v1` | Producer published v2, you didn't update | Either: (a) update topic subscription to `+/v1` wildcard then dispatch by `ce-type`; (b) add a separate subscription for v2; (c) reject v2 events with a clear error |

## Partner Directory failures

| Symptom | Cause | Fix |
|---|---|---|
| Script throws "Routing parameter not found for partnerId: 'ROI_ORDERHUB_ROUTING', parameterId: 'default'" | PD parameter was deleted or renamed | Restore PD parameter in cockpit; verify partner id and parameter id case-sensitively |
| Script throws "Partner Directory service not available" | `ITApiFactory.getApi(PartnerDirectoryService.class, null)` returned null — usually transient, sometimes auth issue | Re-deploy iFlow; if persistent, escalate to trainer / BTP admin |
| Script throws "is not a JSON object" or "'routes' missing" | Someone edited PD parameter to invalid JSON | Restore from version history if PD supports it (some PD instances do, some don't); always paste-validate before saving |
| Resolved route points at wrong target | PD edited carelessly | Apply 4-eyes review discipline on PD changes (treat PD edits like code changes) |
| PD change "not taking effect" | Caching at the PD service tier (rare) or trainee looking at the wrong iFlow run | Wait 30 seconds; check that the iFlow run you're inspecting started AFTER the PD change; confirm via MPL property `targetSystem` |
| Routing decision logged in MPL doesn't match PD parameter content | Script is reading the wrong partner id (typo) | Compare script's `pid` variable to PD cockpit display name |

## Acknowledgement / re-delivery failures

| Symptom | Cause | Fix |
|---|---|---|
| MPL shows Completed but the same `ce-id` is delivered again 5 minutes later | Auto-Acknowledgement mode (you got the ACK fast but iFlow result wasn't tied to it) OR the iFlow completed without sending ACK | Verify Acknowledgement Mode is `Client Acknowledgement` |
| All events fail silently with no MPL entry at all | Auto-Ack + an early-stage crash (rare combination, but possible) | Always Client Ack |
| iFlow finishes successfully but message stays in queue | Adapter version bug or misconfiguration | Restart iFlow; if persists, raise SAP support ticket; verify adapter version |

## CloudEvents header failures

| Symptom | Cause | Fix |
|---|---|---|
| Script can't find `ce-id` header | Producer didn't include `id` (rare — required by spec; producer is malformed) | Reject event with clear error; alert on malformed event rate |
| `ce-time` parsing throws | `ce-time` is a string, not a Date | Use `java.time.OffsetDateTime.parse(headers.get('ce-time'))` |
| Looking for header `id` (no prefix) — null | Header is `ce-id` not `id` | Use the `ce-` prefix |
| `ce-type` arrives as null | Producer didn't include `type` (malformed) OR the AMQP adapter version is old and uses different prefix | Verify adapter version; reject malformed events |

## Throughput / quota failures

| Symptom | Cause | Fix |
|---|---|---|
| Some events delayed by 5+ minutes between publish and processing | Event Mesh throttling — plan limit reached | Check Event Mesh metrics for throttle events; upgrade plan if persistent or stagger producer publish rate |
| Subscription drops every N hours like clockwork | Event Mesh idle disconnect on idle plans (some lower-tier plans drop idle connections) | Heartbeat traffic; or upgrade plan |
| 429 errors on producer side | Event Mesh inbound rate limit | Implement client-side backoff on producer |

## What to do when you can't isolate the failure

The escalation order:

1. **Read MPL of the most recent failed run.** The exception is usually clear; the stack trace points to a step.
2. **Compare to `sample_cloudevents_payload.json`.** Is the event shape what you expect? Schema drift catches this.
3. **Check Event Mesh cockpit queue metrics.** Depth climbing → consumer slow or broken. Depth zero with no recent delivery → producer-side issue.
4. **Verify PD parameter content.** Open in cockpit, compare to `pd_routing_parameter.json` template.
5. **Reproduce with the trainer's helper iFlow.** If a fake event with a known shape works, the issue is the producer's payload, not your subscription.
6. **Re-deploy with no changes.** Sometimes restoration of a broken connection / adapter state. Last resort but cheap.
7. **Ask trainer or escalate.** Especially for transient errors that disappear when you look — those are usually broker / tenant-tier issues you can't fix locally.
