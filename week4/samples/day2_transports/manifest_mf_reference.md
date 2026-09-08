# MANIFEST.MF — what it declares, how CTM uses it

Every iFlow has a `META-INF/MANIFEST.MF` inside its archive. This is CI's version control metadata.

## What's in it (the relevant lines)

```
Manifest-Version: 1.0
Bundle-Name: roi-orderhub-consumer
Bundle-SymbolicName: roi-orderhub-consumer
Bundle-Version: 1.4.0
Bundle-ManifestVersion: 2
Origin: sap.com:tenant=ci-dev
Tool: SAP Cloud Integration
```

The two fields that matter for transports:

| Field | Meaning |
|---|---|
| `Bundle-SymbolicName` | The unique identifier within a package. CI's lookup is by this name. **Never rename.** |
| `Bundle-Version` | The semver-ish version label. Drives CTM diffs and Versions-tab history. |

## CTM uses these for

1. **Identity** — when QA receives the artifact, CTM looks up the existing iFlow by `Bundle-SymbolicName`. If found → update; if not → create.
2. **Version comparison** — Dev's `Bundle-Version` is compared to QA's. If Dev is older or equal, CTM warns. If Dev is newer, transport proceeds.
3. **Audit trail** — the Versions tab on each tenant lists every `Bundle-Version` ever transported there.

## When you can safely edit MANIFEST.MF

You can edit MANIFEST.MF when you're editing the iFlow XML directly (see `reference_iflow_xml_guide.md` in user memory):

| Edit | Rule |
|---|---|
| Bumping `Bundle-Version` after editing the iFlow's `.iflw` file | YES — required for any non-cosmetic change |
| Adding a comment line (`#`) for human readers | NO — not parsed, but linting warns |
| Renaming `Bundle-SymbolicName` | **NEVER** — breaks CTM identity, all transports |
| Changing `Bundle-Name` | YES — display label only; harmless |
| Adding a custom `X-Our-Team-Identifier` header | YES if your tooling reads it; CI ignores it |

The key rule: keep MANIFEST.MF in sync with the iFlow's actual content. If you fixed a bug in `roiam_setHeaders.groovy` but didn't bump `Bundle-Version`, CTM transports the change but logs it as "no-op" because version didn't move. The change *does* land, but the history is misleading.

## When CTM transports a mismatched MANIFEST.MF

Mismatch scenarios that *can* happen:

1. **`.iflw` XML edited, MANIFEST.MF not bumped.** Transport proceeds but the Versions tab on QA shows "no new version" — confusing.
2. **`Bundle-Version` bumped but no actual content change.** Transport proceeds, QA's Versions tab gets a new entry pointing at identical content. Rare.
3. **`Bundle-SymbolicName` changed.** Transport treats the iFlow as new. QA gets a new iFlow alongside the old one, both deployed. Production traffic continues to use the old one. The new one is orphaned and unreachable until you reconfigure routing. **Catastrophic if not noticed.**

The third case is why the rule is "never rename." There is no good reason to rename `Bundle-SymbolicName` after the first transport; if you really must, do it in coordination with trainer and rename it back on Dev *before* the next transport so it propagates.

## Post-CTM mismatch recovery

You arrive on QA and discover:

| Symptom | Likely MANIFEST.MF cause | Fix |
|---|---|---|
| Versions tab on QA shows version 1.4.0 but the iFlow's logic clearly came from 1.5.0 changes | `Bundle-Version` was not bumped on Dev | Bump on Dev, re-transport |
| Two iFlows with similar names in the package, only one is reachable | `Bundle-SymbolicName` was renamed mid-flight | Restore original name on Dev, re-transport; manually delete the orphan on QA |
| QA's iFlow won't redeploy after import | `Bundle-ManifestVersion` mismatch (e.g., changed from 2 to 1) | Restore to `2` on Dev, re-transport |

## Editing safely

The recommended path:

1. Make iFlow changes in CI's editor — let CI manage MANIFEST.MF for you.
2. Only edit MANIFEST.MF by hand if you're working with an exported zip outside CI (e.g., in version control).
3. After hand-editing, re-import to CI on Dev, save, deploy, verify, *then* transport.

Direct hand-edit + transport without a CI round-trip risks the third catastrophic case above.

## What CTM doesn't ship from MANIFEST.MF

Even though MANIFEST.MF travels with the iFlow, these don't end up on QA:

| Field | Why not |
|---|---|
| `Origin: sap.com:tenant=ci-dev` | QA overwrites with its own origin |
| Timestamps (Created-By, Build-Date) | Tenant-specific |
| Custom `X-Team-*` headers (some) | Depends on whether CI deems them metadata |

So MANIFEST.MF on QA after import is not byte-identical to the file on Dev. That's normal.

## Reading the Versions tab

*CI on QA → Design → iFlow → Versions tab:*

```
Version       Saved By                  Date              Comment
1.4.0         CTM Service Account       2026-05-12 09:13  Transport from ci-dev (TRR-0419)
1.3.1         CTM Service Account       2026-04-30 14:22  Transport from ci-dev (TRR-0402)
1.3.0         CTM Service Account       2026-04-12 16:01  Transport from ci-dev (TRR-0387)
```

Note `Saved By` is always the CTM service account on the *target* tenant — not the human who clicked Transport on the source. The human's identity is in the source-tenant Versions tab and in the cTMS TRR record. Your changelog `Author:` field is what bridges human and machine.

## When MANIFEST.MF is your friend

MANIFEST.MF is the canonical answer to "what version of this iFlow is actually deployed on QA right now?" If the cockpit's Versions tab disagrees with what you remember transporting, open the deployed artifact's `META-INF/MANIFEST.MF` (downloadable via the API or by exporting the iFlow) and read `Bundle-Version`. That's the truth.
