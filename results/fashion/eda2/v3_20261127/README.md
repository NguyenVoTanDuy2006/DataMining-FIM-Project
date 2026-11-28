# EDA2 snapshot — 27 November 2026

This is the compact analysis extracted from the full Colab experiment bundle.
It compares the configured K-means codebooks and S0, S1, S3, and S6-B transaction
representations. The source bundle and resume checkpoint are retained locally
under `../archive/20261127/` and are not tracked by Git because of their size.

## Validation and limits

- 15 of 15 codebooks were validated.
- The bundle manifest reports 60 transaction sets, but the analysis validator
  accepted 45 of them.
- The 15 S6-B cases are marked `BLOCKED` because the validator expects `S6-B`
  paths and IDs while the bundle stores their artifacts under `S6B` paths and
  IDs. The source archive contains those artifacts; this is a path/name
  mismatch in validation, not an absent S6-B generation.
- The saved analysis status is `INCONCLUSIVE`; it does not establish a universal
  best K or a best transaction representation.
- The saved common-scope Eclat comparison uses 3% minimum support and limits
  itemsets to length two. It is a narrow comparison, not a full mining benchmark.
- The bundle reports C3 deep mining and manual pattern review as incomplete.

## Files

- `analysis/final/`: comparative tables and the saved conclusion.
- `analysis/recommendations/`: K and representation summaries.
- `analysis/codebook/`: metrics and stability summaries for the 15 codebooks.
- `analysis/transactions/`: transaction, similarity, region, and invariant
  summaries for the validated scope.
- `analysis/validation_report.*`: per-database validation results.
- `analysis/execution/run_summary.toml`: run-level completion counts.
- `manifest.toml`: file inventory and checksums for the original bundle.
- `eda2_database_manifest.toml` and `spatial_extension_run_summary.toml`:
  package-level source metadata.
