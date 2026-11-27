# Feature Specification: Unified Fashion-MNIST Experiment Notebook

**Implementation Branch**: `Fashion-Mnist`

**Created**: 2026-11-27

**Status**: Draft

**Input**: Rebuild the Fashion-MNIST EDA2 and TC6 experiment flow as one Julia notebook with two ordered parts.

## Clarifications

### Session 2026-11-27

- Q: EDA2 bắt đầu từ ảnh gốc hay nhận sẵn descriptor? → A: Bắt đầu từ ảnh gốc, chạy TC1–TC3 rồi fit đủ 5 giá trị K × 3 seed.
- Q: S1/S3 được tạo trong cùng lượt EDA2 hay chờ TC6? → A: EDA2 tự tạo S0/S1/S3 trong cùng lượt để so sánh.
- Q: Tiêu chí chọn “tốt nhất” là gì? → A: Dùng nhiều bằng chứng về codebook, đặc điểm giao dịch và Eclat; giải thích đánh đổi, không chỉ tối đa số tập mục.
- Q: Chọn K và biểu diễn như thế nào? → A: Tổng hợp ba seed để khuyến nghị K; so sánh S0/S1/S3 theo cặp K–seed; nêu khuyến nghị K và biểu diễn riêng.
- Q: Nếu Colab ngắt giữa lượt chạy thì sao? → A: Lưu checkpoint theo từng K–seed để tải lên phiên mới và bỏ qua các fit đã hoàn thành.
- Q: EDA2 và TC6 nên là hai notebook riêng hay một notebook chia phần? → A: Một notebook gồm hai phần. Phần 1 chạy EDA2 và tạo S0/S1/S3; Phần 2 dùng lại các kết quả đó, tạo S6-B và hoàn tất gói spatial. Đây là một lượt làm việc thống nhất; không chạy lại S1/S3 ở Phần 2.
- Q: Thứ tự tạo và phân tích các biểu diễn là gì? → A: Gộp cell tạo S0 và cell tạo S1/S3; tạo cả S1, S3, S6-B trước EDA2, rồi phân tích 60 bộ giao dịch trên cùng các cặp K–seed.
- Q: Quy tắc kiểm tra không gian áp dụng ra sao? → A: Kiểm tra vùng 2×2 và dải ngang chỉ áp dụng cho S1/S3. S6-B có kiểm tra riêng cho cặp patch lân cận, patch bị lọc, đường biên lưới, cặp chéo, quan hệ cùng từ, item trùng và giao dịch không có cặp hợp lệ.

## User Scenarios & Testing

### User Story 1 — Run the complete experiment in one notebook (Priority: P1)

A researcher opens one Julia notebook in a fresh Colab CPU runtime. It starts from verified Fashion-MNIST images, builds descriptors, fits all 15 K–seed configurations, creates S0/S1/S3/S6-B, and analyzes the 60 matched transaction sets. The analysis compares codebook evidence by K and transaction representations by matched K–seed, including S6-B. A final packaging section validates the stage archive and exports one complete experiment archive.

**Why this priority**: A single notebook presents the full experiment in its actual order and avoids rerunning S1/S3 between EDA2 and TC6.

**Independent Test**: Start from a clean runtime and raw Fashion-MNIST data; execute both parts in order; verify the 15 fits, 45 compared transaction sets, 45 spatial outputs, recommendation evidence, and final archive manifest.

**Acceptance Scenarios**:

1. **Given** a fresh compatible Julia CPU runtime, **when** Part 1 runs, **then** it downloads and verifies the original data, builds descriptors, and records one explicit status for every K = 16, 32, 64, 128, 256 and seed = 42, 123, 2026.
2. **Given** completed fits, **when** the combined generation cell runs, **then** it produces up to 15 sets each of S0, S1, S3, and S6-B with matching `(K, seed)` lineage before starting EDA2.
3. **Given** complete transaction inputs, **when** EDA2 runs, **then** its length, support, diversity, class-similarity, Eclat, K-by-representation, and representation comparison outputs include S6-B.
4. **Given** spatial integrity checks, **when** EDA2 validates spatial encodings, **then** the S1/S3 projection and region/stripe checks apply only to S1/S3, while S6-B receives separate neighbor geometry and boundary checks.
5. **Given** a completed run, **when** the researcher downloads the final archive, **then** it contains the analysis, recommendation evidence, S0/S1/S3/S6-B artifacts, provenance, statuses, and checksums.
5. **Given** a failed fit or spatial encoding, **when** the notebook summarizes results, **then** it preserves compatible completed outputs, marks the missing scope, and does not label the full comparison complete.

