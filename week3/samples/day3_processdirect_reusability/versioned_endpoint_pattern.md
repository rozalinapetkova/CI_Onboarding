# Versioned endpoints — `/foo/v1/bar`

ProcessDirect addresses are URI-like strings: `/orderTranslator/translate`. There is **no automatic versioning**. If you change the callee's contract — new required header, different output format, removed field — every caller of the same address breaks at the next message.

The fix is **discipline**, not a feature: every endpoint includes a `/v<N>/` segment, and breaking changes ship as a new version that coexists with the old.

## The address shape

```
/<service>/<version>/<operation>/<scope>
```

| Segment | Example | Notes |
|---|---|---|
| Service | `orderTranslator` | Camel-case, the iFlow's logical name |
| Version | `v1`, `v2` | Major-version only — minor/patch versions of the *iFlow* don't bump the endpoint |
| Operation | `translate`, `healthCheck` | What this entry point does |
| Scope | `<initials>` (lab) or omitted (prod) | Lab only — avoids cohort name clashes |

Lab examples:

- `/orderTranslator/v1/translate/<your_initials>`
- `/orderTranslator/v1/healthCheck/<your_initials>`

Production examples:

- `/orderTranslator/v1/translate`
- `/partnerDirectory/v2/lookup`

## When to bump the version

| Change | Bump? |
|---|---|
| Add a new optional header the callee reads, ignored if absent | No |
| Add a new optional field to the response body, callers can ignore | No |
| Add a new required input header — old callers' messages now fail | **Yes** — breaking |
| Remove a field from the response body | **Yes** — breaking |
| Change a field's type or units (`amount` was decimal, now integer cents) | **Yes** — breaking |
| Fix a bug in the canonical-XML generation | No — bug fix, behavior alignment, not a contract change |
| Performance tuning, refactor the internal Router | No |

Rule: if any caller's current code/contract would stop working, bump the version.

## Rolling out v2 alongside v1

The coexistence period is what versioned endpoints buy you. Workflow:

1. **Add a second ProcessDirect sender** on the callee iFlow at `/orderTranslator/v2/translate/<initials>` (in addition to the existing `/v1/`).
2. Behind it: the new logic. Internally the iFlow may share Router/Mapping with v1, or be entirely separate — that's an implementation choice.
3. Deploy the callee iFlow. v1 and v2 both work.
4. **Migrate callers one at a time.** For each caller, switch its ProcessDirect receiver Address from `/v1/` to `/v2/`. Test. Deploy.
5. When **telemetry shows zero traffic on v1**, decommission v1:
   - Remove the v1 sender adapter from the callee iFlow.
   - Deploy.
   - Confirm no caller breaks.

The decommission step is where teams forget to follow through and end up with five "v1" senders running for legacy callers nobody owns. Set a calendar reminder per v1 deprecation date.

## Telemetry for "is anyone still on v1?"

Each ProcessDirect sender on the callee iFlow generates its own MPL entries when invoked. Filter *Monitor → Message Processing* by:

- iFlow = callee iFlow.
- Sub-step / Endpoint = `/orderTranslator/v1/translate/<initials>`.
- Time window = last 7 days.

Zero results for 7 consecutive days → safe to decommission. Project pattern: announce the decommission, wait another week, then remove.

## What goes wrong without versioned endpoints

Real failure mode the team has hit: changed the canonical-XML output to wrap line items in `<lineItems>` instead of `<orders>`. Five caller iFlows all broke at once on Tuesday morning. Two of them were owned by other teams who didn't see the change. The rollback took 90 minutes; the postmortem said "use versioned endpoints from now on."

## The version segment is not the iFlow's version

Easy confusion:

- **iFlow version** (e.g. 1.5.2) — the artifact's own version, bumped on every deploy. Internal versioning.
- **Endpoint version** (e.g. `/v1/`) — the **contract** version. Bumped only on breaking changes. External versioning.

You can ship iFlow 1.5.2 → 1.5.3 with bug fixes; endpoint stays `/v1/`. You can ship iFlow 1.5.3 → 2.0.0 with the endpoint going from `/v1/` to `/v2/`. They're independent.

## The same pattern outside ProcessDirect

This isn't ProcessDirect-specific. Apply the same versioning to:

- HTTPS sender Address paths: `/http/orderhub/v1/orders`
- SOAP service paths
- AMQP queue names if you ever change the message contract

Wherever a contract crosses an iFlow boundary, the version segment is the cheapest tool to keep migrations boring.
