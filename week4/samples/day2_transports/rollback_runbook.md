# Rollback runbook — rolling QA back to a previous version

CTM doesn't have a "rollback" button. What you do instead is **roll forward to the previous version** by initiating a new transport carrying the older version. The mechanics are the same as a normal Dev→QA transport; the *source artifact* is different.

## When to roll back

Roll back if QA shows a regression that:

- Affects production-equivalent traffic on QA (a customer-facing scenario broken).
- Cannot be fixed with a config change (Configure dialog, parameter values).
- Will take more than 30 minutes to forward-fix.

Do NOT roll back for:

- A trainee-only test failure (use Dev to debug instead).
- An issue only seen with synthetic-test payloads (probably your test, not the iFlow).
- A Cloud ALM alert that hasn't been corroborated by an MPL Failed run.

When in doubt, ask the trainer.

## What you need before rolling back

| Thing | Where it lives |
|---|---|
| The previous version's tag/number | Your changelog history (look for the last green transport) |
| Dev's iFlow history showing that version is still available | *CI on Dev → iFlow → Versions tab* |
| The rollback changelog template entry, pre-filled | `changelog_entry_template.txt` adapted |
| Trainer awareness | Slack message before initiating |

If Dev doesn't still have the previous version in its Versions tab: STOP. Rollback via CTM is impossible. Escalate to trainer.

## Step-by-step rollback

### Step 1 — Identify the rollback target version

Open the most recent changelog entry that was green-verified. Note the package version and per-iFlow versions.

Example: last green was `roi-orderhub 1.4.3`; current broken is `1.5.0`. Target: roll QA from 1.5.0 back to 1.4.3.

### Step 2 — Confirm Dev still has 1.4.3 in history

*CI on Dev → Design → roi-orderhub → click iFlow → Versions tab.*

You should see `1.7.5`, `1.7.4`, `1.7.3`, ... down through history. If `1.7.4` (or whichever version is part of 1.4.3) is missing, Dev's history was truncated — rollback by CTM is not possible; the trainer must restore from backup.

### Step 3 — Switch Dev's package to the rollback version

On Dev, you have two options:

**Option A (preferred):** *Right-click the iFlow → Activate Version → select 1.7.4.* This makes 1.7.4 the "current" version on Dev without losing 1.7.5 from history.

**Option B:** Edit the iFlow on Dev, *Save as Version*, and bump to a new version (1.7.6) that is functionally identical to 1.7.4. Slower but creates a clean forward-only history.

Most teams use Option A for rollbacks because it preserves the audit trail: "we deliberately reverted to 1.7.4."

### Step 4 — Pre-fill the rollback changelog

Open the template; fill it in. **Important fields specific to rollback:**

| Field | Rollback-specific content |
|---|---|
| Date | NOW, not the original transport date |
| Author | You, not the original transporter |
| Source / target | Same as forward (Dev → QA) — the *direction* is identical |
| Package version | `1.5.0 → 1.4.3` (the broken-current to target) |
| Referencing | The TRR and changelog of the broken forward transport |
| Change summary | The reason for rollback. Cite the symptom + decision. |
| Risk | What re-introducing the older code means. Be explicit. |
| Rollback procedure of THIS rollback | If 1.4.3 is also broken (rare), where do you go? |

See `changelog_examples/2026-05-22_rollback_to_1_4_3.txt` for a complete example.

### Step 5 — Notify cohort

Post in Slack: *"Rolling QA back to roi-orderhub 1.4.3 in 2 min. Current broken state: 1.5.0 causing data-store-size growth on Discarded runs. Forward fix is INGEST-455."*

This is non-negotiable. A rollback that surprises your teammates is its own incident.

### Step 6 — Transport via CTM

Identical to a normal transport (see `dev_to_qa_runbook.md` steps 5–6).

*CI on Dev → Design → roi-orderhub → ... → Transport.* Description should be: `"Rollback to 1.4.3 (from 1.5.0) — see changelog 2026-XX-XX_rollback_to_1_4_3.txt"`.

