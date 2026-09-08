# Externalized parameters — what and how

CTM transports the iFlow *definition*. It does NOT transport the per-tenant *configuration*. That gap is bridged by **externalized parameters** — placeholders in the iFlow that you fill in per tenant after deployment.

## The rule

| In the iFlow definition | On the tenant (after deploy) |
|---|---|
| `{{ReceiverOrdersBaseUrl}}` — a placeholder | `https://orders-qa.example.com` — a value |
| `{{OAuth2CredentialAlias}}` — a placeholder | `orderhub-qa-oauth` — a value (refers to a Security Material entry) |
| `{{DataStoreName}}` — a placeholder | `orderhub-idempotency-qa` — a value |

The placeholder syntax `{{name}}` is what externalizes the field. The Configure dialog on each tenant prompts for the value.

## What to externalize

**Always externalize:**

| Field | Reason |
|---|---|
| Receiver HTTPS URLs | Different host per tenant |
| OAuth2 Credential aliases | Each tenant has its own Security Material entry |
| Data Store names | Tenant-scoped state |
| Number Range names | Tenant-scoped counters |
| Globals' identifiers | Tenant-scoped state |
| Email addresses for ANS Actions | Person-specific |
| ProcessDirect address (when the consumer iFlow may be replaced per tenant) | Tenant routing |
| Retry counts and timeouts (where they differ by environment) | QA may be more forgiving than Prod |

**Do NOT externalize (hardcode):**

| Field | Reason |
|---|---|
| `correlationId` | Same name everywhere |
| `X-Idempotency-Key` | Header name, not value |
| Boundary attachment names (`incoming-canonical`, etc.) | Convention, not config |
| MPL custom header property names | Same across tenants |
| `roi.<iflow>.<reason>` ANS category strings | Convention; cross-tenant consistency required |
| Script step references (e.g., `roiam_setCorrelationId.groovy`) | Resource names |
| XPaths and JSONPaths | Schema-level, not env-level |

The principle: externalize what *changes between Dev and QA*. Hardcode what is intrinsic to the iFlow's logic.

## The configure-on-target ritual

After every transport to QA:

1. *CI on QA → Operations → Manage Integration Content → click the iFlow → Configure.*
2. The Configure dialog shows all externalized parameters, prefilled with Dev's values.
3. **Change each one to the QA value.** Use the tenant-config sheet.
4. Click *Save* → *Deploy*.
5. Send a smoke-test curl. Verify the Receiver hit QA's backend, not Dev's.

Step 3 is where every trainee gets bitten at least once. The Configure dialog *defaults to Dev's values* because the iFlow's metadata carries the last configuration from Dev's tenant. Forgetting to switch values is the #1 transport mistake.

## The tenant-config sheet

A simple per-iFlow markdown table kept in `changelog/<iflow-stem>/_config.md`:

```markdown
# roi-orderhub-consumer — tenant configuration

| Parameter | Dev value | QA value |
|---|---|---|
| ReceiverOrdersBaseUrl | https://orders-dev.example.com | https://orders-qa.example.com |
| OAuth2CredentialAlias | orderhub-dev-oauth | orderhub-qa-oauth |
| DataStoreName | orderhub-idempotency-dev | orderhub-idempotency-qa |
| MaxRetries | 5 | 3 |
| RetryBackoffMs | 30000 | 60000 |
| AnsActionEmail | dev-team@example.com | qa-oncall@example.com |
```

Update this file *before* transporting, not after. The transport runbook (`dev_to_qa_runbook.md`) references it at step 7.

## Externalizing in the iFlow editor

To externalize a value:

1. Open the iFlow in Edit mode.
2. Click the step or adapter that has the field.
3. In the field, type `{{ParameterName}}` (curly-curly).
4. A *Externalize Parameter* prompt may appear — accept it.
5. Save. The parameter is now visible in the package's *Externalized Parameters* tab.

To set a parameter's value on a tenant:

1. *Operations → Manage Integration Content → click the iFlow → Configure.*
2. Click the parameter row → enter value.
3. Save → Deploy.

## What CTM transports about externalized parameters

| Component | Transported? |
|---|---|
| The placeholder `{{Name}}` in the iFlow definition | **Yes** — part of the iFlow XML |
| The default value on Dev | **Yes** — propagates to QA as the prefill |
| Whether the parameter is mandatory | **Yes** — schema-level |
| The actual value you configured on Dev | Carried as default; QA *must* re-configure |
| The value on QA | **No** — never overwritten unless you re-configure |

This is why "Configure on target" is a manual step after every transport.

## Common externalization mistakes

| Mistake | Consequence |
|---|---|
| Hardcoded `https://orders-dev.example.com` in a Receiver adapter | QA's iFlow calls Dev's backend; corrupts Dev data with QA test runs |
| Externalized `correlationId` (header name) | Different tenants might rename the header; correlation breaks |
| Externalized OAuth credential value (the secret itself) instead of the alias | Secret leaked into iFlow metadata; bad security hygiene |
| Forgot to update QA after a Dev rename of the parameter | iFlow deploys but parameter is null at runtime; NPE or empty header |
| Per-tenant value missing from `_config.md` | Trainee guesses at QA value; gets it wrong; debugging session ensues |

## Mass-update via Externalized Parameters tab

For changing many parameters across multiple iFlows:

1. *CI on QA → Design → roi-orderhub package → Externalized Parameters tab.*
2. Edit values per iFlow.
3. Save All.
4. Redeploy each iFlow.

The package-level view is what you want when you're configuring a fresh tenant after a tenant rebuild.

## Security Material vs externalized parameters

| Item | Where it lives | Externalize as |
|---|---|---|
| OAuth client ID | Security Material — Credential alias | The *alias name*, e.g. `orderhub-qa-oauth` |
| OAuth client secret | Security Material — alongside the alias | Never externalize the secret itself |
| HTTPS server cert | Keystore | Never externalize the cert bytes |
| Username/password | Security Material — User Credentials | Externalize the alias name only |

The pattern: **secrets stay in Security Material; iFlow references them by alias; the alias name is what gets externalized.**

## Verifying configure-on-target worked

After step 4 of the ritual, send a smoke-test call:

```bash
curl -s -X POST "${QA_RUNTIME_URL}/http/orderhub/orders/${INITIALS}" \
    -H "Authorization: Bearer $(./obtain_qa_token.sh)" \
    -H "Content-Type: application/json" \
    -H "X-Idempotency-Key: $(uuidgen)" \
    -d '{ "orderId": "C-9001", "customer": "Smoke Test",
          "totalAmount": 1, "lines": [{"sku":"S-1","quantity":1,"unitPrice":1}] }'
```

Open Monitor → find the new run → check the `pre-receiver` attachment → confirm the URL written there points at the QA backend, not Dev. If it points at Dev, you forgot to configure.
