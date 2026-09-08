# Transport failures — symptoms and causes

The five canonical lab failures plus silent ones. Keep this open during the Day 4.2 hands-on.

## CTM destination failures

| Symptom | Likely cause | Fix |
|---|---|---|
| *Transport* button greyed out on Dev | Destination `TransportManagementService` doesn't exist or is named wrong | Trainer to recreate; check exact name |
| Transport click → 401 in cTMS log | OAuth credentials wrong (client ID/secret mismatch) | Update Security Material; Check Connection passes |
| Transport click → 404 in cTMS log | URL field of destination wrong | Compare to cTMS service key's URL |
| TRR stays in `Queued` forever | cTMS service down (rare) or destination URL points to wrong cTMS instance | Trainer; verify cTMS UI is reachable |
| TRR `Imported` succeeds but QA's iFlow doesn't appear | QA tenant's `TransportManagementService` destination broken | Check Connection on QA; recreate if needed |

## Version / scope failures

| Symptom | Likely cause | Fix |
|---|---|---|
| TRR `Failed` with "artifact not saved" | Dev iFlow is in Draft state, not Saved | Save as Version on Dev, re-transport |
| TRR `Failed` with "dependency missing" | iFlow scope chosen but iFlow references a script/value-mapping not in transport | Switch to Package scope; re-transport |
| QA's Versions tab doesn't show new entry after `Imported` | `Bundle-Version` not bumped on Dev | Bump on Dev, re-transport |
| Two iFlows now exist on QA with similar names | `Bundle-SymbolicName` was renamed on Dev | Rename back on Dev, re-transport; delete orphan on QA |
| Package version label on QA disagrees with iFlow versions | Mixed transport (iFlow scope then Package scope) | Re-transport at Package scope to reconcile |

## Configuration-on-target failures

| Symptom | Likely cause | Fix |
|---|---|---|
| QA's iFlow deployed but Receiver hits Dev's backend | Forgot Configure-on-target step (or didn't change the value) | Open Configure dialog, set QA value, redeploy |
| QA's iFlow won't start after deploy: "credential alias not found" | OAuth alias on Dev (`orderhub-dev-oauth`) doesn't exist on QA | Set alias to QA's (`orderhub-qa-oauth`); redeploy |
| QA's iFlow returns 500 on every call | Data Store name on Dev doesn't exist on QA | Set to QA's data store name; redeploy |
| QA's MaxRetries is too aggressive (firing 5 retries when QA backend is slow) | Forgot to set QA's looser retry policy | Update parameter; redeploy |
| New parameter added in 1.5.0 is null on QA after import | Configure dialog wasn't opened (defaulted to null) | Open Configure, set value, redeploy |

## Changelog / process failures

| Symptom | Cause | Fix / future avoidance |
|---|---|---|
| Audit asks "who transported 1.4.3 on 2026-04-30?" — no answer | Changelog entry not filled in / not committed | Discipline; trainer issues a soft retro item |
| Rollback impossible because Dev's history was truncated | Trainer rotated Dev tenant; old versions purged | Document rollback boundaries (typically 90 days back); coordinate before rotations |
| Same change transported twice (duplicate TRR) | Two trainees both initiated transport | Cohort Slack coordination; "speak now" rule |
| Production-equivalent test on QA fails but Dev tested green | Synthetic test on Dev didn't match real QA traffic shape | Add the failing payload to Dev's simulation suite |

## Silent failures (look fine, are broken)

| Scenario | What you see | What's actually wrong | How to detect |
|---|---|---|---|
| QA's iFlow deployed but pointed at Dev backend | Dev's Monitor shows mysterious test runs from QA | Configure step skipped | Audit `pre-receiver` attachment URL on every smoke test |
| Externalized parameter typo: `OAuth2CredentialAlias` value is `orderhub-qa-oath` (missing `u`) | iFlow appears to deploy; first real call gets 401 | Typo in alias name | Test connection at Configure time, not at first runtime call |
| QA's data store was deleted at some point | First idempotency-replay returns 500 instead of the cached envelope | DataStoreName points at a deleted store | Cloud ALM check on data store existence; pre-flight in `dev_to_qa_runbook.md` |
| CTM transports the iFlow but a referenced script's version differs between Dev and QA | iFlow deploys; logic runs; producing slightly different output than Dev | Script was hand-edited on QA at some point; CTM transport didn't overwrite (yes, this can happen if file not in package scope) | Compare `roiam_*.groovy` checksums Dev vs QA; periodic audit |
| Value mapping on QA has different entries than Dev | Some SKUs translate correctly, others don't | Value mapping not in transport scope; QA's was edited manually long ago | Diff value mappings Dev vs QA after each transport |
| ANS subscription on QA points at a deleted Action | Events emit, subscription matches, but no email arrives | Action was deleted; subscription kept a stale reference | Send Test Event after each transport; auto-detects stale Actions |

## What to do when you can't figure it out

The escalation order:

1. **Read the changelog entry** for the most recent transport. Often the answer is "the change is in the description; you forgot Configure on QA."
2. **Run Check Connection** on both tenants' CTM destinations.
3. **Diff Dev vs QA**: open the same iFlow on both, look for differences. The `Bundle-Version` on each is the first thing to compare.
4. **Reproduce on Dev**. If it works on Dev, the problem is QA-specific config. If it fails on Dev too, the change has a real bug.
5. **Ask trainer** before initiating a manual edit on QA. Manual edits on QA without a Dev round-trip are a slippery slope to Dev/QA drift.

## The first five minutes after any transport problem

1. Open the changelog entry you just wrote.
2. Open Monitor on QA, filter Status=Failed since the transport.
3. Open Monitor on Dev, do the same.
4. Compare. Difference between Dev and QA failures isolates the problem.
5. If the entire iFlow won't deploy on QA, the issue is config or dependency — not runtime logic.

The cockpit on the failing tenant is authoritative. Don't rely on memory of what you configured.
