# Why not full CI/CD? — the team's reasoning

This is the document that backs Day 4.5's debate. The cohort will be tempted by every blog post claiming "CI/CD is mandatory for any serious integration project." The Order Hub team chose CTM + manual approval instead. Here's why, in a form you can quote.

## The straw-man — what "full CI/CD" would look like

| Stage | Mechanism |
|---|---|
| Trigger | Git push to `main` branch |
| Build | CI pipeline (GitHub Actions / Jenkins) packages the iFlow |
| Deploy to Dev | Pipeline calls CI's deploy API automatically |
| Test on Dev | Automated smoke test suite |
| Deploy to QA | Pipeline auto-promotes if tests pass |
| Test on QA | Automated regression suite |
| Deploy to Prod | Pipeline auto-promotes (or behind a one-click button) |

Sounds great. Many teams successfully run this. The reasons it's a bad fit *for this project* are below.

## Reason 1 — Manual approval at the QA boundary is the value

The cohort's customers (and most enterprise integrations) demand a human checkpoint between Dev and QA. Reasons:

| Driver | What it requires |
|---|---|
| Audit / compliance — who authorized this change to land in QA? | A named human approver |
| Change-management calendar — release freezes, blackout windows | Manual gate to honor the calendar |
| Coordination with downstream business systems' release windows | Manual gate to coordinate |
| Risk assessment per change | Human judgment, not pipeline output |

CTM's "click Transport, watch cTMS, click Configure" rituals encode this checkpoint into the workflow. Replacing them with a pipeline removes the human pause. You can re-add a manual approval *step* in a pipeline (most CI/CD systems support this), but at that point you've reinvented CTM with more moving parts.

## Reason 2 — The iFlow is the artifact, and CI's UI is the IDE

Unlike most code projects:

| Code project | SAP CI iFlow |
|---|---|
| Source files in git, the canonical form | iFlow XML in CI's storage, the canonical form |
| IDE reads source, presents UI | CI's editor IS the IDE; XML is its file format |
| Build = compile + bundle | "Build" = save and version in CI |
| Test = run unit tests in pipeline | Test = simulate in CI, or deploy + curl |

If your canonical form is "what's in CI", then exporting to git, modifying, re-importing, building, and re-deploying is *adding* a build step where none is needed. The export-import cycle has known quirks (whitespace, ordering of XML attributes) that introduce noise diffs.

The team's decision: **CI is the source of truth; git is a backup and changelog store, not a build input.**

(Other teams disagree. Some run the iFlow XML in git and use a build pipeline to push to CI. They report higher friction on the team's Day 4 timeline — your mileage may vary.)

## Reason 3 — Automated tests on Cloud Integration are expensive

A useful smoke test against a deployed iFlow needs:

- A valid OAuth token (token endpoint requires creds; rotation breaks pipelines).
- A reachable runtime URL (only from inside the trusted network for some setups).
- A way to assert MPL status (CI's API returns the status; takes 5–10 seconds per call).
- A way to clean up — DLQ depth, data store entries, etc.

Building this test harness is significant work. The cohort's 4-week timeline doesn't accommodate it.

What the team does instead: a `provoke_8_statuses.sh` script (see `day1_monitoring/`) run manually after big changes. Adequate for cohort-scale risk; would not be adequate for high-volume Prod traffic.

## Reason 4 — Tenant configuration is per-tenant

A CI/CD pipeline that auto-deploys to QA cannot also auto-configure the externalized parameters — those are different per tenant and frequently include secrets that the pipeline shouldn't touch.

Even with a pipeline, you'd need:

1. A separate config repo (per-tenant values).
2. A reconciler that pushes config to CI's Configure dialog.
3. A way to test that config landed correctly without exposing the secrets in pipeline logs.

This is essentially building a homegrown CTM. Why not use CTM?

## Reason 5 — Rollback is harder with a pipeline

A pipeline assumes the desired state is in the source. "Rollback" means revert the source commit and re-deploy.

CTM assumes the desired state is the artifact selected in cTMS. "Rollback" means transport an older artifact.

The CTM model maps more naturally to the question operators actually ask during an incident: *"can we get back to last Tuesday's version?"* You point at a TRR in cTMS and re-import. With a pipeline, you have to find the git commit, revert it, push, and let the pipeline run — adds steps in the wrong moment.

## Reason 6 — Cohort-scale doesn't need it

The Order Hub team transports ~3–5 times per week. Manual CTM costs about 20 minutes per transport. Total: ~100 minutes per week on transports.

A CI/CD pipeline would save maybe 50 minutes per week — *after* spending 2 weeks building it. ROI is negative at this volume.

If transports rose to 10+ per day, the math reverses and a pipeline pays off. That's the trigger to revisit this decision.

## What the team DOES borrow from CI/CD

Not "no automation"; "automation where it pays."

| Borrowed | Where |
|---|---|
| Changelog convention modeled on commit-message style | `changelog/<iflow>/<date>_<note>.txt` |
| Smoke-test script after every transport | `provoke_8_statuses.sh completed` |
| Pre-flight check list | `dev_to_qa_runbook.md` steps 1–4 |
| Rollback runbook with concrete steps | `rollback_runbook.md` |
| Version-bump rules modeled on SemVer | `iflow_version_bump_rules.md` |
| Externalized parameters with per-tenant config sheet | `externalized_parameters_pattern.md` |

The team's stance: take the discipline from CI/CD; skip the toolchain.

## When you SHOULD push back

The trainer's "manual is good enough" reasoning has limits. Push back if any of these apply to your real project:

- Transport frequency > 10 per day per package.
- Geographically distributed team with non-overlapping hours making manual approval slow.
- Regulatory regime requires an immutable build artifact (some financial regulators do; some don't).
- Downstream systems' contracts encode the package version literally and must be tested before each Prod deploy.

At that point, a pipeline starts paying. Until then, CTM + manual + changelog is the cheaper path.

## The debate framing

Day 4.5 will ask you to argue one side. The team's view doesn't mean the other side is wrong; it means the other side has its own context. Be ready to:

- Argue *for* full CI/CD using high-volume Prod, regulated industries, large distributed teams.
- Argue *against* full CI/CD using cohort-scale, ergonomics, CTM's natural fit with CI's model.

The exercise teaches you the tradeoffs. Real architects don't pick a side once and stay there forever — they re-evaluate when team scale or volume changes.
