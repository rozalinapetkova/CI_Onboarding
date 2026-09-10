# Cockpit walkthrough — wiring a Script Collection into an iFlow

This is the step-by-step for adding `sc_<initials>_OrderHubHelpers` as a reference on both `roi_<initials>_OrderHub` (producer) and `roi_<initials>_OrderHubConsumer` (consumer), and replacing inline scripts with collection scripts.

## Prerequisites

- Script Collection `sc_<your_initials>_OrderHubHelpers` exists in your *Training* package.
- It contains `roiam_logIncoming.groovy` and `roiam_formatError.groovy` under `script/v2/`.
- It is **deployed** (not just saved). Confirm in *Monitor → Manage Integration Content → Script Collections* — status `Started`.

## Producer iFlow — add logging at the start

1. *Design → Training → roi_<your_initials>_OrderHub → Edit*.
2. *References* (left sidebar) → *Script Collection* → *+ Add*.
3. Select `sc_<your_initials>_OrderHubHelpers` from the dropdown → *OK*.
4. On the canvas, drop a *Script* flow step right after the sender's first Content Modifier (the one that sets `correlationId` and `orderId`).
5. Click the Script step → properties pane.
6. *Script* field → *Browse*. The dialog now shows two sources:
   - "From iFlow" — local scripts at `script/v2/` inside this iFlow.
   - "From Script Collection sc_<your_initials>_OrderHubHelpers" — the collection's scripts.
7. Pick `roiam_logIncoming.groovy` from the collection.
8. Save → bump iFlow version (e.g. 1.2.0 → 1.3.0) → Deploy.

## Consumer iFlow — add logging at the start + use formatter in Exception Subprocess

1. *Design → Training → roi_<your_initials>_OrderHubConsumer → Edit*.
2. *References → Script Collection → + Add → sc_<your_initials>_OrderHubHelpers*.
3. Main flow: drop a *Script* step right after the JMS sender, pointing to `roiam_logIncoming.groovy` from the collection.
4. Exception Subprocess: locate the existing inline error-handling Content Modifier (the one building error JSON manually) and **replace** it with a *Script* step pointing to `roiam_formatError.groovy` from the collection.
   - The order of steps in the subprocess becomes:
     1. *Script* — `roiam_categorizeError.groovy` (from Day 3.2; inline in this iFlow or in the collection if you've promoted it).
     2. *Router* on `${property.errorCategory}` — branches Retry vs Bypass.
     3. *Script* — `roiam_formatError.groovy` (this one) — builds the canonical error JSON.
     4. Either an Error End Event (Retry) or a JMS receiver to DLQ + Message End Event (Bypass).
5. Save → bump iFlow version → Deploy.

## Verifying after deploy

Send a happy-path order through `call_chained_flow.sh`. Then:

| Where to look | What to see |
|---|---|
| *Monitor → Message Processing → producer run → Attachments* | `incoming` attachment with the full inbound JSON |
| *Monitor → Message Processing → consumer run → Attachments* | `incoming` attachment with the canonical XML (different content, same script — that's the reuse) |
| Both runs, *Run Steps* | Script step labeled `roiam_logIncoming.groovy` early in the flow |

Provoke a Bypass-class failure (malformed body that the downstream rejects with 400). Then check:

| Where to look | What to see |
|---|---|
| Consumer's Exception Subprocess run | Script `roiam_categorizeError.groovy` → Router → `roiam_formatError.groovy` → DLQ |
| DLQ message body | Canonical error JSON envelope shape from `roiam_formatError.groovy` |
| MPL attachments | `categorization` + `error-context` attachments |

## Demonstrating the reuse benefit — update without redeploy

1. Edit `roiam_logIncoming.groovy` in the Script Collection — add a new attachment, e.g. headers snapshot:

   ```groovy
   if (messageLog != null) {
       messageLog.addAttachmentAsString("headers-snapshot",
           headers.toString(), "text/plain");
   }
   ```

2. Bump the Script Collection's version (1.0.0 → 1.1.0).
3. Deploy `sc_<your_initials>_OrderHubHelpers`.
4. **Do NOT redeploy either iFlow.**
5. Send a fresh order through `call_chained_flow.sh`.
6. Both `roi_<initials>_OrderHub` and `roi_<initials>_OrderHubConsumer` MPL runs now show the new `headers-snapshot` attachment.

One collection deploy → behavior change visible in both consumer iFlows. **That's the reuse value.**

## When to redeploy the iFlow anyway

A breaking change in the collection's script signature (e.g. now expects a header that the iFlow doesn't set) requires updating the iFlow. Project pattern: for breaking changes, ship a new script name (`roiam_logIncoming_v2.groovy`) and migrate iFlows one at a time, rather than versioning the script in place.

## Common cockpit mistakes

| Wrong | Symptom | Fix |
|---|---|---|
| Added Script Collection via *Resources* tab of the iFlow | iFlow has a private copy; updates to the collection don't propagate | Remove from Resources. Add via *References → Script Collection* |
| Deployed iFlow but not the Script Collection | Runtime error: "script not found" | Always deploy the collection before any iFlow that references it |
| Bumped iFlow version but not the collection version after editing the script | Runtime behavior changes but the collection still says v1.0 — operations confusion | Bump the collection's version on every script edit |
| Picked the *same* script name in both Resources and Script Collection | Ambiguous resolution; runtime picks one, possibly the wrong one | Don't duplicate. Only one source for each script name |
