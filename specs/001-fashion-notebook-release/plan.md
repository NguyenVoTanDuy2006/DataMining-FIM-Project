# Implementation Plan: Fashion-MNIST Notebook Release

**Branch**: `feature/fashion-mnist-consolidated` | **Date**: 2026-11-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-fashion-notebook-release/spec.md`

## Summary

Release four ordered Fashion-MNIST notebooks that validate the official 70,000-image dataset, construct the fixed B0/K=32/seed=123/S0 transaction set, compare Eclat Set and BitVector, and interpret 3–4 deterministically selected Set itemsets. Reuse the existing `FashionMNIST.jl`, `FashionTCv2.jl`, bounded mining supervisor, and Python interpretation workflow. Add a release-only TC profile, a common per-run artifact root and handoff manifests, backend-aware mining and exact parity checks, and release notebook/README structure. Keep the public Eclat API and the existing 15-codebook experiment profile unchanged.

The implementation must follow the spec's stable image identity (`train:<zero-based-index>` or `test:<zero-based-index>`) throughout release artifacts. Existing TC and FIM artifacts use numeric global image IDs, so the release path must version and migrate its artifact readers and writers instead of silently mixing the old and new schemas.

## Technical Context

**Language/Version**: Julia 1.13.3 for the notebook kernel and Fashion pipeline; repository package compatibility begins at Julia 1.9. Python 3.10 or newer runs the supervisor, audit, and interpretation helpers.

**Primary Dependencies**: Existing `EclatFIM` package; `Clustering.jl` for full-batch K-means; Julia `Downloads`, `SHA`, `TOML`, `Serialization`, `Statistics`, and `Random`; `IJulia` and `PNGFiles` in `environments/fashion_notebooks`; Python `jupyter`, `nbclient`, and `nbformat` from `pyproject.toml`. Mining and interpretation helpers otherwise use Python standard-library modules.

**Storage**: Local files. TOML for run/config/manifests, JSONL for transactions and itemsets, CSV for mappings/summaries/selections/review annotations, and existing binary codebook/assignment checkpoints plus SVG/HTML/PNG interpretation evidence.

**Testing**: Existing Julia suite (`julia --project=. test/runtests.jl`); focused schema, identity, empty-transaction, worker-backend, and parity tests; then execute all four release notebooks in order with fresh kernels and an empty release-results directory. Notebook execution is a release gate; do not treat an incomplete mining status as parity success.

**Target Platform**: Linux with a functioning user systemd manager and cgroup memory accounting. Each mining worker uses one Julia thread, a 3,072 MiB memory cap, no swap, a 3,600-second wall limit, and an 8 GiB output cap; Set and BitVector runs use the same limits and are run sequentially.

**Project Type**: Research notebook workflow over a Julia package and Python orchestration/interpretation scripts.

**Performance Goals**: Process 70,000 images and all six thresholds for both backends. There is no cross-machine runtime target; elapsed time and Peak RSS are measured per worker. Each worker is bounded by the resource limits above, with explicit status if it does not complete.

**Constraints**: Exactly one release codebook (B0, K=32, seed=123), S0 transactions, six support thresholds (80/60/40/20/10/5%), stable split/index image IDs, one shared output directory per run, exact backend parity, no Eclat API redesign, and no changes to the existing full experimental profile. TC4 vector trade-off, spatial encoding, and EDA2 remain experiments.

**Scale/Scope**: 70,000 images, 49 possible patches per image before filtering, 32 visual words, 70,000 transaction records including empty transactions if any, and 12 backend-threshold mining runs. The release contains four notebooks plus shared manifests, summary, interpretation, and review artifacts.

## Constitution Check

**Before Phase 0: PASS.** `.specify/memory/constitution.md` contains template placeholders rather than ratified project principles, so it defines no binding gates. The repository instructions require reading `docs/plan.md` before changing an application data contract and coordinating changes to a shared API. `docs/plan.md` has been read. This design keeps the public Eclat API unchanged, limits schema changes to versioned Fashion release artifacts and their consumers, preserves the existing experiment profile, and includes focused validation. No gate failure or unjustified architecture is identified.

**After Phase 1: PASS.** The design keeps parsing, transaction construction, mining orchestration, and interpretation in their existing boundaries. New contracts are versioned at notebook boundaries; Eclat still receives `Vector{Vector{Int}}` and returns sorted itemset keys with support counts. No constitution violation is introduced.

## Project Structure

### Documentation (this feature)

```text
specs/001-fashion-notebook-release/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    └── notebook-artifacts.md
```

### Source and release artifacts

```text
notebook/UD2/
├── release/
│   ├── 01_dataset_validation.ipynb
│   ├── 02_transaction_construction.ipynb
│   ├── 03_frequent_itemset_mining.ipynb
│   └── 04_visual_interpretation.ipynb
└── experiments/
    ├── 04_tc4_vector_pre_kmeans_tradeoff_60k.ipynb
    ├── 05_tc6_spatial_extension.ipynb
    └── EDA2_FashionMNIST_Transaction_Evaluation.ipynb

