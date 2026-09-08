# Week 2 — Reference Card

> Cumulative through Week 1 + Mappings, Groovy v2, and project conventions. Keep this open while writing transformations.

---

## Transformation tool decision matrix

First match wins:

1. **Non-XML payload with business logic awkward in XSLT** → **Groovy v2** (JSON↔JSON conditionals, CSV parsing, signatures).
2. **XML→XML, mostly identity transform with overrides/enrichments** → **XSLT 3.0**.
3. **XML→XML, schema-to-schema, mostly field mapping + value lookups** → **Message Mapping**.
4. **JSON↔XML pure shape, no logic** → **JSON↔XML Converter step** (no scripting).
5. **CSV/flat-file → XML, uniform** → **CSV-to-XML Converter**; else Groovy.

Rule of thumb: **smallest tool that solves the problem.** Every escalation costs maintainability.

---

## Message Mapping

### Queues + contexts

- Every node is a **queue of values** bracketed by `[CTX]` markers showing grouping.
- Wrong cardinality on the target? **Inspect the queue** (right-click → Display Queue).
- `removeContexts` flattens. `splitByValue` subdivides. `collapseContexts` flattens only one level. `mapWithDefault` emits a default for empty queues.

### UDF execution types

| Type | Per call gets | Use for |
|---|---|---|
| **Single Value** | One scalar | Per-value transform (uppercase, regex) |
| **Context** | Array per context | Reduce a group (sum, concat-with-comma) |
| **All Values of a Queue** | Whole queue with markers | Rare cross-context logic |

UDFs are **JavaScript** (not Groovy — Groovy lives in Script steps).

### Value Mapping (tenant-wide lookup)

- Artifact, separate from iFlows. `(scheme1, key1) → (scheme2, key2)`.
- **Changes do NOT require iFlow redeploy.** Production lifeline for codes/cost centers/classifications.
- "If no mapping found": *Default* / *Apply Source Value* / **Throw Exception**. Pick consciously — `Default` silently masks bad data.

### Common mapping pitfalls

- Forgetting `removeContexts` before `concat`.
- Mapping a multi-value queue into a `maxOccurs="1"` target — silently keeps first.
- `mapWithDefault` on unbounded element only emits one output total.
- Constants with leading whitespace are not trimmed.
- After re-uploading an XSD, broken links go red — re-test.

---

## XSLT 3.0 (Saxon-HE)

### Identity transform — start here

```xsl
<xsl:template match="@*|node()">
  <xsl:copy>
    <xsl:apply-templates select="@*|node()"/>
  </xsl:copy>
</xsl:template>
```

- **Drop element:** empty `<xsl:template match="DebugInfo"/>`.
- **Rename:** wrap and apply-templates.
- **Add child:** copy + apply + new node inside.

### `exf:` extension functions

```xsl
xmlns:exf="http://sap.com/it/"
```

| Function | Purpose |
|---|---|
| `exf:getHeader('name')` | Read header |
| `exf:getProperty('name')` | Read property |
| `exf:setHeader('name','value')` | Set header (side effect) |
| `exf:setProperty('name','value')` | Set property (side effect) |

**Don't depend on side-effect ordering** — set each header in exactly one place.

### XPath 3.1 you'll actually use

`for $x in seq return ...`, `let $v := expr return ...`, `if/then/else`, `=>` chain, `string-join`, `tokenize`, `format-dateTime`, `parse-json`, `castable as`, `instance of`.

### Grouping (SQL `GROUP BY`)

```xsl
<xsl:for-each-group select="Order/Line" group-by="Category">
  <category name="{current-grouping-key()}">
    <xsl:for-each select="current-group()">...</xsl:for-each>
  </category>
</xsl:for-each-group>
```

Also: `group-adjacent`, `group-starting-with`, `group-ending-with`.

### Error handling

Prefer **test before transform** (`castable as`, `instance of`) over `<xsl:try>/<xsl:catch>`.

### XSLT pitfalls

- **Forgetting source namespace declaration** — `match="Order"` matches nothing if source has a default namespace.
- `<xsl:value-of>` outputs a string; `<xsl:copy-of>` outputs nodes.
- `current-dateTime()` is stable within one transform, varies across runs.

---

## Groovy v2 — language & SAP CI APIs

### Mandatory header

```groovy
import com.sap.it.script.v2.api.Message;
import java.io.Reader;

def Message processData(Message message) {
    Reader reader = message.getBody(java.io.Reader);
    def headers = message.getHeaders();
    def properties = message.getProperties();

    // ...

    return message;
}
```

