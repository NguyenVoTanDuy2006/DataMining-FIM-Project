# Research: Fashion-MNIST Experiment Rebuild

## Decisions

### 1. EDA2 starts from verified source images and reuses the existing TC pipeline

- **Decision**: The EDA2 notebook downloads and verifies the original Fashion-MNIST files, runs the existing TC1–TC4 pipeline, then continues through assignment and S0 export. It fits the complete matrix `K = [16, 32, 64, 128, 256] × seed = [42, 123, 2026]`.
- **Rationale**: This reproduces the configuration search from its actual input and avoids a second implementation of patch extraction, filtering, descriptor construction, and K-means.
- **Alternatives considered**: Upload previously generated S0 runs or only refit from saved descriptors. Both omit part of the requested reproducible experiment and make results depend on untracked prior outputs.
- **Evidence**: `configs/transactions/combined_full.toml`, `FashionTC.jl`, and `transaction_construction/pipeline/` define the existing pipeline and configuration. `dataset/FashionMNIST.jl` provides download, checksum verification, and IDX loading.

### 2. Preserve the release preprocessing and fit settings

- **Decision**: Use all 70,000 images; non-overlapping 4×4 patches; strict pixel threshold `>29`; raw, normalized 16-dimensional Float32 descriptors; full retained-descriptor fitting; K-means++ with squared Euclidean distance; 300 iterations and tolerance `1e-4`; CPU execution.
- **Rationale**: These settings are already recorded in the full combined configuration and match the user-approved search. The feature changes orchestration and reporting, not experiment semantics.
- **Alternatives considered**: Sampling descriptors, changing the threshold, or adding a quantized/weighted K-means variant would create a different experiment and are out of this feature's scope.

### 3. Make a fit checkpoint portable, but rebuild preprocessing on resume

- **Decision**: After every K–seed fit, package its existing checkpoint, codebook, and fit metrics plus an explicit 15-row progress manifest. On resume, validate the input/configuration fingerprint, stage valid completed fits, and let TC4 skip them.
- **Rationale**: This limits repeated expensive K-means work after a Colab reset and reuses the source checkpoint protocol.
- **Alternatives considered**: A checkpoint containing only a local path is not portable. Serializing the full descriptor matrix could make resume faster but adds a very large artifact and a new data contract. The first version therefore downloads/reloads the source images and rebuilds TC1–TC3 descriptors before resuming fits.
- **Known cost**: A resumed runtime still pays dataset and descriptor-preparation time. Full sweep wall time is unknown and must be measured in the Colab acceptance run.

### 4. Generate all transaction variants before EDA2

- **Decision**: One transaction-generation cell runs TC5/TC6/TC7 for S0, then generates S1, S3, and S6-B for each successfully fitted K–seed pair. EDA2 begins only after all spatial outputs have been finalized, yielding up to 60 matched transaction sets and 45 spatial outputs.
- **Rationale**: The comparison must use the same 15 codebooks and all four representations. A separate generation cell prevents EDA2 from analyzing an incomplete three-variant set and makes the notebook sequence explicit.
- **Alternatives considered**: Creating S6-B after EDA2 excludes it from the transaction comparison. Keeping two notebooks risks a stale or mismatched handoff. Both conflict with the user's request to analyze S6-B alongside S0/S1/S3.

### 5. Apply variant-specific integrity checks

- **Decision**: Keep S1's 2×2 region and S3's three-stripe checks separate. For S6-B, validate its relation mapping, item bounds, transaction length, and TC6 geometry witnesses, and summarize neighbor-edge cases separately.
- **Rationale**: S6-B encodes relations between retained patches rather than absolute region or stripe membership. Requiring it to project every word and empty status to S0 would incorrectly reject images with isolated retained patches.
- **Edge rules**: Candidate pairs are distinct in-bounds positions on the 7×7 patch grid with Manhattan distance 1–2; pairs do not wrap across image edges. Boundary accounting is separate: 124 valid candidate pairs touch an outer edge, 20 touch a corner, and 68 additional pairs would be eligible only if opposite edges wrapped and must be excluded. Report actual eligible edge/corner pairs after patch filtering. A missing/filtered patch prevents its pair from contributing. A diagonal pair may emit both `ABOVE` and `LEFT_OF`; identical words at distinct patches are allowed; relation items are deduplicated within a transaction; an image with no eligible pair has an empty S6-B transaction.

### 6. Recommend K and representation using separate, inspectable evidence

