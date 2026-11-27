# Data Model: Fashion-MNIST Experiment Rebuild

## 1. Experiment Run

One execution of the unified two-part notebook with enough identity to reproduce and audit both phases.

| Field | Type | Validation |
|---|---|---|
| `experiment_id` | String | Unique per execution; safe filename component |
| `experiment_kind` | Enum | `fashion_full_experiment` |
| `source_commit` | String | Actual checked-out commit or explicit `UNRECORDED`; never infer a historical producer revision |
| `notebook_sha256` | String | SHA-256 of the notebook used |
| `julia_version` | String | Actual runtime version printed and recorded |
| `dataset_identity` | Object | Hashes and expected train/test counts for the four verified source archives |
| `configuration_sha256` | String | Digest of the effective configuration snapshot |
| `status` | Enum | `COMPLETED`, `PARTIAL`, or `FAILED` |
| `phase_statuses` | Map | Separate fit, transaction generation, EDA2, and final packaging states |

Relationships: one Experiment Run contains up to 15 Codebook Fits, up to 60 transaction sets across S0/S1/S3/S6-B, mining measurements, one Recommendation Report, and up to 45 spatial outputs.

## 2. Descriptor Dataset

The in-memory feature matrix produced by TC1–TC3 from the verified source images.

| Field | Type | Validation |
|---|---|---|
| `image_count` | Integer | 70,000 across train and test |
| `patch_size` / `stride` | Integer pair | `[4,4]` / `[4,4]`, non-overlapping |
| `foreground_threshold` | Integer | 29 with strict `>` comparison |
| `descriptor_dimension` | Integer | 16 |
| `dtype` | String | `Float32` |
| `normalization` | String | Divide pixel values by 255 |
| `descriptor_count` | Integer | Count retained after the configured patch filter; record actual count |
| `feature_hash` | String | Digest of effective descriptor content/order when computed |

Class labels and source-image identity are metadata. They are not descriptor dimensions or transaction items.

## 3. Codebook Fit

One K-means result for a canonical `(K, seed)` pair.

| Field | Type | Validation |
|---|---|---|
| `run_id` | String | `FashionMNIST_T2_S0_B0_K{K}_seed{seed}` |
| `k` | Integer | One of 16, 32, 64, 128, 256 |
| `seed` | Integer | One of 42, 123, 2026 |
| `fit_scope` | String | All retained descriptors; no image or descriptor sampling |
| `algorithm` | String | Existing raw full-batch K-means implementation with K-means++ initialization |
| `max_iterations` / `tolerance` | Number | 300 / `1e-4` |
| `status` | Enum | `COMPLETED`, `FAILED`, or `NOT_RUN` |
| `converged` / `iterations` | Boolean / Integer | Actual fit outcome; never infer convergence from status alone |
| `metrics` | Object | Distortion, occupancy, empty clusters, top-cluster share, entropy, and available stability evidence |
| `artifacts` | File entries | Checkpoint, codebook, metrics, and configuration snapshot with hashes |

The complete design has exactly 15 identities. A failed or unfinished fit is not included as a completed codebook in aggregated recommendations.

## 4. Transaction Set

One representation for one completed `(K, seed)` fit.

| Field | Type | Validation |
|---|---|---|
| `source_run_id` | String | Must identify the matching Codebook Fit |
| `variant` | Enum | `S0`, `S1`, `S3`, or `S6-B` |
| `run_id` | String | Unique canonical identity for source pair and variant |
| `transaction_count` | Integer | 70,000 for a full run |
| `status` | Enum | `COMPLETED`, `FAILED`, or `NOT_RUN` |
| `integrity` | Enum | `PASS`, `FAIL`, or `NOT_CHECKED` |
| `source_hashes` | Object | Source S0 transaction and TID/image mapping digests used for spatial variants |
| `metrics` | Object | Existing transaction-length, sparsity, duplicate/empty, support, similarity, and class-conditioned descriptive measures where available |
| `files` | File entries | Transactions, mappings, configuration, lineage, integrity, and checkpoint artifacts |

