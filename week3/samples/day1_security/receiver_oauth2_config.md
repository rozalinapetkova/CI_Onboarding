# HTTP receiver adapter — consuming OAuth2 client credentials

For the *Request-Reply* + *HTTP receiver* added inside `roi_<your_initials>_OrderHub` to call `https://<trainer-stub>/orderhub/accept`.

## Connection tab

| Property | Value |
|---|---|
| Address | `https://<trainer-stub>/orderhub/accept` |
| Proxy Type | `Internet` |
| Method | `POST` |
| Timeout | `60000` ms (default) |

## Authentication tab — the two dropdowns that matter

| Property | Value | Why |
|---|---|---|
| Authentication | `OAuth2 Client Credentials` | **NOT** `None`. Setting the Credential Name without this is silent failure. |
| Credential Name | `oauth2_<your_initials>_orderhub_downstream` | Must match the Security Material entry name exactly. |

## Request tab

| Property | Value |
|---|---|
| Request Headers | `Content-Type,X-Order-Sequence` |
| Request Body Encoding | `none` |
| Throw Exception on Failure | `Checked` (keep on for the lab — Day 3.4 will show how to handle this) |

## Response tab

| Property | Value |
|---|---|
| Response Headers | `*` (forward everything for now; tighten later) |
| Response Body Encoding | `none` |

## What success looks like in the Monitor

1. Open *Monitor → Message Processing*, click the run.
2. *Steps* tab — the receiver call appears as `External Call` with HTTP 200.
3. *Headers* tab on the receiver sub-step — `Authorization` is **not** visible. The runtime stripped it. Correct behaviour.
4. The first call after a (re)deploy or cache expiry has a slightly higher latency — the worker fetched a fresh token. Subsequent calls within ~60-120s reuse the cached token.

## What failure looks like

| Symptom in Monitor | Cause |
|---|---|
| HTTP 401 on the receiver sub-step | Token rejected by downstream — wrong client_id/secret, expired, or scope mismatch |
| `Credential not found: oauth2_xxx_orderhub_downstream` deploy error | Name typo, or the Security Material entry was never deployed |
| HTTP 200 but Authorization header was empty | `Authentication` left as `None` while `Credential Name` was set — silent failure |
| Repeated 401s after rotation | Worker's token cache holds an old token; will self-heal at expiry (~60-120s) |
