# Day 3.1 samples — Authentication & Secure Store

Reference artifacts for the OAuth2-secure-the-Order-Hub lab. None of these
get deployed verbatim — they are the shapes you produce in the cockpit, plus
the curl harness for verifying the end-to-end flow.

| File | What it is |
|---|---|
| `security_material_oauth2_entry.md` | Field-by-field walkthrough of the Security Material OAuth2 Client Credentials entry |
| `security_material_basic_entry.md` | Comparison entry — User Credentials for Basic auth |
| `receiver_oauth2_config.md` | HTTP receiver adapter properties when consuming OAuth2 client credentials |
| `sender_auth_config.md` | HTTP sender adapter configuration for inbound OAuth2 |
| `obtain_token.sh` | curl to fetch a client_credentials access token from XSUAA |
| `call_iflow.sh` | curl invocations: happy path, no auth, garbage token |
| `rotate_secret_runbook.md` | The five-step secret-rotation SOP — what ops actually does |
| `mtls_keystore_walkthrough.md` | Keystore setup for an mTLS receiver — contrast with Security Material |
| `auth_decision_table.md` | Five-method decision matrix with concrete picks per scenario |
| `common_failures_cheatsheet.md` | Symptoms → causes for the most common auth misconfigurations |
