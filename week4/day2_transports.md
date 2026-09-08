# Day 4.2 — Transport Management & Versioning

> **Goal of the day.** Move the Resilient Order Hub from Dev to QA via Cloud Transport Management — once, deliberately, with a proper changelog entry — and understand why this team does *not* run CTM as Jenkins-style hands-off CI/CD even though it technically could.

## 1. Why transport management exists

You have an iFlow that works on Dev. The QA tenant is a different runtime, a different Camel worker, a different Postgres-backed Data Store, different secrets, a different DNS endpoint. Copy-pasting iFlow XML across the two does not move:

- The tenant-scoped configuration (Security Material, Keystore, Number Ranges, Globals).
- The runtime deployment state.
- The version history that lets you roll back.
- The audit trail that compliance asks for at year-end.

**Cloud Transport Management (CTM)** is the BTP service that handles all of that. It transports content between BTP runtime tenants, records who promoted what when, and gives you a two-step "import" gate so the QA team can refuse a transport that doesn't meet their bar.

The mental model: CTM is **change control between tenants**, not a build pipeline. The artifact is the **iFlow archive (.zip)**; the transport is the **delivery + audit record**.

## 2. The CTM landscape

```
            +---------------+               +---------------+
            |   Dev tenant  |  ---export--> |   CTM service |
            |   (CI source) |               |   (transport  |
            +---------------+               |     nodes)    |
                                            +-------+-------+
                                                    |
                                                    v
                                            +---------------+
                                            |   QA tenant   |
                                            |   (CI target) |
                                            +---------------+
```

Three actors:

- **CI Dev tenant** — where you design and test. Acts as the **source**.
- **CTM service** — orchestrates. Holds the transport request, the artifact, and the routing.
- **CI QA tenant** — where the artifact is imported and re-deployed. Acts as the **target**.

A *transport node* in CTM is a logical endpoint. You'll see (at least) two configured:

- `ci-dev-source`
- `ci-qa-target`

A *transport route* connects them: source → target. There can be multiple targets (Prod after QA, etc.); for the lab there's one.

## 3. Required services and destinations

This is the slide nobody pays attention to until something fails. Pay attention. The trainer pre-creates these — trainees don't edit destinations during the lab — but you must understand which destination does what for the day a transport breaks at 11pm.

On the **Dev tenant** (source):

| Destination | Purpose |
|---|---|
| `TransportManagementService` | Base URL + service key for the cTMS API. Used by the Dev tenant to push the artifact into CTM. |
| `TransportManagementService_oauth` | OAuth2 binding (client credentials) for the above. The runtime uses this to acquire tokens. |
| `CloudIntegration` (optional) | Points at the *target* tenant's Design API. Some CTM workflows call back into this to trigger import. Many cohorts don't need it; trainer's setup tells you whether yours does. |

On the **QA tenant** (target):

| Destination | Purpose |
|---|---|
| `TransportManagementService` | Same base URL as Dev's — the QA tenant *also* talks to CTM, to acknowledge transports and report import status. |
| `TransportManagementService_oauth` | OAuth2 binding for that. |

Common failures come from:

- The OAuth2 destination's *Token Service URL* pointing at the wrong tenant's UAA.
- Service-key rotation missed on one side (rotate on both, or transports break asymmetrically).
- HTTP destination in the cockpit named differently from `TransportManagementService` — CI looks up by exact name. Don't rename.

If the trainer asks you to debug a CTM destination during the lab: open *BTP cockpit → Connectivity → Destinations*, click *Check Connection*, look at the response code. 401 means token problem (OAuth destination). 404 means base URL wrong.

## 4. Deployment modes — what CTM actually transports

A CI iFlow can be deployed in three modes:

| Mode | What CTM transports | Use for |
|---|---|---|
| **Integration Flow** alone | Just one iFlow archive | Quick fixes, point updates |
| **Integration Package** | The package + all iFlows + value mappings + script collections in it | The default — keep packages small and transport whole packages |
| **Multiple Packages** | Several packages stitched into one transport request | Coordinated releases across related iFlows |

For the Order Hub, the project rule is **Integration Package**. The package `roi-orderhub` contains:

- `roi_ResilientOrderHub` (the main iFlow)
- `roi_OrderHubLogger` (the ProcessDirect helper from Week 1, refactored in Week 3)
- `roi-orderhub-helpers` (Script Collection from Week 3)
- `roi-orderhub-valuemap` (currency normalization from Week 2)

Transporting the *package* keeps the artifacts coherent. Transporting just the main iFlow when the value mapping has also changed is a frequent source of "works on Dev, breaks on QA" bugs.

## 5. Why the authors discourage productive CI/CD via CTM

