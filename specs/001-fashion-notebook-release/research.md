# Research: Fashion-MNIST Notebook Release

**Feature**: [spec.md](spec.md)

**Date**: 2026-11-21

Repository code, configs, notebooks, tests, and `docs/plan.md` were treated as the primary sources. They resolve the technical unknowns in the specification; no additional package or external service is needed.

## Decisions

### 1. Reuse the verified Fashion-MNIST reader

- **Decision**: Use `src/applications/Fashion-Mnist/dataset/FashionMNIST.jl` from Notebook 01 for downloads, archive SHA-256 checks, gzip IDX validation, and train/test loading.
- **Rationale**: It already pins all four official archive hashes and checks IDX magic values, payload length, image dimensions, label range, and split counts. Duplicate parsers would create another source of truth.
- **Alternatives considered**: Keep the old notebook's embedded parsing/download logic; rejected because it duplicates package validation and currently has Colab/Drive-specific exports.

### 2. Reuse TCv2 and add a separate release profile

- **Decision**: Keep the TC1–TC7 implementation in `src/applications/FashionTCv2.jl`; add `src/applications/Fashion-Mnist/configs/transactions/release.toml` and a release execution mode for the fixed all-image B0/K=32/seed=123 configuration.
- **Rationale**: TCv2 already implements patch geometry, strict `pixel > 29` filtering, 16-value descriptors, full-batch K-means, nearest-centroid assignment, S0 encoding, artifact export, and reload validation. Its full mode currently enforces five K values × three seeds, so it cannot represent the release's one-pair run without a separate mode.
- **Alternatives considered**: Weaken the full-mode validation; rejected because it would silently change the existing 15-codebook experiment contract. Reimplement TC1–TC7 inside the notebook; rejected because it would duplicate the tested pipeline.

### 3. Version and migrate the release image identity

- **Decision**: Serialize the canonical stable image ID as `train:<zero-based-index>` or `test:<zero-based-index>` in release manifests, transactions, mappings, patch assignments, and metadata. Keep the current numeric global index only as an internal array position where useful.
- **Rationale**: The approved spec defines split plus zero-based position. Current TC output uses numeric IDs 1–70,000 and separate 1-based split indices; `FashionFIMWorkflow` and `interpretation.py` also assume numeric IDs. A versioned schema and coordinated readers/writers avoid ambiguity and preserve traceability.
- **Alternatives considered**: Preserve numeric image IDs and expose a second stable key; rejected because it leaves two competing meanings for `image_id` and weakens the approved identity rule. Replace numeric values in core array-index operations; rejected because they are implementation indexes, not external identity.
- **Scope note**: The release codebook is fit on descriptors retained from all 70,000 images, including test-split images, as explicitly specified. Results are descriptive/transductive; this release does not claim held-out classifier performance.

### 4. Keep the Eclat API; extend the worker/supervisor boundary

- **Decision**: Continue calling `EclatFIM.mine(transactions, min_count; backend=:set|:bitvector)`. Add backend selection to `src/applications/Fashion-Mnist/mining/scripts/run_mining_worker.jl` and include backend in the Python supervisor's configuration, run namespace, and manifests.
- **Rationale**: The public miner already dispatches both backends. The current worker omits `backend`, so every run is Set, and the supervisor currently allocates one canonical run per threshold. The missing behavior is orchestration and comparison, not another miner API.
- **Alternatives considered**: Create separate copies of the supervisor; rejected because shared status/error/resource behavior would drift. Change the package API; rejected because no API change is needed.

### 5. Preserve bounded, comparable mining runs and audit complete outputs

- **Decision**: Reuse the current systemd user-service supervisor and its six thresholds (56,000, 42,000, 28,000, 14,000, 7,000, 3,500). Run backend batches sequentially under one thread, 3,072 MiB memory, no swap, 3,600 seconds, and an 8 GiB per-output limit. Add exact Set-versus-BitVector key/support comparison and an independent support audit for the candidate itemsets.
- **Rationale**: These are the supervisor's existing defaults and the thresholds exactly represent the requested percentages over 70,000 transactions. Existing audits check individual output integrity, selected supports, and cross-threshold containment but do not compare backends. The old supervisor also rejects empty production transactions and applies historical singleton/pair guardrails to every input; the release must preserve empty records and scope old guardrails to their exact historical input identity.
- **Alternatives considered**: Run both backends concurrently; rejected because resource contention weakens runtime/RSS comparability. Treat matching itemset counts as parity; rejected because keys and support values must be compared exactly. Drop all resource caps; rejected because an interrupted worker must produce an explicit bounded status.

### 6. Automatically choose a small, diverse itemset sample for interpretation

