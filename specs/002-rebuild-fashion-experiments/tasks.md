# Tasks: Unified Fashion-MNIST Experiment Notebook

**Input**: Design documents from `specs/002-rebuild-fashion-experiments/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/experiment-bundles.md`, and `quickstart.md`

**Tests**: Focused test tasks are included because the feature specification defines independent test scenarios and repository `AGENTS.md` requires tests for application changes. Full-data performance and Colab runtime compatibility remain acceptance checks.

**Organization**: Tasks are grouped by the two user stories. User Story 1 delivers the all-variant analysis before packaging. User Story 2 adds safe continuation after Colab resets.

## Phase 1: Setup

**Purpose**: Verify the Julia CPU runtime and keep generated experiment artifacts out of Git.

- [ ] T001 Verify that the selected Colab Julia CPU runtime can instantiate the checked-in `Project.toml` and `Manifest.toml`; if it cannot, add a separately pinned compatible environment and configure `notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb` to use that lockfile without floating dependency resolution.
- [x] T002 Add or verify ignore rules in `.gitignore` for `results/fashion/experiment_notebooks/` and generated experiment archives so full Fashion-MNIST outputs stay out of Git.

---

## Phase 2: Foundational (Portable Archive Contract)

**Purpose**: Implement the shared archive validation and manifest boundary required by both notebook parts and resume flows.

- [x] T003 Add contract tests in `test/fashion_experiment_bundles.jl` for relative POSIX paths only, rejection of absolute paths, `..`, links and unsupported members, exact inventory, non-negative `size_bytes`, matching SHA-256, supported schema versions, and the `fashion_eda2_checkpoint`, `fashion_eda2_stage`, `fashion_full_experiment`, and `fashion_s0_source` bundle kinds.
- [x] T004 Implement safe `.tar.gz` inspection, staged extraction, inventory checks, file-size validation, SHA-256 calculation, and archive writing in `src/applications/Fashion-Mnist/notebook_tools/ExperimentBundleIO.jl`; reject missing, unlisted, duplicate, unsafe, or tampered files before reuse.
- [x] T005 Extend `src/applications/Fashion-Mnist/notebook_tools/ExperimentBundleIO.jl` with manifests and validators for `fashion_eda2_checkpoint`, `fashion_eda2_stage`, and `fashion_full_experiment`, including all expected run identities, per-phase statuses, provenance, and nested `s0_source/manifest.toml` validation.
- [ ] T006 Include and export the archive utility from `src/applications/Fashion-Mnist/FashionMNIST.jl`, register `test/fashion_experiment_bundles.jl` in `test/runtests.jl`, and verify the focused archive-contract tests with small fixtures.

**Checkpoint**: The notebook can safely write and validate fit checkpoints, a Part 1 stage archive, and the final experiment archive.

---

## Phase 3: User Story 1 — Run Both Parts in One Notebook (Priority: P1) 🎯 MVP

**Goal**: Run EDA2 from raw Fashion-MNIST data after generating S0/S1/S3/S6-B from each codebook.

**Independent Test**: Start a fresh Julia CPU runtime, execute the notebook in order, and verify 15 K–seed fits, up to 60 S0/S1/S3/S6-B transaction sets, all 45 spatial statuses, separate recommendations, and one verifiable final archive.

### Tests for User Story 1

- [ ] T007 [P] [US1] Add integration tests in `test/fashion_unified_experiment.jl` for the exact K matrix `[16, 32, 64, 128, 256] × [42, 123, 2026]`, 70,000 transactions per completed full run, and S0/S1/S3/S6-B lineage matching by `(K, seed, source_run_id)`; incomplete fits or variants must remain `FAILED` or `NOT_RUN` and be excluded from completed comparisons.
- [ ] T008 [P] [US1] Add recommendation tests in `test/fashion_eda2_recommendation.jl` proving K metrics aggregate across all three seeds, S0/S1/S3/S6-B comparisons use matched `(K, seed)` pairs, the common Eclat scope is 3% minimum support with maximum itemset length 2, and the output reports separate K and representation recommendations without a single weighted score.
- [ ] T009 [US1] Register `test/fashion_unified_experiment.jl` and `test/fashion_eda2_recommendation.jl` in `test/runtests.jl` and verify the new tests fail when expected fit identities, paired outputs, or recommendation evidence are absent.

