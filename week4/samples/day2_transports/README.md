# Day 4.2 samples — Transport Management & Versioning

Companion artifacts for `week4/day2_transports.md`. Each file maps to a section.

## Files

| File | Covers |
|---|---|
| `ctm_destinations_reference.md` | Section 3 — `TransportManagementService` + `TransportManagementService_oauth` on Dev and QA, common destination misconfigurations |
| `transport_scope_decision.md` | Section 4 — iFlow vs Package vs Multi-Package choice and why Package is the project default |
| `externalized_parameters_pattern.md` | Section 7 — what to externalize and what to keep hardcoded; configure-on-target ritual |
| `changelog_entry_template.txt` | Section 8 — fill-in template for `YYYY-MM-DD_dev_to_qa_transport.txt` |
| `changelog_examples/` | Section 8 — three example changelogs covering initial transport, hotfix, rollback |
| `dev_to_qa_runbook.md` | Section 6 — the 10-step end-to-end runbook with verification at each step |
| `rollback_runbook.md` | Section 11 — rolling forward to a previous version via CTM, tenant-config caveats |
| `iflow_version_bump_rules.md` | Section 10 — when to bump major/minor/patch, what NOT to bump for |
| `manifest_mf_reference.md` | Section 9 — what MANIFEST.MF declares, post-CTM mismatch recovery |
| `why_not_full_cicd.md` | Section 5 — the team's reasoning, ammunition for Day 4.5 debate |
| `common_failures_cheatsheet.md` | The five failure cases in the lab plus silent failures |

## How to use

1. Read the module first.
2. Use `dev_to_qa_runbook.md` as your checklist during the hands-on lab.
3. Use `changelog_entry_template.txt` to write your transport changelog before exporting.
4. Keep `common_failures_cheatsheet.md` open while debugging.