configs/tc/kmeans/tc_v2_release.toml                 # new release-only profile
src/applications/FashionMNIST.jl                     # verified archive/IDX reader
src/applications/FashionTCv2.jl                      # TC1–TC7; release-mode support
src/fashion_fim/FashionFIMWorkflow.jl                # transaction loading contract
scripts/fashion_fim/
├── supervisor.py                                    # backend-aware bounded runs
├── run_mining_worker.jl                             # pass selected backend
├── audit_outputs.py                                 # exact parity/support audit
└── interpretation.py                                # selected-itemset input
test/                                                 # focused Julia contract tests
results/fashion/release/<run_id>/                    # ignored per-run outputs
README.md                                             # release entry point/run guide
```

**Structure Decision**: Promote/adapt the current dataset, TC construction, mining, and visual interpretation notebooks into `notebook/UD2/release/` in run order. Keep only the three explicitly deferred notebooks in `notebook/UD2/experiments/`. Reuse existing package modules and Python helpers; add no new application layer. A run ID created by Notebook 01 scopes every later notebook output under `results/fashion/release/<run_id>/`.

## Implementation Sequence & Validation Gates

1. **Run identity and dataset validation** — adapt the existing dataset notebook to use `FashionMNIST.jl`'s pinned official archive hashes and IDX checks. Remove its Colab Drive/TAR assumptions. Create a unique run root, validate archive and split contracts, display examples by class, and write a dataset manifest. Gate: exact 60,000/10,000 counts, 28×28 dimensions, ten labels, and four passing archive hashes.
2. **Release TC profile and stable IDs** — add `tc_v2_release.toml` with a distinct release mode constrained to full 70,000-image fitting, one K=32/seed=123 B0 codebook, and S0. Leave `tc_v2_full.toml` and its 15-combination guard intact. Pass the Notebook 01 run ID and manifest to TCv2; retain integer indices only for in-memory array access, while release artifacts use the canonical string image ID from the spec. TC7 writes one aggregate handoff manifest including the transaction hash and paths/hashes for codebook, assignments, mapping, metadata, and config. Gate: reload all artifacts and verify one codebook, 70,000 TIDs, stable ID mapping, and sorted unique visual words.
3. **Backend-aware Eclat comparison** — adapt the existing supervisor and worker to accept `:set` or `:bitvector`; include backend in config identity, run IDs, output paths, manifests, and summary rows. Execute the six existing exact min-count thresholds in backend-separated sequential batches with matching limits. Permit empty transactions while retaining all 70,000 records in the denominator. Make legacy singleton/pair guardrails conditional on the matching historical input identity. Add an independent exact comparison that requires every itemset and support count to match for each completed backend pair, and an independent support audit over the output itemsets. Gate: 12 explicit statuses; exact parity for each complete pair; no parity claim for failed/incomplete pairs.
4. **Deterministic representative selection and interpretation** — adapt the existing v1.3 grid criteria to the 3–4-pattern release target. Use length buckets 1/2/≥3 and support tertiles over distinct support counts with ties grouped. First try the cells (1/high), (2/mid), and (≥3/low) in order to cover pattern lengths and support bands; fill remaining slots with the fixed nine-cell length-major round-robin, ranking candidates within each cell by support descending then length and item IDs. Enforce max item-ID Jaccard ≤0.80; if fewer than four pass, restart once at ≤0.90, and fail if fewer than three remain. Persist the selected rows plus selection provenance. Reuse the existing witness, gallery, retrieval, class-statistics, and review code, but load the new TC7/mining manifests and stable string image IDs. Preserve pending human-review state. Gate: 3–4 selected itemsets each resolve to source patches/images, retrieved count equals support, class totals agree, and review artifacts remain pending until annotated.
5. **Notebook release and README** — ensure all four notebooks begin with purpose/conditions/inputs/outputs and every code cell has an immediately preceding explanatory Markdown cell. Use the shared Julia Fashion kernel, clear stale outputs, and document run-artifact handoffs and reruns. Update README paths. Gate: clean-kernel, empty-run-directory execution of all four notebooks in order, with all expected statuses/artifacts present.

## Complexity Tracking

No constitution gate violations. The stable image-ID migration is required by the approved spec; its cost is bounded to TC release artifacts, FIM input validation, and interpretation joins. The package-level Eclat input/output API remains unchanged.
