# Eclat Frequent Itemset Mining

Julia project for Eclat frequent itemset mining, benchmark experiments, and the Groceries and Fashion-MNIST applications. See [the project plan](docs/plan.md) and [assignment](docs/itemset.md) for requirements.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy (TV3, Fashion-MNIST and demo).

## Current state

The Fashion-MNIST release workflow is organized as four ordered notebooks under
`notebook/UD2/release/`. The TC4 vector benchmark, spatial extension, and
[exploratory data analysis of Fashion-MNIST transactions (EDA2)](notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb)
are in `notebook/UD2/experiments/`. EDA2 compares codebook quality, transaction
density and diversity, and pilot Eclat results across codebook sizes, seeds, and
S0/S1/S3/S6-B encodings.

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

## Fashion-MNIST demo notebooks

Mở từng notebook trên Google Colab, chọn runtime **Julia** và CPU (Hardware accelerator: None). Các ô code chạy trực tiếp trong Julia kernel; notebook tải commit mã nguồn đã ghim và gọi `Pkg.instantiate()` từ môi trường của dự án. Notebook giới hạn BLAS ở một luồng, yêu cầu mục tiêu OpenBLAS Haswell và ghi phiên bản Julia cùng số luồng thực tế của runtime. Notebook 02 đặt trần K-means 400 vòng cho demo, còn `release.toml` vẫn giữ 300. Các CPU và runtime khác nhau vẫn có thể cho kết quả số học khác nhau.

1. **Khám phá dữ liệu ảnh và lựa chọn tiền xử lý** — xem bằng chứng cho vùng 4×4, ngưỡng lọc nền và vectơ đặc trưng 16 chiều.

   [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/NguyenVoTanDuy2006/DataMining-FIM-Project/blob/feature/fashion-mnist-consolidated/notebook/UD2/demo/01_image_exploration.ipynb)

2. **Dựng giao dịch bằng túi từ thị giác nhị phân** — chạy pipeline FashionTC trên 70.000 ảnh và tải gói giao dịch đã kiểm định.

   [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/NguyenVoTanDuy2006/DataMining-FIM-Project/blob/feature/fashion-mnist-consolidated/notebook/UD2/demo/02_transaction_construction.ipynb)

3. **Khám phá giao dịch và khai thác mẫu** — tải gói từ notebook 02 lên một phiên mới, xem phân bố giao dịch, đối chiếu hai backend Eclat, xem mốc tham chiếu giữa hai nhánh và truy mẫu về ảnh nguồn.

   [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/NguyenVoTanDuy2006/DataMining-FIM-Project/blob/feature/fashion-mnist-consolidated/notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb)

Notebook 02 lưu một gói nén tar và gzip có manifest cùng mã SHA-256. Giữ gói này để tải lên notebook 03 trong phiên Colab riêng.

## Fashion-MNIST research notebooks

Các notebook nghiên cứu và release dùng kernel Julia trong Jupyter:

1. [Image preprocessing decisions](notebook/UD2/experiments/01_image_preprocessing_decisions.ipynb)
2. [Transaction construction release](notebook/UD2/release/02_transaction_construction.ipynb), dùng manifest từ [dataset validation](notebook/UD2/release/01_dataset_validation.ipynb)
3. [Transaction EDA](notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb)

## Fashion-MNIST experiments on Colab

Use one Julia notebook on a Colab CPU runtime for the K-means sweep, transaction encodings, EDA2, and spatial extension:

[Open the unified Fashion-MNIST experiment notebook](https://colab.research.google.com/github/NguyenVoTanDuy2006/DataMining-FIM-Project/blob/Fashion-Mnist/notebook/UD2/experiments/EDA2_FashionMNIST_Transaction_Evaluation.ipynb)

The notebook starts from the four Fashion-MNIST source files. It runs all 15 combinations of K = 16, 32, 64, 128, 256 and seeds 42, 123, 2026; creates S0, S1, S3, and S6-B from each matching codebook; then analyzes all 60 transaction sets. The region and stripe checks apply only to S1/S3. S6-B has separate neighbor-geometry checks for retained patch pairs, border and corner candidates, wraparound-only pairs that must be excluded, diagonal relations, and empty transactions; it also records how many eligible pairs touch an image border or corner after filtering. The notebook runs in Julia and does not use Python to coordinate the experiment.

Run the cells in order in a Julia CPU runtime. The notebook downloads or verifies the dataset, clones the `Fashion-Mnist` source, and instantiates the checked-in Julia environment. It writes one portable fit checkpoint after each completed fit, an EDA2 stage archive containing all four encodings and their analysis, and a final `fashion-full-experiment-*.tar.gz` archive under `/content`. Download the checkpoint if you may need to resume the K-means sweep; download the stage archive to create the final archive after a Colab reset. Download the final archive through the Files pane before the runtime ends.

The final archive contains the fit records, transaction files, analysis tables and plots, phase summaries, portable manifests, provenance, spatial statuses, and checksums. The notebook creates a run-specific output directory so existing results under `results/fashion/tc/tc6_configs/` and `results/fashion/eda2/v1` or `v2` remain available as historical runs.

The separate checkout `TeamProject-FrequentItemsetMining-eda2` contains earlier benchmark and smoke outputs; the unified notebook does not use it as an input. See [`specs/002-rebuild-fashion-experiments/quickstart.md`](specs/002-rebuild-fashion-experiments/quickstart.md) for resume steps and archive contents.

## Fashion-MNIST K-means reproduction

Để chạy lại riêng phép fit K-means trên Colab CPU, mở notebook thí nghiệm. Notebook gọi trực tiếp pipeline FashionTC, dùng giới hạn 400 vòng và ghi mục tiêu OpenBLAS Haswell cùng số thread Julia thực tế; cấu hình phát hành vẫn giữ 300 vòng:

[![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/NguyenVoTanDuy2006/DataMining-FIM-Project/blob/Fashion-Mnist/notebook/UD2/experiments/06_tc4_kmeans_colab_reproduction.ipynb)

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
