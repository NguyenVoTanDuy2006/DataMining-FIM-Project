# Quickstart: Fashion-MNIST Release

This guide validates the four-notebook handoff from a clean checkout. Run the notebooks in order; Notebook 01 creates the run ID and later notebooks read manifests from that run.

## Prerequisites

- Linux with a working `systemd --user` manager and cgroup memory accounting.
- Julia 1.13 and Python 3.10 or newer.
- Network access for the first archive download, or the four official Fashion-MNIST archives in `data/raw/fashion-mnist/`.
- Enough disk space for the 70,000-image transaction artifacts and bounded mining outputs.

## Install Notebook Dependencies

From the repository root:

```bash
python -m pip install 'jupyter>=1.1.1' 'nbclient>=0.10.2' 'nbformat>=5.10.4'
julia src/applications/Fashion-Mnist/notebook_tools/install_fashion_tc_kernel.jl
```

The script instantiates the Julia project at the repository root and installs the `fashion-mnist-tc` kernel. The notebooks and mining workers share that project and manifest. Run the installer again if you previously registered the kernel.

## Run and Verify

First run the package checks, then execute each notebook from the repository root. `jupyter execute` starts a fresh kernel for each notebook; the long timeout allows the full-data K-means and bounded mining runs to finish:

```bash
julia --project=. test/runtests.jl
jupyter execute notebook/UD2/release/01_dataset_validation.ipynb --inplace --kernel_name=fashion-mnist-tc --timeout=86400 --startup_timeout=120
jupyter execute notebook/UD2/release/02_transaction_construction.ipynb --inplace --kernel_name=fashion-mnist-tc --timeout=86400 --startup_timeout=120
jupyter execute notebook/UD2/release/03_frequent_itemset_mining.ipynb --inplace --kernel_name=fashion-mnist-tc --timeout=86400 --startup_timeout=120
jupyter execute notebook/UD2/release/04_visual_interpretation.ipynb --inplace --kernel_name=fashion-mnist-tc --timeout=86400 --startup_timeout=120
```

Continue only after each completion manifest reports success:

1. `notebook/UD2/release/01_dataset_validation.ipynb` — expect 60,000 train and 10,000 test images; all archive hashes pass; a new `results/fashion/release/<run_id>/dataset/dataset_manifest.toml` is written.
2. `notebook/UD2/release/02_transaction_construction.ipynb` — load that dataset manifest; expect one B0/K=32/seed=123 codebook, 70,000 S0 rows, and a passing TC7 manifest with transaction hash and TID mapping.
3. `notebook/UD2/release/03_frequent_itemset_mining.ipynb` — load the TC7 manifest; verify Linux user systemd; run Set and BitVector at six thresholds with equal limits. Expect 12 statuses and an exact key/support parity row for every complete pair. The notebook first seeds one Set pattern from `(length 1, high support)`, `(length 2, mid support)`, and `(length >=3, low support)`, then fills by the fixed nine-cell grid. Jaccard must be ≤0.80; if four do not pass, it restarts once at ≤0.90. It outputs 3 only if no fourth pattern passes and fails if fewer than 3 pass. Inspect `mining/selection_manifest.toml`, `mining/representative_patterns.csv`, and `mining/selected_itemsets.csv`.
4. `notebook/UD2/release/04_visual_interpretation.ipynb` — load the automatic 3–4 pattern selection; expect source centroid/patch/image evidence, retrieved counts equal to supports, class summaries, and review status `PENDING_REVIEW` until annotations are entered.

The project Python dependencies are declared in `pyproject.toml`. Julia dependencies for both Eclat and the notebooks are in the root `Project.toml` and `Manifest.toml`. Run through Jupyter or `jupyter execute` with the `fashion-mnist-tc` kernel and a long cell timeout for the full-data steps. Keep the generated run directory intact when rerunning only a downstream notebook.

## Failure Checks

- If Notebook 01 reports a hash or IDX failure, it must not write a valid dataset manifest; restore/download the official archives and rerun it.
- If Notebook 02 reports a missing/mismatched manifest, use the dataset manifest created by Notebook 01 for the same run ID.
- If user systemd limits are unavailable, mining must stop before launching workers. If a worker reaches a bound, keep its explicit status and do not treat that backend pair as parity-passed.
- If mining parity passes but interpretation retrieval differs from stored support, treat the visual handoff as failed and inspect mapping/assignment hashes before writing report conclusions.
