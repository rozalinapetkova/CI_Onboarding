# Security Material entry — OAuth2 Client Credentials

Cockpit path: *Monitor → Integrations → Security Material → Create → OAuth2 Client Credentials*.

## Fields for the outbound (iFlow → downstream API) credential

| Field | Lab value | Notes |
|---|---|---|
| Name | `oauth2_<your_initials>_orderhub_downstream` | This is the **Credential Name** the receiver adapter references. Renaming breaks every iFlow that points at it — there is no compile-time check. |
| Description | `Outbound OAuth2 client for the downstream order-management stub.` | Free text; write it for the on-call engineer at 3am. |
| Client ID | `sb-orderhub-downstream!t12345` | From trainer. Public-ish — fine to commit to a runbook. |
| Client Secret | `(redacted — paste from trainer)` | **Never** commit this anywhere. Lives only here. |
| Token Service URL | `https://<subdomain>.authentication.eu10.hana.ondemand.com/oauth/token` | XSUAA pattern. Different providers use different paths. |
| Client Authentication | `Send as Body Parameter` | Default for SAP XSUAA. Some providers (Auth0, Okta) want `Send as Request Header` — check provider docs. |
| Scope | *(leave blank)* | Or `orderhub.write` if the trainer specifies. Comma-separated for multiple. |
| Resource | *(leave blank)* | Only used by IAS-style providers that require an audience parameter. |
| Custom Headers | *(empty)* | Reserved for providers that want extra headers on the token request. |

## What happens on first message

1. Receiver adapter sees `Authentication = OAuth2 Client Credentials` and `Credential Name = oauth2_<your_initials>_orderhub_downstream`.
2. Runtime looks up the entry in Security Material.
3. POSTs to Token Service URL with `grant_type=client_credentials` + the client_id/secret per the Client Authentication setting.
4. Caches the returned `access_token` per-worker for ~60-120s (provider's `expires_in` minus a safety margin).
5. Attaches `Authorization: Bearer <token>` on the outbound call.

You never see the token in the iFlow. Don't try to.

## Rotation

Operations edits the entry, pastes the new secret, saves. **No iFlow redeploy.** The next token fetch (after the cache expires) uses the new secret.

## The pitfall this entry exists to avoid

Hard-coded secrets in a Content Modifier, Groovy script, or externalised parameter. Those appear in *Monitor → Headers → Trace* and fail CR review.
