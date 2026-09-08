# Day 2.4 — Project Conventions, Sandbox Restrictions & v1 → v2 Refactoring

> **Goal of the day.** Internalize the project's Groovy script conventions so deeply that you write conformant code on the first try. By end of day, refactor a deliberately-bad v1 script into v2 — in front of the trainer — without consulting notes.

## 1. Why conventions matter more than cleverness

Cloud Integration scripts run in a sandboxed JVM, share a tenant with dozens of other iFlows, and are read by people who didn't write them. A "clever" script that works once is worthless next to a boring one that:

- Loads predictably from any iFlow that needs it.
- Fails in a way that surfaces in monitoring instead of hanging silently.
- Doesn't blow the heap on a 50 MB payload.
- Reads the same as every other script on the tenant.

This is why we don't argue about style on this team. Every script in this repository follows the rules below, and CRs that don't will be sent back. Memorize them.

## 2. The non-negotiable script header

Every Groovy v2 script in this project starts with the same header shape:

```groovy
import com.sap.it.script.v2.api.Message;
import java.io.Reader;
// ...other explicit imports...

def Message processData(Message message) {
    Reader reader = message.getBody(java.io.Reader);
    def headers = message.getHeaders();
    def properties = message.getProperties();

    // --- logic ---

    return message;
}
```

Required and non-negotiable:

1. **`com.sap.it.script.v2.api.Message`** — never the v1 `com.sap.gateway.ip.core.customdev.util.Message`.
2. **Explicit imports.** No `import com.sap.it.script.v2.api.*;` — list every class, including `java.io.Reader`, `java.io.ByteArrayInputStream`, `java.io.InputStream`. This makes search-by-import work and removes ambiguity.
3. **Semicolons at end of every statement.** Yes Groovy is optional. Use them anyway — it matches the SAP CI script style and removes ambiguity at line boundaries.
4. **`def Message processData(Message message)`** — exactly this signature, with explicit return type.
5. **`return message;`** — the message object is returned at the end. Always. Even on early-exit branches.
6. **Body read as `Reader`** — `message.getBody(java.io.Reader)` is the default. Drop down to `String` only when you actually need the full text materialized (regex over the whole body, debugging in MessageLog).

## 3. Explicit types on locals

The CI script style uses explicit Java types on local variables wherever it matters:

```groovy
String parameterId = headers.get("roiam_system_destination_name") as String;
int retryCount = (properties.get("retryCount") ?: 0) as int;
boolean skipValidation = "true".equalsIgnoreCase(properties.get("SkipValidation") as String);
```

Use `def` only when:
- The right-hand side is a parsed JSON/XML structure of unknown shape (`def json = jsonSlurper.parse(reader);`).
- The result is a collection you'll mutate dynamically.

The rule of thumb: **if you can write the type without thinking, write it.** The compiler doesn't need it; the next reader does.

## 4. Naming convention — `roiam_*`

Every script file starts with the lowercase prefix `roiam_`, followed by a descriptive **camelCase** name and the `.groovy` extension.

| Right | Wrong |
|---|---|
| `roiam_loadGrcProxyConfig.groovy` | `LoadGrcProxyConfig.groovy` |
| `roiam_jsonOrderToCanonical.groovy` | `roiam-json-order.groovy` |
| `roiam_setRoutingHeaders.groovy` | `routing_headers.groovy` |
| `roiam_csvOrderToCanonical.groovy` | `roiam_CSVorderToCanonical.groovy` |

When you create a new script, ask **what its job is in one verb-phrase** ("loadGrcProxyConfig", "validateOrder", "buildRequestSignature") and that becomes the suffix.

## 5. File placement

```
scripts/
├── standalone/                          ← reusable across iFlows
│   ├── roiam_jsonValidator.groovy
│   └── roiam_loadGrcProxyConfig.groovy
└── collections/<project-name>/          ← all scripts of one iFlow
    ├── roiam_mapOrderItems.groovy
    └── roiam_setHeaders.groovy
```

