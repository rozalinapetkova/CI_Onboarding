# `exf:` extension functions — the XSLT ↔ message bridge

Namespace declaration:

```xml
xmlns:exf="http://sap.com/it/"
```

## Read side

```xsl
<xsl:value-of select="exf:getHeader('correlationId')"/>
<xsl:value-of select="exf:getProperty('SkipProcessing')"/>

<!-- All headers / properties as a map (XPath 3.1) -->
<xsl:variable name="hdrs" select="exf:getHeaders()"/>
<xsl:value-of select="$hdrs('correlationId')"/>
```

## Write side — side effects

```xsl
<!-- Returned value is the empty string — we use value-of just to evaluate. -->
<xsl:value-of select="exf:setHeader('routingHint', 'expedited')"/>
<xsl:value-of select="exf:setProperty('orderCount', count(//order))"/>
```

> The function returns `""`. The visible effect is on the message envelope, not on the result document.

## The ordering trap

`exf:setHeader` evaluates during tree traversal. **The last evaluated call wins** — and that depends on which templates fire in what order.

Bad:

```xsl
<xsl:template match="header">
  <xsl:value-of select="exf:setHeader('routingHint','from-header-template')"/>
  ...
</xsl:template>

<xsl:template match="/CanonicalOrder">
  <xsl:value-of select="exf:setHeader('routingHint','from-root-template')"/>
  <xsl:copy><xsl:apply-templates/></xsl:copy>
</xsl:template>
```

Which value lands in the header? Depends on whether the root template's `setHeader` fires before or after the `apply-templates` walks into `header`. Don't write code that depends on this.

**Rule:** for each header/property name, call `setHeader` in **exactly one** template, ideally at the root.

## What you can't do

- **No HTTP/DB callouts.** `exf:` is purely header/property metadata. Use a Script step for callouts.
- **No looping with state.** Use `xsl:iterate` for that, not `exf:` writes inside `for-each`.
- **No headers across iFlows.** Headers set here affect this iFlow only. To carry into a ProcessDirect callee, put them on the ProcessDirect adapter's allow-list (see Day 1.4 sample).

## Practical pattern — single root-level header writer

```xsl
<xsl:template match="/CanonicalOrder">
  <!-- All header/property writes consolidated here -->
  <xsl:variable name="hint"
                select="if (header/priority='HIGH') then 'expedited' else 'standard'"/>
  <xsl:value-of select="exf:setHeader('routingHint', $hint)"/>
  <xsl:value-of select="exf:setProperty('orderCount', count(lines/line))"/>

  <xsl:copy>
    <xsl:apply-templates select="@*|node()"/>
  </xsl:copy>
</xsl:template>
```

Predictable. Easy to grep. The Day 2.2 reference XSL follows this pattern.
