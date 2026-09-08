# Day 4.1 samples — Monitoring & Logging

Companion artifacts for `week4/day1_monitoring.md`. Each file maps to a section of the day module.

## Files

| File | Covers |
|---|---|
| `mpl_status_reference.md` | Section 1 — the 8 MPL statuses, how to provoke each, alerting recommendations, the "Completed ≠ successful" trap |
| `log_levels_reference.md` | Section 2 — None/Error/Info/Debug/Trace tradeoffs and the production rule |
| `roiam_setCorrelationId.groovy` | Section 5 — first-step script that generates or accepts `correlationId`, sets header, registers as MPL property |
| `roiam_logBoundary.groovy` | Section 3 — reusable MessageLog attachment helper with the null-guard pattern |
| `searchable_headers_config.md` | Section 4 — registering MPL custom header properties from script (the only mechanism; no Content Modifier checkbox exists) |
| `messagelog_attachment_pattern.md` | Section 3 — four-boundary attachment pattern for the Order Hub (incoming-canonical, pre-jms, post-jms, pre-receiver) |
| `ans_subscription_setup.md` | Section 7 — wiring an Alert Notification subscription end-to-end |
| `ans_event_categories_reference.md` | Section 7 — `roi.<iflow-stem>.<reason>` naming convention |
| `cloud_alm_vs_ans.md` | Section 8 — decision matrix |
| `simulation_when_to_use.md` | Section 6 — what works and what doesn't in iFlow Simulation mode |
| `provoke_8_statuses.sh` | Section 9 + lab step 5 — subcommand-per-status reproduction script |
| `common_failures_cheatsheet.md` | The three failure cases at the end of the lab, plus silent failures |

## How to use

1. Read the module first.
2. Use the references during the hands-on lab.
3. Run `provoke_8_statuses.sh` once you have the iFlow instrumented per `messagelog_attachment_pattern.md`.
4. Keep `common_failures_cheatsheet.md` open in another tab while wiring ANS.
