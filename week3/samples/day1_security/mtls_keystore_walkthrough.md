# mTLS via Keystore — when the partner demands it

You will not lab this today, but you must recognise the shape of an mTLS configuration so you can spot the misconfigurations on the slide deck. Contrast with the OAuth2 entry — different store, different cockpit area, different rotation rules.

## What lives in the Keystore

| Item | What it is | Source |
|---|---|---|
| **Key Pair** | Private key + the certificate(s) you present to the partner | Generated in *Keystore → Create → Key Pair*, OR imported from `.p12`/`.jks` |
| **CA Certificate** | The partner's CA, used to validate *their* server cert | Imported `.cer`/`.pem` from the partner |
| **Trusted Certificate** | A specific server cert (when you trust the leaf, not the CA) | Imported `.cer`/`.pem` |

The Keystore is at *Monitor → Integrations → Keystore*. **Do not confuse with Security Material** — the latter is for usernames/passwords/OAuth client credentials, not for X.509.

## Generating the Key Pair

Cockpit path: *Keystore → Create → Key Pair*.

| Field | Lab value | Note |
|---|---|---|
| Alias | `roi-<your_initials>-orderhub-mtls` | Project-style alias. References this on the receiver adapter. |
| CN | `integration.acme.com` | **Verify with partner** — CN mismatch is the cryptic "peer not authenticated" error. |
| OU / O / L / ST / C | Per certificate authority guidelines | Partner often dictates. |
| Validity (years) | `2` | Calendar reminder for renewal at year 1.5. |
| Algorithm | `RSA-4096` (or `EC P-256`) | Partner often dictates. |

After creation, *Download* the CSR if you need a public CA to sign your cert, or skip if you're self-signing and the partner trusts your cert directly.

## Importing the partner's CA

*Keystore → Add → Trusted Certificate / CA Certificate*. Upload the `.cer` or `.pem`. Verify the displayed CN and Issuer match what the partner told you.

**Chain order matters.** SAP CI expects **leaf-first**. If `openssl s_client -showcerts` shows the chain in an unexpected order, rebuild the chain file. Tools like `openssl crl2pkcs7 -nocrl -certfile chain.pem | openssl pkcs7 -print_certs` help debug.

## Receiver adapter wiring

| Property | Value |
|---|---|
| Authentication | `Client Certificate` |
| Private Key Alias | `roi-<your_initials>-orderhub-mtls` |
| Address | `https://<partner-mtls-endpoint>` |

There is **no Credential Name** field — mTLS uses the Keystore alias, not a Security Material entry.

## Rotation — the renewal SOP

Different from OAuth2 rotation. Requires a redeploy.

1. ~30 days before expiry: generate a *new* Key Pair under a new alias (`roi-<your_initials>-orderhub-mtls-2027`).
2. Share the new cert / public key with the partner; they import it in their trust store.
3. Test the new cert by pointing a copy of the iFlow at the new alias in a dev tenant.
4. On cutover day, change the production receiver adapter's *Private Key Alias* to the new alias.
5. **Redeploy** the iFlow. (This is the one case where rotation needs a redeploy.)
6. After 30 days of clean traffic, delete the old Key Pair.

## Pitfalls

- **CN mismatch** — partner expects `integration.acme.com`, you generated `acme`. TLS handshake fails with "peer not authenticated".
- **Chain order** — leaf must be first. Wrong order → "no certificate match".
- **Forgetting renewal** — there is no automated rotation. Manual calendar reminder is the only thing standing between you and a 4am outage.
- **Putting OAuth2 client_id+secret in the Keystore** — no error message, adapter just can't find credentials. Different store.

## Why not "just use OAuth2"?

Some partners — banks, government, identity providers — mandate mTLS as the only acceptable auth. It pre-dates OAuth2 in those sectors and the audit/compliance regimes haven't caught up. When a partner says "we require client cert auth", they mean mTLS, and OAuth2 isn't an option.
