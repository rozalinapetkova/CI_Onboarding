# Monitoring & Logging — symptoms and causes

## MessageLog / logging failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Script crashes with NPE on `messageLog.addAttachmentAsString` | Log Level = None at runtime; `getMessageLog` returned null | Add the `if (messageLog != null)` guard, redeploy |
| No attachments visible in Monitor for any run | Log Level = Error (only Failed runs retain attachments) | Bump to Info via Configure → Log Configuration |
| Attachments visible but not on the run you just sent | You're looking at an older run; Monitor caches; press Refresh | Refresh; verify timestamp |
| Attachments visible but unreadable as XML/JSON | Mime type wrong on `addAttachmentAsString` | Pass `application/xml` or `application/json` explicitly |
| Multi-megabyte attachment kills cockpit responsiveness | Attaching full multi-MB payloads | Attach only what's needed for triage; truncate to first 4 KB if needed |
| Secrets visible in tenant log store | Authorization header logged via Trace level or by attaching full HTTP envelope | Strip `Authorization`, `X-API-Key`, etc. before attaching; never use Trace beyond an investigation |

## Searchable header / property failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Header `orderId` visible in Run Steps but not in Search dropdown | Forgot to tick "MPL custom header property" on the Content Modifier | Open Content Modifier → Message Header → check the box, redeploy |
| Property registered via `setStringProperty` not searchable | Log Level = Error; properties only retained on Failed runs at that level | Bump to Info |
| `correlationId` searchable on Producer but not Consumer | ProcessDirect not configured to allow `correlationId` header through | Add `correlationId` to ProcessDirect Allowed Headers list |
| Header has different value on Consumer than Producer | Header rewritten by Content Modifier in between | Audit; remove the spurious overwrite |
| `setStringProperty` doesn't appear at all | Property name has special chars (spaces, `:`, `/`) | Use camelCase, no special chars |
| Property name registered but old runs don't show it | MPL properties are per-run; only new runs after registration carry the property | Expected — old runs stay as they were |

## Correlation ID failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `correlationId` is blank in Monitor | Inbound caller didn't supply one and `roiam_setCorrelationId.groovy` wasn't placed first | Move the script to first position; verify it generates a UUID on missing input |
| Same `correlationId` for unrelated messages | Caller sent identical value for distinct business transactions | Educate caller; don't try to detect/replace — accept caller's identifier |
| `correlationId` propagated to first ProcessDirect callee but lost on second hop | Second iFlow doesn't allow `correlationId` in its ProcessDirect adapter | Add to Allowed Headers on every ProcessDirect, every iFlow |
| `correlationId` lost after JMS hop | JMS adapter doesn't propagate custom headers by default | Configure "Allowed Headers" on the JMS Sender to include `correlationId` |
| `correlationId` lost after Mapping step | Mapping discarded headers | Use Content Modifier after Mapping to restore the header from property |

## ANS / Alert Notification failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Synthetic Test Event sent but no email arrives | Subscription disabled, or action's email destination misconfigured | Re-enable subscription; verify Action's email field |
| Test Event arrives but real iFlow events don't fire ANS | Day 4.4's emit step isn't yet implemented in the iFlow | Expected at Day 4.1; comes online in Day 4.4 |
| All trainees' subscriptions fire for the same event | Cohort sharing one ANS instance with overlapping subscriptions | Add `tags.initials=<your initials>` to your event payload + filter on it |
| Subscription filter doesn't match emitted event | Category name mismatch (e.g. `roi.OrderHub.dlq` vs `roi.orderhub.dlq`) | Categories are case-sensitive; lowercase everywhere |
| Subscription configured but action is someone else's | Picked wrong action from dropdown | Verify action ownership in ANS cockpit |
| Email flooded with low-severity events | Subscription filter too broad (e.g. `eventType matches roi.orderhub.*`) | Narrow to specific reasons |

## Cloud ALM failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Cloud ALM doesn't see the iFlow | Tenant not registered as monitored system | Trainer-only; out of cohort scope |
| Synthetic check times out | The iFlow's endpoint requires auth Cloud ALM doesn't have | Add an OAuth2 credential or change to public health endpoint |
| Change tracking shows wrong commit author | CTM transport user is a shared service account | Expected; track changes via runbook entries instead |

## "Completed" hiding errors — silent failures

These don't show as Failed in MPL. Only an attentive operator (or a real customer complaint) catches them.

1. **Receiver returned 500, iFlow caught the exception and routed to a "success" Subprocess.** The downstream backend rejected; the order never landed; the MPL says Completed. *Fix:* re-raise from the catch, or have the Subprocess emit a Failed-status MPL via an explicit script that throws.

2. **Filter step dropped the message because a field was empty.** Discarded is correct in principle, but if `customerId` was empty due to a parser bug, the filter masks the real issue. *Fix:* log Discarded with a reason; never silently filter on a field that should always be present.

3. **JMS Sender succeeded but the JMS broker rejected the message** (queue full, size limit, etc.). Some adapter configurations swallow this. *Fix:* configure "Throw Exception on Failure" on the JMS Sender; alert on JMS broker queue-full metrics.

4. **Idempotency cache returned yesterday's response envelope** but with yesterday's `correlationId`. The caller's logs show the request was accepted under their new `correlationId`, but the response references an old trace. *Fix:* either include the cached-from `correlationId` explicitly in the response, or document that idempotent replays return the original trace ID.

5. **The iFlow's Log Level is Error, masking attachments on successful runs.** Operations debugging a "weird payload" complaint sees nothing because the run wasn't Failed. *Fix:* Info level in production for the Order Hub; documented in `log_levels_reference.md`.

6. **Trace level was left on after a Friday investigation.** Comes back Monday morning to find the tenant log store at 95% capacity, oldest messages rolling off. *Fix:* changelog-tracked Trace enablement with a documented revert; alerting on log store usage % from the cockpit.

## When in doubt

The cockpit is authoritative:

- **What status was this run?** *Monitor → Message Processing → click the run → header bar.*
- **What attachments did the iFlow create?** *Run page → Attachments tab.*
- **What headers / properties were set?** *Run Steps tab → click each step → Headers / Properties panels.*
- **Did this run cause an ANS event?** ANS cockpit → *Events* tab → filter by timestamp.
- **What was the message body at the last attachment?** *Attachments → click the boundary name → view.*

Trust the runtime over the spec. The MPL records what actually happened.