- **`standalone/`** — utility scripts that solve a generic problem (signature builder, JSON validator, PD lookup helper). Designed to be copied into multiple iFlows.
- **`collections/<project>/`** — scripts that only make sense inside one specific iFlow. The folder name is the iFlow / scenario name (`orderReplication`, `idmIncomingEventMapping`).

**Inside the iFlow project structure**, scripts live under **`src/main/resources/script/v2/`** — never `script/`. The `v2/` folder is the runtime marker that the engine treats the script as a v2 script. Files placed under plain `script/` will not pick up the v2 API even if the import line says so.

## 6. How to upload a script (and why the order matters)

Even if the script file already exists in the iFlow's project folder on disk, the iFlow's deployed runtime won't see it unless you upload it through the **Script step dialog**:

1. Open the iFlow in the editor.
2. Drop a *Script* step on the canvas (or open an existing one).
3. In the step's properties, click *Browse / Select Script*.
4. Choose **"Create"** for a new script, or **"Upload from file"** for an existing one.
5. Save → the script appears under iFlow Resources automatically.

**Do not** upload scripts directly via the Resources tab as a new resource. The Resources tab is for *.xsd*, *.xsl*, *.jks*, value mappings, and reference data — not Groovy scripts. Scripts uploaded that way end up with stale metadata, no Script step binding, and your changes won't be reflected at runtime even though the file exists.

When updating an existing script file from disk, use the *Upgrade* option inside the Script step's properties — it replaces the file in place and keeps the binding.

## 7. Sandbox restrictions you will hit

The CI runtime sandbox blocks classes that could escape the JVM, hold resources across executions, or destabilize the tenant. The ones you will run into:

| Restricted | Why | What to use instead |
|---|---|---|
| `java.lang.Thread` | Thread management is owned by Camel | `sleep(ms){ onInterrupt }` Groovy closure form, or split into multiple iFlow steps |
| `Thread.sleep(...)` | Same as above | `sleep(500) { interrupted -> /* handle */ }` |
| `System.exit(...)` | Would kill the worker | Throw an exception |
| `System.out.println` | Output is discarded | `MessageLog.addAttachmentAsString(...)` |
| `java.util.logging` | Output is discarded | Same |
| `java.io.File`, `java.nio.file.Files` | No file system | Data Store / Variables / Globals |
| `java.net.Socket`, `URL.openConnection()` | No outbound from script | iFlow HTTP receiver adapter, or `HttpClientFactory` (sparingly) |
| `@Grab` / Grape | No internet at compile time | Use only what's on the runtime classpath |
| Top-level `class Foo {...}` next to `processData` | Not loadable by the script engine | Inline the helper as a closure or method *inside* `processData`, or move it to a Script Collection |

**Top-level class rule** is the one that surprises every cohort. This **does not work**:

```groovy
import com.sap.it.script.v2.api.Message;

class OrderItem {       // ← top-level class — script engine refuses to load this file
    String sku;
    int qty;
}

def Message processData(Message message) { ... }
```

Move the structure inside `processData` (use a `Map`, or `tap` an inner class), or put the data class in a Script Collection that's added to the iFlow as a resource.

## 8. MessageLog — the only logging that works

`MessageLog` is the runtime logging facility. There is no other logger that survives in CI. The pattern:

```groovy
def messageLog = messageLogFactory.getMessageLog(message);
if (messageLog != null) {
    messageLog.addAttachmentAsString("incomingPayload", payloadString, "application/json");
    messageLog.setStringProperty("orderId", orderId);
}
```

The **null guard is mandatory** — `messageLog` is `null` when log level is "None" (a configuration the operator can set), and dereferencing it in that case throws an NPE that takes the message into the error path for no reason.

`addAttachmentAsString(name, content, mimeType)` makes the attachment visible in *Monitor → Message Processing → click message → Attachments*. `setStringProperty(name, value)` adds a searchable property at the message level.

**Do not log secrets** (tokens, passwords, full SSN). You're writing to a tenant-shared log store that operations and other developers read.

## 9. Performance non-negotiables

Project-wide rules — these will catch you in code review:

