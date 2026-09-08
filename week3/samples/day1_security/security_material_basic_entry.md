# Security Material entry — User Credentials (Basic Auth)

Cockpit path: *Monitor → Integrations → Security Material → Create → User Credentials*.

For when a partner cannot do OAuth2 and you've decided Basic over the corporate TLS link is acceptable. Lab/intranet only — never for production cloud-to-cloud.

## Fields

| Field | Lab value | Notes |
|---|---|---|
| Name | `basic_<your_initials>_legacypartner` | The Credential Name. |
| Description | `Basic auth for the legacy CSV partner FTP-bridge. Replace with OAuth2 by 2026-12.` | Always include the *exit plan* for Basic auth in the description. |
| User | `roi-orderhub-svc` | The partner-side service user, not your tenant user. |
| Password | `(redacted)` | Rotated by overwriting this field. |

## Receiver-adapter wiring

On the HTTP receiver:

- `Authentication` = `Basic`
- `Credential Name` = `basic_<your_initials>_legacypartner`

The receiver-adapter pitfall (Section 10 in the module): setting `Credential Name` but leaving `Authentication = None` sends no header. Always verify both.

## When this is acceptable

- Lab demos.
- Intranet partner over corporate TLS with no other option.
- **NOT** cloud-to-cloud production. Use OAuth2 client credentials instead.

## Compared to the OAuth2 entry

| Aspect | OAuth2 Client Credentials | User Credentials (Basic) |
|---|---|---|
| What's stored | client_id + secret + token URL + scope | username + password |
| Token issuance | Runtime fetches a token from the token URL | No tokens — credentials sent on every call |
| Rotation impact | Token cache expires → next call uses new secret | Next call uses new password (no cache) |
| Secret exposure on wire | Bearer token only (short-lived) | `Authorization: Basic base64(user:pass)` on every call |
