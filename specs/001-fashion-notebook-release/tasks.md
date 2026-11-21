---
description: "Dependency-ordered implementation tasks for the Fashion-MNIST notebook release"
---

# Tasks: Fashion-MNIST Notebook Release

**Input**: Design documents from `specs/001-fashion-notebook-release/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/notebook-artifacts.md`, and `quickstart.md`.

**Tests**: Focused tests are included because the specification defines independent test criteria and acceptance checks for the manifest, transaction, mining, and interpretation contracts. Each test task precedes its implementation task.

**Organization**: Tasks follow the four user stories in `spec.md`. The actual end-to-end notebooks depend on prior manifests, so their full-data runs follow the dataset → transaction → mining → interpretation order.

## Phase 1: Setup

**Purpose**: Use the existing Julia notebook environment and Python dependencies; no new project initialization or package dependency is required.

---

## Phase 2: Foundational Contracts

**Purpose**: Establish the stable image identity used by all four user stories.

- [X] T001 Add tests in `test/test_fashion_mnist.jl` for stable IDs `train:0`, `test:0`, the last valid train/test indices, and rejection of a negative index or unknown split; run them before implementation and confirm they fail.
- [X] T002 Implement the canonical split-plus-zero-based-index formatter/parser in `src/applications/FashionMNIST.jl`; make the cases in `test/test_fashion_mnist.jl` pass without changing the integer array indices used internally.

**Checkpoint**: Stable image IDs have one definition before any release manifest or downstream artifact is written.

---

## Phase 3: User Story 1 — Validate the Fashion-MNIST Dataset (Priority: P1) 🎯 MVP

**Goal**: Verify the official 70,000 images and labels and create the dataset manifest consumed by Notebook 02.

**Independent Test**: From a fresh kernel, validate either locally present archives or archives downloaded by the notebook; confirm all four hashes, 60,000/10,000 split counts, 28×28 dimensions, ten classes, sample images by class, and a manifest with stable IDs.

### Tests for User Story 1

- [X] T003 [US1] Add tests in `test/test_fashion_mnist.jl` for dataset-manifest serialization and readback, including `schema_version`, `run_id`, four archive hashes, split counts, image shape, class count, and the stable image-ID rule; verify the new cases fail before implementation.

### Implementation for User Story 1

- [X] T004 [US1] Add dataset-manifest creation and validation in `src/applications/FashionMNIST.jl`; record a unique run ID, official archive paths/hashes, split counts, 28×28 shape, ten classes, stable image-ID scheme, validation status, and `results/fashion/release/<run_id>/` as the shared run root.
- [X] T005 [US1] Move and adapt `notebook/UD2/experiments/01_fashion_mnist_dataset.ipynb` to `notebook/UD2/release/01_dataset_validation.ipynb`; use the existing verified downloader/IDX reader, remove Colab Drive/TAR output assumptions, display examples from all ten classes, and write the manifest under the run root. Begin with purpose, conditions, inputs, and outputs, and put an explanatory Markdown cell immediately before every code cell.
- [ ] T006 [US1] Execute `notebook/UD2/release/01_dataset_validation.ipynb` with a fresh `fashion-mnist-tc` kernel once with archives absent and once with verified archives present; confirm the same validated counts/hashes and a readable dataset manifest in `results/fashion/release/<run_id>/dataset/`.

**Checkpoint**: Notebook 01 independently produces a verified dataset manifest and starts the shared run directory.

---

## Phase 4: User Story 2 — Build the Fixed S0 Transaction Dataset (Priority: P1)

**Goal**: Process all 70,000 images with exactly B0/K=32/seed=123/S0 and export traceable transactions plus a TC7 handoff manifest.

**Independent Test**: With a valid dataset manifest, verify one codebook, 70,000 transactions, stable image IDs, one TID-to-image mapping row per transaction, and a passing TC7 integrity report.

### Tests for User Story 2