1. **Stream the body.** `getBody(Reader)` for text, `getBody(InputStream)` for binary. Avoid `getBody(String)` unless you have a reason.
2. **Parse once.** Don't `JsonSlurper().parse(reader)` and then `parse` it again later because you forgot to keep the result.
3. **`StringBuilder` in loops, never `+`.** Even for "small" loops; small loops grow.
4. **Pre-size collections.** `new ArrayList<>(n)`, `new HashMap<>(n)` when you know the size up front.
5. **Closures over imperative loops.** `list.collect { }` / `findAll { }` / `inject { }` reads better and the JIT optimizes them well.
6. **`@CompileStatic` on helper methods** when the types don't depend on dynamic SAP API objects. The 5-10x speedup is free.

## 10. Changelog convention — *outside* the iFlow folder

Project rule: changelogs live at repo root in `changelog/<iFlow name>/` as dated `.txt` files. They are **not** inside the iFlow folder, because the iFlow folder is the deployable artifact and we don't ship internal commentary into the tenant.

```
changelog/
└── roi_<your_initials>_OrderHub/
    ├── 2026-06-08_initial_iflow.txt
    ├── 2026-06-09_add_xslt_enrichment.txt
    └── 2026-06-11_csv_branch_added.txt
```

Each file is a plain prose description of what changed and why — same shape as a good Git commit message. They get reviewed alongside the iFlow during transports.

## 11. Zipping iFlows

**Do not zip / re-archive an iFlow folder unless explicitly asked.** Zipping is what you do *after* you and the trainer agree the iFlow is ready for transport. Doing it earlier produces stale archives and bloats the repo with intermediate snapshots.

When asked to zip: use the standard archive name `<iFlowId>.zip` matching exactly what the CI tenant expects on import.

---

## Hands-on lab — Refactor a v1 script into v2

> Time: ~3 hours. Goal: take a deliberately-bad v1-styled script and refactor it to project-conformant v2, then deploy and prove it still works. Trainer has the v1 file ready and hands it to you on a memory stick or a chat paste — *do not* search for it in the project repo, it has been kept off the trainees' tenant on purpose.

### The v1 starting script (intentionally bad)

```groovy
// roiam_legacy_signer.groovy  -- v1, deliberately broken in style
import com.sap.gateway.ip.core.customdev.util.Message
import java.security.MessageDigest

class SignatureContext {
    String secret
    String algo
}

def Message processData(Message message) {
    def body = message.getBody(String)
    def headers = message.getHeaders()

    def ctx = new SignatureContext()
    ctx.secret = headers.get("X-Signing-Secret")
    ctx.algo = "SHA-256"

    Thread.sleep(200) // "rate limiting"

    def md = MessageDigest.getInstance(ctx.algo)
    md.update((body + ctx.secret).getBytes("UTF-8"))
    def digest = md.digest()
    def sig = digest.collect { String.format("%02x", it) }.join()

    System.out.println("Signature: " + sig)

    message.setHeader("X-Body-Signature", sig)
    return message
}
```

### Issues to find — make a written list before touching the code

Aim for *at least* eight problems. Compare with your peer or the trainer afterwards.

1. **v1 import.** `com.sap.gateway.ip.core.customdev.util.Message` → must be `com.sap.it.script.v2.api.Message`.
2. **No semicolons.** Project style requires them.
3. **`getBody(String)` for the full body.** Stream with `Reader`. (Note: this script *concatenates* body+secret; you need bytes — see below.)
4. **Top-level class `SignatureContext`.** Forbidden. Inline as a `Map`, or just use locals.
5. **`Thread.sleep(200)`.** Restricted. Replace with `sleep(200){ onInterrupt }` if a delay is genuinely needed — but in this case it's nonsense and should be deleted.
6. **`System.out.println(...)`.** Discarded by the runtime. Replace with `MessageLog`.
7. **No explicit imports for the side classes used (`java.io.Reader`, `java.nio.charset.StandardCharsets`).**
8. **No explicit local types.** `def ctx = ...` etc. should be typed.
9. **No null guard around the secret.** If `X-Signing-Secret` is missing, `null + body` produces "null" silently — bug.
10. **No null guard around `messageLog`.** Once you add `MessageLog`, follow the project pattern.

