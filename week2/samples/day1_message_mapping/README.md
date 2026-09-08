# Day 2.1 samples — Message Mapping

Samples for the Vendor Order → Canonical Order mapping lab.

| File | Purpose |
|---|---|
| `vendor_order.xsd` | Source schema |
| `canonical_order.xsd` | Target schema |
| `vendor_order_sample.xml` | Happy-path input |
| `canonical_order_expected.xml` | Expected mapping output |
| `vendor_order_bad_currency.xml` | Triggers value-mapping "Throw Exception" |
| `vendor_order_missing_header.xml` | Triggers cardinality failure |
| `vm_CurrencyCodes.csv` | Value Mapping rows, CSV import format |
| `udf_priorityFromAmount.js` | UDF body |
| `mapping_links.md` | Field-by-field mapping link table |
| `decision_matrix.md` | Quick-pick decision matrix (MM / XSLT / Groovy / Converter steps) |
