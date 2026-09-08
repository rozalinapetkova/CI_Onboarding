# Day 3.3 — ProcessDirect & Script Collection reusability — sample artifacts

Maps to `week3/day3_processdirect_reusability.md`. Lab compounds the Order Hub: ProcessDirect into the Week 2 Order Translator, plus a `sc_<initials>_OrderHubHelpers` Script Collection consumed by both producer and consumer iFlows.

| File | Purpose | Mapped section |
|---|---|---|
| `processdirect_caller_config.md` | Caller (Order Hub) ProcessDirect *receiver* — Address, MEP, Allowed Headers | §2, §3, §4, §5 |
| `processdirect_callee_config.md` | Callee (Order Translator) ProcessDirect *sender* — matching MEP and Allowed Headers | §2, §3, §4 |
| `header_allowlist_reference.md` | Why allow-listing is mandatory; the five lab headers; properties-never-propagate rule | §3 |
| `script_collection_layout.md` | Folder layout of `sc_<initials>_OrderHubHelpers/` and how iFlows reference it | §7, §8 |
| `roiam_logIncoming.groovy` | v2 Groovy: log correlationId/orderId, attach incoming body to MPL | Lab step 5 |
| `roiam_formatError.groovy` | v2 Groovy: build canonical error JSON with category, correlationId, exception class | Lab step 6 |
| `iflow_reference_walkthrough.md` | Cockpit steps to add the Script Collection as a Reference + pick scripts in flow steps | Lab steps 8–9 |
| `versioned_endpoint_pattern.md` | Why `/foo/v1/bar`; rolling out v2 alongside v1; decommission process | §5 |
| `call_chained_flow.sh` | Curl the producer; verify three correlated runs (producer, translator, consumer) | Lab step 3 |
| `reuse_vs_subflow_decision.md` | ProcessDirect vs Subflow vs Script Collection vs Message Mapping — two-sentence defence templates | §1, §6, §8 |
| `common_failures_cheatsheet.md` | Header-missing, MEP mismatch, version pin, collection-deployed-but-no-effect | §11 |

Read `processdirect_caller_config.md` + `processdirect_callee_config.md` first — they anchor the ProcessDirect link. Then `header_allowlist_reference.md` for the one bug every cohort hits. `script_collection_layout.md` + the two `roiam_*.groovy` scripts cover the Script Collection deliverable.
