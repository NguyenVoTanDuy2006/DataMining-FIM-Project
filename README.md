# Eclat Frequent Itemset Mining

Julia project for Eclat frequent itemset mining, benchmark experiments, and the Groceries and Fashion-MNIST applications. See [the project plan](docs/plan.md) and [assignment](docs/itemset.md) for requirements.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy (TV3, Fashion-MNIST and demo).

## Current state

The Fashion-MNIST release workflow is organized as four ordered notebooks under
`notebook/UD2/release/`. The TC4 vector benchmark, spatial extension, and EDA2
remain in `notebook/UD2/experiments/`.

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
julia --project=environments/fashion_notebooks -e 'using Pkg; Pkg.instantiate()'
julia scripts/install_fashion_tc_kernel.jl
python -m pip install -e .
```

Choose the Julia Fashion-MNIST TC kernel in Jupyter. Each notebook activates
its runtime environment from a fresh kernel. TC uses the repository root and
runs on CPU. `environments/fashion_notebooks/` holds IJulia and the PNG export
tools needed by notebook 01, keeping them out of TC's dependencies.

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