- [X] T007 [P] [US2] Add tests in `test/test_fashion_fim_workflow.jl` and include them from `test/runtests.jl` for JSONL rows with string image IDs and empty `items`; verify expected record counts include empty rows and malformed/duplicate IDs are rejected, then confirm the tests fail before implementation.
- [X] T008 [P] [US2] Add release-profile tests in `test/test_fashion_tc.jl` that require `mode=release`, `K=[32]`, `seed=[123]`, all 70,000 images, B0, and S0, while confirming `configs/tc/kmeans/tc_v2_full.toml` still retains its five K values × three seeds; confirm the tests fail before implementation.

### Implementation for User Story 2

- [X] T009 [P] [US2] Update `src/fashion_fim/FashionFIMWorkflow.jl` to read the versioned release transaction schema with canonical string `image_id`, validate `train:<zero-based-index>`/`test:<zero-based-index>`, keep TIDs unique, and allow empty transactions; do not change the public Eclat input type.
- [X] T010 [P] [US2] Add `configs/tc/kmeans/tc_v2_release.toml` for one full-data B0 codebook with K=32 and seed=123, S0, CPU execution, and a run root supplied from Notebook 01; keep the full experimental config unchanged.
- [X] T011 [US2] Extend `src/applications/FashionTCv2.jl` with a distinct release mode that consumes and verifies Notebook 01's manifest, runs TC1–TC7 on all 70,000 images, emits stable IDs in all release artifacts, reloads and validates the output, and writes `transactions/tc7_manifest.toml` with schema/run identity and hashes for transactions, codebook, patch assignments, mapping, metadata, and config. Preserve the existing full-mode 15-codebook guard.
- [X] T012 [US2] Move and adapt `notebook/UD2/experiments/03_fashion_mnist_transaction_construction_cpu.ipynb` to `notebook/UD2/release/02_transaction_construction.ipynb`; load Notebook 01's manifest, display TC1–TC7 outputs, use the release profile, and explain every code cell in the immediately preceding Markdown cell.
- [X] T013 [US2] Execute `notebook/UD2/release/02_transaction_construction.ipynb` from the Notebook 01 run manifest with a fresh kernel; verify exactly one codebook, 70,000 transaction rows including any empty rows, valid stable-ID mappings, and matching artifact hashes in `results/fashion/release/<run_id>/transactions/tc7_manifest.toml`.

**Checkpoint**: Notebook 02 produces the one release S0 dataset without changing the existing full experimental profile.

---

## Phase 5: User Story 3 — Compare Eclat Backends (Priority: P1)

**Goal**: Run Set and BitVector under identical conditions at six thresholds and report exact itemset/support parity, timing, Peak RSS, and completion status.

**Independent Test**: With a valid TC7 manifest, verify 12 backend-threshold statuses, exact key-and-support comparison for every completed pair, and a direct support audit for every reported itemset.

### Tests for User Story 3

- [X] T014 [US3] Add and run Python `unittest` cases in `test/test_fashion_fim_release.py` and `test/test_fashion_fim_selection.py` for backend selection, the six min-count thresholds (56,000/42,000/28,000/14,000/7,000/3,500), empty transaction handling, exact parity, support mismatch detection, incomplete-run status, deterministic 3–4-pattern selection, tied support tertiles, and one-time Jaccard relaxation.

### Implementation for User Story 3

