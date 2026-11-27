# Feature Specification: Fashion-MNIST Notebook Release

**Feature Branch**: `feature/fashion-mnist-consolidated`

**Created**: 2026-11-21

**Status**: Draft

**Input**: User description: Release four Fashion-MNIST notebooks that validate the dataset, build S0 transactions using B0/K=32/seed=123, compare Set and BitVector Eclat results, and visually interpret selected patterns. Keep the TC4 benchmark, spatial encoding, and EDA2 notebooks in `notebooks/fashion-mnist/archive/experiments/`.

## Clarifications

### Session 2026-11-21

- Q: Notebook 03 nên chọn itemset nào để bàn giao cho Notebook 04? → A: Tự động chọn tối đa 4 và tối thiểu 3 itemset từ catalog Set bằng lưới độ dài/support và lọc đa dạng Jaccard; lưu quy tắc, thứ tự và ngưỡng đã dùng để Notebook 04 đọc lại.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Validate the Fashion-MNIST dataset (Priority: P1)

A project researcher starts from a clean checkout, obtains the four Fashion-MNIST image and label archives, and verifies that the source data contains the expected train and test splits before any transactions are generated.

**Why this priority**: Every later result depends on using the correct 70,000 images and labels.

**Independent Test**: Run the dataset validation notebook with the archives absent and with valid archives present; in both cases it produces the same validated dataset manifest and reports 60,000 training images and 10,000 test images.

**Acceptance Scenarios**:

1. **Given** a clean checkout with no local Fashion-MNIST archives, **When** the researcher runs the first notebook with network access, **Then** the four archives are obtained, their SHA-256 values match the expected values, and the notebook records the verified inputs.
2. **Given** verified archives, **When** the notebook reads the IDX images and labels, **Then** it confirms 28×28 images, ten labels, 60,000 training records, and 10,000 test records.
3. **Given** a validated dataset, **When** the notebook finishes, **Then** it displays examples for each class and writes a manifest containing the archive hashes, split counts, and stable image IDs for use by the next notebook.

### User Story 2 - Build the fixed S0 transaction dataset (Priority: P1)

A project researcher turns all 70,000 validated images into one reproducible transaction dataset with the agreed B0 codebook configuration, then checks that transactions can be traced back to their source images.

**Why this priority**: The transaction dataset is the common input for mining and visual interpretation.

**Independent Test**: Run the transaction construction notebook from the validated manifest and verify its output manifest identifies B0, K=32, seed=123, S0, 70,000 transactions, one codebook, and a complete TID-to-image mapping.

**Acceptance Scenarios**:

1. **Given** the dataset validation manifest, **When** the researcher starts transaction construction, **Then** the notebook rejects missing, invalid, or mismatched input manifests before processing.
2. **Given** all 70,000 validated images, **When** the notebook constructs transactions, **Then** each image is split into 49 positioned 4×4 patches, patches with no pixel greater than 29 are excluded, and retained patches are represented by their 16 raw pixel values.
3. **Given** retained patch descriptors, **When** the notebook fits and applies the release codebook, **Then** it uses exactly one full-batch K-means codebook with K=32 and seed=123, assigns each retained patch to its nearest centroid, and records the assignments and source coordinates.
4. **Given** the patch assignments, **When** the notebook writes S0, **Then** each image has one transaction of sorted, unique visual word IDs, while its label remains available in image metadata.
5. **Given** the written transaction artifacts, **When** the notebook reloads and audits them, **Then** it confirms 70,000 transactions, one codebook, and a complete transaction-ID-to-image mapping, and writes a manifest consumed by the mining notebook.

### User Story 3 - Compare Eclat backends on the same transactions (Priority: P1)

A project researcher mines the S0 transactions with Set and BitVector backends at six fixed support thresholds and checks exact agreement as well as resource use.

**Why this priority**: The release must provide reproducible evidence that both backends return the same frequent itemsets and support counts.

**Independent Test**: Run the mining notebook using a valid TC7 manifest and confirm it produces one comparison row per backend and threshold, plus an exact itemset/support comparison for every completed pair of runs.

**Acceptance Scenarios**:

1. **Given** a valid transaction manifest, **When** the researcher starts mining, **Then** the notebook verifies the configuration, transaction count, input hash, required Linux user-systemd environment, and a successful smoke run before launching the full jobs.
2. **Given** the same S0 transaction file and recorded resource settings, **When** the notebook runs both backends, **Then** each backend is run at support thresholds 80%, 60%, 40%, 20%, 10%, and 5%, and each run records its backend, source-code hash, resource limits, elapsed time, Peak RSS, and completion status.
3. **Given** JSONL itemset outputs from both backends, **When** the notebook audits them, **Then** it recomputes support from the transactions and compares every itemset and support count between Set and BitVector at each threshold.
4. **Given** completed or failed jobs, **When** the notebook produces the comparison summary, **Then** every threshold has an explicit status and itemset count, and failed or incomplete results are not reported as a successful parity check.
5. **Given** matching output files, **When** the transaction hash matches the historical report dataset, **Then** the notebook also checks the historical reference of 7,228 itemsets at 5% support.

