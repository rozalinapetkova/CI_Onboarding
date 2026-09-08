# XSLT failure cases — what happens and why

The lab asks you to provoke these. Here are the expected outcomes.

## 1. Empty `<currencyIso4217>`

Input:
```xml
<currencyIso4217></currencyIso4217>
```

Without the `<xsl:choose>` guard in the reference stylesheet, the `upper-case(normalize-space(.))` evaluates to the empty string. The output element is `<currencyIso4217></currencyIso4217>` — preserved but useless.

With the guard:
```xsl
<xsl:when test="normalize-space(.)=''">
  <xsl:text>EUR</xsl:text>
</xsl:when>
```
Output: `<currencyIso4217>EUR</currencyIso4217>`. **Document this default** on the iFlow card — silent defaults are technical debt.

## 2. Missing `<header>` entirely

Input: only `<lines>` and `<totals>`.

Identity transform copies what's there. **The `match="CanonicalOrder/header"` template never fires** because there's nothing to match. So `<receivedAt>` and `<routingHint>` never appear.

The `match="/CanonicalOrder"` template still fires — including the `setHeader('routingHint',...)` side effect — but because `header/priority` is absent, the `if` returns `'standard'`. The runtime header gets set to `standard` regardless.

**Lesson:** if you need to *guarantee* a `<header>` exists in the output, don't rely on the identity transform plus an override. Either:
- Construct `<header>` unconditionally in the root template, or
- Validate the input against an XSD upstream.

## 3. Unknown root element wrapping the canonical order

Input:
```xml
<Envelope>
  <CanonicalOrder>...</CanonicalOrder>
</Envelope>
```

The override templates have absolute-ish path implications: `match="CanonicalOrder/header"` matches **any** `CanonicalOrder/header`, so they still fire. **But** `match="/CanonicalOrder"` is absolute — it requires `CanonicalOrder` to be the root. Wrapped in `<Envelope>`, that template doesn't fire, the header isn't set on the message envelope, and the side-effect-driven `routingHint` is missing.

**Lesson:** absolute path templates (`/X`) are brittle. Prefer non-anchored patterns (`X` or `*[local-name()='X']`) when payload shape isn't guaranteed. Or unwrap the envelope in a separate step before the enrichment.

## 4. Source has a default namespace

Input:
```xml
<CanonicalOrder xmlns="http://example.com/canonical">
  ...
</CanonicalOrder>
```

**Every override template misses.** `match="CanonicalOrder"` looks for the no-namespace element and finds nothing. The identity transform fires for everything (it uses `node()` which is namespace-agnostic), so output equals input — no enrichment.

Fix:
```xml
xmlns:co="http://example.com/canonical"
...
<xsl:template match="co:CanonicalOrder/co:header">
```

**This is the most-common XSLT bug in CI.** Always check the source namespace before writing match patterns.

## 5. Non-numeric `<totalAmount>` reaching `sum()`

Not exercised by this stylesheet (we don't aggregate `totalAmount`), but generally:

```xpath
sum(line/lineTotal)
```

If any `lineTotal` is non-numeric, `sum` raises `FORG0006`. Wrap in `xsl:try` only if you've decided what graceful degradation looks like — otherwise let it fail loud.