The cTMS TRR will go through the usual `Queued → Importing → Imported` cycle.

### Step 7 — Configure on QA — **AND BE CAREFUL**

This is the dangerous step.

QA's Configure dialog will show the parameters as they currently exist on QA — which may include parameters added in 1.5.0 that don't exist in 1.4.3. Or vice versa.

| Scenario | What to do |
|---|---|
| 1.5.0 added a new parameter `MaxCacheAgeMinutes`, 1.4.3 doesn't have it | The field disappears from the dialog. No action needed — the old code doesn't read it. |
| 1.5.0 renamed `MaxRetries` to `MaxAttempts`, 1.4.3 uses `MaxRetries` | Set `MaxRetries` back to its 1.4.3 value. The 1.5.0 alias `MaxAttempts` is gone. |
| 1.4.3 needs an OAuth alias that was deleted from QA's Security Material when migrating to 1.5.0 | Recreate it before deploying. Trainer can assist. |

Walk through each parameter as you would in a forward transport. Trust nothing.

### Step 8 — Deploy and smoke test

Deploy each iFlow on QA.

Smoke test:

```bash
KEY="$(uuidgen)"
curl -s -o /tmp/rollback_smoke.txt -w "HTTP %{http_code}\n" \
    -X POST "${QA_RUNTIME_URL}/http/orderhub/orders/${INITIALS}" \
    -H "Authorization: Bearer $(./obtain_qa_token.sh)" \
    -H "Content-Type: application/json" \
    -H "X-Idempotency-Key: ${KEY}" \
    -d '{ "orderId": "C-ROLLBACK-1", "customer": "Rollback Test",
          "totalAmount": 1, "lines": [{"sku":"S-1","quantity":1,"unitPrice":1}] }'
```

Expected: HTTP 202.

**Then re-test the specific scenario that triggered the rollback.** In the example: send a replay (same key as a previous request) and confirm the old behavior — response *without* the cached correlationId — returns. The OLD behavior coming back is your proof the rollback landed.

### Step 9 — Watch metrics for 30 min

The original failure mode probably has a Cloud ALM alert or ANS subscription. Watch it.

| Metric | What you want to see |
|---|---|
| Data Store size | Stops growing (in the example) |
| MPL Discarded run count | Returns to historical baseline |
| ANS subscriptions for idempotency-storm | Stop firing |
| Cloud ALM data-store-size alert | Auto-clears |

If after 30 min the original problem is still happening, the rollback didn't address the root cause — possible the symptom was caused by config, not code, or by a different change that wasn't reverted. Escalate.

### Step 10 — Close out the changelog

Fill in verification checkboxes. Save. Commit.

Update the team's incident tracker / blameless postmortem template with the rollback as a containment action.

## Things that don't roll back via CTM

| Thing | Why | How to handle |
|---|---|---|
| Data Store contents | Runtime state, not config | Either drain manually or accept legacy entries |
| Number Range current values | Stateful counter | Note the value before rollback; manually reset if needed |
| Configured parameter values | Tenant-managed | Step 7 above — manual review |
| Already-processed MPL runs | Historical record | Old runs stay as they were; new runs are under 1.4.3 |
| ANS events already emitted | One-shot notifications | They happened; can't un-happen |

## When CTM rollback is NOT viable

If for any reason CTM rollback won't work — Dev history is truncated, the previous version had a different package shape (renamed scripts, removed iFlows), or the regression is in a value mapping that CTM doesn't track — you have two fallbacks:

1. **Manual edit on QA.** Open the iFlow on QA, edit the broken part directly, redeploy. Document this in the changelog as a manual-edit deviation. Plan to re-sync Dev to QA's state in the next quiet window.
2. **Tenant restore from backup.** Trainer-only. Used in extreme cases.

Neither is preferable to a clean CTM rollback. Both leave Dev and QA out of sync until reconciled.
