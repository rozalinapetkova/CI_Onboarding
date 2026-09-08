# HTTP sender adapter — inbound OAuth2

For the existing sender on `roi_<your_initials>_OrderHub` at address `/http/orderhub/orders/<your-initials>`.

The mental model: **OAuth validation happens upstream of the iFlow**, at the subaccount's OAuth instance. The sender adapter itself is configured for *Client Certificate* — that's what the cockpit forces — but the runtime has already validated the bearer token before the message reaches the adapter.

## Connection tab

| Property | Value |
|---|---|
| Address | `/http/orderhub/orders/<your-initials>` |
| URL to WSDL | *(blank)* — not a SOAP endpoint |
| CSRF Protected | `false` for a non-browser caller; `true` for a webhook from a CSRF-aware system |

## Authentication tab

| Property | Value | Note |
|---|---|---|
| Authorization | `User Role` | Default. |
| User Role | `ESBMessaging.send` | The default role. The caller's OAuth token must carry a scope that maps to this role. |

## The token contract for callers

Callers obtain a token from the subaccount's token URL:

```bash
curl -X POST "<token-url>" \
     -u <inbound-client-id>:<inbound-client-secret> \
     -d "grant_type=client_credentials"
```

Then call the iFlow with `Authorization: Bearer <access_token>`.

The runtime validates:

- Signature against the subaccount's XSUAA public key.
- `exp` (expiry) is in the future.
- One of the token's scopes maps to the configured `User Role` (`ESBMessaging.send`).

If any check fails → **401 Unauthorized** before the iFlow runs. You see *nothing* in *Monitor → Message Processing* for a 401 — there is no run to see.

## What you do NOT configure here

- The OAuth provider URL (it's discovered from the subaccount binding).
- The list of valid client_ids (any token signed by the subaccount's XSUAA with the right scope is accepted).
- A credential name (this is *inbound* — credentials are the caller's, not yours).

## Confusion to avoid

This is **inbound** — the iFlow's *sender*. It validates tokens.
The receiver adapter (separate file) is **outbound** — the iFlow's *receiver*. It produces tokens.

Different artifacts, different cockpit areas, easy to mix up. When debugging, write down which direction you're working on before touching the config.
