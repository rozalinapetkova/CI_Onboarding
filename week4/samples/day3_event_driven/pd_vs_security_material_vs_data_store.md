# PD vs Security Material vs Data Store — what belongs where

Three CI storage mechanisms. They look superficially similar (key-value, tenant-scoped) but serve fundamentally different purposes. Choosing the wrong one leads to either security incidents or operational pain.

## At a glance

| Concern | Partner Directory | Security Material | Data Store |
|---|---|---|---|
| **Purpose** | Operational routing/partner config | Secrets, credentials, certificates | Application data, in-flight state, dedup |
| **Tenant scope** | Yes | Yes | Yes |
| **Edit during runtime without redeploy** | Yes | Yes (rotation) | N/A — written by iFlow |
| **Accessible from Groovy script** | Yes (`PartnerDirectoryService`) | Yes (via aliases, but rarely needed in script) | Yes (`DataStoreService`) |
| **Encrypted at rest** | No (config, not secrets) | Yes | Yes |
| **Visible in cockpit UI to operators** | Yes — fully editable | Partial — see aliases, not values | Yes — entries listable, content viewable |
| **Size per entry** | KB (small JSON config) | KB (credentials, certs) | Up to MB (payload caching) |
| **Number of entries** | Tens to hundreds | Tens | Hundreds to millions |
| **TTL / expiration** | None | None (rotation policy) | Configurable per entry |
| **Audit log of changes** | Limited | Yes (via cockpit) | Limited |
| **Transported by CTM** | No — set up per tenant manually | No — set up per tenant manually | No — set up per tenant manually |

## What goes in each — concrete

### Partner Directory