### User Story 2 — Resume after a Colab reset (Priority: P1)

A researcher can continue the experiment in a fresh Colab session using the same notebook. A fit checkpoint resumes the remaining K–seed fits. An EDA2 stage archive stores all four encodings and analysis so the final packaging section can run in a fresh session without repeating fits, transaction creation, or EDA2 analysis.

**Why this priority**: A 15-fit full-data CPU run may outlast one Colab session, and runtime-local files disappear after reset.

**Independent Test**: Interrupt during Part 1 and resume from a compatible fit checkpoint; then separately resume Part 2 from a validated Part 1 stage archive in a clean runtime.

**Acceptance Scenarios**:

1. **Given** a compatible fit checkpoint, **when** the researcher uploads and selects it, **then** the notebook verifies its identity, rebuilds source descriptors, skips completed fits, and continues missing fits.
2. **Given** a completed EDA2 stage archive, **when** the researcher starts the notebook in a clean runtime and selects the archive, **then** it validates the archive and creates the final package without rerunning the experiment or analysis.
3. **Given** an incompatible checkpoint or stage archive, **when** validation runs, **then** the notebook rejects it before combining results and explains the identity mismatch.

### Edge Cases

- The Fashion-MNIST source archive is missing, truncated, or fails checksum validation.
- A checkpoint or stage archive has duplicate, unsafe, unexpected, or checksum-invalid files.
- Some K–seed fits, transaction variants, or spatial outputs are missing or do not match the source run identity.
- Colab resets before the latest checkpoint or Part 1 stage archive is downloaded.
- A run is censored by a configured timeout or resource limit; its status must remain explicit.
- The Julia kernel or package environment is unavailable or incompatible in the selected Colab runtime.
- At an image-grid edge, S6-B must not wrap a patch from one side to the opposite side; only in-bounds pairs at Manhattan distance 1–2 are candidates.
- Boundary accounting is separate from S1/S3 regions: the full 7×7 S6-B grid has 124 candidate pairs touching an outer edge and 20 touching a corner; 68 pairs that would qualify only under wraparound are excluded. For each image, report the eligible edge/corner pairs remaining after patch filtering.
- When one member of a candidate pair was filtered out, S6-B emits no relation for that pair; an image with no remaining eligible pair can have an empty S6-B transaction even when S0 is nonempty.
- A diagonal pair at Manhattan distance 2 can emit both `ABOVE` and `LEFT_OF`; the same visual word at distinct patch positions is valid, and repeated relation items are deduplicated per image.

## Requirements

### Functional Requirements

