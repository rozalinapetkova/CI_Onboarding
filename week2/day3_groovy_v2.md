# Day 2.3 — Groovy v2 — Language Essentials & SAP CI APIs

> **Goal of the day.** Write a v2 Groovy script that follows every project convention, parses a streamed body, transforms it, sets headers and properties, and writes a useful `MessageLog` attachment. By the end of the day you should be able to write the JSON and CSV branches of the Order Translator without consulting notes.

## 1. v1 vs. v2 — and why the project mandates v2

There are two generations of the Groovy script API in CI. They look almost the same, but the import is different:

| | v1 (legacy) | v2 (mandatory here) |
|---|---|---|
| Message import | `com.sap.gateway.ip.core.customdev.util.Message` | `com.sap.it.script.v2.api.Message` |
| Groovy runtime | older 2.x | **4.0.29** |
| Method signature | `def Message processData(Message message)` | (same) |
| API surface | smaller | richer (typed accessors, structured logging) |

**Project rule (from `CLAUDE.md`):** if you find a v1 script, rewrite it. The signature `def Message processData(Message message)` is identical, so the migration is almost always a one-line import change — but Day 2.4 will show you the real-world v1→v2 refactor with all the gotchas.

## 2. The canonical script template

This is the skeleton every script in this repo starts from:

```groovy
import com.sap.it.script.v2.api.Message;
import java.io.Reader;

def Message processData(Message message) {
    Reader reader = message.getBody(java.io.Reader);
    def headers = message.getHeaders();
    def properties = message.getProperties();

    // --- logic here ---

    message.setBody(body);
    return message;
}
```

Notice:

- **Semicolons** at end of statements. Yes, Groovy doesn't require them; the project requires them. Do not argue.
- **Explicit imports.** `java.io.Reader`, `java.io.ByteArrayInputStream` if you use it. No wildcard imports.
- **Explicit type on locals** where it's a known JDK type (`Reader reader`, `String s`, `int n`). For SAP types (the dynamic message API), `def` is fine.
- **Always return `message`.** Every code path. Even the early-exit ones.
- **Stream the body** with `getBody(java.io.Reader)`. Only fall back to `getBody(String)` when you genuinely need the entire payload as one String (e.g., regex-replace on the whole body) — and document why.

## 3. Headers, properties, body — the message API

```groovy
// Reading
def headers     = message.getHeaders();          // returns Map<String,Object>
def properties  = message.getProperties();
def correlation = headers.get("correlationId");

// Writing
message.setHeader("X-Order-Id", "C-1001");
message.setProperty("processedAt", new Date());

// Body
Reader reader     = message.getBody(java.io.Reader);   // preferred
String wholeBody  = message.getBody(String);           // only when needed
InputStream binIn = message.getBody(InputStream);      // for binary
message.setBody("<some>output</some>");                // accepts String, byte[], InputStream
```

**Reminder of the boundary:**

| | Headers | Properties |
|---|---|---|
| Travel out of iFlow? | Yes | No |
| Use for | External-facing metadata | Internal scratch state |
| Visibility to receiver | Yes | No |

If you need a flag to influence routing later in the same iFlow, **use a property.** If you need to send something with the outgoing message, **use a header.**

## 4. Logging via `MessageLog`

The **only** logging mechanism that produces visible output in the runtime is `MessageLog`:

```groovy
def messageLog = messageLogFactory.getMessageLog(message);
if (messageLog != null) {                                    // null when log level too low
    messageLog.setStringProperty("orderId", "C-1001");        // searchable in MPL custom search
    messageLog.addAttachmentAsString("input.json",
        bodyString, "application/json");
}
```

`messageLogFactory` is **already in scope** in the script — it's an SAP-provided binding. You don't import it.

**Critical:** `getMessageLog(message)` returns `null` when the iFlow's *log level* is set to `None`. Always guard with `if (messageLog != null)`. Forgetting this is one of the top "my script throws NPE in prod" causes.

`addAttachmentAsString` becomes a tab in the MPL — visible in *Monitor → Message Processing → Attachments*. Use it for diagnostic snapshots: input, output, intermediate transformation, error context.

