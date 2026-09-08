# CTM destinations — required on both tenants

CTM works because of HTTP destinations configured in the BTP cockpit. CI looks them up **by exact name**. Rename one and CTM fails immediately.

## Required destinations

Both tenants (Dev and QA) need the same two destinations. Same names; different *values* per tenant.

### `TransportManagementService` — HTTP

| Field | Dev value | QA value |
|---|---|---|
| **Name** | `TransportManagementService` | `TransportManagementService` |
| **Type** | HTTP | HTTP |
| **URL** | cTMS API base URL (single URL for the cohort's CTM instance) | Same as Dev — both tenants talk to the same CTM service |
| **Proxy Type** | Internet | Internet |
| **Authentication** | `OAuth2ClientCredentials` (references the `_oauth` destination below) | Same |
| **Token Service URL Type** | Dedicated | Dedicated |
| **Token Service URL** | The cTMS UAA URL (provided in the service key) | Same as Dev |
| **Client ID** | From the cTMS service key on Dev | From the cTMS service key on QA (different key, different ID) |
| **Client Secret** | From the cTMS service key on Dev | From QA's service key |

### `TransportManagementService_oauth` — OAuth2 binding

In some CI versions the OAuth fields above are on a *second* destination named `TransportManagementService_oauth`. Check both naming conventions on your tenant; trainer will confirm which applies. Functionally identical.

## How CI uses these

1. You click *Transport* on the package → CI's design service uses `TransportManagementService` to authenticate against cTMS via the OAuth client credentials, then POSTs the artifact.
2. cTMS stores the artifact, creates a transport request `TRR-XXXX`, and queues it on the target node `ci-qa-target`.
3. The QA tenant's `TransportManagementService` destination is what *its* design service uses to acknowledge the import and report status back to cTMS.

If only Dev's destination works, you can transport *to* CTM but QA can't acknowledge. The artifact lands but nobody knows.

## Verifying a destination works

*BTP Cockpit → Connectivity → Destinations → click destination → Check Connection*.

| Response | Meaning | Fix |
|---|---|---|
| 200 / 204 | Destination + auth both work | Continue |
| 401 / 403 | Token problem | OAuth destination misconfigured: wrong client ID/secret, wrong Token URL |
| 404 | URL wrong (base path) | Compare URL to the cTMS service key |
| 500 from `xs2.security.com` | OAuth UAA itself rejecting | Service key may be stale; rotate |
| Timeout | Network reachability problem | Trainer or BTP support needed |

The Check Connection button is your first move when CTM transports fail.

## Common destination misconfigurations

| Misconfiguration | Symptom |
|---|---|
| Renamed destination (e.g., `TransportManagementService_v2`) | CI doesn't find it; transport button fails immediately |
| URL points at wrong cTMS instance (cohort uses one shared instance) | Transport succeeds technically but lands in another cohort's nodes |
| OAuth Token Service URL points at Dev UAA but client credentials are QA's | 401 with confusing error in the CTM log |
| Client secret rotated on cTMS side but not updated in destination | 401 starting at the rotation timestamp |
| Both tenants share the same client ID (mis-copy) | Transport works one direction but QA acknowledgments fail |

## What trainees should NOT do

- **Don't rename a destination.** Even if a name looks "wrong" or "ugly", CI's lookup is by exact name. Renaming breaks every iFlow that uses CTM.
- **Don't delete a destination "to test".** Recreating it requires the service key, which the trainer manages.
- **Don't share client secrets across tenants.** Each tenant gets its own cTMS service key.
- **Don't paste service-key JSON into a Slack channel** to "ask for help". Service keys are secrets. Use a private DM or the trainer's password manager.

## Service-key rotation policy

Trainer rotates cTMS service keys every quarter. After rotation:

1. Update both Dev and QA destinations with new client IDs/secrets.
2. Check Connection on both.
3. Run a synthetic transport (no-op package) to confirm.
4. Record the rotation date in `changelog/_infra/` (the project's infra changelog folder).

If you arrive on Monday and CTM is broken, suspect a missed rotation step first.

## Where the destinations come from

- The cTMS service is provisioned per subaccount. Service key generated once.
- Trainer documents the destination names and values in the cohort's setup runbook (`reference_training_setup.md` in trainer's repo).
- Trainee tenants get destinations pre-created at cohort setup; you should never need to create them during the lab.

If your tenant is missing one, escalate to trainer — don't create it yourself.
