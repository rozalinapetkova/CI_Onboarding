# Mapping links — `mm_<initials>_VendorOrderToCanonical`

Each row is one mapping link in the editor. Drag from source → target unless a function is in between.

| Source | Function chain | Target | Notes |
|---|---|---|---|
| `Hdr/OrderId` | — | `header/orderId` | Direct |
| `Hdr/SoldTo` | — | `header/customer` | Direct |
| `Hdr/Curr` | `valueMapping(VENDOR/CURR → ISO/4217, mode=ThrowException)` | `header/currencyIso4217` | Uses `vm_<initials>_CurrencyCodes` |
| `Hdr/TotalAmt` | — | `header/totalAmount` | Direct (decimal coercion at target) |
| `Hdr/TotalAmt` | `priorityFromAmount` (UDF, Single Value) | `header/priority` | See `udf_priorityFromAmount.js` |
| `Itm/Sku` | — | `lines/line/sku` | One-to-one, queue carries the context |
| `Itm/Qty` | — | `lines/line/quantity` | One-to-one |
| `Itm/Qty` + `Itm/UnitPrice` | `multiply` (standard arithmetic) | `lines/line/lineTotal` | Two inputs into the function |
| `Itm` | `count` (node function) | `totals/lineCount` | Counts nodes per context |
| `(computed) lineTotal` | `removeContexts` → `sum` | `totals/grandTotal` | **`removeContexts` first** — without it the sum collapses inside per-line contexts and returns the first line's value |

## Context-issue debugging shortcut

If `totals/grandTotal` shows `12000` instead of `148500`, that's the classic context bug: the `sum` is running inside each line's context, so it sums a single value. Insert `removeContexts` upstream of `sum`. Same fix pattern applies any time a reduce-style function gives one-per-context output instead of a single rollup.

## Conscious choices to document on the iFlow card

- `valueMapping` mode = **Throw Exception** (chose loud failure over silent default — see Day 2.1 reference card).
- `priorityFromAmount` falls through to `LOW` on non-numeric input. Intentional — bad data shouldn't escalate to HIGH.
- `lineCount` uses `count`, not `count-with-context-handling` — works because `Itm` is unbounded inside one parent.
