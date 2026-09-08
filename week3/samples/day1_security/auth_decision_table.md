# Auth method — decision matrix

Five scenarios; the right pick is the one you can defend in two sentences.

| # | Scenario | Right pick | Why |
|---|---|---|---|
| 1 | Cloud-to-cloud, modern partner exposes XSUAA | **OAuth2 Client Credentials** | Default for 2026 cloud-to-cloud. Rotation without redeploy. Secret stored in Security Material. |
| 2 | Bank demands client cert auth, regulator-driven | **mTLS** | Bank's compliance regime predates OAuth2. Keystore-managed. Cert renewal needs a redeploy — calendar reminder mandatory. |
| 3 | Legacy CSV partner over corporate VPN, no OAuth support | **Basic Auth** | Reluctantly. User Credentials in Security Material. Description must include an exit plan to OAuth2. |
| 4 | On-premise S/4HANA via Cloud Connector with named-user accountability | **Principal Propagation** | The downstream needs the *original calling user's* identity. Cloud Connector handles the tunnel; Principal Propagation handles the auth. |
| 5 | iFlow receiving traffic from an internal tool over the same subaccount | **User Role** (default `ESBMessaging.send`) | The runtime validates basic-auth credentials against the BTP subaccount user store. No external auth provider involved. |

## Wrong picks that look right

| Wrong pick | What it looks like | Why it's wrong |
|---|---|---|
| **OAuth2 for an on-premise system without Cloud Connector** | "OAuth2 is modern, let's use it everywhere" | There's no public IP for the iFlow to call. You need Cloud Connector first, then Principal Propagation on top. |
| **Basic Auth for production cloud-to-cloud** | "Both sides support it, OAuth setup is annoying" | Credentials sent on every call. Rotation requires redeploy on the *caller* side (every caller has the password). CR review rejects. |
| **mTLS for a low-stakes lab API** | "It's more secure, why not?" | Cert renewal is a manual ops burden. The 4am page when the cert expires has cost more than any incremental security gained. Use OAuth2 for anything that isn't compliance-driven. |
| **Hard-coded secret in a Content Modifier** | "Just for testing, I'll fix it later" | The secret appears in *Monitor → Headers → Trace*. Discovered on day one of an audit. Always Security Material. |
| **OAuth2 details in the Keystore** | "Both feel like 'credentials'" | The adapter can't find the credential. No error message. Always Security Material for OAuth2 client_credentials. |

## The two-sentence defence — examples

> Q: Why OAuth2 client credentials for the Order Hub's downstream call?
> A: It's cloud-to-cloud against a modern API that exposes XSUAA; OAuth2 lets ops rotate the secret without an iFlow redeploy. The token-cache behaviour is well-understood and documented in the runbook.

> Q: Why not Basic auth here, it would be simpler?
> A: Basic auth sends the password on every call and ties rotation to a deploy, which doesn't fit our SOP. The OAuth2 client_credentials setup is a one-time configuration, after which rotation is operations-only.