### Implementation for User Story 1

- [x] T010 [US1] Keep TC6 spatial generation in `src/applications/Fashion-Mnist/spatial/FashionTCSpatial.jl`; generate and finalize S1/S3/S6-B from each matching S0 run before EDA2, retaining separate S6-B neighbor geometry and boundary validation.
- [x] T011 [US1] Extend `src/applications/Fashion-Mnist/transaction_eda/analysis/ConfigurationRecommendation.jl` to aggregate codebook evidence over three seeds per K, include all four transaction encodings in per-K metrics, and compare S0/S1/S3/S6-B over matched K–seed inputs.
- [x] T012 [US1] Include and call `ConfigurationRecommendation.jl` from `src/applications/Fashion-Mnist/transaction_eda/FashionMNISTEDA2.jl`; include S6-B in structural analysis and common C1 Eclat scope while keeping codebook-fit metrics distinct from transaction metrics.
- [x] T013 [US1] Rebuild `notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb` as the canonical Julia notebook: create S0/S1/S3/S6-B in one transaction-generation cell before EDA2, analyze all valid matched inputs, show separate S1/S3 and S6-B checks, write an all-variant stage archive, and use the final section only to validate and package that archive. Place explanatory Markdown before each substantive code cell and keep experiment execution in Julia.
- [x] T014 [US1] After porting the spatial workflow, retire the duplicate executable notebook `notebook/UD2/experiments/05_tc6_spatial_extension.ipynb` so the experiment directory has one canonical two-part notebook.
- [x] T015 [US1] Update `src/applications/Fashion-Mnist/notebook_tools/validate_release_notebooks.py` to validate the canonical notebook's Julia kernel, Part 1/Part 2 headings, explanatory Markdown before substantive code cells, and absence of Python orchestration.
- [x] T016 [US1] Update `README.md` to link to the unified notebook, explain that all four variants are analyzed before packaging, describe separate S6-B boundary checks, and document stage/final archive downloads through the Colab Files pane.

**Checkpoint**: One fresh-runtime run completes EDA2 and the spatial extension without regenerating successful S1/S3 outputs.

---

## Phase 4: User Story 2 — Resume After a Colab Reset (Priority: P1)

**Goal**: Resume unfinished K–seed fits from a portable checkpoint or continue Part 2 from a validated Part 1 stage archive.

**Independent Test**: Interrupt a fixture sweep and resume from a compatible fit checkpoint; then start a clean runtime with a completed stage archive and verify Part 2 runs without repeating Part 1.

### Tests for User Story 2

- [ ] T017 [P] [US2] Add resume tests in `test/fashion_unified_resume.jl` for compatible/incompatible dataset, preprocessing, source, configuration, Julia/library and K–seed fingerprints; confirm completed fits are skipped, missing fits continue, and a valid all-variant EDA2 stage archive resumes final packaging without rerunning transaction generation or EDA2 analysis.
- [ ] T018 [US2] Register `test/fashion_unified_resume.jl` in `test/runtests.jl` and verify incompatible archives are rejected before their artifacts are staged or combined.

### Implementation for User Story 2

- [x] T019 [US2] Extend `src/applications/Fashion-Mnist/notebook_tools/ExperimentBundleIO.jl` to package the per-fit `checkpoint.toml`, `codebook.bin`, `tc4_metrics.toml`, and configuration snapshot after each completed K–seed fit, recording all 15 expected fit rows and the resume fingerprint.
- [x] T020 [US2] Integrate checkpoint restoration into the K–seed execution path used by `notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb`; rebuild descriptors from verified raw data, validate the checkpoint fingerprint, stage compatible completed fits, and continue only missing or failed fits.
- [x] T021 [US2] Add a final packaging continuation path in `notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb` that accepts a user-selected `fashion_eda2_stage` archive in a fresh runtime, validates its root and nested S0 manifests plus all S1/S3/S6-B lineage, and resumes without rerunning the experiment or EDA2.
- [x] T022 [US2] Preserve partial progress and actionable failure reasons in `src/applications/Fashion-Mnist/notebook_tools/ExperimentBundleIO.jl` and the unified notebook when a fit, spatial variant, checksum, or archive identity check fails; never mark missing or incompatible outputs as completed.

