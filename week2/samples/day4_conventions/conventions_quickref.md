# Project conventions — one-page summary

## The non-negotiable script header

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

| Rule | Required |
|---|---|
| Import `com.sap.it.script.v2.api.Message` | Yes |
| Explicit imports (no wildcards) | Yes |
| Semicolons at end of every statement | Yes |
| Signature `def Message processData(Message message)` | Yes |
| `return message;` on every code path | Yes |
| Body via `getBody(java.io.Reader)` | Default — String only with reason |

## Explicit types on locals

Write the type when you can write it without thinking:

```groovy
String parameterId = headers.get("roiam_system_destination_name") as String;
int retryCount = (properties.get("retryCount") ?: 0) as int;
boolean skipValidation = "true".equalsIgnoreCase(properties.get("SkipValidation") as String);
```

Use `def` only for:
- Parsed JSON/XML of unknown shape (`def json = new JsonSlurper().parse(reader);`)
- Dynamic collections that mutate during the script

## Naming

| Pattern | Example |
|---|---|
| `roiam_camelCaseName.groovy` | `roiam_jsonOrderToCanonical.groovy` |
| Lowercase prefix, then camelCase verb-phrase | `roiam_loadGrcProxyConfig.groovy` |

Ask "what is its job in one verb-phrase?" → that's the suffix.

## Placement

In the repository:
```
scripts/
├── standalone/         ← reusable across iFlows
└── collections/<project>/
```

Inside an iFlow project:
```
src/main/resources/script/v2/    ← always v2, never plain script/
```

## Upload

- **Script step dialog** — Create or Upgrade from inside the step's properties panel.
- **Not** via the Resources tab — that produces stale metadata.

## MessageLog

```groovy
def messageLog = messageLogFactory?.createMessageLog(message);
if (messageLog != null) {
    messageLog.setStringProperty("orderId", orderId);
    messageLog.addAttachmentAsString("input.json", body, "application/json");
}
```

`messageLog` is `null` when log level is "None". **The null-guard is mandatory.**

Don't log secrets.

## Forbidden

- `java.lang.Thread` / `Thread.sleep` → use `sleep(ms){ }`
- `System.out.println` / `java.util.logging` → use `MessageLog`
- `java.io.File`, sockets → use Data Store / HTTP adapter
- Top-level `class Foo {}` next to `processData` → inline or Script Collection
- `@Grab` → Grape disabled

## Performance defaults

1. Stream the body (`Reader` / `InputStream`).
2. Parse once.
3. `StringBuilder` in loops, never `+`.
4. Pre-size collections when the size is known.
5. Closures (`each`, `collect`, `findAll`, `inject`) over `for`/`while`.
6. `@CompileStatic` on helper methods that don't touch SAP dynamic types.

## Changelogs

```
changelog/<iFlow>/<YYYY-MM-DD>_<note>.txt
```

At repo root. Plain prose. **Not inside the iFlow folder** — the iFlow folder is the deployable artifact.

## Zipping

Only when explicitly asked. Archive name: `<iFlowId>.zip`.
