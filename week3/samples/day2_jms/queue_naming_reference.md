# Queue naming reference — `roi.<flow>.<purpose>.<initials>`

## Convention

| Segment | Rules | Example |
|---|---|---|
| `roi` | Fixed prefix — identifies queues owned by the ROI integration team (vs. queues created by other teams on the same tenant) | `roi` |
| `<flow>` | The integration flow / business domain. Lower-case, no separators | `orderhub` |
| `<purpose>` | What the queue carries. `outbound`, `dlq`, `retry`, `callback`, `audit` | `outbound`, `dlq` |
| `<initials>` | Trainee initials. **Lab only.** Omitted in production | `ab` |

Full lab examples:

- `roi.orderhub.outbound.ab` — main queue between `roi_ab_OrderHub` producer and `roi_ab_OrderHubConsumer`.
- `roi.orderhub.dlq.ab` — DLQ for the above.

Production examples (no trainee suffix):

- `roi.orderhub.outbound`
- `roi.orderhub.dlq`
- `roi.invoice.callback`

## Rules

1. **All lower-case.** The broker accepts uppercase, but mixed-case names get fat-fingered.
2. **Dots only.** No dashes, no underscores, no slashes. Dots are the team's chosen separator.
3. **One queue per business purpose.** Not one per iFlow, not one per payload type.
4. **DLQ name = source name + `.dlq`** suffix replacement on the `<purpose>` segment. Predictable, scriptable.

## What NOT to name a queue

| Bad name | Why bad |
|---|---|
| `roi.orderhub.json` | Splits by payload type — the canonical Order XML is already format-agnostic by the time it's enqueued |
| `roi.orderhub_outbound` | Underscore breaks the dot-segment convention; cockpit search filters by segment |
| `roi.orderhub.outbound.AB` | Mixed case — search filters and DLQ-name string math fail |
| `orderhub.queue` | No team prefix — clashes with other teams on the tenant |
| `roi.dlq.orderhub` | Purpose before flow — DLQ-name derivation breaks (`<flow>.<purpose>` is fixed order) |

## Plan limits — Standard plan

| Resource | Limit | Lab budget |
|---|---|---|
| Queues per tenant | 30 | 8 trainees × 2 queues = 16 lab queues. Confirm tenant total before Monday |
| Queue storage (total) | 9.3 GB | Per-queue cap not separately set; aggregate across all queues |
| Transactions / consumers / providers (concurrent JMS adapter slots) | 150 | Each Concurrent Processes count on each consumer counts toward this |

The 30-queue limit is what trainees hit first. **Clean up old test queues before the day starts** — *Monitor → Message Queues → select → Delete*. Empty queues are free to delete; non-empty queues need their messages drained first (or accept the data loss for test queues only).

## Lifecycle

- **Created** lazily on first deploy of an adapter that references the queue name. There is no "Create Queue" UI step.
- **Renamed** = not supported. To rename, create a new queue, point adapters at it, redeploy, delete the old. **Update both producer and consumer in the same deploy window** — otherwise messages enqueue to the new name and the consumer still listens on the old.
- **Deleted** via *Monitor → Message Queues*. Refuses to delete a non-empty queue without confirmation.

## CTM and queues

Queue names travel with the iFlow's adapter config when transported. CTM Dev → QA → Prod creates the same queue names on each tenant. The **contents** of the queue do not transport — production queue depth is independent from dev queue depth.

If a queue name contains `<your_initials>`, the lab artifact will create that exact queue on every tenant. **Strip the initials suffix before transporting production-bound artifacts.**