- **Decision**: Adapt `src/applications/Fashion-Mnist/mining/scripts/interpretation.py` to read 3–4 Set itemsets selected by a deterministic rule in Notebook 03, and bind the selection and rule-manifest hashes to interpretation provenance.
- **Prior-art check**: The retained `EDA2_FashionMNIST_Transaction_Evaluation.ipynb` manually chooses configurations, not frequent itemsets; TC4's repeat selection uses median runtime; `05_tc6_spatial_extension.ipynb` does not define a pattern selector. The applicable pattern-selection criteria are in the existing v1.3 implementation in `src/applications/Fashion-Mnist/mining/scripts/analysis.py` and its FIM spec: length buckets 1/2/≥3, support tertiles over distinct support counts with ties grouped, nine-cell length-major round-robin, within-cell ordering by descending support then length and item IDs, Jaccard ≤0.80, and one-time relaxation to ≤0.90.
- **Small-sample adaptation**: Applying the old length-major traversal unchanged to a target of four filled the quota with one singleton and three pairs, despite thousands of length-3+ candidates. The release therefore seeds (1/high), (2/mid), and (≥3/low) before filling any remaining slot with the original nine-cell traversal. This preserves deterministic ranking and diversity while actually covering all three length buckets when candidates pass the rule.
- **Rationale**: The user sets the release target to four and accepts three only if a fourth cannot pass the diversity rule. Existing interpretation code already validates support, finds patch witnesses, retrieves supporting images, computes class statistics, creates galleries, and writes pending-review annotations.
- **Alternatives considered**: Select only top-support patterns; rejected because it overweights frequent patterns and does not cover lengths/support bands. Rebuild interpretation in Julia; rejected because the Python workflow is reusable and no language change is required.

### 7. Promote the four primary notebooks and update their narrative

- **Decision**: Adapt the current dataset, TC, FIM mining, and visual interpretation notebooks into `notebooks/fashion-mnist/archive/release/`; retain only the TC4 vector benchmark, spatial extension, and EDA2 notebook under `experiments/`.
- **Rationale**: The current primary notebooks are in `experiments/`, while README links point to older root-level notebook paths. The release needs one unambiguous four-step entry point and Markdown setup/explanation immediately before each code cell.
- **Alternatives considered**: Keep all seven notebooks in the release directory; rejected because the user explicitly deferred three. Keep stale README links; rejected because clean-checkout users would not find the release sequence.

## Repository Evidence

- `src/applications/Fashion-Mnist/dataset/FashionMNIST.jl`: official archive URLs and four SHA-256 values; checksum-safe download; gzip IDX checks.
- `src/applications/FashionTCv2.jl`: TC1–TC7 pipeline and full-mode configuration guard.
- `src/applications/Fashion-Mnist/configs/transactions/combined_full.toml`: all 70,000 images, K `[16,32,64,128,256]`, seeds `[42,123,2026]`.
- `src/applications/Fashion-Mnist/mining/scripts/supervisor.py`: systemd limits, six min-count thresholds, durable run manifests and sidecars; one backend namespace today.
- `src/applications/Fashion-Mnist/mining/scripts/run_mining_worker.jl`: invokes the default Set backend and rejects empty production transactions today.
- `src/fashion_fim/FashionFIMWorkflow.jl`: transaction loader currently stores numeric `image_id` values.
- `src/applications/Fashion-Mnist/mining/scripts/analysis.py`: existing v1.3 deterministic nine-cell representative selector; `src/applications/Fashion-Mnist/mining/scripts/interpretation.py` provides patch witnesses, retrieval, class counts, galleries, and review output.
- `notebooks/fashion-mnist/archive/experiments/`: contains the seven current Fashion notebooks; four are promoted, three remain deferred.
- `README.md`: current links do not identify the new release directory.
- `docs/plan.md`: shared Eclat input/output contract and Fashion transaction expectations were reviewed before proposing data-boundary changes.

## Risks Closed by These Decisions

- **Profile interference**: A separate release mode preserves the existing full profile's 15 fits.
- **Schema drift**: Every release boundary uses a canonical string image ID and a new schema version.
- **Invalid empty-row rejection**: The mining path accepts empty transactions and retains them in the support denominator.
- **False historical guardrails**: Old singleton/pair expectations are evaluated only for their matching recorded input hash; the 7,228 reference is marked not applicable for other inputs.
- **False parity**: A parity result requires completed runs and exact itemset/support equality, not equal output sizes.
- **Unreproducible interpretation**: Automatically selected itemsets, the selection-rule version, source output hashes, and the selection manifest are persisted in the shared run directory.
