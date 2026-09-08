# ProcessDirect & Script Collection — symptoms and causes

## ProcessDirect failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Caller fails immediately: "no consumer registered for endpoint /orderTranslator/v1/translate" | Callee iFlow not deployed, or its ProcessDirect sender Address typo | Deploy callee first. `Monitor → Started iFlows` confirms status `Started`. Diff Address strings character-by-character |
| Caller deploys and runs; callee MPL has no run | Caller's ProcessDirect Address doesn't match any callee's ProcessDirect sender | Same — Address must match exactly. Lab uses `/orderTranslator/v1/translate/<initials>` |
| Caller's MPL run shows Failed at the ProcessDirect sub-step with cryptic deploy error | MEP mismatch — Request-Reply on one side, One-Way on the other | Match MEPs |
| Callee MPL run completes but caller's body is unchanged after the call | MEP is One-Way (Send) — by design no reply | If you need the reply, set MEP = Request-Reply on both sides |
| Callee MPL `Headers` tab shows the body but `correlationId` is empty | Allowed Headers list missing the header on caller OR callee | Symmetric lists: `correlationId,orderId,X-Order-Format,X-Idempotency-Key,X-Order-Sequence` on both |
| Property `errorCategory` is null on the callee even though set on caller | Properties **never** propagate through ProcessDirect | Lift to a header before the call; restore to property after |
| Caller's MPL and callee's MPL aren't linked in the "Continues to" view | `correlationId` not in the allow-list, or never set in the first place | Always allow-list `correlationId`. Set it at the HTTPS sender's first Content Modifier |
| Two ProcessDirect senders on the same iFlow with the same Address | Deploy error: duplicate endpoint | One Address = one sender. Use distinct versions or operations |

## Script Collection failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Runtime error: "Script not found: roiam_logIncoming.groovy" | Script Collection not deployed, or not referenced from this iFlow | Deploy collection. Add as *References → Script Collection* on the iFlow |
| iFlow does not pick up new behavior after editing a script in the collection | Collection edited but not deployed | Deploy after every edit. Always |
| Collection deployed, iFlow still uses old behavior | Iflow's Script Collection reference pinned to an older version | Update the reference to "latest" or to the new version explicitly, then redeploy iFlow |
| Script step's Browse dialog doesn't show the collection's scripts | Script Collection added as a *Resource* on the iFlow instead of a *Reference* | Remove from Resources. Add via References. Resources gives a private copy, not a reference |
| Two scripts with the same name (one inline, one in collection) | Ambiguous resolution at runtime | Don't duplicate. Remove the inline copy |
| Operations sees behavior change but Script Collection version unchanged | Edited the script without bumping the collection version | Bump on every edit. 1.0.0 → 1.1.0 etc |
| Script in collection imports `com.sap.gateway.ip.core.customdev.util.Message` and fails | v1 API import in a v2-path script | Use v2 import: `com.sap.it.script.v2.api.Message`. Path must be `script/v2/` |
| Script in collection uses `java.lang.Thread.sleep` | SAP CI sandbox blocks java.lang.Thread | Use Groovy's `sleep(ms) { onInterrupt }` closure form |
| Script in collection defines a top-level class | SAP CI restriction — no top-level class declarations alongside `processData` | Inline helpers as closures or methods inside `processData` |

## Versioning failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Caller fails after callee's iFlow version bump | Breaking contract change shipped under the same endpoint version | Version-segment the endpoint. Ship breaking changes at `/v2/`, keep `/v1/` deployed during migration |
| v2 endpoint not picking up traffic after caller migration | Caller's ProcessDirect Address still points at `/v1/` | Update Address. Redeploy caller |
| v1 endpoint quietly removed after migration; one stragger caller breaks | Decommission step skipped the "verify zero traffic" check | Roll back v1 removal; check MPL by sub-step Endpoint for v1 traffic; communicate decommission |

## Properties vs headers — silent failures

These are the worst because there's no error:

1. **Set property `userId` on caller, expect on callee.** Doesn't cross. Callee reads null. Logic proceeds with wrong assumption. → Lift `userId` to header `X-User-Id`, allow-list it, restore to property on callee.

2. **Set header `customerSegment` on caller, allow-list on caller, forget to allow-list on callee.** Caller's MPL shows the header outbound; callee's MPL shows it absent. Caller "sent" it, callee never received it. → Symmetric allow-lists.

3. **Header allow-list contains `correlationid` (lower-case) but the header is `correlationId` (mixed case).** Allow-list is case-sensitive — header dropped silently. → Match exact case.

4. **Script Collection reference uses "latest" but the collection has been deployed to a different tenant.** CTM transport carries the iFlow's reference, but the collection's deploy is per-tenant. → After CTM, deploy the collection on the target tenant too.

## When in doubt: open the MPL

Every ProcessDirect link can be debugged in one place: *Monitor → Message Processing → caller's run*. The ProcessDirect sub-step shows the outbound headers; clicking through to the callee's run shows the inbound headers. The diff between them tells you everything.

Add `roiam_logIncoming.groovy` (from the Script Collection) as the first step on the callee — its `incoming` and `headers-snapshot` (after v1.1 of the collection) attachments are how you confirm what actually crossed the boundary versus what you intended to send.