- [X] T015 [P] [US3] Update `scripts/fashion_fim/run_mining_worker.jl` to accept `--backend set|bitvector`, pass the selected backend to `EclatFIM.mine`, record backend identity in worker results, and remove the production rejection of empty transactions while preserving their denominator contribution.
- [X] T016 [P] [US3] Update `scripts/fashion_fim/supervisor.py` to create separate Set and BitVector run namespaces for all six thresholds, pass the worker backend option, record backend/source/input hashes and the shared resource limits, keep the two backend batches sequential, and apply legacy singleton/pair guardrails only when the input hash matches their historical dataset.
- [X] T017 [US3] Extend `scripts/fashion_fim/audit_outputs.py` to compare every canonical itemset and support count for each completed Set/BitVector threshold pair, independently recompute support from the source transactions, and write `mining/parity_audit.json` plus the 12-row `mining/comparison.csv`; check the 7,228 reference only when the transaction hash matches the historical report input.
- [X] T018 [US3] Move and adapt `notebook/UD2/experiments/FIM_Mining_Experiments.ipynb` to `notebook/UD2/release/03_frequent_itemset_mining.ipynb`; load and verify the TC7 manifest, preflight Linux user-systemd and run the smoke check, run both backends at all six thresholds with equal limits, show itemset count/runtime/Peak RSS/status/parity, and automatically persist 3–4 representative Set patterns using the versioned grid and Jaccard rule. Add the required notebook introduction and Markdown explanation before each code cell.
- [X] T019 [US3] Execute `notebook/UD2/release/03_frequent_itemset_mining.ipynb` against the TC7 transaction hash; confirm all 12 jobs have explicit statuses, every completed pair has exact parity and direct-support audit, the historical 7,228 check is either verified or recorded `NOT_APPLICABLE`, and the selector writes its 3–4-pattern handoff plus provenance manifest.

**Checkpoint**: Notebook 03 provides comparable results and an automatically persisted 3–4-pattern selection plus provenance for Notebook 04.

---

## Phase 6: User Story 4 — Interpret and Report Selected Patterns (Priority: P2)

**Goal**: Trace the automatically selected 3–4 representative itemsets to centroid, patch, image, and class evidence, then export a review-pending report.

**Independent Test**: With a TC7 manifest, mining manifest, and selected Set itemsets, confirm every pattern's retrieved image count equals support, source patches are identified, class totals reconcile, and review status remains pending until annotated.

### Tests for User Story 4

- [X] T020 [US4] Add and run Python `unittest` cases in `test/test_fashion_fim_interpretation.py` for stable string image IDs, the selected-itemset CSV contract and 3–4-row handoff bound, support/retrieval mismatch failure, class-count reconciliation, and initial `PENDING_REVIEW` status.

### Implementation for User Story 4

- [X] T021 [US4] Update `scripts/fashion_fim/interpretation.py` to read the selected itemsets and parent manifests from the shared run root, validate stable string IDs and hashes, and preserve patch witnesses, support retrieval, class statistics, galleries, review annotations, and report output without hard-coded legacy paths.
- [X] T022 [US4] Move and adapt `notebook/UD2/experiments/FIM_Visual_Interpretation.ipynb` to `notebook/UD2/release/04_visual_interpretation.ipynb`; load the persisted selection, render centroids/source patches/supporting images and available contrast images, show class distributions, and export the review sheet/report. Add the notebook introduction and an explanatory Markdown cell immediately before every code cell.
- [X] T023 [US4] Run `notebook/UD2/release/04_visual_interpretation.ipynb` using Notebook 03's automatic 3–4-pattern Set selection; confirm up to six deterministic supporting examples and one contrast image where available, support equals retrieved-image count, and the report remains `PENDING_REVIEW` until comments are entered.

**Checkpoint**: Notebook 04 creates traceable, reviewable visual evidence from the automatic mining selection.

---

## Phase 7: Polish and Cross-Cutting Release Checks

**Purpose**: Make the release discoverable, enforce notebook structure, and validate the complete clean-checkout workflow.

