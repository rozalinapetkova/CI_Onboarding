# Transformation decision matrix — pocket card

First match wins. Read top-down.

| # | Question | If yes | Notes |
|---|---|---|---|
| 1 | Can a Content Modifier *expression* do it? (`${header.X}`, `${property.Y}`, `simple` language) | **Content Modifier** | Almost free at runtime. Always try first. |
| 2 | Pure shape conversion JSON ↔ XML, no logic? | **JSON↔XML Converter step** | Don't reach for a mapping tool. |
| 3 | CSV / flat-file → XML, uniform structure? | **CSV-to-XML Converter** | Use Groovy only when rows need validation or branching. |
| 4 | Non-XML payload + business logic? (JSON↔JSON with conditionals, multipart, signatures) | **Groovy v2** | Streaming with `message.getBody(Reader)`. See Day 2.3. |
| 5 | XML → XML, mostly identity-transform with a few overrides or enrichments? | **XSLT 3.0** | Adds `<receivedAt>`, normalizes codes, drops fields. See Day 2.2. |
| 6 | XML → XML, schema-to-schema, mostly field-by-field with value lookups? | **Message Mapping** | The bread-and-butter case. Day 2.1 lab. |

## Anti-patterns

| Smell | Reach for |
|---|---|
| 500-line Groovy that does field-by-field XML → XML mapping | Message Mapping (you've reinvented it badly) |
| Message Mapping with 12 UDFs and complex conditionals | XSLT or Groovy — you've outgrown the visual editor |
| Two separate Message Mappings chained "to keep things modular" | One Message Mapping with grouped target structure |
| Groovy "router" that reads body and sets a property to pick a branch | Router step + Content Modifier expression |
| XSLT that does CSV parsing | Groovy |

## "Smallest tool" rule

Every escalation up this list costs maintainability. A junior can read a Content Modifier in 10 seconds; an XSLT in 5 minutes; a Groovy script in maybe 20 minutes. Pick the smallest tool that solves the problem cleanly, even if a "bigger" tool would be slightly faster to write today.
