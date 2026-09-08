# Auth misconfigurations — symptoms and causes

The symptom is what you see in the cockpit / curl output. The cause is what's actually wrong.

## Inbound (sender) failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `HTTP 401 Unauthorized`, no entry in *Monitor → Message Processing* | Token rejected before the iFlow ran — wrong signing key (different subaccount), expired token, or missing scope | Re-fetch token from the correct token URL with the right client_id; confirm scope `<xsapppname>.ESBMessaging.send` |
| `HTTP 403 Forbidden` | Token validated but the role mapping does not include `ESBMessaging.send` for this caller's role collection | Add the role collection to the caller's service instance or user |
| `HTTP 401` after rotation 30 seconds ago | The runtime's introspection cache still holds the old token's validity | Wait the cache TTL or send a fresh token (caller-side) |
| iFlow run shows `Authentication: User Role` succeeded but `User` header is empty | Token has machine identity (`client_credentials`), not user identity | This is expected for service-to-service calls. Use Principal Propagation if you need the original user |

## Outbound (receiver) failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Receiver sub-step shows `Credential not found: oauth2_xxx_orderhub_downstream` at deploy time | Typo in Credential Name, or Security Material entry was created but never **deployed** | Spell-check; confirm the Security Material entry shows "Deployed" status |
| Receiver sub-step shows HTTP 401 from the downstream | client_id/secret wrong in Security Material, or scope mismatch with what the downstream API requires | Verify by running curl against the token URL with the same creds; check the downstream's expected scope |
| HTTP 200 from downstream but `Authorization` header was never sent | The receiver's `Authentication` field is `None` while `Credential Name` is set — silent failure | Set `Authentication = OAuth2 Client Credentials` |
| All calls succeed for 60-120s after rotation, then start failing | Worker token cache holding the (still-valid) old token; downstream invalidated it server-side | Wait — token cache will expire and refresh against new credentials. No iFlow action required |
| Random intermittent 401s under load | Worker pool re-creating workers; each new worker re-fetches a token. If the token URL itself is slow or rate-limited, some workers fail | Investigate token URL latency; increase token cache TTL if provider supports it |

## mTLS failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `SSLHandshakeException: peer not authenticated` | CN of our cert doesn't match what the partner expects | Regenerate Key Pair with the partner-specified CN |
| `unable to find valid certification path to requested target` | Partner's CA is not in our Keystore | Import the partner's CA as a Trusted Certificate |
| Handshake works for a while, then suddenly all calls fail | Cert expired | Renew (see mTLS runbook); this is the case that does need a redeploy |
| Different partner endpoint works fine, this one fails | Chain order mismatch — partner expects leaf-first, we sent intermediates-first | Rebuild the chain file leaf-first |

## The "looks fine but isn't" failures

These are the ones that bite hardest because there's no error message:

1. **OAuth2 credentials uploaded to the Keystore instead of Security Material.** No error. Adapter logs nothing. The Credential Name field on the receiver simply won't find a match → call fails with "credential not found" only at runtime, not at deploy.

2. **Renamed Security Material entry while iFlows reference the old name.** The iFlow's deployed copy still says `oauth2_old_name`; the entry now says `oauth2_new_name`. Next message → "credential not found". *Monitor → Where Used* before renaming.

3. **Hard-coded secret in a Content Modifier expression.** Works fine. Until *Monitor → Headers → Trace* on a Failed message shows the secret to the on-call engineer, who escalates. CR review will catch this if you ever PR it, but the iFlow editor lets you save it.

4. **Token cache "doesn't reflect" the rotation.** Not a bug — token cache. Wait ~60-120s. If you can't wait, redeploy (empties the cache).
