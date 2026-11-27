# Implementation Plan: Unified Fashion-MNIST Experiment Notebook

**Branch**: `Fashion-Mnist` | **Date**: 2026-11-27 | **Spec**: `specs/002-rebuild-fashion-experiments/spec.md`

**Input**: Feature specification from `specs/002-rebuild-fashion-experiments/spec.md`

## Summary

Build one end-to-end Fashion-MNIST notebook with an experiment section and a final packaging section. The experiment starts from verified raw images, reuses the Julia TC1–TC5 pipeline, fits all 15 K/seed configurations, creates S0/S1/S3/S6-B before EDA2, and compares codebook and all transaction-representation evidence over matched K–seed inputs. Apply region/stripe checks only to S1/S3 and separate neighbor geometry and boundary checks to S6-B. Add portable per-fit checkpoints and an EDA2 stage archive so a fresh Colab runtime can package completed results without rerunning the experiment. Export one final archive with provenance, statuses, evidence, and checksums.

## Technical Context

**Language/Version**: Julia. The project declares Julia 1.9 compatibility; the root `Manifest.toml` was generated with Julia 1.13.3. The notebook must print the actual runtime version and instantiate a checked-in lockfile before analysis. The exact managed Colab CPU runtime remains an acceptance check. If it cannot instantiate the root lockfile, implementation must add a separately pinned Colab-compatible environment or document a supported pinned runtime; it must not silently resolve floating dependencies.

**Primary Dependencies**: Existing `EclatFIM.FashionMNIST.FashionTC`, `FashionTCSpatial`, `FashionMNISTEDA2`, and `ExperimentBundleIO` modules; existing official dataset reader/downloader; Julia standard libraries `Downloads`, `Tar`, `SHA`, and `TOML`; existing `CodecZlib` for gzip archives; `Pkg` and `IJulia` for the notebook runtime. No Python orchestration or new package dependency is planned.

**Storage**: Dataset downloads, run outputs, fit checkpoints, the EDA2 stage archive, and final archive are staged under `/content` or a run-specific ignored `results/fashion/experiment_notebooks/` directory. Colab storage is temporary. The notebook writes a portable fit checkpoint after each completed fit and a `fashion_eda2_stage` archive after all 60 transaction inputs and EDA2 are prepared; these can be downloaded and uploaded to continue in a fresh runtime. The final `fashion_full_experiment` archive contains analysis plus S0/S1/S3/S6-B outputs.

**Testing**: Focused Julia tests for safe bundle/checkpoint paths, inventory and checksum validation, fit-checkpoint resume/rejection, EDA2 stage-archive continuation, the exact 15-fit matrix, paired S0/S1/S3/S6-B identities, separate recommendation aggregation, S1/S3 projection checks, S6-B relation-boundary checks, final status accounting, and archive round trips; existing TC4/TC6/EDA2 unit checks; notebook structure and Julia-cell parsing. Full 70,000-image sweep, 60 transaction databases, Eclat, archive transfer, and actual Colab CPU runtime remain acceptance scenarios.

**Target Platform**: One Julia notebook in a fresh Google Colab CPU runtime; local Julia is supported for package preparation and smoke validation. No Python cell or Python bridge is used.

**Project Type**: Julia package with one two-part experiment notebook and shared Fashion-MNIST artifact utilities.

**Performance Goals**: No user-specified wall-clock target. Run all 15 full-data fits sequentially on Colab CPU using a 1,000-iteration ceiling and per-fit checkpoints. Stop earlier when the configured tolerance is met. Measure elapsed time and memory in the acceptance run rather than claim a target before evidence exists. Export partial status for interrupted or failed phases; Eclat C1 retains its per-database timeout and resumable results.

