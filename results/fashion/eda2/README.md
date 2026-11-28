# Fashion-MNIST EDA2 results

This directory keeps the EDA2 result generations separate. Each version is a
snapshot; do not combine their tables as if they came from one run.

| Snapshot | Contents | Status and use |
|---|---|---|
| `v1/` | Earlier transaction and codebook analysis | Partial: 52 of 60 databases validated. Retained locally as history; excluded from Git. |
| `v2/` | S0, S1, and S3 comparisons, common-scope mining, shortlist and interpretability review artifacts | 45 of 45 S0/S1/S3 databases validated. The saved decision records B0, K=32, seed 123, S0 as the selected working configuration. The overall assessment remains `INCONCLUSIVE`: 319 patterns await manual review and 108 deep-mining runs hit the configured maximum itemset length. |
| `v3_20261127/` | Newer experiment covering S0, S1, S3, and S6-B, with compact analysis outputs and source manifests | The bundle manifest reports 60 transaction sets, while the analysis validator accepts 45. Its 15 S6-B cases are marked `BLOCKED` because the validator expects `S6-B` paths/IDs while the bundle stores them as `S6B`. The overall decision remains `INCONCLUSIVE`; see the version-specific report and validation files. |

`v2/` and `v3_20261127/` are the compact result sets intended for Git. The
earlier Eclat timing benchmark is kept separately at
[`../colab_report_20261125/`](../colab_report_20261125/); it is historical
benchmark evidence and is not reproduced by the EDA2 snapshots.

Full transaction bundles and the resumable checkpoint for the 27 November run
are kept locally in `archive/20261127/`. These large archives are ignored by
Git. The downloaded originals are also left in the user's Downloads folder.

## Reading the latest snapshot

Start with [`v3_20261127/README.md`](v3_20261127/README.md), then inspect its
`analysis/final/`, `analysis/recommendations/`, `analysis/validation_report.*`,
and `analysis/execution/run_summary.toml`. The package-level `manifest.toml`
records the archived bundle's files and checksums.
