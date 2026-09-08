# Script step — settings and upload procedure

## Step settings (in the iFlow palette)

- **Type:** Groovy Script (NOT Groovy Script v1; if the icon shows v1, replace it).
- **Script File name:** `roiam_jsonOrderToCanonical.groovy` (or `roiam_csvOrderToCanonical.groovy`).
- **Function:** `processData` (default — leave as-is).

That's the entire UI. There are no other knobs.

## Where the file lives in the iFlow archive

```
src/main/resources/
└── script/
    └── v2/
        ├── roiam_jsonOrderToCanonical.groovy
        └── roiam_csvOrderToCanonical.groovy
```

**Critical: v2 scripts go under `script/v2/`, not `script/`.** Project memory: putting them in `script/` works at runtime but breaks the editor's "Open referenced script" navigation in CPI's UI.

## Upload procedure — the only correct flow

1. Open the iFlow in the Web UI.
2. Click the Script step in the canvas.
3. In the side panel, click the **pencil** next to *Script File* (or *Create* if first time).
4. Either paste the script or click *Browse* to upload from disk.
5. **Save → Save as Version → Deploy.**

## What NOT to do

- **Don't upload via the Resources tab first.** Project memory: doing so creates a stale metadata entry that the Script step then references — but edits made via the Script step dialog don't update the Resources view, and vice versa. You end up debugging a script you're not running.
- **Don't `@Grab`.** Grape is disabled at runtime. The iFlow deploys but the step throws `ClassNotFoundException`.
- **Don't put a top-level `class Foo {}` next to `processData`.** Compiles in IDE, fails at deploy. Use methods or closures inside the script body instead.

## Verifying it works

After deploy:
1. POST to the iFlow endpoint with the appropriate `X-Order-Format` header.
2. Open Monitor → Message Processing → click the run.
3. Confirm the **Steps tree** shows your script step name.
4. Click **Attachments** — `canonical-from-json.xml` (or `-csv.xml`) should be there.
5. In Monitor's custom-header search, confirm `orderId` is filterable (registered via `addCustomHeaderProperty`) — this makes the run findable via MPL custom search later.
