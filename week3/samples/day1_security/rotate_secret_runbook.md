# Runbook — Rotate the outbound OAuth2 client secret

The five-step SOP from Section 11 of the day module, with the operational annotations.

## When to rotate

- Quarterly per policy.
- Immediately on suspected leak.
- Immediately on departure of a person who had production access to the secret.
- Annually as part of the OAuth provider's compliance audit.

## Prerequisites

- You have access to the OAuth provider's UI (XSUAA, partner system).
- You have the **Tenant Administrator** or **Integration Developer** role on the BTP subaccount.
- The downstream API supports two valid secrets at once for a 24h grace window. (XSUAA does. Some partners don't — those rotations are riskier.)

## Steps

1. **Generate a new secret on the provider side.**
   - Note the new secret in a temporary location (1Password / Vault). Do not paste it into chat.
   - The old secret is still valid at this point.

2. **Open the Security Material entry.**
   - *Monitor → Integrations → Security Material*.
   - Filter on Credential Name `oauth2_<your_initials>_orderhub_downstream`.
   - *Actions → Edit*.

3. **Paste the new secret.**
   - **Do not change the Credential Name.** Renaming the entry breaks every iFlow that references it — there is no compile-time link check.
   - Save.

4. **Verify the rotation took.**
   - Wait ~60-120 seconds for the worker's token cache to expire.
   - Send a test order through the iFlow (see `call_iflow.sh`).
   - In *Monitor → Message Processing*, open the iFlow run.
   - On the HTTP receiver sub-step, confirm HTTP 200 from the downstream.
   - The very first call after rotation may show a slightly higher latency — the worker fetched a fresh token using the new secret.

5. **Revoke the old secret on the provider.**
   - Wait at least 24h before this step, to let in-flight messages with cached old-secret tokens complete naturally.
   - Then disable the old secret in the provider's UI.

## What you do NOT do

- **No iFlow redeploy.**
- **No CTM transport.**
- **No version bump on any iFlow artifact.**

If your rotation procedure ever involves any of those, the iFlow is hard-coding the credential somewhere. Find it, route through Security Material, redeploy once. After that, rotations are operational and zero-touch.

## Caching pitfall — the FAQ

> *"I rotated the secret 30 seconds ago and the iFlow still works with the old one."*

The worker's token cache is still serving the previously-issued token, which was issued under the *old* secret and remains valid until its `expires_in`. This is **healthy** — operationally desirable, even. After the cached token expires (60-120s typically), the worker fetches a new one using the *new* secret. From then on, only the new secret is in play.

If you need an *immediate* cut-over, redeploy the iFlow — that empties the worker cache. But under the rotation SOP, you don't need to.

## mTLS — the one exception

mTLS cert renewal is the **one** credential-rotation case that DOES require a redeploy:

1. Upload new key+chain under a new alias in the Keystore.
2. Change the receiver adapter's Private Key Alias to the new alias.
3. Save → version → deploy the iFlow.
4. Old alias can be deleted after a grace period.

Calendar reminder for 30 days before cert expiry. The renewal is **not automated.**