**Constraints**: Fit on all 70,000 Fashion-MNIST images and retained descriptors using the existing 4×4 patch, strict pixel `>29`, raw 16D Float32 descriptor, K-means++/squared-distance, K `[16,32,64,128,256]`, seeds `[42,123,2026]`, 1,000-iteration ceiling, and `1e-4` tolerance. The full analysis compares 60 transaction sets (15 each of S0/S1/S3/S6-B) and finalizes 45 spatial outputs. S1/S3 must project back to S0; S6-B is exempt from full S0 projection and empty-status equality because isolated retained patches may produce no relation. Its checks validate relation mapping, Manhattan range 1–2, in-bounds pairs without wrap-around, diagonal dual relations, same-word pairs, deduplication, and maximum transaction length 298. Existing transaction meanings and Eclat APIs remain unchanged. Bundle paths are relative and safe; data files are inventoried with SHA-256. Colab uses manual Files-pane transfer.

**Scale/Scope**: One notebook; a full TC1–TC5 source-to-assignment run, all 15 K–seed fits, S0/S1/S3/S6-B generation and EDA2 analysis before archive packaging; portable fit checkpoints, one all-variant EDA2 stage archive, one final result archive; a focused evidence report with separate K and representation recommendations; README instructions; and unit/contract tests. No Eclat public API changes.

## Constitution Check

The repository constitution is still the untouched template and defines no project-specific gates. The repository's `AGENTS.md` does define applicable guidance: keep Julia modules separated by responsibility, preserve the transaction contract, add focused tests, and keep large results out of Git. The plan follows those constraints: computation stays in the existing spatial/EDA modules; the new helper is limited to archive and manifest I/O; no Eclat API or transaction encoding changes are planned; output bundles stay under ignored `results/` or `/content`.

**Gate result**: Pass. No constitution principles are ratified in the current file. No complexity exception is needed.

### Post-design check

Pass. Reuse existing TC4, TC6, and EDA2 modules; add only the two-part orchestration and portable checkpoint/stage/final-result boundaries needed by the clarified workflow. Spatial encoding and Eclat logic remain in their source modules. Part 2 uses Part 1 outputs directly or from its validated stage archive.

## Project Structure

### Documentation (this feature)

```text
specs/002-rebuild-fashion-experiments/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── experiment-bundles.md
└── tasks.md                 # Generated later by $speckit-tasks
```

### Source Code (repository root)

```text
src/applications/Fashion-Mnist/
├── FashionMNIST.jl                         # Include/export the bundle utility
├── notebook_tools/
│   └── ExperimentBundleIO.jl                # Safe archive I/O, manifest, checksums
├── spatial/FashionTCSpatial.jl              # Existing TC6 implementation; preserve encodings
├── transaction_eda/
│   ├── FashionMNISTEDA2.jl                  # Existing EDA2 pipeline
│   ├── analysis/RunAnalysis.jl               # Correct stale notebook provenance path
│   ├── analysis/ConfigurationRecommendation.jl # Separate evidence-based K/variant summary
│   └── inputs/ArtifactReaders.jl              # Support valid S0 label/mapping fallback
└── configs/
    ├── spatial/full.toml                    # Existing full TC6 settings
    └── transaction_eda.toml                 # Existing EDA2 settings

notebook/UD2/experiments/
└── EDA2_FashionMNIST_Transaction_Evaluation.ipynb # Canonical notebook: Part 1 EDA2, Part 2 spatial extension

test/
├── fashion_experiment_bundles.jl             # Bundle, checkpoint, and archive contract tests
└── fashion_eda2_recommendation.jl            # Matched comparison and recommendation tests

README.md                                    # Unified notebook link and two-part Colab guide
```

**Structure Decision**: Keep the existing EDA2 notebook path as the canonical notebook and combine the S0/S1/S3/S6-B generation calls into one code cell before EDA2; retire the separate spatial-only notebook. The later packaging section validates an all-variant stage archive and writes the final archive, without generating S6-B or rerunning EDA2. Keep recommendation logic in the EDA2 analysis module and bundle logic under `Fashion-Mnist/notebook_tools/`. Every substantive code cell has an explanatory Markdown cell.

## Design Decisions