**Checkpoint**: A reset between fits or between notebook parts does not require recomputing already validated work.

---

## Phase 5: Polish and Cross-Cutting Validation

**Purpose**: Verify the deliverable and make Colab execution instructions match the final artifact contract.

- [x] T023 Update `specs/002-rebuild-fashion-experiments/quickstart.md` with the final notebook path, Part 1 and Part 2 execution steps, fit-checkpoint and stage-archive resume instructions, expected output counts, and archive-manifest validation steps.
- [ ] T024 Run `julia --project=. test/runtests.jl` and `python src/applications/Fashion-Mnist/notebook_tools/validate_release_notebooks.py`; fix failures in the source, notebook, or tests that own them.
- [ ] T025 Complete the Colab CPU acceptance run documented in `specs/002-rebuild-fashion-experiments/quickstart.md`: run from raw data, interrupt/resume a fit checkpoint, package from a downloaded all-variant stage archive in a clean runtime, and verify the final archive's 15 fits, 60 transaction sets, 45 spatial statuses, provenance, inventory, and checksums.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 and T002 establish the compatible Julia runtime and ignored output paths.
- **Foundational (Phase 2)**: T003 → T004 → T005 → T006. Archive safety and manifests block both user stories.
- **User Story 1 (Phase 3)**: Depends on Setup and Foundation; completes the end-to-end notebook from raw images through Part 2.
- **User Story 2 (Phase 4)**: Depends on the checkpoint and stage archive contracts from Foundation and the Part 1/Part 2 flow from US1.
- **Polish (Phase 5)**: Depends on both user stories.

### User Story Dependencies

- **US1 (P1)**: Can start after Foundation. It delivers the MVP: one complete two-part notebook.
- **US2 (P1)**: Builds on US1's fit and stage outputs, then verifies continuation from portable archives.

### Parallel Opportunities

- T001 and T002 can proceed in parallel because they address the Julia environment and Git ignore rules.
- T007 and T008 can proceed in parallel because they add integration and recommendation tests in separate files.
- After those tests are defined, T010 and T011 can proceed in parallel because spatial orchestration and recommendation logic are in separate source files.
- Resume fixture tests T017 can be prepared alongside the US1 source-module work after the archive contract is stable; US2 implementation remains dependent on the completed Part 1 stage flow.

## Parallel Examples

### Independent User Story 1 work after tests are defined

```text
Task: Implement S0/S1/S3/S6-B reuse and finalization in src/applications/Fashion-Mnist/spatial/FashionTCSpatial.jl
Task: Implement K and representation evidence aggregation in src/applications/Fashion-Mnist/transaction_eda/analysis/ConfigurationRecommendation.jl
```

### Resume workflow

```text
Task: Add checkpoint and stage archive validation cases in test/fashion_unified_resume.jl
Task: Add manifest fingerprint and staged restore support in src/applications/Fashion-Mnist/notebook_tools/ExperimentBundleIO.jl
```

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational archive contracts.
2. Complete US1: generate and analyze 15 fits and all 60 S0/S1/S3/S6-B transaction sets before final packaging.
3. Validate the final archive's complete and partial status behavior before adding resume support.

### Incremental Delivery

1. Build and validate the shared archive contract.
2. Deliver the single end-to-end notebook and final experiment archive.
3. Add fit-checkpoint resume and Part 2 continuation from the Part 1 stage archive.
4. Run local checks, then complete full Colab CPU acceptance.

## Notes

- Every task follows `- [ ] Txxx [P?] [US?] Description with exact file path`.
- `[P]` is used only when tasks modify different files and have no unfinished dependency.
- Test tasks precede their corresponding implementation tasks; tests use small fixtures, while full-data computation is reserved for Colab acceptance.
