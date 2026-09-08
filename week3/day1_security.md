# Day 3.1 — Authentication & Secure Store

> **Goal of the day.** Stop hard-coding secrets. By end of day, your refactored Order Hub iFlow rejects unauthenticated calls, the consumer iFlow obtains an OAuth2 token at runtime via Security Material, and you can rotate the client secret without touching the iFlow. You should be able to defend the right auth choice for each of the five common scenarios.

## 1. The five auth methods you will meet on this tenant

In rough order of frequency on a real tenant:

| Method | When to use it | What you store | Storage location |
|---|---|---|---|
| **Basic Auth** | Lab / intranet over TLS / legacy partners that cannot do anything else | username + password | Security Material → *User Credentials* |
| **OAuth 2.0 Client Credentials** | Cloud-to-cloud, machine-to-machine, the default for most receivers in 2026 | client_id + secret + token URL + scope | Security Material → *OAuth2 Client Credentials* |
| **mTLS (Client Certificate)** | High-security comms — banking partners, government endpoints, anything with a hardware token | private key + certificate chain | **Keystore** (not Security Material) |
| **SAML 2.0 / SAML Bearer** | Corporate federation, SuccessFactors, on-premise SAP via Principal Propagation | depends on flow — keystore key + IdP metadata | Keystore + Security Material |
| **JWT** | API Management front-door, B2B token exchange | signing key (sometimes), public key for verification | Keystore |

The single most important property of all of these on Cloud Integration: **the iFlow does not bake credentials into its deployable.** The iFlow holds a *reference name* (`oauth2_orderhub_client`) and the runtime resolves the secret from Security Material at message time. **Rotating a secret is an operations task, not a deploy task.** Memorize this — it's the litmus test for "is my iFlow production-shaped".

## 2. Security Material vs. Keystore — they are different stores

The two confusable artifacts:

| | Security Material | Keystore |
|---|---|---|
| What it stores | Username/password, OAuth2 client_id+secret, OAuth2 access tokens (cached) | X.509 certificates, private keys, public keys |
| Where in cockpit | *Monitor → Integrations → Security Material* | *Monitor → Integrations → Keystore* |
| Used by adapter property | "Credential Name" | "Private Key Alias" / "Authentication" → "Client Certificate" |
| Format on import | manual / API / CSV | `.jks`, `.p12`, `.pem` |
| Rotated by | overwriting the entry | uploading a new entry, then re-pointing the alias |

You'll add an **OAuth2 Client Credentials** entry to Security Material today. Do **not** put it in the Keystore by mistake — there is no error message, just an adapter that won't auth.

## 3. OAuth2 client credentials — the default for receivers in 2026

The grant flow you will use 90% of the time:

```
iFlow ──► Token URL ───► OAuth provider
                            │
                            ▼
                      access_token (JWT)
       ◄──────────────────────
iFlow ──► Resource API + Authorization: Bearer <token>
```

What's stored in Security Material:

- **Client ID** — public-ish identifier of the iFlow's "service account".
- **Client Secret** — the rotatable secret.
- **Token Service URL** — `https://<subdomain>.authentication.eu10.hana.ondemand.com/oauth/token`.
- **Authentication** — *Body Parameter* (default for SAP XSUAA) or *Basic Authorization* (depends on provider).
- **Client Authentication** — *Send as Body Parameter* / *Send as Request Header*.
- **Scope** — optional, comma-separated.

The receiver adapter then references this Security Material entry by **Credential Name**. On every call (or every cache refresh — usually 60-120 seconds), the runtime fetches a token, attaches it as `Authorization: Bearer ...`, and makes the call. **You never see the token in the iFlow.**

### The token cache that catches everyone

Tokens are cached **per-credential-name** at the worker level. If you rotate the secret in Security Material and an old worker is still holding a valid token, calls will succeed *until* that token expires. This is fine — operationally desired, even — but trainees who say "I rotated the secret and nothing changed!" are seeing the cache, not a bug.

## 4. mTLS — when the partner demands it

mTLS is two-way TLS: server authenticates client *and* client authenticates server. The iFlow needs:

- A **private key** in the Keystore. Generate via *Keystore → Create → Key Pair* (CN, validity, algorithm). Or import a pre-generated key+chain.
- The partner's **CA certificate** in the Keystore so we trust their server cert.
- The receiver adapter's *Authentication* set to **Client Certificate** with the right alias.

Pitfalls:

- **CN mismatch.** Partner expects `CN=integration.acme.com` and you generated `CN=acme`. Cert is rejected at TLS handshake — error message is cryptic ("SSLHandshakeException — peer not authenticated"). Always verify CN with the partner before generating.
- **Chain order.** Some partners reject if the leaf comes before intermediates; SAP CI expects leaf-first. If `openssl s_client -showcerts` shows an unexpected order, re-build the chain.
- **Expiry.** Cert renewal is **not automated** on the iFlow side. You will need to upload the new key under a new alias, change the receiver to point at the new alias, and *redeploy* — yes, this is the one credential-rotation case that does need a redeploy. Make a calendar reminder for 30 days before expiry.

## 5. Cloud Connector + Principal Propagation

If your downstream is **on-premise** (S/4HANA on-prem, an ECC system, an HR system behind the corporate firewall), there's no public IP for the iFlow to call. **Cloud Connector** is the SSL tunnel that solves this:

```
Cloud Integration ──► BTP Connectivity Service ──► Cloud Connector (on-prem) ──► Backend
```

Configuration is done in the **BTP cockpit + Cloud Connector admin UI**, not the iFlow. The iFlow just sees a **virtual host** like `myhost:443` that the Cloud Connector maps to the real backend.

**Principal Propagation** is the auth pattern *on top* of Cloud Connector that lets the on-premise system see the *original calling user's identity*, not the iFlow's service account. It works via short-lived X.509 certificates issued by SAP IAS or the Cloud Connector itself. You enable it on the receiver adapter's *Authentication* dropdown → **Principal Propagation**.

Most labs do **not** use Cloud Connector — there's no on-premise system in your training tenant. Recognize the term, know when it's needed, defer the deep configuration to a real project.

## 6. Basic auth — when it's still acceptable

Basic auth is the simplest auth scheme: `Authorization: Basic base64(user:pass)`. It is also the most likely to leak a credential by accident.

Acceptable uses:

- **Lab work and Day-1 demos.** Yes.
- **Intranet partner over corporate TLS** with no other option. Reluctantly.
- **Production cloud-to-cloud.** **No.** Use OAuth2 client credentials instead.

Storage: Security Material → *User Credentials*. Reference by **Credential Name** on the receiver. Rotation: overwrite the entry, no redeploy.

The receiver-adapter pitfall: when *Authentication* is **None**, the adapter sends no auth header at all. People sometimes set the Credential Name and forget the Authentication dropdown — credential is unused, calls fail with 401, debugging is painful. Always check both fields.

## 7. SAML & JWT — the front-door cases

Most often, the iFlow is *receiving* a SAML or JWT-bearing request, not issuing one. The pattern:

- **Sender HTTP adapter → Authentication: Client Certificate** (or *User Role*) and the actual SAML/JWT validation happens **upstream of the iFlow**, in API Management or in the BTP authorization tier.
- The iFlow trusts the upstream — the call only reaches the iFlow if the token was already validated.

When the iFlow is *issuing* a SAML bearer token to call SuccessFactors, the configuration lives in Security Material → *OAuth2 SAML Bearer Assertion* and a Keystore key for signing. Beyond today's scope; you'll see one if you ever do an SF integration.

JWT validation inside an iFlow (uncommon — usually upstream): use a Groovy script with the public key from the Keystore, or an XSLT step with `exf:` extension functions. We won't lab this.

## 8. The User Role for sender authentication

When a sender adapter says **Authentication: User Role**, what it means: "the caller must present basic auth credentials, the user must exist on the BTP subaccount, and the user must be assigned a role collection that includes the role specified in the Role field". The default role is **`ESBMessaging.send`**.

For the lab: your OAuth2 callers won't use User Role — OAuth2 is configured separately. But you'll see User Role used for service users on internal-tool-to-iFlow integrations. Recognize it.

## 9. Sender HTTPS + OAuth2 — the lab's auth setup