### User Story 4 - Interpret and report selected patterns (Priority: P2)

A project researcher uses mined itemsets to inspect their visual-word centroids, source patches, supporting images, and class distribution, then records a human review of the interpretation.

**Why this priority**: Visual evidence makes the mined patterns interpretable and suitable for the project report.

**Independent Test**: Give the interpretation notebook a valid mining manifest and selected Set itemsets; verify that it traces those itemsets to their source patches and supporting images, checks retrieved image counts against support, and creates a reviewable report.

**Acceptance Scenarios**:

1. **Given** a mining manifest and selected itemsets, **When** the researcher starts interpretation, **Then** the notebook verifies the codebook, patch assignments, image mapping, and transaction input hashes before displaying results.
2. **Given** selected visual words, **When** the notebook renders their evidence, **Then** it displays each 4×4 centroid and corresponding real source patches with their image and patch locations.
3. **Given** an itemset with supporting images, **When** the notebook builds its image gallery, **Then** it marks the supporting patches and includes contrasting images when available.
4. **Given** an itemset with recorded support, **When** the notebook retrieves matching images, **Then** the retrieved image count equals the itemset support and the notebook presents the label distribution.
5. **Given** completed visual analysis, **When** the notebook exports its review sheet and run report, **Then** the report remains marked as awaiting review until human comments are recorded.

### Edge Cases

- An archive is missing, unreadable, has a checksum mismatch, or contains an unexpected IDX count; validation stops before creating a manifest that appears valid.
- An input manifest refers to a different dataset, image-ID rule, configuration, or transaction hash; downstream notebooks stop before consuming incompatible artifacts.
- The patch filter retains no patches for an image; that image still has a transaction and mapping entry, even if its transaction is empty.
- A mining run returns zero itemsets, exceeds a resource limit, or fails; the result is represented with an explicit count and status, and is not treated as a completed parity comparison.
- No non-supporting image exists for a selected itemset; the notebook records that no contrast image is available and still shows supporting evidence.
- The retrieved supporting-image count differs from the reported support; the notebook reports an audit failure and does not label the interpretation as verified.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The release MUST provide four notebooks in `notebooks/fashion-mnist/archive/release/`, numbered and named in execution order: `01_dataset_validation.ipynb`, `02_transaction_construction.ipynb`, `03_frequent_itemset_mining.ipynb`, and `04_visual_interpretation.ipynb`.
- **FR-002**: Each notebook MUST begin with its purpose, execution conditions, inputs, and outputs.
- **FR-003**: Each code cell MUST be immediately preceded by a Markdown cell that explains the code cell's purpose, required data, and output to inspect.
- **FR-004**: The release notebooks MUST share a unique per-run output directory under `results/fashion/release/`; the first notebook creates the run identity, and later notebooks consume that run's artifacts.
- **FR-005**: Dataset validation MUST obtain or reuse the four Fashion-MNIST image and label archives, verify each archive's SHA-256 against its expected value, read both IDX splits, and validate image dimensions, labels, and split counts.
- **FR-006**: Dataset validation MUST display sample images by class and export a manifest containing verified archive identities, split counts, and stable image IDs. An image ID MUST combine its original split and zero-based record position.
- **FR-007**: Transaction construction MUST accept the validation manifest and MUST stop before processing if the manifest or any verified archive is missing or inconsistent.
- **FR-008**: The release transaction configuration MUST be exactly B0 / K=32 / seed=123 / S0 and MUST process all 70,000 images using one codebook. The existing full experimental profile MUST continue to support its 15-codebook configuration matrix.
- **FR-009**: Transaction construction MUST divide each 28×28 image into 49 non-overlapping 4×4 patches, retain patch coordinates, and keep only patches containing at least one pixel greater than 29.
- **FR-010**: Each retained patch MUST be represented by its 16 raw pixel values; the single release codebook MUST be fit with full-batch K-means on descriptors from all 70,000 images using K=32 and seed=123.
- **FR-011**: Each retained patch MUST be assigned to its nearest codebook centroid, and the output MUST retain patch-to-image and patch-coordinate provenance.
- **FR-012**: S0 MUST contain one transaction per image, with sorted unique visual-word IDs; class labels MUST be kept in associated image metadata. The notebook MUST reload and verify the transaction file, codebook count, transaction count, and TID-to-image mapping.
- **FR-013**: The transaction manifest MUST identify the transaction file, its hash, the B0/K=32/seed=123/S0 configuration, image count, and the run directory for downstream use.
- **FR-014**: Mining MUST consume the TC7 manifest and verify the input hash, configuration, and transaction count before running. It MUST verify the Linux user-systemd resource-accounting environment and run a smoke check.
- **FR-015**: Mining MUST run Set and BitVector on the same transaction file at 80%, 60%, 40%, 20%, 10%, and 5% support with the same thread and resource limits.
- **FR-016**: For each backend and threshold, mining MUST record completion status, number of itemsets, elapsed time, Peak RSS, backend identity, source-code hash, input hash, and resource settings in run manifests and a comparison table.
- **FR-017**: Mining MUST recompute itemset supports from the transaction file and compare every itemset key and support count between the two backends at each threshold. It MUST report parity only when both runs completed and all itemsets and support counts match.
- **FR-018**: When the transaction hash matches the historical report input, mining MUST verify the reference count of 7,228 itemsets at 5% support.
- **FR-019**: Notebook 03 MUST automatically select 3–4 representative itemsets from the verified Set outputs across all six support thresholds. It MUST group patterns by length (1, 2, ≥3) and support tertiles computed over distinct support counts (ties remain together). To preserve length coverage in a 3–4-pattern sample, it MUST first try one candidate from the cells (1/high), (2/mid), and (≥3/low), in that order; within a cell rank by descending support, then itemset length and lexicographic item IDs. It MUST fill remaining slots by a fixed length-major round-robin over all nine cells. Each accepted itemset MUST have maximum Jaccard similarity on visual-word IDs ≤0.80 against already selected itemsets. If fewer than four pass, it MUST restart the full selection once with a limit of ≤0.90; it MUST fail if fewer than three remain. It MUST save the selected rows and a manifest recording the rule version, candidate count/hash, selected order, threshold, and whether relaxation was used. Notebook 04 MUST consume that saved selection.
- **FR-020**: Interpretation MUST verify its manifests and hashes, render 4×4 centroids and source patches, show supporting-image evidence and available contrast images, and report class distributions.
- **FR-021**: For each interpreted itemset, the number of retrieved supporting images MUST be checked against its support count; mismatches MUST be shown as audit failures.
- **FR-022**: Interpretation MUST export a sample review sheet and a run report whose review status remains pending until human comments are recorded.
- **FR-023**: The TC4 vector-tradeoff benchmark, spatial-encoding notebook, and EDA2 notebook MUST remain in `notebooks/fashion-mnist/archive/experiments/` and MUST NOT be part of the four-notebook release sequence.
- **FR-024**: The project README MUST link to the four release notebooks, identify their handoff artifacts, and explain how to rerun them when input data is missing.

