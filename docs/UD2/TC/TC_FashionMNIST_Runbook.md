# Fashion-MNIST TC runbook

## Cài đặt và smoke

Run from the repository root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
uv sync --locked
julia --project=. scripts/install_fashion_tc_kernel.jl
uv run jupyter execute notebook/UD2/03_fashion_mnist_transaction_construction.ipynb --inplace --timeout=600
```

The installer registers the fixed Jupyter kernel name `fashion-mnist-tc`; the notebook uses that same kernel for either config. There is one code cell per TC0–TC7 step. Run top to bottom so each cell receives the state from the prior step. By default the notebook reads `configs/tc_smoke.toml`, using 100 train and 20 validation images, and writes to `results/fashion/tc/smoke/T2_K8_seed42/`. The saved notebook contains the execution output; `smoke_test_report.json` is PASS only when all pipeline checks, reload checks and the Eclat pilot pass.

Run the Julia test suite with:

```bash
julia --compiled-modules=existing --project=. test/runtests.jl
```

`--compiled-modules=existing` avoids a local Julia/ZMQ precompile crash observed in the development environment; it does not change the tested pipeline code.

## Full benchmark

To run full, keep the same installation, kernel and notebook; select only the full config:

```bash
FASHION_TC_CONFIG=configs/tc_full.toml uv run jupyter execute notebook/UD2/03_fashion_mnist_transaction_construction.ipynb --inplace --timeout=600
```

The full config uses all 60,000 train and 10,000 validation images, fits Q10+ on train only, and runs K={16,32,64,128,256} × seeds={42,123,2026} sequentially. It writes under `results/fashion/tc/benchmark/` and refuses to overwrite that output directory. Full data, benchmark runtime and results were not run or verified as part of smoke hand-off.

Both notebook modes call the same `prepare_run` and TC0–TC7 functions. The config selects the sample size, K/seed schedule and output path; no notebook installation or code-cell changes are required when switching modes.