- [X] T024 [P] Add `scripts/validate_release_notebooks.py` to require the four exact release notebook paths, the purpose/conditions/inputs/outputs opening section, and an immediately preceding Markdown cell for every code cell.
- [X] T025 [P] Update `README.md` with links to the four release notebooks in run order, each handoff artifact, Julia/Python/systemd prerequisites, and instructions for rerunning when archives are missing.
- [X] T026 Reconcile `notebook/UD2/release/` and `notebook/UD2/experiments/` so release contains the four numbered notebooks and experiments retains the TC4 vector benchmark, spatial extension, and EDA2 notebooks only; verify no README links point to stale primary-notebook paths.
- [ ] T027 Follow `specs/001-fashion-notebook-release/quickstart.md` from a clean checkout with an empty `results/fashion/release/` run area; run `julia --project=. test/runtests.jl`, the Python release unit tests, notebook structure validation, and all four notebooks with fresh kernels, then confirm each manifest/audit reaches its expected status.

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No initialization task; existing Julia and Python environments are reused.
- **Foundational (Phase 2)**: T001 and T002 establish the canonical image-ID contract and block dataset-manifest work.
- **US1 (Phase 3)**: Depends on T001–T002; produces the run ID and dataset manifest required by US2.
- **US2 (Phase 4)**: Depends on US1's stable identity and dataset manifest; produces TC7 artifacts required by US3.
- **US3 (Phase 5)**: Depends on US2's transaction and TC7 contracts; produces mining results and a selected-itemset file required by US4.
- **US4 (Phase 6)**: Depends on US2 and US3 manifests and selected patterns.
- **Polish (Phase 7)**: Depends on all four story deliverables.

### User Story Dependencies

- **US1** can be tested and delivered independently after the foundational stable-ID helper.
- **US2** depends on the validated archive manifest from US1 for the full release flow; config and loader tests can use fixtures.
- **US3** depends on TC7's transaction file and hash from US2; backend and audit tests use small synthetic databases.
- **US4** depends on the versioned automatic Set selection and selection manifest from US3; interpretation tests use fixture artifacts.

### Parallel Opportunities

- **US1**: No safe implementation split inside the story; manifest helper → Notebook 01 → full-data validation is sequential.
- **US2**: T007 (transaction-loader tests) and T008 (release-profile tests) can be authored in parallel; after they pass, T009 (loader) and T010 (config) touch different files and can be implemented in parallel.
- **US3**: After T014, T015 (Julia worker) and T016 (Python supervisor) can be implemented in parallel against the agreed `--backend set|bitvector` option. T017 audit and T018 notebook depend on both.
- **US4**: Keep test → interpretation helper → Notebook 04 in sequence because the notebook consumes the selector's persisted rows and artifact contracts.
- **Polish**: T024 notebook validator and T025 README update can proceed in parallel after the four notebook paths are established.

### Parallel Execution Example

```text
Phase 2:       T001 and T002 are separate identity tests/implementation only after T001 passes.
US2 tests:     T007 || T008
US2 build:     T009 || T010, then T011 → T012 → T013
US3 build:     T014 → (T015 || T016) → T017 → T018 → T019
US4 build:     T020 → T021 → T022 → T023
Polish:        T024 || T025 → T026 → T027
```

## Implementation Strategy

### MVP First

1. Complete T001–T002 and User Story 1 (T003–T006).
2. Validate Notebook 01 independently: archive hashes, IDX counts, class samples, and dataset manifest.
3. Stop for a reviewable MVP before starting full-data transaction construction.

### Incremental Delivery

1. Add US2 to produce the fixed S0 transaction dataset and TC7 manifest.
2. Add US3 to compare both backends and save selected Set itemsets.
3. Add US4 to interpret the saved selection and export pending-review artifacts.
4. Complete README, structure checks, and the full clean-checkout run.

## Task Format Validation

Every task uses the required unchecked checkbox, sequential task ID, optional `[P]` marker only for independent file-level work, `[US#]` label in user-story phases, and at least one exact repository path.

## Remaining Release Gates

- T006: Notebook 01 was executed with all four verified local archives. The download path from an archive-absent directory was not exercised in this run.
- T023: Complete via MCP. Notebook 04 interpreted four selected patterns; gallery/witness validation and exact retrieval passed, and review remains `PENDING_REVIEW`.
- T027: The clean-checkout end-to-end run remains a release gate. The full Julia suite also has an unrelated existing failure in `test/test_eda2.jl`: malformed JSONL currently throws `ArgumentError` where the test expects `ErrorException`.