- **v2 import only.** Never `com.sap.gateway.ip.core.customdev.util.Message`.
- **Semicolons** at end of statements. **Explicit imports** — no wildcards. **Explicit local types** for JDK types.
- **Always `return message;`** — every code path.
- **Body as `Reader`** — drop to `String` only when you must.

### Message API

```groovy
def headers = message.getHeaders();           // Map<String,Object>
def properties = message.getProperties();
message.setHeader("X-Order-Id", "C-1001");
message.setProperty("processedAt", new Date());
Reader r = message.getBody(java.io.Reader);
InputStream b = message.getBody(InputStream); // binary
message.setBody(output);                       // String / byte[] / InputStream
```

### Logging — `MessageLog` only

```groovy
def messageLog = messageLogFactory.getMessageLog(message);
if (messageLog != null) {
    messageLog.addCustomHeaderProperty("orderId", orderId);
    messageLog.addAttachmentAsString("input.json", body, "application/json");
}
```

- **`messageLogFactory` is in scope** — don't import.
- **Always null-guard** — `getMessageLog` returns null when log level is None.
- `addCustomHeaderProperty` makes the value searchable in MPL custom-search. `setStringProperty` is not the same thing — step-local, Debug/Trace only, never searchable.

- **No `System.out.println`, no `java.util.logging`, no `println`** — output goes nowhere.

### Parsing

```groovy
// JSON
def json = new JsonSlurper().parse(reader);              // streamed
message.setBody(JsonOutput.toJson(result));

// XML — read-only: use Slurper (lazy)
def root = new XmlSlurper().parse(reader);
def id = root.header.orderId.text();

// XML output: MarkupBuilder + StringWriter
StringWriter sw = new StringWriter();
new MarkupBuilder(sw).Order { id('X-1') };
```

`JsonSlurper.parse(Reader)` is one-shot — parse once, walk many times.

### CSV — roll your own

No CSV library on the classpath. **Don't `@Grab`** — Grape disabled. Tokenize line-by-line, or use the **CSV-to-XML Converter step** for quoted-comma edge cases.

### HttpClient from a script — usually wrong

```groovy
def httpClient = new com.sap.it.api.asdk.runtime.HttpClientFactory().newHttpClient();
```

Prefer a **Request-Reply with HTTP receiver adapter** — the script form bypasses monitoring, retry, and central credential management.

---

## Sandbox restrictions — what's blocked

| Blocked | Use instead |
|---|---|
| `java.lang.Thread`, `Thread.sleep(n)` | Groovy `sleep(ms) { /* on interrupt */ }` closure form |
| `System.exit`, `Runtime.exec` | Throw an exception |
| `System.out.println`, `java.util.logging`, `println` | `MessageLog.addAttachmentAsString` |
| `java.io.File`, `java.nio.file.Files` | Data Store / Variables / Globals |
| `java.net.Socket`, `URL.openConnection()` | HTTP receiver adapter |
| `@Grab` / Grape | Only the runtime classpath |
| **Top-level `class Foo {}` next to `processData`** | Inline as method/closure inside script, or use a Script Collection |

The top-level class rule surprises every cohort. Compiles in IDE, **fails at deploy**.

---

## Performance non-negotiables

1. **Stream the body** — `getBody(Reader)` for text, `getBody(InputStream)` for binary.
2. **Parse once, walk many times.**
3. **`StringBuilder` in loops**, never `+=`.
4. **Pre-size collections** when size is known.
5. **Closures over imperative loops** — `collect`, `findAll`, `inject`.
6. **`@CompileStatic` on helper methods** (not on `processData`).
7. **`XmlSlurper` over `XmlParser`** for reads.

---

## Project conventions — code-review checklist

- File name `roiam_camelCaseName.groovy`.
- Standalone scripts in `scripts/standalone/`; iFlow scripts in `scripts/collections/<project>/`.
- Inside iFlow project: under `src/main/resources/script/v2/`, **not** `script/`.
- Upload via the **Script step dialog**, not the Resources tab. Use *Upgrade* to replace.
- Changelog at repo root: `changelog/<iFlow>/<YYYY-MM-DD>_<note>.txt`.
- **Don't zip the iFlow** until explicitly asked.
- **No secrets in MessageLog** — tenant-shared log store.

---

## Groovy 4 features worth using here

- `!in`, `!instanceof` — `if (status !in ['DONE','FAILED'])`.
- Switch expression — `def label = switch(s) { case 'OK' -> 'g'; default -> 'r'; }`.
- `tap` / `with` for configure-an-object.
- Safe nav `?.` and Elvis `?:`.
- **Skip records / sealed classes** — top-level, forbidden here.
