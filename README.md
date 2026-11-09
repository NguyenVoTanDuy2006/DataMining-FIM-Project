# Eclat Frequent Itemset Mining

Julia project for a from-scratch Eclat implementation, SPMF comparison, four benchmarks, and two applications: Groceries and Fashion-MNIST. See [the project plan](docs/plan.md) and [assignment](docs/itemset.md) for requirements.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy (TV3, Fashion-MNIST and demo).

## Current state

The Fashion-MNIST download, checksum verification, IDX reader, and basic EDA
are implemented in Julia. Eclat, the remaining applications, and benchmark
runner are still under development.

## Julia setup

Install Julia 1.9 or newer, then run:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EclatFIM'
```

Dependencies are pinned in `Project.toml` and `Manifest.toml`. Run the tests
and open the Julia notebooks from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
julia --project=. -e 'using IJulia; IJulia.notebook(dir="notebook")'
```

Choose the Julia 1.13 kernel in Jupyter. The notebooks activate this project
themselves and work independently from a fresh kernel.

## Fashion-MNIST: dataset validation and EDA

- [01 — Download, checksums, and dataset validation](notebook/01_fashion_mnist_dataset.ipynb)
- [02 — Basic EDA](notebook/02_fashion_mnist_eda.ipynb)

The official `.gz` archives are kept locally under `data/raw/fashion-mnist/`
and are not committed. Notebook 01 validates SHA-256, image/label IDX headers,
28×28 grayscale images, labels 0–9, and the 60,000/10,000 train/test split.
Notebook 02 reports class counts and black-pixel fractions, selects one
training image per class with seed 42, displays the sample grid, and saves the
CSV, SVG, index list, summary, and metadata to `results/fashion/`.

Latest verification: Julia 1.13.3; **43/43 tests pass**; both notebooks execute
from fresh Julia kernels; 6,000 train and 1,000 test images per class. See
`results/fashion/` for the validation report and EDA outputs.

Large source datasets belong outside Git. Place local copies under `data/raw/` or `data/benchmark/`, and document their download URLs, versions, and preparation steps. Keep reproducible summaries and selected plots under `results/`.
