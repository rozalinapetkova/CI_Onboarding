# Day 2.3 samples — Groovy v2 essentials

Materials for the Day 2.3 lab: JSON and CSV branches of the Order Translator.

| File | Purpose |
|---|---|
| `order_sample.json` | Happy-path JSON input for the json branch |
| `order_sample.csv` | Happy-path CSV input (headers: sku,quantity,unitPrice) for the csv branch |
| `order_empty.json` | Failure case — `{}`. Tests default behavior |
| `order_missing_unitprice.csv` | Failure case — header lacks unitPrice column |
| `canonical_from_json_expected.xml` | Expected `<CanonicalOrder>` from `order_sample.json` |
| `canonical_from_csv_expected.xml` | Expected `<CanonicalOrder>` from `order_sample.csv` + headers |
| `roiam_jsonOrderToCanonical.groovy` | Reference v2 script for json branch |
| `roiam_csvOrderToCanonical.groovy` | Reference v2 script for csv branch |
| `script_step_config.md` | Script step settings, upload procedure, `script/v2/` placement |
| `router_branch_config.md` | Router branch conditions on `X-Order-Format` |
| `curl_examples.sh` | Curl invocations for all three branches |
| `restricted_classes_demo.groovy` | Wrong-vs-right: `Thread.sleep` vs `sleep(ms){}` |
| `messagelog_pattern.md` | The null-guard pattern, custom search property, attachment lifetime |
