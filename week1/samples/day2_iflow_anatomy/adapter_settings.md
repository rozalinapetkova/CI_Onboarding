# HTTPS sender — common settings cheatsheet

Applies to both `roi_<initials>_HelloIFlow` and the `roi_<initials>_CustomerEchoService` scaffold.

| Setting | Day 1.2 value | Why |
|---|---|---|
| Address | `/roi/hello/<initials>` or `/customer/<initials>/echo` | Must start with `/`. Multi-tenant routing on the tenant runtime URL. |
| Authorization | Role-based | Clients call with Basic Auth credentials of a user assigned to the role. |
| User Role | `ESBMessaging.send` | Default role for tenant-runtime ingress. Use a custom role only if you need finer ACLs. |
| CSRF Protected | `false` | Off for now. Turn on for browser-originating POSTs in Week 3. |
| URL to WSDL | (blank) | We're not enforcing a WSDL/JSON schema yet. |
| Message Exchange Pattern | Request-Reply | We return a body. Use *One-Way* only for fire-and-forget receivers. |

## Allowed HTTP methods

Set explicitly on the HTTPS sender's *Method* dropdown:

- `roi_<initials>_HelloIFlow` → `GET`
- `roi_<initials>_CustomerEchoService` → `POST`

Leaving "All" allowed is a common mistake — it means `OPTIONS`/`HEAD` reach the iFlow and waste metering.

## Common pitfalls

1. **Address missing the leading slash** — deploy succeeds, runtime returns 404.
2. **Role missing from the BTP role collection** — deploy succeeds, runtime returns 403.
3. **CSRF on for a non-browser caller** — the first POST is rejected with 403 *CSRF Token required*. Fetch one with a `GET … X-CSRF-Token: Fetch` first.
4. **MEP = One-Way but the iFlow ends with a body** — the body is silently dropped. Confuses everyone the first time.
