# SFTP sender — baseline reference (not used in the lab)

Day 1.4 introduces SFTP but the Customer Echo Service doesn't use it. Keep this card for the Week 2 batch lab.

## Read lock options — pick one

| Mode | When to use | Risk if wrong |
|---|---|---|
| **None** | Partner pushes complete files atomically (rare). | Polling can read a half-written file. |
| **Content Change** | Partner writes incrementally with no done-file. Sweep waits for two consecutive polls with the same size. | Slows the pipeline by one polling interval. |
| **Done File Expected** | Partner writes `orders.csv` then `orders.csv.done`. Sweep waits for the marker. | If the partner forgets the marker once, the file sits forever. Alert on idle SFTP folders. |
| **Rename** | Sweep renames the file to `*.processing` before reading. | Two competing consumers will fight. Single-consumer pattern only. |

## Post-processing

- **Delete** — default. Don't archive on the same SFTP server unless you control retention.
- **Move to subdirectory** — useful for partner-side audit. Set `archive/yyyy/MM/dd` and prune externally.
- **Rename with timestamp** — same idea, lighter.

## Idempotent repository

Always on. Tenant-local. Backed by the same store as Data Store. Prevents reading the same filename twice across worker restarts.

> Pitfall: if a partner *re-uploads the same filename* after you processed it, the idempotent repository will skip it silently. Two fixes:
> 1. Configure expiry on the repository (default 90 days).
> 2. Require timestamps in filenames in the partner contract.

## Polling interval

Default is 60s. Lower than 30s causes load on the partner SFTP server and rarely improves business latency. If you need near-real-time, switch the partner to push (HTTPS / AS2) — don't poll harder.