1. **Reuse the full combined transaction-construction pipeline.** Use `configs/transactions/combined_full.toml` as the source of the agreed 70,000-image preprocessing and TC4 settings. The EDA2 run creates a runtime snapshot with only run/output paths adjusted, calls the existing `FashionTC` stages, and runs TC4 over all 15 K–seed pairs. Do not reimplement dataset parsing, patch extraction, filtering, descriptor construction, K-means, assignment, or S0 writing in notebook cells.
2. **Download and verify the source dataset through the existing API.** Call `download_fashion_mnist` and rely on the four archive SHA-256 checks already implemented by the dataset module. Preserve labels as metadata only; the feature matrix and fit never contain class labels. Include the dataset file hashes and preprocessing snapshot in each run fingerprint.
3. **Make per-fit resume portable.** Reuse TC4's existing `checkpoint.toml`, `codebook.bin`, `tc4_metrics.toml`, and fingerprint validation. Extend `ExperimentBundleIO` with a versioned checkpoint archive that packages the completed K–seed run directories plus a progress manifest. After each fit EDA2 updates the downloadable checkpoint. On a new runtime, it validates dataset, source revision, preprocessing, K/seed, Julia/library, and fit settings before staging compatible runs; existing TC4 code then skips valid completed fits. TC1–TC3 descriptors are in memory today, so a resumed runtime re-downloads/loads Fashion-MNIST and rebuilds descriptors before it can reuse codebook fits; the checkpoint avoids repeating completed K-means fits but does not promise to skip preprocessing.
4. **Create every transaction representation before EDA2.** In the combined generation cell, reuse `FashionTCSpatial` to create S1, S3, and S6-B from each corresponding S0 run. S1/S3 receive the existing projection/region/stripe checks. S6-B receives separate checks for the exact item formula, Manhattan distance 1–2, retained-patch eligibility, no wrap-around at image edges, diagonal pairs emitting both relation types, same-word pairs, item deduplication, and valid empty transactions. Finalize the 45 spatial run identities before analysis starts.
5. **Run EDA2 across all 60 databases.** Point `FashionMNISTEDA2` at S0 and the `S1`, `S3`, and `S6B` roots in `FULL_S0_S1_S3_S6B` scope. Preserve structural metrics, per-TID comparisons, common C1 settings, and per-database checkpoints. Do not require S6-B words or empty status to project exactly to S0. Keep C3 and pattern review behind their existing controls; their optional/manual states must not block the core 15-codebook/60-database comparison.
6. **Add separate, evidence-based K and representation recommendations.** Aggregate codebook metrics across three seeds for each K. Include S0/S1/S3/S6-B transaction length, diversity, and bounded common C1 evidence by K, and compare all four variants in matched `(K, seed)` groups. Use existing distortion, occupancy/entropy, stability, support, and Eclat evidence (currently 3% minimum support and maximum itemset length 2). State that the recommendation is scoped to this pilot; optional C2/C3 results may add evidence but are not silently assumed complete. Do not use an arbitrary scalar score or itemset count alone. Keep label-conditioned measures descriptive and do not make classification claims.
7. **Export an all-variant stage archive and one final experiment archive.** After EDA2, write `fashion_eda2_stage` with all 60 transaction sets, EDA2 tables, recommendation evidence, spatial summary, manifests, and checksums. The packaging section can validate this stage after a Colab reset and write one `fashion_full_experiment` archive without repeating any computation. Keep a validated S0 sub-bundle inside the final archive for downstream use.
8. **Keep archives safe and provenance explicit.** Use `Tar`, `CodecZlib`, `SHA`, and `TOML`; validate relative POSIX paths, entry types, exact inventories, sizes, hashes, run identities, and source/config fingerprints before extraction or resume. Record source commit, notebook hash, Julia version, dataset hashes, effective configuration, and output inventory. Never infer old source revisions that were not recorded.
9. **Transfer through Colab's Files pane.** A fresh run needs no precomputed transaction bundle: it downloads and verifies raw data, then writes fit checkpoints and the all-variant EDA2 stage archive under `/content`. To resume K-means, upload the latest fit checkpoint. To package results after a reset, upload the validated `fashion_eda2_stage` archive and select the final packaging section. Download the final archive before the Colab runtime is reset.

## Complexity Tracking

No constitution violations or unnecessary architectural layers are introduced. `ExperimentBundleIO` is justified because checkpoints and stage/final archives share security-sensitive extraction, manifest, and checksum rules; implementing them inside notebook cells would create divergent bundle contracts.