- **Decision**: Aggregate codebook quality and stability over the three seeds for each K. Include S0/S1/S3/S6-B transaction length, diversity, and common Eclat evidence in each K row; compare all four representations as matched K–seed inputs. Produce separate K and representation recommendations with supporting metrics, tradeoffs, failed scope, and uncertainty. Label the recommendation as scoped to this pilot; optional C2/C3 results can supplement it but are not silently treated as complete.
- **Rationale**: No single metric defines the best exploratory representation. An itemset count alone can reward dense or redundant transactions and does not establish downstream predictive value.
- **Alternatives considered**: A single weighted score has arbitrary weights and hides tradeoffs; selecting one seed is unstable; classification accuracy is outside this experiment and would require a separately controlled evaluation.
- **Analysis boundary**: Keep current EDA2 descriptive measures, C1 settings, timeouts, and optional C2/C3/review controls. A recommendation is marked provisional if the required fit/encoding/mining evidence is incomplete; no classifier claim is made.

### 7. Use an all-variant stage archive and one final archive

- **Decision**: After EDA2, write a validated `fashion_eda2_stage` archive with S0/S1/S3/S6-B, all analysis outputs, and spatial summaries. The final packaging section can consume it in a fresh runtime or the current one and write `fashion_full_experiment` without rerunning computation.
- **Rationale**: The intermediate archive protects work across Colab resets; the final archive gives the user one complete deliverable.
- **Alternatives considered**: Recomputing Part 1 after a reset repeats expensive fits and mining. Requiring users to manually extract or rebuild bundles adds fragile steps.

### 7. Treat every transferred archive as untrusted input

- **Decision**: Keep relative-path validation, exact file inventories, run identity checks, file sizes, SHA-256 checks, staged extraction, and explicit producer/consumer provenance. A source commit mismatch alone is recorded; incompatible data/configuration or invalid hashes block reuse.
- **Rationale**: Colab transfer and checkpoints cross runtime boundaries. Existing `ExperimentBundleIO.jl` already centralizes safe archive behavior for Fashion artifacts.
- **Alternatives considered**: Relying on filenames or trusting a tar archive without validating members cannot detect corruption or path traversal.

### 8. Verify the actual Colab Julia environment during acceptance

- **Decision**: Pin dependencies in a checked-in Julia environment, print the actual Julia and package versions in the notebook, and stop with an actionable error if the selected Colab runtime cannot instantiate that environment. Do not silently resolve floating versions.
- **Rationale**: Colab runtime images change. Its official runtime FAQ lists Julia in some runtime images, while the general FAQ says Colab's primary focus is Python and availability of other kernels is not guaranteed. The exact CPU runtime must therefore be checked when the notebook is run.
- **Alternatives considered**: Assuming any current Colab runtime has the same Julia kernel creates an unverified setup promise. Switching to Python orchestration contradicts the user's requirement for Julia execution.

## Risks and follow-up

- The full CPU run fits 15 codebooks against all retained descriptors and mines up to 60 transaction databases. No end-to-end runtime estimate exists; log elapsed time and memory in acceptance without promising a duration.
- Existing EDA2 config has an 8 GiB memory-cap field that is not enforced. Do not present it as a hard limit; resource behavior must be reported from actual measurements.
- A fit checkpoint can be reused only when dataset hashes, preprocessing, source revision, K/seed, fit settings, and relevant Julia/library identity match. Otherwise the notebook must reject it or make the mismatch explicit; it must never blend incompatible runs.
- Cluster stability currently uses the configured fixed descriptor sample. Confirm its provenance and metric interpretation in the recommendation report before treating it as comparable evidence.
- Recommendation evidence can be incomplete when a fit, spatial encoding, or Eclat database fails or times out. Preserve successful results but qualify the recommendation and scope.

## Sources

- Repository configuration and implementation: `src/applications/Fashion-Mnist/configs/transactions/combined_full.toml`, `src/applications/Fashion-Mnist/FashionTC.jl`, `src/applications/Fashion-Mnist/dataset/FashionMNIST.jl`, `src/applications/Fashion-Mnist/spatial/FashionTCSpatial.jl`, `src/applications/Fashion-Mnist/transaction_eda/`, and `src/applications/Fashion-Mnist/notebook_tools/ExperimentBundleIO.jl`.
- Colab runtime-version FAQ: <https://research.google.com/colaboratory/runtime-version-faq.html>.
- Colab FAQ: <https://research.google.com/colaboratory/faq.html>.
- Julia package environments and manifests: <https://pkgdocs.julialang.org/dev/toml-files/>.
