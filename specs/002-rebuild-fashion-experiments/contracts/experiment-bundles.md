# Contract: Unified Fashion-MNIST Experiment Archives

This contract defines the portable artifacts used by one Julia notebook. It preserves the meanings of S0, S1, S3, and S6-B.

## Bundle kinds

The root `manifest.toml` declares one supported `bundle_kind`:

- `fashion_eda2_checkpoint`: per-fit artifacts for resuming the 15-configuration K-means sweep.
- `fashion_eda2_stage`: all four transaction variants plus EDA2 outputs, allowing final packaging after a Colab reset.
- `fashion_full_experiment`: final archive containing the complete analysis and spatial outputs.
- `fashion_s0_source`: optional standalone source package for reuse by other Fashion-MNIST workflows.

`schema_version` is an integer. Readers reject unsupported versions with a clear message. All paths are relative POSIX paths.

## Archive safety and integrity

Before reading or extracting, the Julia reader validates the full inventory and rejects absolute paths, `..`, duplicate normalized paths, links, devices, unsupported entry types, missing or unlisted regular files, malformed manifests, duplicate/unknown run IDs, and mismatched size or SHA-256. Extraction uses a run-specific staging directory and never overwrites the uploaded archive or existing production artifacts.

Each manifest lists every regular file other than that manifest with `path`, `size_bytes`, and lowercase 64-character `sha256`. An embedded `s0_source/manifest.toml` is inventoried by its parent manifest and separately inventories S0 files using paths relative to `s0_source/`. Readers validate both levels. An adjacent `.sha256` file may checksum the compressed archive itself.

## Canonical experiment identities

The fit matrix is `K = [16, 32, 64, 128, 256]` and seeds `[42, 123, 2026]`. Each pair has canonical S0 identity `FashionMNIST_T2_S0_B0_K{K}_seed{seed}`. A full run expects one matching S0, S1, S3, and S6-B set per pair, for 60 transaction sets, of which 45 are spatial outputs.

Manifests list every expected identity, including missing, failed, and not-run rows. No archive may silently substitute a K, seed, source, or encoding. A variant must match its source `(K, seed, source_run_id)`, transaction denominator, mapping identity, and supported encoding configuration.

## Fit checkpoint archive

Expected structure:

```text
manifest.toml
fits/<canonical-run-id>/checkpoint.toml
fits/<canonical-run-id>/codebook.bin
fits/<canonical-run-id>/tc4_metrics.toml
fits/<canonical-run-id>/config_snapshot.toml
```

The manifest contains schema version, source commit, notebook/effective configuration hashes, Julia and relevant clustering-library versions, dataset archive hashes, preprocessing fingerprint, the exact 15 expected K–seed rows, fit statuses, and inventory. Completed rows include all required fit files. Failed/not-run rows remain in the matrix without claiming completed artifacts.

On resume, the fit workflow validates dataset, preprocessing, source, configuration, K/seed, Julia, and library identity before staging a fit. It rejects incompatible archives before combining outputs. Compatible completed fits are skipped by the existing TC4 checkpoint logic; missing/failed fits remain runnable. The descriptor matrix is rebuilt from verified images and is not included in the checkpoint archive. A refreshed checkpoint is written after every completed fit.

## EDA2 stage archive

Expected structure:

```text
manifest.toml
s0_source/manifest.toml
s0_source/S0/<canonical-run-id>/...
S1/<canonical-run-id>/...
S3/<canonical-run-id>/...
S6B/<canonical-run-id>/...
spatial_extension_run_summary.toml
eda2_database_manifest.toml
analysis/tables/...
analysis/figures/...
analysis/reports/...
analysis/logs/...
```

The root manifest records all expected fit and 60 transaction identities, phase statuses, recommendation evidence coverage, source/config/runtime identity, and file inventory. The nested S0 manifest inventories paths relative to `s0_source/`; the packaging section validates both manifests and all source/variant lineage before reuse. A completed EDA2 stage can be used to write the final archive without rebuilding descriptors, fitting codebooks, recreating any transaction variant, or repeating EDA2 analysis.

## Final experiment archive

Expected structure:

```text
manifest.toml
s0_source/manifest.toml
s0_source/S0/<canonical-run-id>/...
S1/<canonical-run-id>/...
S3/<canonical-run-id>/...
S6B/<canonical-run-id>/...
analysis/tables/...
analysis/figures/...
analysis/reports/...
analysis/logs/...
spatial_extension_run_summary.toml
```

The root manifest records the data, configuration, source, notebook, and runtime identity; all 15 fit statuses; 60 expected S0/S1/S3/S6-B transaction statuses; 45 spatial statuses; recommendation evidence; fit/generation/analysis/packaging status; and output inventory. The spatial finalizer may claim completion only after every expected S1/S3/S6-B identity and integrity check passes.

The EDA2 recommendation uses all four encodings in matched `(K, seed)` groups and the configured common Eclat pilot (currently 3% minimum support and maximum itemset length 2). Codebook fit metrics remain separate from downstream transaction metrics. S1/S3 use projection and region/stripe checks; S6-B instead uses neighbor geometry, edge, mapping, item-range, and length checks. Empty S6-B transactions are valid when no retained neighbor pair exists. Optional deeper mining and manual pattern review retain explicit completed, censored, awaiting-review, or not-requested status.

Overall status is `COMPLETED`, `PARTIAL`, or `FAILED`. Recommendation evidence is `SUPPORTED`, `PROVISIONAL`, or `UNAVAILABLE`. A complete computation may have a provisional recommendation if evidence was censored or incomplete. No incomplete fit, variant, or timed-out Eclat result is represented as completed.

## Optional S0 source archive

A standalone `fashion_s0_source` package uses root `manifest.toml` plus `S0/<canonical-run-id>/...`. Completed runs contain the artifacts required by the current TC6 source validator: transactions, patch assignments, TID/image mapping, image metadata, configuration snapshot, integrity report, checkpoint, codebook, and TC4 metrics. It enumerates all 15 expected identities and records source-generation revision separately from packaging commit. Class labels remain metadata and do not enter transactions.

## Colab transfer

The notebook writes fit checkpoints, the EDA2 stage archive, and the final archive under `/content`. The user downloads the checkpoint to resume K-means, or downloads the stage archive to package final results in a fresh runtime. The Files pane is the transfer mechanism; runtime-local files are temporary. Notebook cells validate uploaded archives before reuse.