To require OAuth2 on a *sender* HTTP adapter, you set **Authentication: Client Certificate** *or* **User Role** at the iFlow level — and the actual OAuth validation is done by the **subaccount's OAuth instance** in front of the iFlow. The conventional pattern in 2026:

1. Caller obtains a token from the BTP token URL with `client_credentials` grant + scope `<xsapppname>.ESBMessaging.send`.
2. Caller calls the iFlow runtime URL with `Authorization: Bearer <token>`.
3. The runtime validates the token *before* the message reaches the sender adapter — you don't write any iFlow code for this.

In the cockpit, this appears as a **Service Instance** of plan `integration-flow` bound to your subaccount, with a **service key** that contains `clientid`, `clientsecret`, and `url`. The trainer creates one per trainee on Sunday.

## 10. Common mistakes and how to spot them

- **Putting OAuth2 details in the Keystore.** No error message; adapter just can't find the credential. Always Security Material for client_credentials.
- **Hard-coding the secret in a Content Modifier or Groovy script.** Discoverable in *Monitor → Headers → Trace*. **Hard fail in CR review.**
- **Forgetting to set Authentication on the receiver dropdown.** Credential Name is set, but Authentication is "None" → no auth header. Always verify both.
- **Renaming a Security Material entry that an iFlow references.** The iFlow stops working at the next message — there is no compile-time link check. Use the *Monitor → Where Used* feature before renaming.
- **Confusing the *iFlow's outbound* OAuth (receiver) with the *iFlow's inbound* OAuth (sender).** Different artifacts, different cockpit areas. Newcomers mix them up — slow down and check sender vs. receiver before configuring.

## 11. Secret rotation as an SOP

Production secret rotation should look like this:

1. Generate a new secret on the OAuth provider (XSUAA, partner system, etc.).
2. *Operations* opens *Monitor → Security Material → <entry> → Edit*.
3. Update the secret. **Do not change the Credential Name.**
4. Save. The next message that requests a fresh token gets the new one.
5. (Optional) On the iFlow's first call after rotation, monitor the *Steps* for an HTTP receiver retry — that's the cached-token expiry kicking in and a fresh token being issued. Healthy behavior.
6. Revoke the old secret on the provider after a 24h grace.

**No iFlow redeploy.** No CTM transport. No version bump. If your rotation procedure involves any of those, the iFlow is hard-coding the credential somewhere — find it.

---

## Hands-on lab — OAuth2-secure the Order Hub receiver

> Time: ~3 hours. Goal: continue evolving Week 2's `roi_<your_initials>_OrderHub` — swap the sender auth to OAuth2, add a receiver call to a downstream API authenticated via OAuth2 client credentials stored in Security Material. Demonstrate secret rotation without redeploy.

### Setup

- Trainer has provisioned each trainee a service instance with **client_id**, **client_secret**, **token URL**, and **scope** for the inbound side (caller → iFlow).
- Trainer has provisioned each trainee a *separate* OAuth2 client (or a shared one) for the outbound side (iFlow → downstream API). Different credentials than the inbound — keep them separate.
- The downstream API is `https://<trainer-stub>/orderhub/accept` for today. (Real API in Day 3.2.)

### Steps

1. **Open `roi_<your_initials>_OrderHub`** from Week 2 in the *Training* package. The sender address from Week 2 is already `/http/orderhub/orders/<your-initials>`. Method: POST.

2. **Configure OAuth2 on the sender (inbound).**
   - Open the sender HTTP adapter.
   - *Authentication*: **Client Certificate** is what the cockpit forces; the **OAuth validation happens upstream** at the subaccount level (see Section 9). Leave the role as `ESBMessaging.send`.
   - Save the iFlow. Deploy.

3. **Obtain a token** from the inbound credential:
   ```bash
   curl -X POST "<token-url>" \
        -u <inbound-client-id>:<inbound-client-secret> \
        -d "grant_type=client_credentials"
   ```
   Save the `access_token` from the response. It's a long JWT string.

4. **Call the iFlow with the token:**
   ```bash
   curl -X POST "<runtime-url>/http/orderhub/orders/<your-initials>" \
        -H "Authorization: Bearer <access_token>" \
        -H "Content-Type: application/json" \
        -d '{ "orderId": "C-3001", "customer": "Acme GmbH", "totalAmount": 1500 }'
   ```
   Confirm 200. Try without the header — confirm 401.

