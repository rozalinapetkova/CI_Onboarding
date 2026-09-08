# Day 2.1 — Mapping Decision Matrix + Message Mapping

> **Goal of the day.** Stop guessing which transformation tool to use. Build one solid Message Mapping with conditional logic, value mapping, and a UDF. By the end of the day you should be able to look at any transformation requirement and pick — within 30 seconds — between Message Mapping, XSLT, and Groovy.

## 1. Three transformation tools, one decision

Cloud Integration gives you three native ways to transform a payload:

| Tool | Strength | Weakness |
|---|---|---|
| **Message Mapping** | Visual, hierarchical drag-and-drop. Great for stable schema-to-schema mappings. Built-in **value mapping** lookups that don't require redeploy. Non-developers can read it. | Awkward for branching logic, awkward for non-XML, queue/context model has a learning cliff, version-control diffs are noisy XML. |
| **XSLT 3.0** | Declarative, exact XML control, excellent for *enrichment* passes (identity transform + a few overrides), grouping, recursive structures. Fast. | XML-only. Steep ramp for non-XSLT people. Verbose for simple field-by-field maps. |
| **Groovy v2** | Anything goes — JSON, CSV, binary, calling out to `MessageLog`, complex business rules. Streaming. | Easy to write *poorly*: blocking I/O, memory blow-ups, logic that nobody else can re-read in a year. The compiler can't catch schema drift. |

## 2. The decision matrix

Use this in order — first match wins.

1. **Is the payload non-XML and the transformation involves business logic that's awkward in XSLT?** → **Groovy v2.** (JSON↔JSON with conditionals, CSV parsing, signature generation, multipart assembly.)
2. **Is it XML-to-XML, mostly identity transform with a few overrides or enrichments?** → **XSLT 3.0.** (Adding `<receivedAt>`, normalizing codes, dropping fields.)
3. **Is it XML-to-XML, schema-to-schema, mostly straight field-mapping with maybe value lookups?** → **Message Mapping.** (Vendor XML → canonical XML, IDoc → canonical XML.)
4. **Is it JSON↔XML pure shape conversion with no business logic?** → **JSON↔XML Converter step** (no scripting). Don't reach for Message Mapping or Groovy for this.
5. **Is it CSV/flat-file → XML?** → **CSV-to-XML Converter** if the structure is uniform; **Groovy v2** if you need to validate / split / branch on rows.

Ambiguous cases — the rule of thumb is **smallest tool that solves the problem.** If a Content Modifier expression can do it, don't pull in a script. If XSLT can do it, don't pull in Groovy. Each escalation costs maintainability.

## 3. Message Mapping — the editor and its parts

Anatomy when you create a Message Mapping artifact:

```
┌──────────────────────────┐                         ┌──────────────────────────┐
│   Source structure       │                         │   Target structure       │
│   (left tree)            │ ───── mapping links ──▶ │   (right tree)           │
└──────────────────────────┘                         └──────────────────────────┘
                                       │
                                       ▼
                          ┌────────────────────────┐
                          │   Function bar         │  Standard / Constant / Variable / UDF
                          │   (between the trees)  │
                          └────────────────────────┘
                                       │
                                       ▼
                          ┌────────────────────────┐
                          │   Test tab             │  Drop a sample, see the result
                          └────────────────────────┘
```

Source and target structures are loaded from XSDs / WSDLs / EDMX you upload as **Resources** to the iFlow or to the package. The editor reads the schema and shows you the tree; if you change the XSD, you must reopen the mapping for the tree to refresh.

**Pre-mapping checklist:**

- Both schemas must be in the iFlow's *Resources* tab (or the package's *Schemas* folder).
- For repeating elements, check `minOccurs` / `maxOccurs` in the XSD — they drive how many *contexts* you'll deal with.
- For optional elements, decide *up front* whether the target should produce an empty tag, omit the tag, or default to a literal. This decision shapes the whole mapping.

## 4. Queues and contexts — the concept that trips everyone up

This is the single most confusing part of Message Mapping. Read it twice.

**The whole point of Message Mapping is that it operates on *queues of values*, not single values.** A queue is what you get when you trace a path from the root to a node. Every value in that queue is bracketed by *context markers* — `[CTX]` boundaries that tell the engine "this group of values belongs together."

Take a source like:

```xml
<Order>
  <Lines>
    <Line><Sku>A</Sku><Qty>2</Qty></Line>
    <Line><Sku>B</Sku><Qty>5</Qty></Line>
  </Lines>
</Order>
```

If you click `Sku` and inspect its queue, you'll see:

```
[CTX] A B [CTX]
```

Both `Sku` values are inside one context — the parent `Order`. Now if there were two `Order` elements, you'd see:

```
[CTX] A B [CTX] C D [CTX]
```

Two contexts. **The context boundary is what tells you "these values are grouped together."**

### Built-in context-aware functions

