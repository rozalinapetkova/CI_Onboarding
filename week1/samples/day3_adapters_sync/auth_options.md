# Auth options — receiver-side picker

For a *sender* you also pick role-based vs cert-based, but this card is about the receiver hop.

| Method | When to use | Where credentials live | Pitfalls |
|---|---|---|---|
| **None** | Public APIs (restcountries, IP lookup, etc.) | — | Fine for the Day 1.3 lab; rare in real systems. |
| **Basic** | Legacy partners; internal SAP systems with technical users. | Security Material → User Credentials artifact. Adapter references it by name. | Password rotation requires *redeploying* every iFlow that names the artifact. The Week 3 lab uses Externalized Parameters to centralize the name. |
| **OAuth2 Client Credentials** | The default for modern SaaS and S/4HANA Cloud. | Security Material → OAuth2 Client Credentials artifact. Token URL + scope are part of the artifact. | Token caching is automatic — but the cache is per worker node, not global. Don't assume single-token-per-second. |
| **Client Certificate (mTLS)** | B2B partners; SAP S/4HANA on-premise via Cloud Connector. | Keystore (private key) + the partner's trusted CA in the truststore. | Cert expiry is the #1 production outage. Cookbook: monitor 60/30/7-day windows via Cloud ALM. |
| **SAML Bearer Assertion** | User-propagation scenarios into S/4HANA Cloud. | Keystore (signing key) + a configured Trust Configuration in BTP. | Don't use for system-to-system — too much setup for too little gain. |
| **JWT** | Rare in receiver direction; used by API Management policies more often. | — | If you find yourself building JWT in Groovy, you're probably solving the wrong problem. Use a Security Material artifact. |

## Day 1.3 choice

For the restcountries call: **None**. The whole point is that the auth method is the simplest possible, so we can isolate the lesson about *Throw Exception on Failure*.

## The "no native canonical format" gotcha

Each receiver speaks its own dialect. There's no XML/JSON canonical interchange that adapters auto-convert. If you call HTTP then SOAP then OData in one flow, you (or a mapping step) own the conversion. Plan the message shape *per hop*, not per iFlow.