### The v2 refactored script

This is what you should land on:

```groovy
import com.sap.it.script.v2.api.Message;
import java.io.Reader;
import java.io.BufferedReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

def Message processData(Message message) {
    def headers = message.getHeaders();

    String secret = headers.get("X-Signing-Secret") as String;
    if (secret == null || secret.isEmpty()) {
        throw new RuntimeException("Missing required header 'X-Signing-Secret'");
    }

    Reader reader = message.getBody(java.io.Reader);
    StringBuilder bodyBuilder = new StringBuilder();
    char[] buffer = new char[4096];
    int read;
    while ((read = reader.read(buffer)) != -1) {
        bodyBuilder.append(buffer, 0, read);
    }
    String body = bodyBuilder.toString();

    String algo = "SHA-256";
    MessageDigest md = MessageDigest.getInstance(algo);
    md.update((body + secret).getBytes(StandardCharsets.UTF_8));
    byte[] digest = md.digest();

    StringBuilder hex = new StringBuilder(digest.length * 2);
    for (byte b : digest) {
        hex.append(String.format("%02x", b));
    }
    String sig = hex.toString();

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("signatureAlgo", algo);
    }

    message.setHeader("X-Body-Signature", sig);
    message.setBody(body);
    return message;
}
```

Note the deliberate trade-off: we *do* read the full body to a `String` because signing requires it. That's a documented exception to the streaming rule, not laziness — and the comment-ish StringBuilder loop makes the cost visible.

### Steps

1. **Read the v1 script** carefully. Don't refactor yet — just *read*.
2. **Write the issues list** in your notebook. Aim for eight or more.
3. **Refactor** in your editor. Compile-check it against the project's existing v2 scripts (e.g., `roiam_loadGrcProxyConfig.groovy`) for style consistency.
4. **Save** the file as `roiam_bodySigner.groovy` under `scripts/standalone/`.
5. **Deploy** to a fresh test iFlow:
   - HTTP sender → Script step (your new file) → return.
   - Upload via the *Script step dialog*, **not** the Resources tab.
6. **Test** with `curl`:
   ```bash
   curl -u <u>:<p> -X POST "<runtime>" \
        -H "X-Signing-Secret: shh" \
        -H "Content-Type: text/plain" \
        --data "hello world"
   ```
7. **Verify** the response header `X-Body-Signature` matches what `echo -n "hello worldshh" | sha256sum` returns.
8. **Force the failure case** — call without the header, watch the runtime exception, see it surface in *Monitor → Failed*.

### Trainer review checkpoints

When the trainer comes around:

- Do you have all v1 issues identified?
- Does your refactored script use semicolons + explicit types + explicit imports?
- Did you upload via the Script step dialog?
- Do you have a `MessageLog` null guard?
- Is the file under `scripts/standalone/` with the correct `roiam_*` name?
- Did you write a changelog entry under `changelog/<iFlow name>/<date>_<note>.txt` for the test iFlow?

If you can answer yes to all six, you're ready for Friday's quiz.

---

## Reference card excerpt — Day 2.4

- **v2 import only.** `com.sap.it.script.v2.api.Message`. No exceptions.
- **Style:** semicolons, explicit imports, explicit local types, `def Message processData(Message message)`, always `return message;`.
- **Body:** `getBody(java.io.Reader)` first; `String` only when you must.
- **Naming:** `roiam_camelCaseName.groovy`. Ask for the suffix when creating a new script.
- **Placement:** standalone in `scripts/standalone/`; iFlow scripts in `scripts/collections/<project>/`. Inside the iFlow project, always under `script/v2/`.
- **Upload via Script step dialog**, never via the Resources tab.
- **Forbidden:** `Thread`, `System.out.println`, `java.util.logging`, top-level `class` next to `processData`, `@Grab`.
- **MessageLog with null guard** every time you log.
- **Changelogs at repo root** under `changelog/<iFlow>/<YYYY-MM-DD>_<note>.txt`. **Don't zip** until explicitly asked.
