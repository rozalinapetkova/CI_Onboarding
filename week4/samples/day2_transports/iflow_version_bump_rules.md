# iFlow version bump rules

Each iFlow carries a SemVer-ish three-number version: `MAJOR.MINOR.PATCH`. CI stores every saved version; CTM transports a specific one. The bump rule decides which number changes.

## The rule

| Change type | Bump |
|---|---|
| Breaking contract change (input/output schema, headers expected, response shape) | **MAJOR** |
| New capability added without breaking existing callers (new endpoint, new optional field, new error category) | **MINOR** |
| Bug fix, log message tweak, externalized-param rename, retry-count tuning | **PATCH** |
| Comment-only edit, formatting, unused-import cleanup | **No bump** (don't transport — irrelevant) |

The bump applies to the *iFlow* version. The *package* version follows similar rules but at the aggregate level (a MINOR iFlow bump within the package usually triggers a MINOR package bump).

## What counts as breaking (MAJOR)

| Change | Breaking? |
|---|---|
| Renamed `orderId` field in the canonical to `order_id` | YES — downstream parsers break |
| Added a new required header `X-Tenant-Id` | YES — old callers don't send it |
| Changed response from `202 Accepted` to `200 OK` | YES — callers checking the code break |
| Removed an externalized parameter that downstream uses | YES |
| Changed the ANS event category from `roi.orderhub.dlq` to `roi.orderhub.dead-letter` | YES — subscribers no longer match |
| Changed retry policy from 3 attempts to 5 | NO — internal, not contract |
| Changed log boundary attachment names | NO — operations-facing, not contract |

The test: would a working caller / downstream system have to change something to continue working? If yes → MAJOR.

## What counts as a new capability (MINOR)

| Change | MINOR? |
|---|---|
| Added a new optional field `shippingNotes` to the canonical | YES (existing callers ignore; new callers can use) |
| Added a new endpoint `/orders/<id>/cancel` | YES |
| Added a new ANS event category `roi.orderhub.cancellation` | YES (existing subscribers unaffected) |
| Added a new boundary attachment `post-translator` | YES (Monitor users see more, but nothing breaks) |
| Switched a Content Modifier from JSONPath to a Groovy script for the same output | NO — internal, not capability |
| Added a new externalized parameter with a sensible default | YES (existing tenants get the default) |

## What counts as PATCH

| Change | PATCH? |
|---|---|
| Fixed `take(80)` truncation bug | YES |
| Tuned retry backoff from 30s to 60s | YES |
| Renamed a Groovy script variable for readability | YES (or no bump if invisible — see below) |
| Changed log message wording | YES |
| Externalized a previously-hardcoded value (with a default matching the hardcode) | YES |

## When NOT to bump

Don't bump for purely cosmetic changes that don't affect runtime:

- Comments in a script.
- Formatting / indentation.
- Unused-import cleanup.
- Renaming a local variable in a Groovy script.

But: if you're going to transport at all, bump. CTM diffing relies on the version label; transporting an unbumped iFlow makes the changelog confusing. So the practical rule is:

- **Don't transport invisible changes.** They cost CTM time and pollute history.
- **If you must transport, bump PATCH** even if the change is small.

## Sequencing: who bumps first?

If three iFlows in the package are all changing in one transport:

1. Decide each iFlow's bump independently per the rules above.
2. The package bump is the highest of the iFlow bumps.
   - If any iFlow goes MAJOR → package MAJOR.
   - Else if any goes MINOR → package MINOR.
   - Else PATCH.

Example:
- Producer: 1.1.0 → 1.2.0 (added new optional header) — MINOR
- Consumer: 1.3.1 → 1.4.0 (added DLQ alerting, but no API change) — MINOR
- Translator: 1.7.4 → 1.7.5 (regex fix) — PATCH

Package: highest is MINOR. Bump `1.4.2 → 1.5.0`.

## Versions in MANIFEST.MF

Each iFlow's MANIFEST.MF carries:

```
Bundle-Version: 1.2.0
```

This is the source of truth. CI updates it when you *Save as Version*. The iFlow tile in the package shows it. CTM uses it.

If you're editing the iFlow XML directly (see `manifest_mf_reference.md`), **keep MANIFEST.MF in sync.** A version label that doesn't match the XML's actual content is the worst kind of bug — confusing diffs, lost rollback targets.

## When NOT to bump MAJOR

There's a project rule on `roi-orderhub`: avoid MAJOR bumps unless coordinated cross-team.

Reason: MAJOR means breaking. Breaking means upstream + downstream all must change in lock-step. The cohort doesn't have the bandwidth for that.

Practical workaround: instead of a MAJOR bump that breaks a contract:

1. Add the new behavior as MINOR (new optional field, new endpoint, new event category).
2. Migrate callers / subscribers over weeks.
3. Once all callers are off the old behavior, do the MAJOR bump that removes it.

This is the "expand / contract" pattern. It costs more time but avoids a coordinated outage.

## Don't bump for these reasons

| Bad bump reason | Why bad |
|---|---|
| "It's been a while since the last release; let's go MAJOR." | Bump is driven by change content, not calendar time. |
| "I think MINOR sounds too small for this work." | Use rules, not feelings. |
| "I need to test that CTM rollback works for MAJOR transitions." | Use a synthetic iFlow, don't pollute the real one. |
| "MAJOR makes the changelog look more important." | Misleads future readers. |

## Reading the version history in CI

*CI → Design → iFlow → Versions tab.*

You see:

| Version | Saved By | Date | Comment |
|---|---|---|---|
| 1.7.5 | abc | 2026-05-08 14:22 | Fix shippingNotes truncation; SUP-2104 |
| 1.7.4 | xyz | 2026-04-30 09:12 | Add log boundary post-translator |
| 1.7.3 | abc | 2026-04-15 16:01 | Tune retry backoff to 60s |

The comment field is *short and searchable*. Treat it like a commit message subject line — one line, present tense, what changed. Don't paste the full changelog entry; that's what the `changelog/` folder is for.