The SAP CI Cookbook and the team's experience converge on the same recommendation: **don't fully automate CTM in production**. CTM *can* be driven by API; it's tempting to wire it to GitHub Actions / Jenkins / cTMS pipelines. The team's reasons not to:

1. **Tenant configuration drift.** Security Material, Keystore entries, Number Ranges, Globals are tenant-scoped. They are *not* in the iFlow archive. An automated pipeline doesn't notice that the QA tenant is missing a credential the iFlow needs.
2. **Side effects of "deploy".** A re-deploy resets JMS consumer connections, drops in-flight retry counters, and can re-trigger SFTP polling. Doing this without a human's eyes on it loses messages.
3. **Audit clarity.** Manual transports correlate 1:1 to a changelog entry. Automated batches stack changes in a way that makes "what changed in last Tuesday's release" hard to answer.
4. **Rollback semantics are weak.** CTM lets you re-import a previous version, but it does not auto-revert tenant config that was changed alongside.
5. **Approval gates are valuable.** Ops should look at the change before it lands. The 30 seconds it takes to import in CTM is the cheapest insurance you can buy.

What this team *does* automate:
- Source-of-truth git repository (this one) for iFlow XML, scripts, changelogs.
- Lint/style checks pre-commit (Groovy script style, changelog presence).
- A `Build` step that produces the iFlow archive when explicitly asked.

What we **do not** automate:
- The actual transport request to CTM.
- The import on the target tenant.
- The deployment after import.

This is opinionated. Be ready to defend it on Day 4.5.

## 6. The transport workflow — how Dev → QA actually goes
   > **Note:** this exact path doesn't exist on our tenant. Not doing it this way for now — needs to be discussed with Todor before this section gets corrected.

End-to-end, the path is:

1. **Make the change** on Dev — edit iFlow, edit script, deploy locally, test.
2. **Write the changelog entry.** Required before exporting. See section 8.
3. **Export from Dev** — *Design → Integration Packages → roi-orderhub → Actions → Transport*. Pick "Cloud Transport Management".
4. **Confirm transport request** — gives a transport request ID, e.g., `TRR-3812`. Visible on the CTM cockpit.
5. **Approve in CTM** — the QA target is gated. Someone with QA approval rights clicks "Import" on the transport node `ci-qa-target`. Trainees won't have approval rights in production — for the lab, trainer grants them temporarily.
6. **Import lands on QA tenant** — the package appears in the QA tenant's *Design → Integration Packages*, status "Configure".
7. **Configure the package** on QA — set tenant-specific externalized parameters (URLs, credentials), point Security Material aliases, set the Data Store name (it's tenant-local).
8. **Deploy** on QA — *Manage Integration Content* → *Add* → select the iFlow → *Deploy*.
9. **Smoke test** on QA — same `curl` you ran on Dev, against the QA endpoint URL.
10. **Update the changelog** with the transport ID and the fact that QA promotion was completed.

The whole thing takes 5-10 minutes when nothing's wrong. When something's wrong, it takes hours — usually because of step 7 (configuration) or because a Security Material was renamed between Dev and QA.

## 7. Externalized configuration — how the same iFlow runs on two tenants

Tenant-specific values must *not* be hardcoded into the iFlow. CI provides **externalized parameters** — placeholders that are bound to actual values at deploy time on each tenant.

Externalize at minimum:

- Receiver URLs (Dev points at `dev-orders.example.com`, QA at `qa-orders.example.com`).
- Security Material aliases (the alias name is the same; the underlying credential differs per tenant).
- JMS queue names if they differ (we keep them identical).
- The Number Range name (Number Range artifacts are tenant-local).

Pattern in the iFlow editor:
- Open the receiver, find the URL field.
- Click *Externalize* (the small variable icon).
- Give the parameter a name like `ReceiverOrdersBaseUrl`.
- On *each tenant*, when you deploy, the *Configure* dialog asks you to set this value.

Trap: forgetting to externalize. Then you push Dev's URL into Prod and watch the wrong system get the order. Code review catches this before transport.

## 8. The changelog convention — *outside* the iFlow folder

This is a hard project rule, repeated from Week 2 Day 2.4:

```
changelog/
└── roi_ResilientOrderHub/
    ├── 2026-06-08_initial_iflow.txt
    ├── 2026-06-09_add_xslt_enrichment.txt
    ├── 2026-06-11_csv_branch_added.txt
    ├── 2026-06-15_oauth_added.txt
    └── 2026-06-22_dev_to_qa_transport.txt
```

Rules:

- **Filename:** `<YYYY-MM-DD>_<short_note>.txt`. Underscores, no spaces.
- **Location:** repo root `changelog/<iFlow stem>/`. **Never** inside the iFlow folder. The iFlow folder is the deployable artifact — internal commentary doesn't ship to the tenant.
- **Content:** plain prose. Same shape as a good Git commit message — what changed, why, any gotchas, the transport ID if applicable.

Example contents for today's lab:

```
2026-06-22_dev_to_qa_transport.txt
---
Promoted roi-orderhub package from Dev to QA via CTM.

Transport request: TRR-3812
Source tenant:    ci-dev-source
Target tenant:    ci-qa-target
Approved by:      <trainer name>

Externalized parameters set on QA:
  ReceiverOrdersBaseUrl  = https://qa-orders.example.com
  OAuth2CredentialAlias  = orderhub_qa_oauth
  DataStoreName          = roi_orderhub_idempotency

Smoke test: POST /http/order/translate with sample-order.json
  -> HTTP 200, MPL Completed, MessageLog attachments visible.

Notes:
  - Currency value mapping needed re-deploy on QA (separate artifact).
  - JMS consumer concurrency left at default; revisit before Prod.
```

CRs without a changelog entry get sent back. No exceptions.

## 9. iFlow XML editing — when, why, and what's safe

Sometimes the editor doesn't do what you need and you have to edit the iFlow's `.iflw` XML directly — a participant declaration is missing, a configuration option isn't surfaced in the UI, an externalized parameter wasn't generated. The team has a memory note (`reference_iflow_xml_guide`) covering this. The Day 4.2 callout: **CTM round-trips can break iFlow XML when there's a tenant-version mismatch**, and you'll need to fix it by hand.

Rules of the road:

1. **Participant declarations live at the top of the `.iflw`.** Don't reorder them. Don't drop them when you copy-paste a sender between iFlows; the canvas references them by ID.
2. **Removing an element** means removing it everywhere — the `<bpmn:flowNode>`, the source/target arrows referencing its ID, and any `<bpmn:messageFlow>` it participates in. The editor does this; manual edits often miss the references and the iFlow fails to load.
3. **`MANIFEST.MF`** declares the iFlow's version, dependencies, and required packages. After CTM transport, check the manifest hasn't been auto-bumped to a version your QA tenant doesn't support. (Tenants advance independently.)
4. **Post-export sync workflow:** export from CI → unzip → diff against repo → patch repo → re-zip *only when explicitly asked* (project rule). Never edit the unzipped artifact in place and re-import.

For today's lab: you should not need to edit XML. But know it's an option, know the rules, know where the memory note lives. When something goes wrong with CTM transport — corrupted artifact, version-mismatch import failure — this is the recovery path.

## 10. Versioning iFlows in CI

Each iFlow has a **version number** stamped on its design artifact (visible top-right in the editor). Bump it when:

- You change behavior that callers might depend on.
- You add or remove an externalized parameter.
- You change a dependency (Script Collection, Value Mapping).

Don't bump it for changelog-only edits or comment changes. The version flows through CTM and helps QA confirm "what version landed".

CI also keeps a **deployment history** per iFlow on each tenant — *Monitor → Manage Integration Content → click iFlow → History*. Useful for "what was the previous version we ran in QA?" — answer there, not in your head.

## 11. Rollback strategy

CTM doesn't have a "rollback" button. Rollback is just "transport the previous version forward". So:

1. Don't delete previous versions on the source tenant — keep at least the last three.
2. When QA finds a regression, identify the last good version (changelog tells you which).
3. Transport that version to QA via CTM. Same workflow as forward — CTM treats it as a new transport request.
4. Update the changelog to record the rollback.

Tenant-config side effects are not rolled back automatically. If a transport set a Security Material alias to a new credential, your rollback iFlow may still need that alias — be explicit in the rollback changelog about what tenant config to reset.

---

## Hands-on lab — Move the Order Hub Dev → QA via CTM

> Time: ~3 hours. Goal: complete one full Dev → QA promotion of the `roi-orderhub` package, with a properly written changelog entry and a smoke test on QA.

### Setup

- Resilient Order Hub deployed on Dev tenant from Day 4.1 (now with monitoring instrumentation).
- CTM destinations on both tenants pre-created by trainer (section 3 above).
- Trainee has temporary "approver" rights on `ci-qa-target` (trainer grants for the lab).
- A clean QA tenant — no pre-existing `roi-orderhub` package.
- The `changelog/roi_ResilientOrderHub/` folder exists at repo root with prior entries from earlier weeks.

### Steps

1. **Pre-flight on Dev.** Confirm the iFlow's externalized parameters are populated:
   - `ReceiverOrdersBaseUrl`
   - `OAuth2CredentialAlias`
   - `DataStoreName`
   If any are still hardcoded, externalize them now. Bump the iFlow version (e.g., `1.0.4` → `1.1.0`) since externalization is a behavior change for callers' tenant config.
2. **Write the changelog entry first.** Create `changelog/roi_ResilientOrderHub/<YYYY-MM-DD>_dev_to_qa_transport.txt`. Use the example in section 8 as a template. Yes, write it before you transport — if you can't articulate what's changing, you shouldn't transport.
3. **Export to CTM.** *Design → Integration Packages → roi-orderhub → Actions → Transport*. Pick "Cloud Transport Management". Confirm the transport request is created. Capture the `TRR-XXXX` ID and write it into the changelog file.
   > **Note:** this exact path doesn't exist on our tenant. Not doing it this way for now — needs to be discussed with Todor before this section gets corrected.
4. **Approve in the CTM cockpit.** Open *BTP Cockpit → Cloud Transport Management*. Find the transport request. Verify it's queued at `ci-qa-target`. Click *Import*.
5. **Verify on the QA tenant.** Open the QA tenant's *Design → Integration Packages*. Confirm the `roi-orderhub` package appeared. Open it — status will be **Configure**.
6. **Configure for QA.** Trainer pre-set tenant-specific values:
   - `ReceiverOrdersBaseUrl` = QA-specific URL.
   - `OAuth2CredentialAlias` = `orderhub_qa_oauth` (Security Material on QA, pre-seeded).
   - `DataStoreName` = `roi_orderhub_idempotency` (creating the Data Store happens automatically on first message).
   Save the configuration.
7. **Deploy on QA.** *Manage Integration Content → Add → select the iFlow → Deploy*. Wait for status **Started**.
8. **Smoke test.**
   ```bash
   curl -u <qa-user>:<qa-pass> -X POST \
        "https://<qa-tenant>.it-cpi.cfapps.eu10.hana.ondemand.com/http/order/translate" \
        -H "X-Order-Format: json" \
        -H "Content-Type: application/json" \
        --data @sample-order.json
   ```
   Verify HTTP 200, response shape matches Dev's, MPL on QA shows Completed.
9. **Close out the changelog.** Append the smoke-test result and the timestamp to the changelog entry. Commit.
10. **Bonus — rollback drill.** Trainer asks one trainee to perform a rollback: transport the *previous* version of the iFlow to QA via CTM. Same workflow, but pick the older version on export. Write a separate changelog entry for the rollback.

### Failure cases to provoke

- **Forget to externalize a URL.** Push Dev's URL to QA, run smoke test → message goes to the *Dev* receiver from QA. *Lesson:* externalize before transport, not after the leak.
- **Skip the changelog entry.** Trainer asks: "what changed?" — you can't say without opening the editor. *Lesson:* changelog first.
- **Missing Security Material on QA.** Smoke test gets `401 Unauthorized` from the OAuth receiver. Open Security Material on QA, see the alias is missing, ask trainer to seed it, retry.
- **Wrong destination name.** Trainer renames `TransportManagementService` to `TransportManagementService_v2` on Dev for 5 minutes; transport fails immediately. *Lesson:* CI looks up by exact name. Standard names are non-negotiable.
- **Re-import without re-configuring.** Externalized parameters reset to defaults on import; deploy fails or runs against wrong URL. *Lesson:* Configure step is required after every import.

---

## Reference card excerpt — Day 4.2

- **CTM transports content between tenants;** it is *not* a CI/CD pipeline. Treat it as change control with a human gate.
- **Required destinations:** `TransportManagementService` and `TransportManagementService_oauth` on **both** Dev and QA tenants. Names are exact — don't rename.
- **Transport scope:** prefer **Integration Package**, not single iFlow. Keeps the iFlow + scripts + value mappings + script collections coherent.
- **Don't auto-CTM in production.** Tenant-config drift, deploy side-effects, audit clarity, weak rollback semantics. Keep the human gate.
- **Externalize:** receiver URLs, Security Material aliases, queue names if they vary, Data Store names. Configure on each tenant after import.
- **Changelog convention:** `changelog/<iFlow stem>/<YYYY-MM-DD>_<note>.txt` at repo root. **Never** inside the iFlow folder. Write it *before* transport.
- **Standard transport workflow:** edit Dev → write changelog → export to CTM → approve at target node → configure on target → deploy on target → smoke test → close out changelog.
- **Rollback** = transport the previous version forward. CTM has no revert button.
- **iFlow XML editing rules** apply when CTM round-trips break artifacts: preserve participant declarations, remove elements with all references, validate `MANIFEST.MF`, sync via export → unzip → diff → patch → re-zip *only on request*.
- **Bump iFlow version** when behavior or externalized parameters change. Don't bump for cosmetic edits.
- **"Don't zip until explicitly asked"** — project rule. Zipping speculatively bloats the repo and produces stale archives.
