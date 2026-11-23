# Eclat Frequent Itemset Mining

Julia project for Eclat frequent itemset mining, benchmark experiments, and the Groceries and Fashion-MNIST applications. See [the project plan](docs/plan.md) and [assignment](docs/itemset.md) for requirements.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy (TV3, Fashion-MNIST and demo).

## Current state

The Fashion-MNIST release workflow is organized as four ordered notebooks under
`notebook/UD2/release/`. The TC4 vector benchmark, spatial extension, and
[exploratory data analysis of Fashion-MNIST transactions (EDA2)](notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb)
are in `notebook/UD2/experiments/`. EDA2 compares codebook quality, transaction
density and diversity, and pilot Eclat results across codebook sizes, seeds, and
S0/S1/S3 encodings.

Julia callers can load the application with `using EclatFIM: FashionMNIST`.
The [FashionMNIST module](src/applications/Fashion-Mnist/FashionMNIST.jl) groups
dataset loading, transaction construction, Spatial, EDA2, and mining. Existing
notebooks and scripts can still use their `EclatFIM` entry points.

The [FashionTC module](src/applications/Fashion-Mnist/FashionTC.jl) runs both
transaction construction profiles. The split profile fits on train and exports
separate train and validation text files. The combined profile takes smoke, full,
or release configuration and exports S0 JSONL with image and patch mappings.
Both use the same K-means, word assignment, and binary BoVW implementations.

Under `src/applications/Fashion-Mnist/`, `dataset/` handles verified archive
and IDX loading, and `spatial/` handles location-aware transaction encodings.
`transaction_eda/` contains input checks, transaction and codebook analysis,
pilot mining, and pattern review.
`mining/` prepares transaction inputs for the Julia worker. Both use readers
from `transaction_io/`, which also handles the TC and spatial artifacts.
Mining scripts live in `mining/scripts/`, and the kernel installer and release
notebook validator live in `notebook_tools/`.

The application keeps its TOML profiles under [configs/](src/applications/Fashion-Mnist/configs/).
`transactions/` groups split, combined, and release profiles. `spatial/` holds
the smoke and full profiles. `transaction_eda.toml` configures the exploratory
analysis of S0, S1, and S3 transactions.

To run the split transaction smoke profile from the command line:

```sh
julia --project=. src/applications/Fashion-Mnist/transaction_construction/scripts/run_tc.jl split_smoke
```

## Julia setup

Install Julia 1.13 and Python 3.10 or newer, then run:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EclatFIM'
```

Dependencies are pinned in `Project.toml` and `Manifest.toml`. Run the tests
and open the Julia notebooks from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
julia src/applications/Fashion-Mnist/notebook_tools/install_fashion_tc_kernel.jl
python -m pip install -e .
```

Choose the Julia Fashion-MNIST TC kernel in Jupyter. The kernel, notebooks,
and Julia workers all use the repository root project. That project also
includes IJulia and the PNG libraries used by notebook 01. If you previously
installed the kernel, run the installer again to update its project path.

## Fashion-MNIST release

Run these notebooks in order from fresh Julia kernels. Notebook 01 creates a
run ID; notebooks 02–04 consume artifacts under the same
`results/fashion/release/<run_id>/` directory.

1. [01 — Dataset validation](notebook/UD2/release/01_dataset_validation.ipynb):
   downloads or reuses the four official archives, verifies SHA-256 and IDX
   dimensions/counts, displays one image per class, and writes
   `dataset/dataset_manifest.toml`.
2. [02 — Transaction construction](notebook/UD2/release/02_transaction_construction.ipynb):
   builds S0 using one B0 codebook with K=32 and seed 123 across all 70,000
   images. Its handoff is `transactions/tc7_manifest.toml`, containing hashes
   and paths for transactions, codebook, centroids, assignments, image mapping,
   metadata, config, and integrity report.
3. [03 — Frequent itemset mining](notebook/UD2/release/03_frequent_itemset_mining.ipynb):
   compares Set and BitVector at 80%, 60%, 40%, 20%, 10%, and 5% support.
   `mining/comparison.csv` reports itemset counts, exact parity, runtime, peak
   RSS, and job status. It automatically selects four representative Set
   patterns by seeding one from length/support cells `(1/high)`, `(2/mid)`,
   and `(>=3/low)`, then filling by the fixed nine-cell grid under the Jaccard
   diversity limit. If a fourth pattern cannot pass after one relaxation, it
   selects three; fewer than three stops with an error. Review
   `mining/selection_manifest.toml` for the rule and selected order,
   `mining/representative_patterns.csv` for each pattern's support/length
   buckets and diversity score, and `mining/selected_itemsets.csv` for the
   Notebook 04 handoff. The full `itemset_selection_candidates.csv` is an
   audit catalog; no manual edits are needed.
4. [04 — Visual interpretation](notebook/UD2/release/04_visual_interpretation.ipynb):
   traces the automatically selected 3–4 patterns to centroids, source patches,
   images, and class counts, then writes a review sheet and a report marked
   `PENDING_REVIEW`.

Prerequisites are Julia 1.13, Python 3.10+, the `fashion-mnist-tc` Julia
kernel, and Linux `systemd --user` with cgroup memory accounting for mining.
For the first run, Notebook 01 downloads the official dataset if the archives
are absent; otherwise it checks the local files in `data/raw/fashion-mnist/`.
Large archives and generated run artifacts are not committed. See
[`specs/001-fashion-notebook-release/quickstart.md`](specs/001-fashion-notebook-release/quickstart.md)
for setup and rerun details.

Large source datasets belong outside Git. Place local copies under `data/raw/` or `data/benchmark/`, and document their download URLs, versions, and preparation steps. Keep reproducible summaries and selected plots under `results/`.
