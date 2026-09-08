# Script Collection — folder layout and how iFlows reference it

A **Script Collection** is a tenant-deployed artifact that contains shared Groovy scripts (and optionally JARs, config files). Multiple iFlows reference the *same* Script Collection by name. When the collection is updated and redeployed, every iFlow that references it picks up the change without an iFlow redeploy.

## Naming

| Artifact | Convention | Example |
|---|---|---|
| Script Collection | `sc_<initials>_<Purpose>` | `sc_ab_OrderHubHelpers` |
| Scripts inside | `roiam_<purpose>.groovy` | `roiam_logIncoming.groovy` |
| Path inside | `script/v2/` (v2 API) | `script/v2/roiam_logIncoming.groovy` |

The `roiam_` prefix matches the project convention for all Groovy scripts in this repo (see CLAUDE.md). The `script/v2/` path matches the iFlow convention for v2 scripts (vs legacy `script/` for v1).

## Folder layout

```
sc_<your_initials>_OrderHubHelpers/                  ← Script Collection artifact root
├── META-INF/
│   └── MANIFEST.MF                                  (tenant + collection metadata)
├── src/main/resources/
│   └── script/
│       └── v2/
│           ├── roiam_logIncoming.groovy
│           └── roiam_formatError.groovy
└── scriptcollection.properties                      (optional, name + version)
```

In this repo, the same scripts live at:

```
scripts/standalone/
├── roiam_logIncoming.groovy
└── roiam_formatError.groovy
```

The repo's `scripts/standalone/` is the source of truth; the cockpit's Script Collection is the deployment target. Edits flow source → cockpit, not the other way around.

## Decision — when to put a script in a Script Collection

| Situation | Where to put it |
|---|---|
| One iFlow uses it, tightly coupled to that iFlow's contract | Inline at `script/v2/` inside the iFlow → repo `scripts/collections/<iflow>/` |
| Two or more iFlows use it, same contract | Script Collection → repo `scripts/standalone/` |
| Two iFlows use it with subtly different contracts | Two separate scripts, each inline. Don't force-share |
| One iFlow today, two tomorrow | Inline today. Promote when the second consumer arrives. **Don't pre-emptively share.** |

The "don't pre-emptively share" rule comes from project memory: speculative shared scripts grow speculative parameters that no caller actually uses. Wait for real second consumers before extracting.

## Adding a Script Collection on the cockpit

1. *Design → Training package → Add → Script Collection*.
2. Name: `sc_<your_initials>_OrderHubHelpers`.
3. Description: `Shared logging and error-formatting helpers for the Order Hub iFlows.`
4. Inside the artifact: *Resources → Add → Script* — create each `roiam_*.groovy` via this dialog, **not** by uploading a file through a Resources tab on an iFlow. (Project memory: scripts upload via the Script step / Script Collection script dialog.)
5. Path inside: `script/v2/<filename>.groovy`.
6. Save → version (1.0.0) → Deploy.

## Referencing a Script Collection from an iFlow

1. Open the iFlow.
2. *References → Add → Script Collection → sc_<your_initials>_OrderHubHelpers*.
3. The iFlow now has access to the collection's scripts at runtime.
4. Drop a *Script* flow step.
5. In the Script step's properties, *Browse* → choose `roiam_logIncoming.groovy` from the now-available collection.
6. Save → version → Deploy.

## Updating a script without redeploying iFlows

This is the headline reuse benefit:

1. Edit `roiam_logIncoming.groovy` in the Script Collection.
2. **Bump the collection's version** — e.g. 1.0.0 → 1.1.0. Operations needs to know.
3. Deploy the Script Collection.
4. **Do NOT redeploy** `roi_<initials>_OrderHub` or `roi_<initials>_OrderHubConsumer`.
5. Send a new message — both iFlows pick up the new script behavior on the next run.

The iFlow's Script Collection reference uses "latest version" semantics by default. Pinning to a specific version is possible but rare; use only when a breaking change in the collection requires staged rollout.

## What goes in a Script Collection — and what doesn't

| Belongs | Doesn't belong |
|---|---|
| `roiam_logIncoming.groovy` — generic logger, two consumers | iFlow-specific transformation logic for a single iFlow |
| `roiam_formatError.groovy` — canonical error envelope used by every error subprocess | One-off field rename for a single mapping |
| Project-wide helper JAR (rare) | Vendor-specific JSON parser used in one place |
| `roiam_validateCanonicalOrder.groovy` — schema validation shared by translator + downstream | "Just for testing" scripts |

## Common configuration mistakes

| Wrong | Symptom | Fix |
|---|---|---|
| Script Collection edited but not redeployed | iFlows still see old behavior | Deploy after every edit. Always |
| Version not bumped | Operations sees the same version number with new behavior — can't tell what shipped | Bump even for trivial changes |
| Script path is `script/` not `script/v2/` | iFlow can find the script but it uses v1 API conventions | Always `script/v2/` for `com.sap.it.script.v2.api.Message` imports |
| Script Collection added via *Resources* tab on iFlow | The iFlow gets a private copy, not a reference. Updates to the collection don't propagate | Add via *References → Script Collection*. Never Resources |
| Same script name in collection and inline iFlow | Ambiguous resolution at runtime | Don't duplicate names. Either-or |
