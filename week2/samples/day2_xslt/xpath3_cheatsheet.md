# XPath 3.1 — the constructs you'll actually use in CI

## Selection

| Pattern | Example | Notes |
|---|---|---|
| Absolute | `/CanonicalOrder/header/priority` | Anchored at document root |
| Relative | `header/priority` | From the context node |
| Descendant | `//line` | Walks the whole tree — slow on large docs |
| Predicate | `line[Qty > 5]` | Filter |
| Position | `line[1]`, `line[last()]` | 1-indexed |
| Wildcard | `*`, `@*`, `node()` | All elements / all attrs / any node |

## Sequences and FLWOR

```xpath
for $l in /CanonicalOrder/lines/line
return $l/sku

let $sum := sum(/CanonicalOrder/lines/line/lineTotal)
return $sum

(: combined :)
for $l in line
let $tot := $l/quantity * $l/lineTotal
where $tot > 1000
return $l/sku
```

> `for` returns a sequence; `let` binds a variable; both fit inside `<xsl:value-of select="…"/>`.

## Pipeline with `=>`

```xpath
.=>normalize-space()=>upper-case()
```

Equivalent to `upper-case(normalize-space(.))`. Reads left-to-right like a Unix pipe.

## Conditionals

```xpath
if (priority='HIGH') then 'expedited' else 'standard'
```

Nested:
```xpath
if (priority='HIGH') then 'expedited'
else if (priority='MEDIUM') then 'normal'
else 'standard'
```

## Type-safe coercion

```xpath
@amount castable as xs:decimal       (: returns true/false :)
xs:decimal(@amount)                  (: cast — throws on failure :)
@amount instance of xs:string        (: type predicate :)
```

Use `castable as` *before* the cast inside `<xsl:choose>` to avoid runtime errors.

## String helpers

| Function | Example |
|---|---|
| `string-join(seq, sep)` | `string-join(line/sku, ',')` → `"A-100,A-205,B-200"` |
| `tokenize(str, regex)` | `tokenize('a,b,c', ',')` → `("a","b","c")` |
| `substring-before` / `-after` | `substring-before('A-100','-')` → `"A"` |
| `replace(str, regex, repl)` | `replace($x, '\s+', '_')` |
| `matches(str, regex)` | Boolean test |
| `lower-case` / `upper-case` / `normalize-space` | The everyday three |

## Dates

```xpath
current-dateTime()                                           (: 2026-06-22T14:31:07Z :)
format-dateTime(current-dateTime(),'[Y0001]-[M01]-[D01]')   (: ISO date only :)
xs:dateTime($s) + xs:dayTimeDuration('P1D')                  (: tomorrow :)
```

> Inside a single transform `current-dateTime()` is stable. Across transforms it varies — never compare full output verbatim in tests.

## JSON inside XSLT 3.1

```xpath
parse-json('{"a":1,"b":2}')           (: → a map :)
serialize($map, map{'method':'json'}) (: → JSON string :)
```

Useful when an iFlow accepts a JSON body but you still prefer XSL transformation logic — convert at the edges.

## Maps and arrays

```xpath
map{ 'sku': 'A-100', 'qty': 10 }
array{ 1, 2, 3 }

$m('sku')        (: map lookup :)
$arr(1)          (: array index, 1-indexed :)
```

> Rarely worth the syntax cost in everyday enrichment. Mostly useful with `parse-json` results.

## What NOT to use

- `xsl:variable` to imperatively accumulate state — XSLT variables are immutable. Use `xsl:iterate` for state-carrying loops.
- `position()`-driven logic where `xsl:for-each-group` would be cleaner.
- `//` at the start of templates that fire often — walk specific paths instead.
