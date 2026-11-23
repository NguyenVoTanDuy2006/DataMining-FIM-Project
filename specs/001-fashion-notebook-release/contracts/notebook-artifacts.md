# Notebook Artifact Contracts

Release artifacts are rooted at `results/fashion/release/<run_id>/`; manifest paths are repository-relative and resolve from the recorded repository root. Each notebook reads only artifacts named in the prior notebook's manifest and rejects a schema-version, run-ID, or SHA-256 mismatch.

## Directory Layout

```text
<run_id>/
├── dataset/
│   ├── dataset_manifest.toml
│   └── sample_images/                 # optional rendered examples
├── transactions/
│   ├── tc7_manifest.toml
│   ├── transactions.jsonl
│   ├── tid_image_mapping.csv
│   ├── image_metadata.csv
│   ├── patch_assignments.csv
│   ├── centroids.csv
│   └── codebook.bin
├── mining/
│   ├── manifest.toml
│   ├── set/<support-percent>/itemsets.jsonl
│   ├── bitvector/<support-percent>/itemsets.jsonl
│   ├── comparison.csv
│   ├── parity_audit.json
│   ├── itemset_selection_candidates.csv
│   ├── representative_patterns.csv
│   ├── selection_manifest.toml
│   └── selected_itemsets.csv
├── interpretation/
│   ├── interpretation_manifest.toml
│   ├── pattern_gallery/
│   ├── retrieval_examples.csv
│   ├── pattern_annotations.csv
│   └── interpretation_summary.json
└── report/
    └── fashion_mnist_release_report.md
```

## Manifest Rules

- `dataset_manifest.toml` records `schema_version`, `run_id`, dataset name/source, four archive paths and hashes, train/test counts, image shape, class count, canonical image-ID rule, validation status, and creation time.
- `tc7_manifest.toml` records the parent dataset-manifest path/hash, exact B0/K=32/seed=123/S0 settings, image/transaction counts, transaction path/hash, codebook/assignment/mapping/metadata paths and hashes, support denominator, and TC7 status.
- The mining manifest records the TC7 manifest hash, transaction hash, backend names, the six percentage/count pairs, worker source hashes, Julia/Python/runtime details, systemd limits, output directories, and overall status. Backend-specific run manifests carry their own status and timing/RSS fields.
- `interpretation_manifest.toml` records the mining and TC7 manifest hashes, selected-itemset file hash, evidence paths/hashes, retrieval audit status, and review status.
- Every artifact path is repo-relative; consumers resolve it from the recorded repository root, not from the process's current working directory.

## Row Formats

### Transactions (`transactions.jsonl`)

One JSON object per image, in ascending TID order:

```json
{"tid":1,"image_id":"train:0","items":[1,4,19]}
```

Required keys are exactly `tid`, `image_id`, and `items`. `tid` is a unique integer starting at 1. `image_id` is the stable split plus zero-based source index. `items` is sorted, unique, and contains only integers 1–32; an empty array is valid. There must be exactly 70,000 lines.

### Mapping and metadata CSV

- `tid_image_mapping.csv`: `tid,image_id,split,source_index`; one row per transaction, no duplicate TID or image ID; source index is zero-based.
- `image_metadata.csv`: `image_id,split,source_index,class_label`; one row per image, class label is 0–9, and split/index recomposes the same `image_id`.
- `patch_assignments.csv`: `image_id,patch_id,patch_row,patch_col,word_id`; one row per retained patch with valid 1–49 patch ID, 1–7 grid coordinates, and 1–32 visual word.
- `centroids.csv`: `word_id,pixel_index,centroid_value`; exactly 32×16 rows, pixel indices 1–16, finite centroid values.

### Mining artifacts

- Per-backend `itemsets.jsonl` rows have exactly `items`, `length`, `support_count`, and `support_fraction`, sorted by `(length, items)`.
- `comparison.csv` has one row for each backend/threshold (12 rows): `backend,minsup_percent,min_count,status,itemset_count,runtime_seconds,peak_rss_mib,input_sha256,source_sha256,direct_support_status,parity_status`.
- `parity_audit.json` records for every threshold the missing/extra itemsets, support mismatches, direct-support audit count/status, input identity, and overall result. A pair is `PASS` only when both runs completed and every itemset and count is identical.
- `itemset_selection_candidates.csv`: full de-duplicated Set catalog, with `selected=true` only on the automatic 3–4 representatives. It is an audit view; users do not edit it to make the Notebook 04 handoff.
- `representative_patterns.csv`: `pattern_id,items,length,support_count,support_fraction,reference_minsup,selection_order,support_bucket,length_bucket,diversity_max_jaccard,rule_version,selection_notes`. `items` uses semicolon-separated visual-word IDs; `reference_minsup` is the highest completed threshold where the itemset appears.
- `selection_manifest.toml`: records rule version, target 4/minimum 3, unique candidate count, candidate catalog hash, initial length-coverage cells `(1/high)`, `(2/mid)`, `(>=3/low)`, fixed fill order, strict/relaxed Jaccard limits, actual limit, relaxation status, selected pattern order, and hashes of all six Set threshold outputs.
- `selected_itemsets.csv`: `selection_order,backend,minsup_percent,items,support_count,pattern_id`. Notebook 03 writes 3–4 Set rows automatically; serialize `items` as canonical JSON array text and preserve the exact support and highest observed source threshold.
- When the canonical transaction hash equals the historical report input hash, the audit additionally checks 7,228 itemsets at 5%. Otherwise the report records that historical comparison as `NOT_APPLICABLE`.

### Interpretation artifacts

- The notebook reads the selection and all parent manifests before rendering. Galleries show up to six deterministic supporting images per selected pattern and one contrast image where available, with source patches highlighted.
- `retrieval_examples.csv` records pattern ID, image ID, class, support membership, and patch-witness coordinates. Retrieved image count must equal stored support.
- `pattern_annotations.csv` begins with each selected pattern in `PENDING_REVIEW`; review fields and report status change only after human comments are recorded.
- The report links each summary and visual claim to its run-relative artifact path and states whether review is pending or complete.

## Failure Semantics

An invalid/missing parent manifest, artifact hash mismatch, wrong configuration, or wrong record count stops that notebook before consuming the input. Worker limits/failures are persisted as explicit run statuses. Failed or incomplete runs may appear in the summary, but cannot be presented as successful parity or verified interpretation.
