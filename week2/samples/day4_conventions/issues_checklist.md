# Issues to find in `roiam_legacy_signer_v1_BAD.groovy`

Grade your refactor against this list. Aim for **at least 8 of 10** spotted before peeking.

- [ ] **1. v1 import.** `com.sap.gateway.ip.core.customdev.util.Message` → must be `com.sap.it.script.v2.api.Message`.

- [ ] **2. No semicolons.** Every statement should end with `;` per project style.

- [ ] **3. `getBody(String)` for the full body.** Default is `getBody(java.io.Reader)` and stream. If you genuinely need the full body materialized (as here, for signing), document the exception.

- [ ] **4. Top-level class `SignatureContext`.** Forbidden — script engine refuses to load files with classes alongside `processData`. Inline as locals or a `Map`.

- [ ] **5. `Thread.sleep(200)`.** Restricted by sandbox. Replace with `sleep(ms){ }` only if a delay is genuinely needed — here, delete it.

- [ ] **6. `System.out.println(...)`.** Output is discarded. Use `MessageLog`.

- [ ] **7. Missing explicit imports** for `java.io.Reader`, `java.nio.charset.StandardCharsets`. Project rule: no wildcard, list every class.

- [ ] **8. No explicit local types.** `def ctx`, `def body`, `def md`, `def digest`, `def sig` should be typed (`String`, `byte[]`, `MessageDigest`, etc.).

- [ ] **9. No null-guard on the secret.** `null + body` silently produces `"null"` + body, signing succeeds with a wrong-but-valid signature. Fail fast with a `RuntimeException`.

- [ ] **10. No null-guard around `messageLog`.** Once you add `MessageLog`, guard `if (messageLog != null)` — it returns null when log level is "None".

## Bonus issues worth mentioning in code review

- [ ] **11. Charset string `"UTF-8"`** vs. `StandardCharsets.UTF_8` constant.
- [ ] **12. Body not written back.** `setBody` is missing — downstream steps see an empty body in v2 because the Reader was drained.
- [ ] **13. `digest.collect{}.join()`** allocates an intermediate list. Pre-sized `StringBuilder` is the project pattern in loops.
- [ ] **14. Signature logged via println** if uncaught — even after replacing with `MessageLog`, **don't log the signature value itself**, only the algorithm name. Tenant log store is shared.

If you spotted 10 before peeking, you're ready for Friday's quiz. If you spotted 12+, you're ready for code review duty.