**Yes:**
- Per-partner endpoint URLs (`partner-X-target-url`)
- Per-partner certificate aliases (`partner-X-cert-alias`)
- Routing rules (the Order Hub's `routes` JSON)
- Feature flags that ops should be able to toggle live
- Per-partner business rules (timeout per partner, retry count per partner)
- Lookup tables that change weekly without code change

**No:**
- Secrets (use Security Material)
- Large XML/JSON payloads
- Application data (orders, customers)
- Anything that needs strong encryption at rest

### Security Material

**Yes:**
- OAuth client id / secret pairs (`orderhub-qa-oauth`)
- Basic auth usernames + passwords
- AMQP / JMS credentials (`event_mesh_amqp_<your_initials>`)
- Private keys and certificates for mTLS
- API keys with secret components
- Any value where exposure to operators is itself a problem

**No:**
- Routing configuration (use PD)
- Endpoint URLs (use PD or externalized parameter)
- Anything that doesn't grant access if revealed

### Data Store

**Yes:**
- Idempotency dedup entries (`roi_orderhub_event_dedup` keyed on `ce-id`)
- In-flight transaction state (correlation between request and async response)
- Cached idempotency response envelopes (Week 3 pattern)
- Short-term forensics (last 7 days of failed payloads)
- Inter-iFlow communication state when JMS overkill

**No:**
- Routing config (use PD)
- Credentials (use Security Material)
- Permanent business state — Data Store is for *integration* state, not application state; the system of record lives downstream
- Multi-megabyte blobs (Data Store has per-entry size limits and large entries hurt performance)

## The "which one?" decision tree

```
Does the value grant access if exposed (cred, key, secret)?
   |
   YES → Security Material
   |
   NO → Will it change without an iFlow code change?
         |
         YES → Is it config/routing (read-only from iFlow's perspective)?
         |       |
         |       YES → Partner Directory
         |       NO  → Data Store (the iFlow writes it)
         |
         NO → Externalized Parameter on the iFlow itself
```

Four destinations: Security Material, Partner Directory, Data Store, Externalized Parameter. Match the value to the right one and you'll never have to refactor.

## Things commonly mistaken

| Value | Tempted to use | Should use | Why |
|---|---|---|---|
| Downstream OMS endpoint URL | Externalized parameter | PD if it varies per partner; Externalized parameter if same across all partners (just differs Dev/QA/Prod) | Per-partner needs runtime lookup; per-tenant doesn't |
| OAuth alias name (which alias to use) | Hardcoded | Externalized parameter | The alias name changes per tenant (`orderhub-dev-oauth` vs `orderhub-qa-oauth`); the credentials themselves live in Security Material |
| 7-day dedup TTL value | Externalized parameter | Hardcoded in script OR externalized parameter | Either works. If you might tune it per environment, externalize. Most teams hardcode and tune in code. |
| Email distribution list for alerts | Hardcoded in ANS action | PD or Externalized parameter | Changes when staff rotates — keep it editable without iFlow redeploy |
| List of allowed source IPs | Hardcoded | PD if it changes; CI's IP allowlist feature if it's static | PD if ops needs to add a partner quickly without redeploy |
| Schema validation XSD content | iFlow Resources tab | iFlow Resources tab | XSDs are part of the iFlow's contract; they version with the iFlow |
| Inline mapping rules ("map vendor X's `OrderNum` to canonical `orderId`") | PD | Value Mapping artifact OR mapping step | Value mappings are CI's first-class concept for this; PD for *routing* not *transformation* |

## A worked example — the Order Hub

The Order Hub uses all four:

| Value | Storage | Why |
|---|---|---|
| OAuth client id / secret for downstream OMS | Security Material (`orderhub-dev-oauth`) | Secret — must be encrypted, rotated, not visible in code or UI |
| AMQP credentials for Event Mesh | Security Material (`event_mesh_amqp_<your_initials>`) | Secret |
| Per-event-type routing decision | Partner Directory (`ROI_ORDERHUB_ROUTING/default`) | Changes without redeploy; ops-editable; not secret |
| OMS endpoint base URL | Externalized parameter (`OMSEndpointBase`) | Differs Dev/QA/Prod but doesn't change at runtime; configured at deploy time |
| Idempotency dedup entries | Data Store (`roi_orderhub_event_dedup`) | iFlow-written state; per-message; 7-day TTL |
| Cached response envelopes (Week 3) | Data Store (`roi_orderhub_idem_cache`) | iFlow-written state; per-message; short-lived |

Five places to look when something is wrong. The discipline pays off — each value lives in exactly one place, and the place tells you the right tool for changing it.

## Operational consequences

### How a credential rotation works

1. Generate new OAuth client secret on the auth server.
2. Update Security Material alias `orderhub-prod-oauth` with new value.
3. iFlow picks up the new value on its next outbound call.
4. No redeploy, no iFlow change, no transport.
5. Audit trail: Security Material logs who changed the alias when.

### How a routing rule change works

1. Ops decides partner X should route to a new endpoint.
2. Edit PD parameter `ROI_ORDERHUB_ROUTING/default`, update one entry in `routes`.
3. iFlow picks up new value on next message.
4. No redeploy, no iFlow change, no transport.
5. Audit trail: PD change log (limited; complement with a separate ops changelog).

### How a dedup-TTL change works

1. Decide 7 days is too long, want 3 days.
2. Edit iFlow's Data Store Write step to set TTL = 3 days.
3. Save iFlow as a new version, transport through CTM, Configure on QA.
4. Existing dedup entries keep their old TTL (set when written); only new writes get 3-day TTL.

The third case is the most painful (full deployment cycle) because TTL is integrated into the iFlow's logic, not the data. If TTL changes often, externalize it as a parameter; for the Order Hub, it doesn't, so it stays in code.

### How a "new partner" onboarding works

1. Ops creates a new entry in PD `routes` for `partner-newco`.
2. If newco needs different credentials: add Security Material alias `newco-oauth`.
3. (If the iFlow needs to know about newco at all beyond routing: add an externalized parameter or a new PD entry; usually not needed.)
4. No redeploy. New events from newco are processed.

This is the operational payoff of PD: onboarding doesn't touch the iFlow. The iFlow handles "any partner" by design; PD handles "what each partner needs."

## Cross-tenant consistency

None of these is auto-transported by CTM. After a Dev → QA transport:

| Storage | Action needed on QA |
|---|---|
| Security Material | Pre-create QA-specific aliases with QA credentials; iFlow uses different alias names per tenant (set via externalized parameter) |
| Partner Directory | Either pre-create same partner+parameter structure on QA, or accept that Dev and QA have different content (often the case — QA has test partners) |
| Data Store | Pre-create the named stores on QA; entries are intrinsically per-tenant |
| Externalized parameters | Configure-on-target step during deployment |

The Day 4.2 transport runbook calls out all four as pre-flight checks. PD especially is easy to forget because the iFlow appears to deploy fine on QA — the error only surfaces when the first event fires and the script can't find the partner.