- **FR-001**: The single notebook MUST introduce its purpose, runtime, inputs, outputs, and the responsibilities of Part 1 and Part 2 before execution.
- **FR-002**: The notebook MUST run from a fresh Colab CPU runtime without depending on variables or files from another notebook.
- **FR-003**: Part 1 MUST download and verify the original Fashion-MNIST data and run the existing TC1–TC5 pipeline with the agreed preprocessing and fit configuration.
- **FR-004**: Part 1 MUST fit all 15 K–seed configurations and record fit status plus comparable codebook metrics for each; incomplete fits MUST be excluded from completed-result aggregation.
- **FR-005**: The transaction-generation stage MUST generate and validate S0/S1/S3/S6-B for each completed fit before EDA2 begins, with matched `(K, seed)` identities.
- **FR-006**: Part 1 MUST analyze codebook quality/stability, transaction characteristics, and the existing common Eclat evidence, then provide separate, evidence-based K and representation recommendations with tradeoffs. It MUST NOT select solely by itemset count or claim classifier performance.
- **FR-007**: The common Eclat recommendation evidence MUST state its configured support and itemset-length scope. Optional deeper mining or manual review MUST have explicit status and MUST NOT be presented as completed when it was not run.
- **FR-008**: EDA2 MUST analyze all available S0/S1/S3/S6-B inputs over matched `(K, seed)` pairs, including S6-B transaction structure and common Eclat evidence. It MUST distinguish codebook fit metrics from downstream representation metrics.
- **FR-009**: The notebook MUST apply the 2×2 region checks only to S1 and the horizontal-stripe checks only to S3. S6-B MUST instead receive explicit neighbor mapping, item-range, transaction-length, witness-geometry, in-bounds edge, and empty-transaction checks; it MUST NOT be required to project every word or empty status exactly back to S0.
- **FR-010**: The notebook MUST save a compatible fit checkpoint after every completed K–seed fit. Resume MUST validate dataset, preprocessing, source, configuration, runtime, and fit identities before skipping completed fits.
- **FR-011**: After transaction creation and EDA2, the notebook MUST create a portable stage archive containing S0/S1/S3/S6-B and analysis outputs so final packaging can resume in a fresh runtime without rerunning the experiment. It MUST validate the archive before reuse.
- **FR-012**: The final experiment archive MUST be one downloadable file with a manifest containing input identity, configuration, source and notebook provenance, file inventory, checksums, phase statuses, and per-run statuses.
- **FR-013**: The notebook MUST distinguish `COMPLETED`, `PARTIAL`, `FAILED`, `UNAVAILABLE`, `NOT_REQUESTED`, and censored work where applicable; incomplete outputs MUST NOT be represented as completed comparisons.
- **FR-014**: The notebook MUST provide clear Julia-cell instructions for setup, checkpoint upload, stage-archive continuation, and result download through the Colab Files pane; it MUST warn that `/content` is temporary.
- **FR-015**: The notebook MUST use Julia for experiment execution and archive handling; Python MUST NOT orchestrate or perform the experiment.
- **FR-016**: Existing transaction meanings, spatial encoding semantics, EDA2 measures, Eclat APIs, and agreed experiment settings MUST be preserved unless a change is recorded and justified.
- **FR-017**: The README MUST link to the unified notebook, describe its two parts and resume artifacts, and explain the recommended end-to-end run order.

### Key Entities

- **Experiment run**: One notebook execution with input, configuration, source, runtime, phase statuses, outputs, and completion state.
- **Codebook fit**: One K–seed run in the 15-fit sweep, with fit metrics and resumable artifacts.
- **Transaction set**: A completed S0, S1, S3, or S6-B encoding linked to its source fit.
- **EDA2 stage archive**: EDA2 tables and all S0/S1/S3/S6-B artifacts needed to create the final archive after a Colab reset.
- **Spatial validation**: S1/S3 projection and region/stripe checks plus separate S6-B relation and boundary checks.
- **Recommendation report**: Separate K and representation conclusions with evidence coverage, limitations, and tradeoffs.
- **Final experiment archive**: One downloadable artifact containing both parts and a complete manifest.
- **Fit checkpoint**: A portable archive used to resume incomplete K–seed fits.

## Success Criteria

### Measurable Outcomes

- **SC-001**: One linked Julia notebook runs both parts in order from a fresh Colab CPU runtime.
- **SC-002**: Part 1 records a status and comparable codebook metrics for all 15 K–seed configurations or explicitly identifies every omitted fit.
- **SC-003**: The notebook accounts for all 60 S0/S1/S3/S6-B transaction sets or lists each missing/failed set.
- **SC-004**: EDA2 starts only after all available S0/S1/S3/S6-B outputs are generated and checked; it reports 60 database statuses and 45 spatial statuses for a full run.
- **SC-005**: The recommendation report provides separate K and representation conclusions, aggregates K evidence across seeds, compares all four variants in matched pairs, and explains tradeoffs within the measured Eclat scope.
- **SC-006**: A compatible fit checkpoint resumes the sweep without repeating completed K–seed fits; an incompatible checkpoint is rejected.
- **SC-007**: A Part 1 stage archive resumes Part 2 in a clean runtime without rerunning Part 1.
- **SC-008**: The final archive contains verifiable manifests, checksums, provenance, artifacts, and accurate complete/partial statuses.
- **SC-009**: The README links the one notebook and explains the two-part workflow and Colab transfer steps.

## Assumptions

- The two parts run in a Julia CPU runtime on Colab; the selected runtime and pinned environment are verified at notebook startup.
- EDA2 uses the existing verified dataset download and preprocessing definitions; no precomputed fit is required for a fresh run.
- The existing Eclat common pilot is evidence for exploratory frequent-itemset mining within its configured thresholds, not proof of predictive value.
- The 15-fit sweep and up to 45-database mining workload may require checkpoints and more than one Colab session.
- A Part 1 stage archive is the supported boundary for resuming Part 2 after runtime reset; no shared Drive mount is assumed.
