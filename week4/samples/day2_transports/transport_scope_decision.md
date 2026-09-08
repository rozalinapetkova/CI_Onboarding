# Transport scope — iFlow vs Package vs Multi-Package

CTM transports *artifacts*. You choose what to bundle into a single transport request. Three options:

| Scope | What goes | When to use |
|---|---|---|
| **Integration Flow** | One iFlow only, current version | Hotfix to a single iFlow with no shared-resource impact |
| **Integration Package** | All iFlows + value mappings + scripts + globals in the package | **Default for `roi-orderhub`** — keeps the bundle internally consistent |
| **Multiple Packages** | Several packages in one transport | Cross-package coordinated release; rare |

## Why Integration Package is the project default

The Order Hub package (`roi-orderhub`) contains:

- `roi-orderhub-producer` iFlow (the HTTPS sender)
- `roi-orderhub-consumer` iFlow (the JMS-to-receiver step)
- `roi-orderhub-translator` iFlow (the canonical-form transformer)
- Shared scripts: `roiam_setCorrelationId.groovy`, `roiam_logBoundary.groovy`, etc.
- Value mapping for SKU translation
- Globals: `orderhub-idempotency-store-name`

These are *interdependent*. If you transport only the Producer iFlow but the Consumer still references an older Translator iFlow signature, QA breaks. Package-scope guarantees the whole set moves together.

## When iFlow-scope is acceptable

Only when the change is *self-contained*:

- Fixing a regex in one Groovy script that no other iFlow imports.
- Adjusting a Content Modifier value that doesn't change message structure.
- Adding a logging boundary that nobody else depends on.

Even then, the package-scope cost is small — CTM is fast — so the team's standing rule is "package by default, iFlow only if you can explain why."

## When Multi-Package scope is appropriate

Rare. Two scenarios:

1. **Cross-system coordinated release.** A new field is being added to the Order Hub *and* the Master Data Sync package consumes it — both must land on QA at the same moment, or the consumer breaks for the window between transports.
2. **Lifting all cohort packages at once after a tenant rebuild.** Trainer scenario; trainees never do this.

If you find yourself reaching for Multi-Package, stop and ask: can the two packages be transported in sequence with a feature flag bridging the gap? Usually yes.

## What CTM does NOT transport

| Not transported | Why | What to do |
|---|---|---|
| **Tenant credentials / OAuth secrets** | Sensitive; each tenant manages its own | Externalize and configure on target |
| **Number Range artifacts' current value** | Stateful; QA starts at its own counter | Document the starting value; trainer sets on target |
| **Data Store contents** | Runtime data, not config | Expected — QA is fresh |
| **Global variable values** | Tenant-specific values | Re-set on QA after transport |
| **Destinations in BTP Cockpit** | Cockpit-level, not CI artifact | Pre-created by trainer |
| **Externalized parameter values** | Per-tenant | Set in QA's Configure dialog after transport |

The iFlow's *definition* transports. The iFlow's *configuration on a tenant* does not. This is the most common source of "it worked on Dev but not QA" confusion.

## The decision in practice

```
Is the change in one iFlow only AND uses no shared scripts/values?
├─ Yes → iFlow scope is OK, but Package scope is safer
└─ No  → Package scope (always)

Does the change require another package to change at the same moment?
├─ Yes → Multi-Package scope (rare; document why)
└─ No  → Package scope
```

## Versioning interaction

- **iFlow scope:** transports only the iFlow version you have selected. The package version on QA is unchanged.
- **Package scope:** transports the whole package; QA's package version becomes Dev's package version.

Bumping the package version on Dev (e.g., 1.4.2 → 1.5.0) signals a coordinated change set. CTM carries that version label across. See `iflow_version_bump_rules.md`.

## What the transport request looks like in cTMS

After clicking *Transport* in CI:

| cTMS field | Value |
|---|---|
| Transport Request | `TRR-0421` (auto-assigned) |
| Description | "roi-orderhub 1.5.0 — adds DLQ alerting" (you write this) |
| Source node | `ci-dev` |
| Target node | `ci-qa-target` |
| Status | `Queued` → `Importing` → `Imported` (or `Failed`) |

The Description field is what your teammates see in the cTMS UI. Write it like a commit message: what changed and why, not "transport from Dev".

## Common scope mistakes

| Mistake | Consequence |
|---|---|
| Transporting Producer iFlow only after a Translator signature change | QA's Consumer can't parse messages from Producer; runtime failures |
| Transporting the package while a teammate's WIP iFlow is in it | Their unfinished work lands on QA |
| Transporting Multi-Package "to save round-trips" when changes are unrelated | Diffs in cTMS become huge; rollback granularity is lost |
| Transporting iFlow scope but the iFlow imports a script that was renamed in the package | QA references missing script; iFlow won't deploy |

## Coordination with teammates

Before transporting at Package scope:

1. *CI → Design → roi-orderhub → click each iFlow → check Status.* Anything marked "Draft" or "Saved as Version X.Y (Draft)" is somebody's WIP.
2. Slack the cohort channel: "Transporting roi-orderhub 1.5.0 to QA in 2 min — speak now."
3. After transport, post the cTMS TRR number for traceability.

The package-scope blast radius makes coordination mandatory, not optional.
