# Router — branching by `X-Order-Format`

The Router step sits right after the initial Content Modifier and dispatches by header.

## Branches (top-to-bottom — order matters)

| # | Condition (Camel Simple) | Target |
|---|---|---|
| 1 | `${header.X-Order-Format} = 'xml'` | Message Mapping branch (Day 2.1) |
| 2 | `${header.X-Order-Format} = 'json'` | Script `roiam_jsonOrderToCanonical` |
| 3 | `${header.X-Order-Format} = 'csv'` | Script `roiam_csvOrderToCanonical` |
| Default | *(unconditional)* | Content Modifier sets `{"error":"unknown X-Order-Format"}` → End |

## Why the default branch is mandatory

A Router without a default branch throws `RuntimeCamelException: no matching when clause for body` at runtime. The exception is unhelpful — the MPL just shows "Failed" with a stack trace. Always wire a default, even if it just sets an error body and routes to End.

## Where conditions go

In the Router's *Routing Rules* table:
- **Expression Type:** XPath or Non-XML — choose **Non-XML** for header tests.
- **Expression:** `${header.X-Order-Format}`
- **Value:** the literal string (no quotes in the UI field — CPI adds them).

The generated Camel expression in the iFlow XML looks like:
```xml
<bpmn2:conditionExpression xsi:type="bpmn2:tFormalExpression">${header.X-Order-Format} = 'json'</bpmn2:conditionExpression>
```

## Common mistakes

- **Case mismatch.** `X-Order-Format: JSON` vs `'json'` in the rule → falls through to default. Either normalize in the Content Modifier (`setHeader("X-Order-Format", "${header.X-Order-Format,lowercase}")`) or write three rules covering case variants.
- **Default branch unreachable.** Putting the default *first* in the table makes it match before anything else. The order in the rules table is the evaluation order.
- **Using `==` instead of `=`.** Camel Simple uses single `=`. Double `==` works in some versions but is not the documented syntax — stick to single `=`.