5. **Add an OAuth2 Client Credentials entry to Security Material.**
   - *Monitor → Integrations → Security Material → Create → OAuth2 Client Credentials*.
   - **Name**: `oauth2_<your_initials>_orderhub_downstream` (this is the Credential Name you'll reference later).
   - **Description**: `Outbound OAuth2 client for the downstream order-management stub`.
   - **Client ID**: paste from trainer.
   - **Client Secret**: paste from trainer.
   - **Token Service URL**: from trainer.
   - **Client Authentication**: *Send as Body Parameter*.
   - **Scope**: leave blank or as trainer specifies.
   - Deploy the entry.

6. **Add a Request-Reply step + HTTP receiver** to call the downstream API:
   - Drop a Request-Reply on the canvas, just before End.
   - Drop an HTTP receiver on its outbound line.
   - **Address**: `https://<trainer-stub>/orderhub/accept`.
   - **Method**: POST.
   - **Authentication**: **OAuth2 Client Credentials**.
   - **Credential Name**: `oauth2_<your_initials>_orderhub_downstream`.
   - **Throw Exception on Failure**: keep checked for now.

7. **Save → version → deploy.** Test the end-to-end happy path:
   ```bash
   curl -X POST "<runtime-url>/http/orderhub/orders/<your-initials>" \
        -H "Authorization: Bearer <access_token>" \
        -H "Content-Type: application/json" \
        -d '{ "orderId": "C-3001", "customer": "Acme GmbH" }'
   ```
   Inspect the Monitor — both the sender and the HTTP receiver should appear in *Steps*, and the receiver call should show *200* on its sub-step.

8. **Rotate the downstream secret.**
   - Trainer rotates the client_secret on the OAuth provider for the *outbound* client.
   - You **wait 30 seconds** for the worker token cache to expire.
   - You hit the iFlow again with a fresh inbound token. The receiver call should fail (cached token still works) — wait again, retry. Eventually it fails.
   - You go to *Monitor → Security Material → `oauth2_<your_initials>_orderhub_downstream` → Edit*, paste the new secret, save.
   - Hit the iFlow again. **Should succeed.** No iFlow redeploy.
   - Note in your journal: at no point did you change anything in the iFlow itself.

### Failure cases to provoke

- **Wrong inbound token** — call without `Authorization` or with a garbage token. Expect 401.
- **Token from a different subaccount** — try a token issued by a different XSUAA instance. Expect 401.
- **Wrong Credential Name** in the receiver — set it to `oauth2_does_not_exist_<your_initials>`. Deploy. Call. Watch the iFlow fail with a credential-not-found error. Fix it.
- **Authentication dropdown mismatch** — set Credential Name correctly but Authentication to *None*. Calls succeed *if* the downstream allows anonymous; otherwise fails 401. Lesson: both fields matter.
- **Hard-coded secret in a Content Modifier** — try to put the client_secret in a Content Modifier expression "just to test". Trainer will fail you on the spot. **Do not do this.**

---

## Reference card excerpt — Day 3.1

- **Five auth methods**: Basic, OAuth2 Client Credentials, mTLS, SAML, JWT. OAuth2 client credentials is the 2026 default for receivers.
- **Security Material** holds usernames, passwords, OAuth2 client credentials. **Keystore** holds X.509 keys/certs. They are different stores — don't cross-pollinate.
- **Reference by name, not by value.** Every iFlow uses a *Credential Name*. Secrets live in Security Material; iFlows don't.
- **Secret rotation = operations task.** No redeploy needed except for **mTLS cert renewal** (the one exception).
- **Token cache** at the worker level explains "rotated the secret and nothing changed for 60s". Healthy, not a bug.
- **Cloud Connector** is the SSL tunnel for on-premise targets. **Principal Propagation** is the auth pattern on top of it.
- **`ESBMessaging.send`** is the default role for sender HTTP `User Role` auth.
- Receiver dropdown gotcha: *Credential Name* AND *Authentication* both matter. Setting one without the other is silent failure.
- **Never hard-code a secret.** It will be discovered in trace headers; it will fail CR review; it will be a Week 4 incident.
