# Day 2.2 — XSLT 3.0 / XPath 3.1 in Cloud Integration

> **Goal of the day.** Get fluent enough in XSLT 3.0 to write enrichment passes, exclusion templates, and grouped output. By the end of the day, you should never reach for Groovy when XSLT would do — and you should know when XSLT is the wrong tool too.

## 1. Why XSLT belongs in your toolbox

You will hear "just use Groovy for everything" from people who never learned XSLT. They're wrong, and you should not become one of them. XSLT 3.0 is:

- **Declarative.** You describe the output, not the loop.
- **Fast.** The Saxon-HE engine in CI is heavily optimized for streaming and node-set operations.
- **Concise** for enrichment / identity-transform-with-overrides — three-line XSLT replaces fifty lines of Groovy DOM manipulation.
- **Readable** by anyone who knows XML — including people who can't read Groovy.
- **Schema-aware** — if your runtime has the schema, you can validate inline.

XSLT is the wrong tool when:
- The payload isn't XML (JSON, CSV, binary).
- The transformation needs to call out (HTTP, DB, MessageLog).
- Business logic involves mutable state or multi-pass algorithms.

## 2. The XSLT 3.0 step in CI

The *XSLT 3.0 Mapping* step takes a `.xsl` file from the iFlow's Resources tab. The engine is **Saxon-HE 9.x**. Practical implications:

- XPath **3.1** is fully available — `array{}`, `map{}`, `let`, `for`, `=>` chaining, `xsl:try`/`xsl:catch`, `xsl:iterate`, JSON parse / serialize functions.
- The XSLT step can read `<headers>` and `<properties>` via the **`exf:` extension namespace**:
  ```xsl
  xmlns:exf="http://sap.com/it/"
  …
  <xsl:value-of select="exf:getHeader('correlationId')"/>
  <xsl:value-of select="exf:getProperty('SkipProcessing')"/>
  ```
- And **set** them on the way out:
  ```xsl
  exf:setHeader('routingHint', 'expedited')
  exf:setProperty('orderCount', count(//order))
  ```
- The result document becomes the new message body. If you want to *also* write a header, the `exf:setHeader` call is evaluated as a side effect during the transform.

## 3. The identity transform — your starting point

Every enrichment XSL begins from the **identity transform**: copy everything as-is, then override the bits you want to change.

```xsl
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <!-- Identity: copy everything by default -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>
```

That's it. Drop this on any XML, you get the same XML back. Now you add overrides. **Want to drop an element?** Add an empty template:

```xsl
<xsl:template match="DebugInfo"/>
```

**Want to rename it?**

```xsl
<xsl:template match="OldName">
  <NewName><xsl:apply-templates select="@*|node()"/></NewName>
</xsl:template>
```

**Want to add a child?**

```xsl
<xsl:template match="Order/Header">
  <xsl:copy>
    <xsl:apply-templates select="@*|node()"/>
    <receivedAt><xsl:value-of select="current-dateTime()"/></receivedAt>
  </xsl:copy>
</xsl:template>
```

The pattern: **identity transform + a few `match` overrides**. This is *the* mental model.

## 4. XPath 3.1 essentials you'll actually use

| Construct | Example | Why |
|---|---|---|
| Predicate | `Line[Qty > 5]` | Filter |
| `for` expression | `for $l in Line return $l/Sku` | Map (returns a sequence) |
| `let` | `let $sum := sum(Line/Qty) return $sum` | Local variable |
| `if`/`then`/`else` | `if (.='X') then 'A' else 'B'` | Inline conditional |
| `=>` chain | `.=>upper-case()=>normalize-space()` | Pipeline |
| `string-join` | `string-join(Sku, ',')` | CSV-ify a sequence |
| `tokenize` | `tokenize(., ',\s*')` | Parse CSV-ish strings |
| `format-dateTime` | `format-dateTime(current-dateTime(),'[Y0001]-[M01]-[D01]')` | Output formatting |
| `parse-json` | `parse-json($body)` | Parse JSON inside XSLT (3.1) |
| `xsl:iterate` | streamed iteration with state | Loop with running totals |

You won't memorize all of these — but recognize them in code so you can read XSL written by your team.

## 5. Grouping with `xsl:for-each-group`

When you need SQL-style `GROUP BY` in XSLT, this is it:

```xsl
<xsl:for-each-group select="Order/Line" group-by="Category">
  <category name="{current-grouping-key()}">
    <xsl:for-each select="current-group()">
      <line><xsl:value-of select="Sku"/></line>
    </xsl:for-each>
    <subtotal><xsl:value-of select="sum(current-group()/LineTotal)"/></subtotal>
  </category>
</xsl:for-each-group>
```

