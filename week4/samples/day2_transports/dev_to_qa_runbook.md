# Dev → QA transport runbook (10 steps)

The canonical end-to-end. Print this; check off each step during the lab.

## Pre-flight (do BEFORE clicking Transport)

### Step 1 — Confirm Dev is the source of truth

*CI on Dev → Design → roi-orderhub → click each iFlow.*

| Check | Expected |
|---|---|
| Each iFlow's *Status* is `Saved` (not `Draft`) | All three iFlows |
| Latest version number matches the change you intend to ship | Compare to your local notes |
| No teammate's WIP iFlow is in the package | Confirm in cohort Slack |

If any iFlow is in `Draft`: open it → *Save as Version* → bump per `iflow_version_bump_rules.md`.

### Step 2 — Pre-fill the changelog

Open `changelog/<iflow-stem>/<YYYY-MM-DD>_dev_to_qa_<note>.txt` from the template.

Fill in everything *except* the cTMS TRR number and the verification checkboxes. The TRR comes from step 5; verification from steps 8–10.

Save the file. Save it again. (Half of changelog entries get lost because someone forgot to save before clicking Transport.)

### Step 3 — Verify Dev's CTM destinations

*BTP Cockpit (Dev subaccount) → Connectivity → Destinations → TransportManagementService → Check Connection.*

Repeat for `TransportManagementService_oauth` if it exists separately.

Expected: 200/204. If not, fix per `ctm_destinations_reference.md` table before transporting.

### Step 4 — Verify QA's destinations too

Same check on QA's subaccount. The target tenant's destinations are also used (for the import-acknowledgment hop).

If QA's destinations are broken, the artifact will arrive but the import will hang in `Importing` forever. Better to know now.

## Transport (the actual click)

### Step 5 — Initiate transport from CI

*CI on Dev → Design → roi-orderhub → ... menu (three dots, top-right of the package) → Transport.*

A dialog opens:
- *Scope:* default is Package. Leave unless you have a documented reason.
- *Description:* paste a one-line summary. Mirror your changelog's `Change summary` first line.
- Click *Transport*.

CI returns a *TRR-XXXX* number. **Write this number into your changelog entry now** (the field you left blank in step 2).

### Step 6 — Watch the transport request in cTMS

*BTP Cockpit (Dev) → Open cTMS app → Transport Requests → find your TRR.*

Status progression:
1. `Queued` (a few seconds)
2. `Importing` (10–30 seconds)
3. `Imported` (success) OR `Failed` (read the error)

If `Failed`: the error message points at one of:
- Destination misconfigured → `ctm_destinations_reference.md`
- Artifact has a structural problem (unsaved Draft, missing dependency) → fix on Dev, re-save, re-transport
- cTMS quota hit → trainer-only

## Post-import (on QA tenant)

### Step 7 — Configure each iFlow on QA

This is the step everyone forgets. For each iFlow in the package:

*CI on QA → Operations → Manage Integration Content → click iFlow → Configure.*

Walk through every externalized parameter. Verify the value matches QA, not Dev. See `externalized_parameters_pattern.md` for the rules. Use the `_config.md` tenant-config sheet.

| Trap | Reality |
|---|---|
| "The Configure dialog is empty, so there's nothing to set." | Wrong — the parameters defaulted to Dev's values. They need to be reviewed even if no field is missing. |
| "Same OAuth alias, same URL — must be QA's already." | Always double-check. Aliases sometimes match by coincidence. |
| "I'll deploy first, then configure later." | Wrong — deploy without Configure picks up Dev's values. |

Click *Save* → *Deploy* for each iFlow.

### Step 8 — Smoke test the whole flow

Run a single end-to-end curl against QA:

```bash
export QA_RUNTIME_URL="https://<qa-runtime-host>"
export INITIALS="abc"
KEY="$(uuidgen)"
curl -s -o /tmp/qa_smoke.txt -w "HTTP %{http_code}\n" \
    -X POST "${QA_RUNTIME_URL}/http/orderhub/orders/${INITIALS}" \
    -H "Authorization: Bearer $(./obtain_qa_token.sh)" \
    -H "Content-Type: application/json" \
    -H "X-Idempotency-Key: ${KEY}" \
    -d '{ "orderId": "C-SMOKE-1", "customer": "Smoke Test",
          "totalAmount": 1, "lines": [{"sku":"S-1","quantity":1,"unitPrice":1}] }'
cat /tmp/qa_smoke.txt
```

Expected: HTTP 202.

### Step 9 — Verify in QA's Monitor

*CI on QA → Monitor → Message Processing → Status=Completed → search by `correlationId`.*

| Check | Expected |
|---|---|
| Producer MPL run | Completed, four attachments |
| `pre-receiver` attachment URL | QA backend, NOT Dev backend |
| Consumer MPL run | Completed, processed through JMS |
| `correlationId` searchable in dropdown | Yes |
| `orderId` searchable in dropdown | Yes |
| Receiver responded 200 | Yes |

If `pre-receiver` shows Dev's URL — go back to step 7. You forgot to configure.

### Step 10 — Close out the changelog

Fill in the verification checkboxes in the changelog entry. Save.

Commit the changelog file (if your team uses git).

Post the cTMS TRR in cohort Slack with a one-line "transported 1.5.0 to QA; smoke green."

You're done.

## Rollback decision point

If verification at step 9 fails *and* the failure is QA-only (not a Dev-side bug):

- **Soft failure (config issue)** — fix the Configure value, redeploy. Don't roll back.
- **Hard failure (iFlow broken on QA but Dev is fine)** — roll back per `rollback_runbook.md`.

Don't try to "fix forward" under time pressure. Roll back, then fix on Dev calmly, then re-transport.

## Total time budget

| Step | Time |
|---|---|
| 1–4 (pre-flight) | 5 min |
| 5–6 (transport + cTMS watch) | 1–2 min |
| 7 (Configure on QA, three iFlows) | 5–10 min |
| 8 (smoke test) | 1 min |
| 9 (verify in Monitor) | 3 min |
| 10 (close out) | 2 min |
| **Total** | **15–25 min** for a clean transport |

If you're going over 30 min, something is wrong — stop and ask the trainer rather than press on.