### Key Entities *(include if feature involves data)*

- **Dataset archive**: One of the train/test image or label archives, identified by split, content hash, and validated record count.
- **Image record**: One Fashion-MNIST image and label, identified by split and zero-based position, with a 28×28 pixel matrix.
- **Patch assignment**: A retained 4×4 patch linked to an image, its grid coordinates, a 16-value descriptor, and an assigned visual-word ID.
- **Codebook**: The single B0 set of 32 centroids created with seed 123 and used to encode S0.
- **Transaction**: A sorted, unique set of visual-word IDs linked to one image; its transaction ID and image ID are recorded in the mapping.
- **Mining run**: One backend and support-threshold execution with input/source hashes, resource settings, status, itemsets, elapsed time, and Peak RSS.
- **Interpreted itemset**: A selected set of visual words, its support, matching images, source patch evidence, and class distribution.
- **Release run**: A unique run identity that groups all notebook inputs, outputs, manifests, summaries, and review status.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Dataset validation confirms exactly 60,000 training images and 10,000 test images, all 28×28 pixels, across ten classes, with all four archive hashes verified.
- **SC-002**: Transaction construction produces exactly one release codebook and 70,000 transactions from the specified B0/K=32/seed=123/S0 configuration, with a complete TID-to-image mapping.
- **SC-003**: The mining summary contains results or an explicit failure status for all 12 backend-threshold combinations (two backends × six thresholds).
- **SC-004**: Every pair of completed backend runs has identical itemset keys and support counts; the audit independently recomputes support from the transaction data.
- **SC-005**: Every interpreted itemset has a displayed support count equal to the number of retrieved supporting images, or a visible audit failure.
- **SC-006**: Starting from a clean checkout, a researcher can identify the four notebooks and their handoff artifacts from the README and run directory manifests.
- **SC-007**: Notebook 03 automatically persists exactly three or four Set itemsets, with deterministic order and enough provenance to reproduce the selection; Notebook 04 interprets the persisted rows without manual CSV edits.

## Assumptions

- The intended user is a project researcher or student who can run the repository's notebooks in its documented environment.
- The four archives are the official Fashion-MNIST train/test image and label files; if absent, the dataset validation notebook can obtain them from the project's documented source.
- The release execution environment uses Julia 1.13 and Linux user systemd resource accounting as stated in the release plan.
- Image IDs use the source split plus the zero-based record position, so IDs remain stable across reruns of the same archives.
- One run ID is created for a release execution and reused by all four notebooks; outputs from different run IDs are kept separate.
- The release profile is added for FashionTCv2 without replacing the existing full experimental profile.
- Representative itemsets are selected deterministically from the verified Set catalog; human review remains required for visual coherence and interpretation claims, not for choosing which patterns Notebook 04 receives.
- A fresh run is expected to reproduce data identity, configuration, and exact itemset/support results. Elapsed time and Peak RSS are recorded for comparison but may vary by machine.
- The three deferred notebooks remain available as experiments and are outside the release acceptance criteria.