Every spatial variant must match the same `(K, seed, source_run_id)` as its S0 base. The full analysis expects 15 S0 + 15 S1 + 15 S3 + 15 S6-B sets. All four representations are compared by EDA2 over matched `(K, seed)` pairs.

S1 is validated by projection back to S0 and region mapping; S3 is validated by projection and stripe mapping. S6-B uses separate neighbor-geometry checks: retained patch pairs only, Manhattan distance 1–2, no wrap-around, diagonal relation handling, same-word pairs at distinct patches, deduplication, item mapping, and transaction-length limits. Empty S6-B transactions are valid when no retained pair can form a relation.

## 5. Mining Measurement

One bounded Eclat result for one Transaction Set and one common-pilot configuration. The current common C1 pilot uses 3% minimum support and a maximum itemset length of 2; conclusions must state this scope.

| Field | Type | Validation |
|---|---|---|
| `transaction_set_id` | String | Must point to a completed S0/S1/S3/S6-B set |
| `pilot_id` | String | Identifies the common C1 settings |
| `min_support_fraction` | Number | The configured common support threshold (currently 0.03) |
| `max_itemset_length` | Integer | The configured common cap (currently 2) |
| `status` | Enum | `COMPLETED`, `CENSORED`, `FAILED`, or `NOT_RUN` |
| `result_metrics` | Object | Existing itemset/support and runtime measurements emitted by EDA2 |
| `elapsed_seconds` | Number or null | Recorded runtime; null if not measured |
| `reason` | String or null | Timeout, resource bound, or failure explanation |

C2/C3 and manual representative-pattern review remain optional phases with their own statuses. They do not silently replace the common matched C1 comparison.

## 6. Recommendation Report

Two separate evidence summaries, not a single weighted score.

| Field | Type | Validation |
|---|---|---|
| `k_recommendation` | Object | Aggregates codebook evidence over seeds for each K and includes transaction/mining evidence relevant to K |
| `representation_recommendation` | Object | Compares S0/S1/S3/S6-B in matched `(K, seed)` groups and reports paired differences/tradeoffs |
| `evidence_coverage` | Object | Counts expected, completed, failed, and censored fits, variants, and mining runs |
| `status` | Enum | `SUPPORTED`, `PROVISIONAL`, or `UNAVAILABLE` |
| `limitations` | List of strings | Missing scope, censoring, or evidence that limits interpretation |

The report may explain that evidence is mixed or insufficient. It must not claim a universally optimal K, select only by itemset count, or claim classification/predictive value.

## 7. Portable Fit Checkpoint

One archive for continuing the 15-fit sweep after a runtime reset.

| Field | Type | Validation |
|---|---|---|
| `bundle_kind` | String | `fashion_eda2_checkpoint` |
| `schema_version` | Integer | Reader supports the version or stops clearly |
| `expected_fits` | List | Exact canonical 15 K–seed identities |
| `fit_statuses` | List | `COMPLETED`, `FAILED`, or `NOT_RUN` for every identity |
| `resume_fingerprint` | Object | Dataset, preprocessing/configuration, source revision, K/seed, Julia, and required library identity |
| `files` | List of File Entry | Completed fit checkpoints, codebooks, and fit metrics with sizes and SHA-256 |

Only complete, fingerprint-compatible fits may be staged for resume. Descriptor preparation is rebuilt in a fresh runtime; the checkpoint does not contain the full descriptor matrix.

## 8. Stage and Final Archives

### Part 1 stage archive

One `fashion_eda2_stage` archive contains the validated S0/S1/S3/S6-B outputs, EDA2 analysis tables/figures/logs, recommendation report, spatial summary, provenance, complete expected identities, and checksums. Its manifest lets the same notebook validate and package the final archive in a fresh runtime without rerunning fits, transaction generation, or EDA2.

### Final experiment archive

One `fashion_full_experiment` archive contains the complete stage content and final packaging summary. It records all 15 fits, 60 transaction sets, 45 spatial statuses, fit/generation/analysis/packaging states, provenance, and a complete file inventory. A validated S0 sub-bundle may be retained for later reuse by other Fashion-MNIST workflows.

Every archive manifest inventories regular files by relative POSIX path, size, and SHA-256. Archive safety and validation rules are defined in `contracts/experiment-bundles.md`.
