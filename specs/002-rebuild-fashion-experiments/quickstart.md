# Quickstart: Unified Fashion-MNIST Experiment

The experiment uses one Julia notebook. It starts from the original Fashion-MNIST files, fits 15 K–seed configurations, creates S0/S1/S3/S6-B before EDA2, then analyzes all 60 transaction sets. The region and stripe checks apply only to S1/S3. S6-B uses separate checks for neighbor pairs, image-grid edges, diagonal pairs, same-word relations, and empty transactions. Colab's `/content` storage is temporary; download checkpoints and archives before a runtime ends.

## Run the notebook end to end

1. Open `notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb` in a Colab runtime with a Julia kernel and CPU selected.
2. Run the setup cells. They clone the `Fashion-Mnist` source, instantiate its checked-in Julia environment, and print the source commit, Julia version, and thread settings.
3. Run the notebook in order. It downloads and verifies the four original Fashion-MNIST files, runs TC1–TC7, fits all five K values for all three seeds, and uses one transaction-generation cell for S0/S1/S3/S6-B. EDA2 begins only after the spatial generation and integrity checks finish.
4. Review the per-K recommendation tables and matched representation comparisons. S6-B appears in transaction length, support, diversity, class-similarity, common Eclat, and recommendation evidence. Its edge summary is separate from S1/S3 region and stripe summaries.
5. Download `fashion-eda2-stage-*.tar.gz` after EDA2. It contains the fit records, 60 transaction sets, 45 spatial statuses, analysis artifacts, manifests, and checksums.
6. Run the final packaging section in the same runtime, or upload the stage archive in a clean runtime and run that section. It validates the archive and writes `fashion-full-experiment-*.tar.gz` without rerunning the experiment.
7. Download the final archive through the Files pane. A complete run includes a portable `eda2_database_manifest.toml` with all 60 transaction references and checksums; a partial run records each status and does not claim that manifest is ready.

Expected full scope: 15 K–seed fits; 15 transaction sets for each of S0, S1, S3, and S6-B; and 45 spatial outputs. The recommendation summarizes codebook metrics across seeds for K and compares all four representations in matched K–seed pairs. Eclat evidence is scoped to the configured common pilot (currently 3% minimum support and maximum itemset length 2); optional deeper mining and manual pattern review retain their own statuses. The notebook reports failed, missing, or censored work and makes no classification claim.

## Resume after a Colab reset

### Resume K-means fits

Upload the latest `fashion-eda2-checkpoint-*.tar.gz` through the Files pane. In the setup cell, set `FIT_CHECKPOINT_ARCHIVE` to its `/content/...` path, then rerun the setup and experiment cells. The notebook reloads verified images and rebuilds descriptors, checks source, dataset, preprocessing, Julia, and Clustering.jl fingerprints before staging completed K–seed fits, and then continues missing fits.

### Package a completed EDA2 stage

Upload the `fashion-eda2-stage-*.tar.gz` archive created after EDA2. Start a fresh runtime, run the Julia setup cell, set `PART1_STAGE_ARCHIVE_PATH` in the final packaging cell, and run that cell. The notebook validates the stage inventory, lineage, source and notebook checksums, configuration, Julia version, and Clustering.jl version; it then writes the final archive without refitting codebooks, regenerating transactions, or rerunning EDA2.

An incompatible archive is rejected before its outputs are combined. Do not delete the only downloaded copy of a checkpoint or stage archive until the final archive is verified. Existing local outputs under `results/fashion/tc/tc6_configs/` and `results/fashion/eda2/v1` or `v2` are historical results; the notebook creates a run-specific output directory and does not use the sibling `TeamProject-FrequentItemsetMining-eda2` checkout as an input.

## Local validation

From the repository root, instantiate the pinned environment and run the focused checks:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
python src/applications/Fashion-Mnist/notebook_tools/validate_release_notebooks.py
```

Local checks do not prove full Colab CPU compatibility or full-sweep performance. Verify the downloaded final archive against its manifest after the Colab acceptance run.
