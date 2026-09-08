# v1 → v2 walkthrough — every change explained

Read this with both `roiam_legacy_signer_v1_BAD.groovy` and `roiam_bodySigner_v2_GOOD.groovy` open side-by-side.

## Change 1 — import

```diff
- import com.sap.gateway.ip.core.customdev.util.Message
+ import com.sap.it.script.v2.api.Message;
```

The v1 import binds to the old `Message` API with a smaller method surface and the Groovy 2.x runtime. v2 binds to Groovy 4.0.29 and richer typed accessors. **The package change is the entire definition of "v2."**

Also added explicit imports for `java.io.Reader`, `java.nio.charset.StandardCharsets`, `java.security.MessageDigest`. No wildcards, no implicit JDK imports — list everything you touch.

## Change 2 — semicolons

Every statement in the v2 file ends with `;`. Groovy doesn't require it; this project does, because:
- It removes ambiguity at line boundaries when a statement wraps.
- It matches the SAP CI script style the cookbook uses.
- It makes diffs cleaner (no "added a closing paren, now needs a newline" churn).

## Change 3 — removed top-level class `SignatureContext`

```diff
- class SignatureContext {
-     String secret
-     String algo
- }
- def ctx = new SignatureContext()
- ctx.secret = headers.get("X-Signing-Secret")
- ctx.algo = "SHA-256"
+ String secret = headers.get("X-Signing-Secret") as String;
+ String algo = "SHA-256";
```

Top-level classes alongside `processData` **fail to deploy** in the CI script engine. The script body is the only thing that gets compiled. Two fields didn't deserve a class anyway — locals are fine.

## Change 4 — body read as Reader (with documented exception)

```diff
- def body = message.getBody(String)
+ Reader reader = message.getBody(java.io.Reader);
+ StringBuilder bodyBuilder = new StringBuilder();
+ char[] buffer = new char[4096];
+ int read;
+ while ((read = reader.read(buffer)) != -1) {
+     bodyBuilder.append(buffer, 0, read);
+ }
+ String body = bodyBuilder.toString();
```

Why so much code just to read a String? Because:
- The **default** is to stream. Anyone reading the script should see streaming code unless there's a reason not to.
- Signing requires the full body bytes. That's a reason — and the StringBuilder loop makes the trade-off visible. A future reader can see "ah, we *had* to materialize."
- Using `getBody(String)` directly works, but hides the choice. The comment at the top of the v2 file calls out the exception explicitly.

## Change 5 — null-guard the required header

```diff
- ctx.secret = headers.get("X-Signing-Secret")     // no check
+ String secret = headers.get("X-Signing-Secret") as String;
+ if (secret == null || secret.isEmpty()) {
+     throw new RuntimeException("Missing required header 'X-Signing-Secret'");
+ }
```

The v1 script silently produced `digest("hello" + "null")` when the header was missing — a valid-but-wrong signature. **Fail fast** at the boundary; let the iFlow surface the error in monitoring.

## Change 6 — removed `Thread.sleep`

```diff
- Thread.sleep(200) // "rate limiting"
```

Three problems:
1. `java.lang.Thread` is **blocked by the sandbox**. The script throws at runtime.
2. Even if it weren't blocked, blocking a Camel worker thread for arbitrary milliseconds is hostile to other iFlows on the tenant.
3. "Rate limiting" in a transformation step is the wrong layer. Rate limiting belongs in the iFlow flow control or the receiver adapter.

If a delay is genuinely needed (it almost never is), the replacement is `sleep(200) { /* on interrupt */ };` — Groovy's `sleep` method, not Thread's.

## Change 7 — explicit charset

```diff
- md.update((body + ctx.secret).getBytes("UTF-8"))
+ md.update((body + secret).getBytes(StandardCharsets.UTF_8));
```

`"UTF-8"` works but is a stringly-typed lookup. `StandardCharsets.UTF_8` is the JDK-blessed constant. No allocation, no possibility of a typo. Same hash, better code.

## Change 8 — hex encoding via StringBuilder, not collect+join

```diff
- def sig = digest.collect { String.format("%02x", it) }.join()
+ StringBuilder hex = new StringBuilder(digest.length * 2);
+ for (byte b : digest) {
+     hex.append(String.format("%02x", b));
+ }
+ String sig = hex.toString();
```

The v1 version allocates an intermediate `List<String>` of 32 elements, then joins them. The v2 version pre-sizes a `StringBuilder` to the final length and appends directly. For a SHA-256 (32 bytes → 64 hex chars) the difference is microseconds, but the pattern matters: **pre-size and append** is the project default in loops.

## Change 9 — replaced println with MessageLog

```diff
- System.out.println("Signature: " + sig)
+ def messageLog = messageLogFactory?.createMessageLog(message);
+ if (messageLog != null) {
+     messageLog.setStringProperty("signatureAlgo", algo);
+ }
```

`System.out.println` silently discards. `MessageLog` is the only logger that produces visible output.

Note we log the **algorithm**, not the signature, and definitely not the secret. **Don't log secrets** — the tenant log store is read by operations and other developers.

## Change 10 — set the body before returning

```diff
  message.setHeader("X-Body-Signature", sig)
+ message.setBody(body);
  return message
```

The v1 script consumed the body (via `getBody(String)`) but never wrote it back. In v1 that *sometimes* worked because the old API kept a cached copy. In v2 the body is a stream that's been drained — if you don't set it, downstream steps see an empty body.

## Summary

| Aspect | v1 | v2 |
|---|---|---|
| Import | gateway.ip | it.script.v2.api |
| Semicolons | absent | present |
| Top-level class | yes (broken) | no |
| Body read | `String` | `Reader` (with documented exception) |
| Required header check | none | throws |
| Sleep | `Thread.sleep` (blocked) | removed |
| Charset | `"UTF-8"` string | `StandardCharsets.UTF_8` |
| Hex build | `collect{}.join()` | pre-sized StringBuilder |
| Logging | `System.out.println` | `MessageLog` with null-guard |
| Body restored | no | yes |

Ten changes. Memorize the categories — they cover roughly 90% of v1→v2 refactors you'll do on the project.