The Function bar's *Node Functions* group contains functions that *manipulate* contexts:

- **`removeContexts`** — flattens. `[CTX] A B [CTX] C [CTX]` → `[CTX] A B C [CTX]`. Use when you want to operate on all values regardless of grouping.
- **`splitByValue`** — inserts a context boundary at every value (or at every value change). Use when you have a flat list and want to map each item independently.
- **`collapseContexts`** — like `removeContexts` but only inside the immediate parent. Surgical version.
- **`mapWithDefault`** — emits a default if the queue is empty. Use to force a tag to appear even when the source is missing.
- **`exists`** / **`ifWithoutElse`** — boolean-style functions that emit an empty queue or a value depending on input.

**Practical rule:** when your mapping is producing the wrong number of target nodes, 9 times out of 10 it's a context issue. Click the target node, hit *Display Queue*, and look at the brackets.

## 5. UDFs (User-Defined Functions)

When the built-in functions can't express the rule, you write a UDF. UDFs in CI are JavaScript-only (no Groovy here — Groovy is in *Script* steps, not in mappings). They have three execution types:

| Execution type | What it gets per call | Use when |
|---|---|---|
| **Single Value** | One scalar value at a time | Simple per-value transforms (uppercase, regex extract) |
| **Context** | An array per context | You need to reduce a group of values (sum, average, concatenate-with-comma) |
| **All Values of a Queue** | The whole queue including context markers | Rarely. Cross-context logic. |

UDF skeleton:

```javascript
function priorityFromAmount(amount) {
    var n = parseFloat(amount);
    if (isNaN(n)) return "LOW";
    if (n >= 100000) return "HIGH";
    if (n >= 10000) return "MEDIUM";
    return "LOW";
}
```

UDFs live inside the Message Mapping artifact — they don't go to a Resources tab. They're invoked by drag-dropping them onto the mapping link.

## 6. Value mapping — lookups without redeploy

A **Value Mapping** is a tenant-wide lookup table — `(scheme1, key1) → (scheme2, key2)` — stored as an artifact and referenced by mappings via the `valueMapping` standard function.

**Why it matters:** changing a value-mapping entry **does not require redeploying any iFlow** that uses it. You change the artifact, save & deploy *the value mapping*, and downstream iFlows see the new value at the next message. This is the production lifeline for things like:

- Country-code translations (`DE` ↔ `Germany` ↔ `276`).
- Cost-center mappings between source and target ERPs.
- Product-classification lookups.

Compare this to hardcoding the lookup as a UDF inside the mapping — every change requires a fresh iFlow version + redeploy + retransport. The value-mapping pattern is *the* answer when business asks "can we change this without a release?"

**Default behaviour when the key isn't found:** the standard function offers three modes — *Default*, *Apply Source Value*, *Throw Exception*. Pick one consciously. The default `Default` mode silently emits the value you supply, which is friendly but can mask bad data.

## 7. Common mapping mistakes

Encountered every cohort:

1. **Forgetting `removeContexts` before a `concat`.** Concat respects contexts. Two source contexts → two concatenated outputs, not one combined string.
2. **Wrong cardinality on the target.** Mapping to an element with `maxOccurs="1"` from a queue with multiple values silently keeps only the first one (or fails at runtime). The editor shows a warning — read it.
3. **`mapWithDefault` on an unbounded element.** This produces *one* default-only output even when the source queue is empty across multiple contexts. Usually you want `ifWithoutElse(exists(...), ..., constant("default"))`.
4. **Constants with whitespace.** A constant `" XYZ"` with a leading space will surface in the output. The editor doesn't trim.
5. **Schema mismatch after re-uploading XSD.** When you replace an XSD, mappings to fields that moved or renamed *don't* automatically re-link — they go red. Always re-test after a schema upload.

---

## Hands-on lab — Vendor Order → Canonical Order via Message Mapping

> Time: ~3 hours. Goal: build a Message Mapping artifact that converts a vendor-specific `<VendorOrder>` XML to your canonical `<CanonicalOrder>` XML, using a value mapping for currency and a UDF for priority.

### Setup

The trainer has placed `vendor_order.xsd` and `canonical_order.xsd` in the shared training package's *Resources*. Sample inputs:

`vendor_order_sample.xml`:
```xml
<VendorOrder>
  <Hdr>
    <OrderId>V-90021</OrderId>
    <SoldTo>10001</SoldTo>
    <Curr>EUR</Curr>
    <TotalAmt>148500</TotalAmt>
  </Hdr>
  <Itm>
    <Sku>A-100</Sku><Qty>10</Qty><UnitPrice>1200</UnitPrice>
  </Itm>
  <Itm>
    <Sku>B-200</Sku><Qty>5</Qty><UnitPrice>27300</UnitPrice>
  </Itm>
</VendorOrder>
```

