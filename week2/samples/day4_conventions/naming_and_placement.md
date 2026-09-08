# Naming and placement — where every file lives

## Script naming

| Component | Rule |
|---|---|
| Prefix | `roiam_` (lowercase, underscore-suffixed) |
| Body | camelCase verb-phrase describing the job |
| Extension | `.groovy` |

| Right | Wrong | Why wrong |
|---|---|---|
| `roiam_jsonOrderToCanonical.groovy` | `JsonOrderToCanonical.groovy` | Missing prefix; PascalCase |
| `roiam_loadGrcProxyConfig.groovy` | `roiam-load-grc-proxy-config.groovy` | Kebab-case |
| `roiam_validateOrder.groovy` | `roiam_Validate_Order.groovy` | Snake_Case + mixed caps |
| `roiam_buildRequestSignature.groovy` | `signer.groovy` | No prefix, vague name |

When in doubt, name it after the **verb-phrase that describes the script's job** — that's also a good check that the script *has* a single job.

## Folder layout — repository

```
scripts/
├── standalone/                          ← reusable across iFlows
│   ├── roiam_jsonValidator.groovy
│   ├── roiam_loadGrcProxyConfig.groovy
│   └── roiam_bodySigner.groovy
└── collections/
    └── <project-name>/                  ← all scripts for one iFlow
        ├── roiam_mapOrderItems.groovy
        └── roiam_setHeaders.groovy
```

| Location | When to use |
|---|---|
| `scripts/standalone/` | Script solves a generic problem and could be copied into multiple iFlows. Signature builder, JSON validator, PD lookup helper. |
| `scripts/collections/<project>/` | Script only makes sense inside one iFlow. Folder name is the iFlow name. |

## Folder layout — inside an iFlow project

```
<iFlowId>/
└── src/
    └── main/
        └── resources/
            ├── script/
            │   └── v2/                  ← v2 scripts ONLY here
            │       ├── roiam_jsonOrderToCanonical.groovy
            │       └── roiam_csvOrderToCanonical.groovy
            ├── xslt/
            │   └── xslt_<initials>_EnrichCanonicalOrder.xsl
            ├── mapping/
            │   └── mm_<initials>_VendorToCanonical.mmap
            └── value-mapping/
                └── vm_CurrencyCodes/
```

**The `v2/` subfolder is the runtime marker.** Files in plain `script/` are loaded with the v1 engine even if the import says v2 — silent downgrade, surprising failures. Always `script/v2/`.

## Changelog placement

Changelogs go **outside** the iFlow folder, at the repo root:

```
changelog/
└── <iFlowId>/
    ├── 2026-06-08_initial_iflow.txt
    ├── 2026-06-09_add_xslt_enrichment.txt
    └── 2026-06-11_csv_branch_added.txt
```

Why outside? Because the iFlow folder is what gets zipped and shipped to the CI tenant. Internal commentary doesn't belong in the deployable artifact.

## Other artifact naming

| Artifact | Pattern | Example |
|---|---|---|
| iFlow | `roi_<initials>_<Purpose>` | `roi_amk_OrderHub` |
| Message Mapping | `mm_<initials>_<Purpose>` | `mm_amk_VendorToCanonical` |
| Value Mapping | `vm_<Purpose>` | `vm_CurrencyCodes` |
| XSLT | `xslt_<initials>_<Purpose>` | `xslt_amk_EnrichCanonicalOrder` |
| Groovy script | `roiam_<purpose>` | `roiam_jsonOrderToCanonical` |
