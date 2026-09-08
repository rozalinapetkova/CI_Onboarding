# Alert Notification Service — subscription setup

SAP Alert Notification Service (ANS) is the BTP service that turns CI events into actions: email, webhook, Teams, Slack, PagerDuty, ServiceNow, OpenAPI. This file walks through wiring a subscription end-to-end for the Order Hub.

## Prerequisites

- ANS instance entitled to your subaccount. For training, the trainer pre-provisions a cohort-shared instance.
- An Action already created — typically the trainer wires one Email action to a cohort distribution list before the lab.
- An iFlow that emits events under a known category (Day 4.4 wires the explicit emit step; for the lab, ANS's *Test Event* button is enough to prove wiring).

## Walkthrough

### 1. Open the ANS cockpit

*BTP cockpit → Services → Alert Notification → Go to Application*.

### 2. Verify the trainer's Action exists

*Actions* tab → expect at least one Email action named like `cohort-email-<initials>` pointing at the training distribution list.

If absent: ask the trainer. Don't create your own without permission — the cohort shares one ANS instance and stray actions are noisy.

### 3. Create a Subscription

*Subscriptions* tab → *Create*. Fill in:

| Field | Value | Notes |
|---|---|---|
| **Name** | `sub-<initials>-orderhub-dlq` | Project naming — `sub-<your initials>-<purpose>` |
| **Description** | `Order Hub messages landing in DLQ` | One sentence for the next operator |
| **Conditions** | `eventType = roi.orderhub.dlq` | Filter the firehose down to your iFlow's events |
| **Actions** | `cohort-email-<initials>` | The trainer's email action |
| **State** | Enabled | Defaults to enabled; double-check |

### 4. Define the Condition

ANS conditions are key/value filters with predicates. For the Order Hub:

```
eventType = roi.orderhub.dlq
```

For broader subscriptions:

```
eventType matches roi.orderhub.*
severity = ERROR
```

Operators: `=`, `!=`, `matches` (glob), `contains`, `startsWith`, `endsWith`.

### 5. Test the wiring

Two options:

**A. Synthetic test event** — *Subscriptions → your subscription → Send Test Event*. ANS generates a synthetic event matching your conditions and routes it to the action. Email arrives in your inbox within ~30 seconds.

**B. Real event** — wait until Day 4.4 wires the explicit emit step in the iFlow. Then run the Escalated scenario from `provoke_8_statuses.sh` and confirm the email arrives.

For the Day 4.1 lab, **option A is the verification.**

### 6. Disable, don't delete, when done

After the lab, set the subscription to *Disabled* rather than deleting. If you re-take the lab next week, you can re-enable rather than re-create.

## Action types — when to use which

| Action | When |
|---|---|
| **Email** | Cohort training, on-call mailbox, audit copies |
| **Webhook** | Custom incident management tooling, ChatOps bridges |
| **MS Teams** | Operations team channel; common Sev-2 destination |
| **Slack** | Slack-shop tenants; same role as Teams |
| **PagerDuty / ServiceNow** | Real on-call rotations with escalation policies |
| **OpenAPI** | Calls into a tenant-specific API with auth — most flexible |

For the lab: **Email only**. Production-grade wiring is Day 4.4 + Week 4 follow-up.

## Filtering tips

- `eventType` is the most-used filter. Stick to the `roi.<iflow-stem>.<reason>` convention so you can subscribe to one iFlow's events without cross-contamination.
- `severity` is a free string in CI's emitted events; project convention is `INFO` / `WARNING` / `ERROR`. Don't over-engineer with extra levels.
- `resource` filters on the iFlow name. Useful when one iFlow emits multiple event types and you want to subscribe to all of them.

## Anti-patterns

| Anti-pattern | Consequence |
|---|---|
| One mega-subscription for "everything ERROR" | Floods the inbox; trainees miss the alert that matters |
| Per-trainee duplicates of the same subscription | Cohort inbox gets N copies of every event; unsubscribe noise |
| Subscription points at someone else's action | Person leaves project, alerts vanish — bus factor 1 |
| Disabled subscription left for 6 months | Forgotten dependency; nobody knows why it exists |

## Verification checklist

- [ ] Subscription created with name following `sub-<initials>-<purpose>` convention.
- [ ] Condition filters on `eventType = roi.orderhub.dlq` (or your iFlow's category).
- [ ] Action wired (trainer's email or your own webhook).
- [ ] Test event delivered (synthetic).
- [ ] Subscription state = Enabled.
- [ ] Logged in the iFlow's changelog: "Day 4.1 lab — ANS subscription wired".