`canonical_order.xsd` defines `<CanonicalOrder>` with:
- `<header>` containing `<orderId>`, `<customer>`, `<currencyIso4217>`, `<totalAmount>`, `<priority>`
- `<lines>` with repeating `<line>` containing `<sku>`, `<quantity>`, `<lineTotal>`
- `<totals>` with `<lineCount>`, `<grandTotal>`

### Steps

1. **Create the iFlow.** Design → Training package → New Integration Flow → `roi_<your_initials>_OrderHub` (this is the same iFlow you'll evolve all the way through Week 4 — pick the name once, keep it).
   - Sender HTTPS at `/http/orderhub/orders/<your-initials>`. MEP Request-Reply. CSRF off.
   - Add a Content Modifier that sets header `X-Order-Format` defaulting to `xml` (we'll branch later).
   - Add a *Message Mapping* step.

2. **Create the Message Mapping artifact.** Inside the iFlow, click the Message Mapping step → *Create new mapping*.
   - Source: load `vendor_order.xsd`. Target: load `canonical_order.xsd`.
   - Name: `mm_<your_initials>_VendorOrderToCanonical`.

3. **Field-by-field mapping.**
   - `Hdr/OrderId` → `header/orderId` (drag).
   - `Hdr/SoldTo` → `header/customer`.
   - `Hdr/TotalAmt` → `header/totalAmount`.
   - `Itm/Sku` → `lines/line/sku`.
   - `Itm/Qty` → `lines/line/quantity`.
   - For `lines/line/lineTotal` — drag `Qty` and `UnitPrice` into a *multiply* function, then connect output to `lineTotal`.

4. **Value mapping for currency.**
   - Create a new Value Mapping artifact in the package: `vm_<your_initials>_CurrencyCodes`.
   - Source agency `VENDOR`, identifier `CURR`. Target agency `ISO`, identifier `4217`.
   - Add rows: `EUR → EUR`, `USD → USD`, `GBP → GBP`, `CHF → CHF`. (Yes the values are the same — your vendor sometimes sends `Euro` instead of `EUR`; that row catches it.)
   - In the mapping, drag `Curr` to a *valueMapping* standard function. Configure source/target agencies/identifiers. Set "If no mapping found" to *Throw Exception* — bad data should not be silent.
   - Connect output to `header/currencyIso4217`.

5. **UDF for priority.**
   - In the mapping, *Functions* tab → *Create UDF* → execution type *Single Value* → name `priorityFromAmount` → arg `amount`.
   - Body:
     ```javascript
     function priorityFromAmount(amount) {
         var n = parseFloat(amount);
         if (isNaN(n)) return "LOW";
         if (n >= 100000) return "HIGH";
         if (n >= 10000) return "MEDIUM";
         return "LOW";
     }
     ```
   - Drag `TotalAmt` → UDF → connect to `header/priority`.

6. **Totals.**
   - `lines/line` queue → *count* node-function → `totals/lineCount`.
   - `lineTotal` (the computed value) → *sum* function → `totals/grandTotal`. *Hint: you may need `removeContexts` first if the sum picks up only one line; that's the lesson on context.*

7. **Test it inside the mapping editor.** *Test* tab → paste `vendor_order_sample.xml` → run → inspect the canonical XML output.

8. **Wire it into the iFlow.** Save mapping → return to iFlow canvas → ensure the Message Mapping step references your `mm_<your_initials>_VendorOrderToCanonical` artifact → save iFlow → version → deploy.

9. **Test end-to-end:**
   ```bash
   curl -u <u>:<p> -X POST "<runtime-url>" \
        -H "X-Order-Format: xml" \
        -H "Content-Type: application/xml" \
        --data-binary "@vendor_order_sample.xml"
   ```

10. **Inspect in Monitor.** Confirm the *Steps* tree shows the Message Mapping step. Click into it — the trace shows source and target XML.

### Failure cases to provoke

- Send a payload with `<Curr>YEN</Curr>` (not in the value mapping). Mapping fails because you set "Throw Exception". Check the error in Monitor.
- Send a payload with a non-numeric `<TotalAmt>`. Watch the UDF fall through to `LOW` — by design.
- Drop a `<Hdr>` block entirely. The mapping fails on cardinality. Read the runtime exception carefully.

---

## Reference card excerpt — Day 2.1

- **Decision order:** Message Mapping (XML schema-to-schema) → XSLT (XML enrichment / identity-transform-with-overrides) → Groovy (JSON / CSV / business logic / non-XML).
- **Queues + contexts:** every node is a queue of values bracketed by `[CTX]`. Wrong cardinality? Inspect the queue. Use `removeContexts` to flatten, `splitByValue` to subdivide.
- **UDF execution types:** Single Value / Context / All Values of a Queue. Pick the smallest scope that works.
- **Value mapping:** lookup table artifact, **changes do not require iFlow redeploy.** Always set "If no mapping found" consciously.
- **Editor caveat:** XSD changes need a mapping reopen; some links may go red.
