# Repository Guidelines

## Project Structure & Module Organization

This is a Julia Eclat project. `src/EclatFIM.jl` is the package entry point; `src/algorithm/` holds the baseline and optimized miners, `src/applications/` holds Groceries and Fashion-MNIST pipelines, and `src/utils/` holds SPMF I/O. Put runnable entry points in `scripts/`, tests in `test/`, demo cells in `notebooks/demo.ipynb`, and selected outputs in `results/`. Read `docs/plan.md` before changing the algorithm API or application data contract. `docs/itemset.md` is the assignment specification.

## Setup and Development Commands

- `julia --project=. -e 'using Pkg; Pkg.instantiate()'`: install dependencies recorded in `Project.toml` and `Manifest.toml`.
- `julia --project=. -e 'using EclatFIM'`: check that the package loads.
- `julia --project=. test/runtests.jl`: run the test suite once implemented.

Julia is required for these commands. `Manifest.toml` should be generated and committed after dependencies are chosen. The current source, scripts, test runner, and notebook are scaffolds, not finished functionality.

## Coding Style & Data Contracts

Use four-space indentation, descriptive `snake_case` filenames for scripts and `PascalCase` for Julia modules/types. Keep parsing, mining, applications, and measurement separate. The shared miner accepts `Vector{Vector{Int}}` with positive, unique item IDs per transaction; duplicate transactions remain distinct. The planned output is `Dict{Tuple{Vararg{Int}},Int}` with sorted itemset keys and support counts. Coordinate API changes with all three members. Implement Eclat from the original paper; use SPMF only as a correctness reference.

## Testing and Results

Add focused tests under `test/` and include them from `test/runtests.jl`. Compare each itemset and support count against SPMF on at least five databases; test both `Set` and `BitVector` backends. Fix random seeds, record Julia/package versions and benchmark settings, and keep large datasets out of Git. Run tests and a clean Colab demo before submission.

## Commits and Reviews

There is no commit history yet. Use short imperative subjects, such as `Add Fashion-MNIST patch extraction`. Work on separate branches and review each pull request before merging. Include the tested commands, result files, and a brief description of any changed plots or metrics.