`setStringProperty(name, value)` makes the value **searchable in the MPL custom-search box** — this is how you find a message by `orderId` later. Pair with the MPL custom-header search you saw in Week 1.

**Don't use:**
- `System.out.println` — output goes to `/dev/null`.
- `java.util.logging` — same.
- `println` (Groovy's default) — same.

## 5. Parsing JSON in CI

```groovy
import groovy.json.JsonSlurper;
import groovy.json.JsonOutput;
import java.io.Reader;

Reader reader = message.getBody(java.io.Reader);
def json = new JsonSlurper().parse(reader);                  // streamed parse — preferred

// json is a Map (object) or List (array)
def items = json.items as List;
def transformed = items.collect { item ->
    [id: item.materialNumber, qty: item.quantity, total: item.quantity * item.unitPrice]
};

message.setBody(JsonOutput.toJson(transformed));
return message;
```

`JsonSlurper.parse(Reader)` consumes the stream once. Don't try to `parse(reader)` twice — the second call returns null/empty.

For pretty-printing in attachments (not for production output): `JsonOutput.prettyPrint(JsonOutput.toJson(obj))`.

## 6. Parsing XML in CI

Two options: `XmlSlurper` (lazy, GPath, read-only) and `XmlParser` (eager, mutable).

```groovy
import groovy.xml.XmlSlurper;
import groovy.xml.MarkupBuilder;

Reader reader = message.getBody(java.io.Reader);
def root = new XmlSlurper().parse(reader);

// GPath access
def orderId = root.header.orderId.text();
def lines   = root.lines.line.collect { [sku: it.sku.text(), qty: it.quantity.text()] };

// Build output XML
def writer = new StringWriter();
def xml = new MarkupBuilder(writer);
xml.CanonicalOrder {
    header { orderId(orderId) }
    lines {
        lines.each { line ->
            line { sku(line.sku); quantity(line.qty) }
        }
    }
}
message.setBody(writer.toString());
```

**Use `XmlSlurper` for read-only.** It's lazy and uses less memory. Only reach for `XmlParser` if you need to mutate the tree in place.

## 7. Parsing CSV — keep it simple

CI doesn't ship a CSV library. Don't `@Grab` one — Grape is disabled. Roll your own with `tokenize` or read line-by-line:

```groovy
import com.sap.it.script.v2.api.Message;
import java.io.Reader;
import java.io.BufferedReader;
import groovy.json.JsonOutput;

def Message processData(Message message) {
    BufferedReader reader = new BufferedReader(message.getBody(java.io.Reader));
    String headerLine = reader.readLine();
    if (headerLine == null) {
        throw new RuntimeException("Empty CSV body");
    }
    List<String> cols = headerLine.split(",").collect { it.trim() };

    List<Map<String,String>> rows = new ArrayList<>();
    String line;
    while ((line = reader.readLine()) != null) {
        if (line.trim().isEmpty()) continue;
        List<String> values = line.split(",", -1).collect { it.trim() };
        Map<String,String> row = new LinkedHashMap<>(cols.size());
        cols.eachWithIndex { col, i ->
            row.put(col, i < values.size() ? values[i] : "");
        }
        rows.add(row);
    }

    message.setBody(JsonOutput.toJson(rows));
    return message;
}
```

Note the explicit types on locals (`BufferedReader reader`, `String headerLine`). This is project style. **Do not** use third-party CSV libraries — there's no resolver; the iFlow won't deploy.

If you're tempted by quoted-comma corner cases (`"foo, bar"`), the right fix is the **CSV-to-XML Converter** flow step, not a smarter Groovy regex. Reach for the converter step when in doubt.

## 8. HttpClient — calling out from a script

The script sandbox forbids raw `URLConnection` / `HttpURLConnection` / `Socket`. The supported way to make an HTTP call from a script is via SAP's `HttpClient`:

```groovy
import com.sap.it.api.asdk.runtime.HttpClientFactory;

def httpClient = new HttpClientFactory().newHttpClient();
def response = httpClient.execute(/* request */);
```

But honestly: **don't.** Calls from Groovy bypass the iFlow's adapter framework — no monitoring of the call as a sub-step, no automatic retry, no central credential management. **The right way to make HTTP calls is via a Request-Reply step with an HTTP receiver adapter.** Use `HttpClient` from a script only when the iFlow flow really cannot express the call — e.g., a fan-out call inside a transformation.

## 9. Groovy 4 features worth using

CI runs Groovy 4.0.29. New-ish features that improve readability:

- **`!in` and `!instanceof`** — `if (status !in ['DONE','FAILED'])`.
- **Switch expressions** — `def label = switch(status) { case 'OK' -> 'green'; case 'WARN' -> 'yellow'; default -> 'red'; }`.
- **`tap` / `with`** — configure-an-object idiom: `new Foo().tap { name = 'X'; count = 3 }`.
- **Records and sealed classes** — but recall: **no top-level classes** in CI scripts. So skip records here — they're top-level by definition. Use plain Maps.
- **Safe navigation `?.`** and **Elvis `?:`** — `def email = user?.contact?.email ?: 'no-reply@x.com'`.

The package rename note from CLAUDE.md: legacy `groovy.json.*` and `groovy.xml.*` still work via the compatibility layer. Stick to those — they match what's already in the codebase.

## 10. Performance — the rules you already half-know

From CLAUDE.md, formalized:

1. **Stream large payloads.** `getBody(java.io.Reader)` then `JsonSlurper.parse(reader)` — one pass, no String allocation of the whole payload.
2. **Parse once, extract many times.** Don't re-parse the body for each field; parse to a tree, then walk.
3. **Reuse builders.** `StringBuilder` / `StringWriter` outside loops. Don't `s = s + x` inside a loop — quadratic memory.
4. **`XmlSlurper` over `XmlParser` for reads** — lazy + lower memory.
5. **`@CompileStatic`** on helper methods/classes (not on `processData` itself, which uses dynamic SAP types). Skips method dispatch overhead in tight loops.
6. **Initialize collections with capacity** when known: `new ArrayList<>(expectedSize)`, `new LinkedHashMap<>(cols.size())`.
7. **`closure-based loops`** (`each`, `collect`, `findAll`, `inject`) over imperative `for` — clearer, and JIT handles them well.

## 11. Restricted classes — sandbox surprises

These are **not allowed** by the CI Groovy sandbox:

- `java.lang.Thread` — *blocked*. If you need a delay, **don't** `Thread.sleep(n)`. Use Groovy's closure form: `sleep(1000) { /* on interrupt */ }` — the keyword `sleep` is a Groovy method, not Thread.
- File I/O (`new File(...)`) — sandbox forbids it.
- Network sockets directly — use `HttpClient` (Section 8).
- `System.exit`, `Runtime.getRuntime().exec(...)` — blocked.
- `System.out.println` — silently goes nowhere.

**The most common newbie trap is `Thread.sleep`.** Replace with:

```groovy
sleep(2000) { /* this closure runs only if interrupted */ };
```

This is **project memory** — captured from a real incident.

## 12. No top-level classes

CI script files are evaluated as Groovy script bodies. **You cannot declare top-level `class Foo {}` next to `processData`.** It compiles in IDE; it fails at iFlow deploy.

If you want shared helpers, declare them as **methods inside the same script** (above or below `processData`):

```groovy
def Message processData(Message message) {
    def result = transform(message.getBody(java.io.Reader));
    message.setBody(result);
    return message;
}

Object transform(Reader reader) {
    // ...
}
```

…or as **closures** assigned to local variables inside `processData`. The constraint is: nothing declared at the top level except `processData` and helper methods. **No `class`, no `enum`, no `record`, no `interface`.**

This is project memory — and again, comes from real incidents.

---

## Hands-on lab — JSON and CSV branches of the Order Translator

> Time: ~3 hours. Goal: extend `roi_<your_initials>_OrderHub` to handle `json` and `csv` inputs by writing two v2 Groovy scripts that produce the same `<CanonicalOrder>` XML the Message Mapping produces from XML.

### Architecture additions

```
Sender → Content Modifier → Router on X-Order-Format
                                 ├─ "xml"  → Message Mapping (yesterday)
                                 ├─ "json" → Script: roiam_jsonOrderToCanonical
                                 └─ "csv"  → Script: roiam_csvOrderToCanonical
                                 ↓ (joined)
                              XSLT enrichment (yesterday) → End
```

### Steps

1. **Add a Router after the Content Modifier.** Branches:
   - `${header.X-Order-Format} = 'xml'` → existing Mapping branch.
   - `${header.X-Order-Format} = 'json'` → new branch.
   - `${header.X-Order-Format} = 'csv'` → new branch.
   - Default → set body to `{ "error": "unknown X-Order-Format" }` and route to End. (We're keeping it simple; full error handling is Week 4.)

2. **Add a Script step on the json branch** → upload `roiam_jsonOrderToCanonical.groovy` via the Script step's own dialog. **Important (project memory): never upload via the Resources tab first — that causes stale metadata.**

3. **Write the JSON script** at `script/v2/roiam_jsonOrderToCanonical.groovy`. (Project memory: v2 scripts go under `script/v2/`, not `script/`.)

   ```groovy
   import com.sap.it.script.v2.api.Message;
   import java.io.Reader;
   import java.io.StringWriter;
   import groovy.json.JsonSlurper;
   import groovy.xml.MarkupBuilder;

   def Message processData(Message message) {
       Reader reader = message.getBody(java.io.Reader);
       def order = new JsonSlurper().parse(reader);

       String orderId  = order.orderId  as String;
       String customer = order.customer as String;
       String currency = (order.currency as String)?.toUpperCase();
       Number total    = (order.totalAmount ?: 0) as Number;
       List lines      = (order.lines ?: []) as List;

       String priority = priorityFromAmount(total);

       StringWriter sw = new StringWriter();
       MarkupBuilder xml = new MarkupBuilder(sw);
       xml.CanonicalOrder {
           header {
               'orderId'(orderId);
               'customer'(customer);
               'currencyIso4217'(currency);
               'totalAmount'(total);
               'priority'(priority);
           }
           'lines' {
               lines.each { line ->
                   'line' {
                       'sku'(line.sku as String);
                       'quantity'((line.quantity ?: 0) as Number);
                       'lineTotal'(((line.quantity ?: 0) as BigDecimal) *
                                   ((line.unitPrice ?: 0) as BigDecimal));
                   }
               }
           }
           'totals' {
               'lineCount'(lines.size());
               'grandTotal'(total);
           }
       }

       def messageLog = messageLogFactory.getMessageLog(message);
       if (messageLog != null) {
           messageLog.setStringProperty("orderId", orderId ?: "");
           messageLog.addAttachmentAsString("canonical-from-json.xml",
               sw.toString(), "application/xml");
       }

       message.setHeader("X-Order-Id", orderId);
       message.setBody(sw.toString());
       return message;
   }

   String priorityFromAmount(Number total) {
       BigDecimal n = total as BigDecimal;
       if (n >= 100000g) return "HIGH";
       if (n >= 10000g)  return "MEDIUM";
       return "LOW";
   }
   ```

   Notice: semicolons, explicit types where it matters, helper method (not a class), `MessageLog` guarded for null, body read as Reader, properties never used (no need here).

4. **Write the CSV script** at `script/v2/roiam_csvOrderToCanonical.groovy`. The CSV is `sku,quantity,unitPrice` rows; the order header (id, customer, currency) comes from headers.

   ```groovy
   import com.sap.it.script.v2.api.Message;
   import java.io.Reader;
   import java.io.BufferedReader;
   import java.io.StringWriter;
   import groovy.xml.MarkupBuilder;

   def Message processData(Message message) {
       def headers = message.getHeaders();
       String orderId  = headers.get("X-Order-Id")  as String;
       String customer = headers.get("X-Customer")  as String;
       String currency = (headers.get("X-Currency") as String)?.toUpperCase();
       if (orderId == null || customer == null || currency == null) {
           throw new RuntimeException("CSV branch requires X-Order-Id, X-Customer, X-Currency headers");
       }

       BufferedReader reader = new BufferedReader(message.getBody(java.io.Reader));
       String hdr = reader.readLine();
       if (hdr == null) throw new RuntimeException("Empty CSV body");

       List<String> cols = hdr.split(",").collect { it.trim() };
       int iSku   = cols.indexOf("sku");
       int iQty   = cols.indexOf("quantity");
       int iPrice = cols.indexOf("unitPrice");
       if (iSku < 0 || iQty < 0 || iPrice < 0) {
           throw new RuntimeException("CSV header must contain sku,quantity,unitPrice");
       }

       List<Map> lines = new ArrayList<>();
       BigDecimal grand = 0g;
       String line;
       while ((line = reader.readLine()) != null) {
           if (line.trim().isEmpty()) continue;
           List<String> v = line.split(",", -1).collect { it.trim() };
           BigDecimal qty   = v[iQty]   as BigDecimal;
           BigDecimal price = v[iPrice] as BigDecimal;
           BigDecimal lineT = qty * price;
           grand += lineT;
           lines.add([sku: v[iSku], quantity: qty, lineTotal: lineT]);
       }

       String priority = priorityFromAmount(grand);

       StringWriter sw = new StringWriter();
       MarkupBuilder xml = new MarkupBuilder(sw);
       xml.CanonicalOrder {
           header {
               'orderId'(orderId); 'customer'(customer);
               'currencyIso4217'(currency); 'totalAmount'(grand);
               'priority'(priority);
           }
           'lines' {
               lines.each { l ->
                   'line' {
                       'sku'(l.sku);
                       'quantity'(l.quantity);
                       'lineTotal'(l.lineTotal);
                   }
               }
           }
           'totals' { 'lineCount'(lines.size()); 'grandTotal'(grand); }
       }

       def messageLog = messageLogFactory.getMessageLog(message);
       if (messageLog != null) {
           messageLog.setStringProperty("orderId", orderId);
           messageLog.addAttachmentAsString("canonical-from-csv.xml",
               sw.toString(), "application/xml");
       }

       message.setBody(sw.toString());
       return message;
   }

   String priorityFromAmount(BigDecimal n) {
       if (n >= 100000g) return "HIGH";
       if (n >= 10000g)  return "MEDIUM";
       return "LOW";
   }
   ```

5. **Save → version → deploy.** Test all three input shapes with `curl`:

   ```bash
   curl -u <u>:<p> -X POST "<url>" -H "X-Order-Format: json" \
        -H "Content-Type: application/json" -d @order_sample.json
   curl -u <u>:<p> -X POST "<url>" -H "X-Order-Format: xml" \
        -H "Content-Type: application/xml" --data-binary @vendor_order_sample.xml
   curl -u <u>:<p> -X POST "<url>" -H "X-Order-Format: csv" \
        -H "X-Order-Id: C-3001" -H "X-Customer: 50001" -H "X-Currency: usd" \
        -H "Content-Type: text/csv" --data-binary @order_sample.csv
   ```

6. **Inspect each MPL run.** Confirm:
   - The Groovy step appears in the Steps tree.
   - The `canonical-from-*.xml` attachment is visible.
   - The `orderId` is searchable in the MPL custom-search.
   - The XSLT enrichment fires after the script and the final response includes `<receivedAt>`, `<routingHint>`, etc.

### Failure cases to provoke

- Send empty JSON `{}`. Watch the script tolerate (or not) missing fields. Decide whether your defaults are sane.
- Send CSV without the `unitPrice` column. The script throws — by design. Confirm the error in Monitor and that the `MessageLog` attachment is **not** there (because the attachment write happens after the throw).
- Add `Thread.sleep(100)` somewhere "just to test". Watch the deploy fail. Replace with `sleep(100) { }`.

---

## Reference card excerpt — Day 2.3

- v2 import: `com.sap.it.script.v2.api.Message`. Every script.
- Always `message.getBody(java.io.Reader)`, parse the stream with `JsonSlurper.parse(reader)` / `XmlSlurper().parse(reader)`.
- `messageLogFactory.getMessageLog(message)` — **guard for null** (returns null when log level is None).
- `MessageLog.setStringProperty(name, value)` makes the value searchable in MPL custom-search.
- **No `Thread.sleep`** — use Groovy's `sleep(ms) { }`. **No top-level classes** — use methods inside the script.
- v2 scripts placed under `script/v2/`, named `roiam_*`. Upload via the Script step dialog, **not** the Resources tab.
- Streaming Reader + parse-once is the default for any payload over a few KB.