Group attributes:
- `group-by="expr"` — equivalent SQL `GROUP BY`.
- `group-adjacent="expr"` — group only consecutive items with same key (useful for run-length structures).
- `group-starting-with="pattern"` — groups starting at each match of pattern.
- `group-ending-with="pattern"` — groups ending at each match.

## 6. Error handling in XSLT 3.0 — `xsl:try`

```xsl
<xsl:try>
  <amount><xsl:value-of select="xs:decimal(@amount)"/></amount>
  <xsl:catch errors="*:FORG0001">
    <amount>0</amount>
  </xsl:catch>
</xsl:try>
```

Use sparingly. XSLT idiom is to *test before you transform*, not catch exceptions:

```xsl
<xsl:choose>
  <xsl:when test="@amount castable as xs:decimal">
    <amount><xsl:value-of select="@amount"/></amount>
  </xsl:when>
  <xsl:otherwise>
    <amount>0</amount>
  </xsl:otherwise>
</xsl:choose>
```

`castable as` and `instance of` are your friends.

## 7. Performance and streaming

XSLT 3.0 supports **streaming mode** (`xsl:mode streamable="yes"`) for very large XML documents. Saxon-HE in CI supports this with restrictions. For most CI iFlows, payloads are small enough that streaming is unnecessary. **But** know it exists for the day someone hands you a 500 MB IDoc batch.

When writing non-streaming XSL:
- Avoid `//foo` as the root pattern of large templates — it walks the full tree.
- Use specific paths (`/Order/Lines/Line`) where possible.
- Don't chain multiple `<xsl:apply-templates>` over the same nodeset when one with a mode parameter will do.

## 8. The `exf` extension functions you'll use

| Function | Purpose |
|---|---|
| `exf:getHeader('name')` | Read a message header |
| `exf:getProperty('name')` | Read a message property |
| `exf:setHeader('name','value')` | Set a header (side effect) |
| `exf:setProperty('name','value')` | Set a property (side effect) |
| `exf:getHeaders()` / `exf:getProperties()` | All headers / properties as a map |

**Side-effect ordering caveat:** `exf:setHeader` is evaluated during XSL execution, not before/after. If you have multiple writes to the same header, the *last evaluated* wins — which depends on tree traversal order. Don't depend on order; set each header in exactly one place.

## 9. Common XSLT pitfalls in CI

1. **Forgetting the namespace declaration** on the source root. If the source has `xmlns="http://example.com"` and your XSL doesn't bind that prefix and use it in match patterns, your `match="Order"` matches nothing. *Every*-cohort issue.
2. **Confusing `<xsl:value-of>` with `<xsl:copy-of>`.** `value-of` outputs a string; `copy-of` outputs nodes (preserves children/attributes). For copying sub-trees, use `copy-of`.
3. **Identity-transform precedence with attribute overrides.** Adding an attribute via a template doesn't auto-replace the source attribute — the identity template fires first. Use `<xsl:attribute name="x">…</xsl:attribute>` *inside* the override and don't apply-templates over the attribute.
4. **`current-dateTime()` non-determinism.** During a single transform, it's stable; across re-tests it changes. Don't write tests that compare full output verbatim — compare structurally.
5. **Result document encoding.** Default is `UTF-8` — usually fine, but if a downstream expects something else, set `<xsl:output encoding="…"/>`. Don't manually inject a BOM.

---

## Hands-on lab — Canonical Order enrichment XSL

