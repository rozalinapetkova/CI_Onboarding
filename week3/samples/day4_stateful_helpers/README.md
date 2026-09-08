# Day 3.4 samples — Stateful Helpers (Data Store, Number Range, Global Variable)

These samples accompany `week3/day4_stateful_helpers.md`. They cover the artifacts that survive across iFlow runs: keyed payload storage (Data Store), atomic counters (Number Range), and named string slots (Global Variable).

## Files

| File | Purpose | Day-module section |
|---|---|---|
| `data_store_get_config.md` | Field-by-field walkthrough of the *Get* (read) flow step | §2, §3 |
| `data_store_write_config.md` | Field-by-field walkthrough of the *Write* (cache) flow step | §2, §3 |
| `data_store_select_delete_config.md` | Cockpit and flow-step config for *Select* and *Delete* | §2, §8 |
| `number_range_definition.md` | Creating `nr_<initials>_OrderSequence` artifact + flow step | §4, §5 |
| `global_variable_when_to_use.md` | Decision matrix; the one right pattern + four wrong ones | §6 |
| `roiam_requireIdempotencyKey.groovy` | v2 script that rejects calls missing `X-Idempotency-Key` with 400 | Lab §4 |
| `roiam_buildResponseEnvelope.groovy` | v2 script that builds the cached JSON envelope as a property | Lab §5 |
| `idempotency_pattern_diagram.md` | ASCII canvas of the Get → Router → process → Write state model | §10, Lab |
| `call_orderhub_idempotent.sh` | Curl with UUID idempotency key; runs twice to demo cache hit | Lab §7–§8 |
| `provoke_idempotency_failures.sh` | Scripts the five failure cases listed in §11 + Lab "Failure cases" | Lab failure cases |
| `ctm_runtime_data_caveat.md` | Why transports carry definitions but not runtime data; post-transport runbook | §8 |
| `storage_quotas_reference.md` | Tenant quotas + ops-friendly cleanup queries | §9 |
| `common_failures_cheatsheet.md` | Idempotency / Number Range / Global Variable silent failures | §11 |

## How to use

Follow `idempotency_pattern_diagram.md` for the canvas layout. Cross-reference each step's config against the matching `data_store_*.md` / `number_range_definition.md`. Test with `call_orderhub_idempotent.sh` (happy path + cache hit). Break it with `provoke_idempotency_failures.sh`.