> Time: ~3 hours. Goal: write an XSLT 3.0 stylesheet that, given a `<CanonicalOrder>` (output from yesterday's mapping), enriches it with: a `<receivedAt>` timestamp from `current-dateTime()`, a `<routingHint>` derived from the priority (`HIGH` → `expedited`, others → `standard`), normalizes `<currencyIso4217>` to upper-case, and groups lines by SKU prefix.

### Setup

You already have a sample canonical XML from yesterday. Save it as `canonical_sample.xml` in the iFlow's Resources tab.

### Steps

1. **Add an XSLT 3.0 step** to `roi_<your_initials>_OrderHub` *after* the Message Mapping. Wire the canvas:
   ```
   Sender → Content Modifier → Router → Message Mapping (xml branch) → XSLT enrichment → Receiver/End
   ```
   *(For the json/csv branches, the Router will go elsewhere — that's tomorrow.)*

2. **Create the XSL file.** Right-click iFlow Resources → New → XSL Mapping → name `xslt_<your_initials>_EnrichCanonicalOrder.xsl`.

3. **Start with identity transform:**

   ```xsl
   <?xml version="1.0" encoding="UTF-8"?>
   <xsl:stylesheet version="3.0"
                   xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                   xmlns:exf="http://sap.com/it/"
                   xmlns:xs="http://www.w3.org/2001/XMLSchema">

     <xsl:output method="xml" indent="yes"/>

     <xsl:template match="@*|node()">
       <xsl:copy>
         <xsl:apply-templates select="@*|node()"/>
       </xsl:copy>
     </xsl:template>

   </xsl:stylesheet>
   ```

4. **Add `<receivedAt>` to the header:**

   ```xsl
   <xsl:template match="CanonicalOrder/header">
     <xsl:copy>
       <xsl:apply-templates select="@*|node()"/>
       <receivedAt><xsl:value-of select="format-dateTime(current-dateTime(),
         '[Y0001]-[M01]-[D01]T[H01]:[m01]:[s01]Z')"/></receivedAt>
     </xsl:copy>
   </xsl:template>
   ```

5. **Add `<routingHint>` based on priority.** Override the `priority` element so we can see both:

   ```xsl
   <xsl:template match="header/priority">
     <xsl:copy-of select="."/>
     <routingHint>
       <xsl:value-of select="if (.='HIGH') then 'expedited' else 'standard'"/>
     </routingHint>
   </xsl:template>
   ```

6. **Normalize currency to upper-case:**

   ```xsl
   <xsl:template match="header/currencyIso4217">
     <xsl:copy>
       <xsl:value-of select="upper-case(normalize-space(.))"/>
     </xsl:copy>
   </xsl:template>
   ```

7. **Set a header `routingHint` on the message** (so a downstream router can read it without parsing the body):

   ```xsl
   <xsl:template match="/CanonicalOrder">
     <xsl:variable name="hint"
       select="if (header/priority='HIGH') then 'expedited' else 'standard'"/>
     <xsl:value-of select="exf:setHeader('routingHint', $hint)"/>
     <xsl:copy>
       <xsl:apply-templates select="@*|node()"/>
     </xsl:copy>
   </xsl:template>
   ```

8. **Group lines by SKU prefix** — emit a `<grouped>` block alongside the original `<lines>`:

   ```xsl
   <xsl:template match="CanonicalOrder/lines">
     <xsl:copy>
       <xsl:apply-templates select="@*|node()"/>
     </xsl:copy>
     <grouped>
       <xsl:for-each-group select="line" group-by="substring(sku,1,1)">
         <group prefix="{current-grouping-key()}">
           <xsl:for-each select="current-group()">
             <sku><xsl:value-of select="sku"/></sku>
           </xsl:for-each>
         </group>
       </xsl:for-each-group>
     </grouped>
   </xsl:template>
   ```

9. **Save → version → deploy.** Test end-to-end with the same `curl` call as yesterday. Inspect the output: you should see `<receivedAt>`, `<routingHint>` after `<priority>`, currency in upper-case, and a `<grouped>` block. Headers panel in Monitor should show `routingHint`.

### Failure cases to provoke

- Send a payload with `<currencyIso4217></currencyIso4217>` (empty). Watch the upper-case template emit empty — that's fine, but think: should you be defaulting to a value here? Refactor with `if (normalize-space(.)='')` to default.
- Send a payload missing `<header>`. The identity copy still works for the rest, but `<receivedAt>` doesn't appear — `<header>` template never fires. Discuss with the trainer: how would you make this "ensure a header element exists" idempotent?
- Add an unknown root element wrapping the canonical order. Watch the override templates not fire. Lesson: paths are absolute when they start with `/`.

---

## Reference card excerpt — Day 2.2

- **XSLT 3.0 belongs in CI** — pick it for XML→XML enrichment / identity-with-overrides / grouping.
- **Identity transform** is `<xsl:template match="@*|node()"><xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy></xsl:template>`. Memorize it.
- **Drop element:** empty `match`. **Rename:** wrap apply-templates. **Add child:** copy + apply + new node.
- `exf:getHeader/setHeader/getProperty/setProperty` for message integration. Don't depend on side-effect order.
- `xsl:for-each-group` does GROUP BY; `xsl:try`/`xsl:catch` for error containment; `castable as`/`instance of` for safe coercion.
- Forgetting source-namespace declarations is the #1 mistake. Always declare and prefix.
