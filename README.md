# Eclat Frequent Itemset Mining

Julia project for a from-scratch Eclat implementation, SPMF comparison, four benchmarks, and two applications: Groceries and Fashion-MNIST. See [the project plan](docs/plan.md) and [assignment](docs/itemset.md) for requirements.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy (TV3, Fashion-MNIST and demo).

## Tổng quan

Dự án có hai phiên bản Eclat (`:set` và `:bitvector`), kiểm chứng với SPMF
trên năm CSDL, bốn nhóm benchmark và hai ứng dụng Groceries, Fashion-MNIST.
Xem [báo cáo nhóm](docs/Report.pdf) và [hướng dẫn biên dịch](docs/report/README.md).

Bắt đầu với [demo Eclat, Groceries và benchmark](#demo-eclat-groceries-và-benchmark-trên-google-colab)
hoặc [ba notebook Fashion-MNIST](#demo-fashion-mnist-trên-google-colab).
Notebook Eclat đã chạy đầy đủ trên Linux local; việc xác nhận trên Colab đang
được thực hiện. Các nguồn benchmark được lưu trên
[Hugging Face](https://huggingface.co/datasets/Yelgsef/fimi-eclat-benchmarks).

## Julia setup

Install Julia 1.9 or newer, then run:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EclatFIM'
```

`Manifest.toml` ghi môi trường Julia 1.13.3 của lần kiểm chứng. Phần Fashion-MNIST
dùng các dependency trong `Project.toml`; cần chạy `Pkg.instantiate()` trước. Chạy các lệnh bên dưới từ thư mục gốc
dự án trong terminal, không nhập vào dấu nhắc `julia>`.
Các khối PowerShell bên dưới có ghi rõ loại terminal cần dùng.

Dữ liệu và đầu ra sinh khi chạy được lưu trong `data/` và `results/`,
không đưa vào Git. Các đường dẫn đầu ra bên dưới chỉ xuất hiện sau khi chạy
script tương ứng; bảng và hình đã chọn nằm trong báo cáo.

Bốn benchmark Chess, Mushroom, Retail và T10I4D100K được lưu công khai tại
[Hugging Face: Yelgsef/fimi-eclat-benchmarks](https://huggingface.co/datasets/Yelgsef/fimi-eclat-benchmarks).
Chạy `julia --project=. scripts/prepare_data.jl` để tải và chuẩn hóa dữ liệu.
Downloader ghim phiên bản `92ce74f1107250b7c8cd79df07ba415df58ca98d`,
xác minh SHA-256 và giữ nguyên dữ liệu đã có nếu checksum đúng. Bản lưu khớp từng
byte với dữ liệu FIMI dùng cho thực nghiệm; Mushroom có 8.124 giao dịch.
Xem [nguồn, checksum và điều kiện sử dụng](docs/benchmark_data.md).

The core API is:

```julia
using EclatFIM
transactions = [[1, 2, 3], [1, 2], [2, 3]]
mine(transactions, 0.5; backend = :bitvector)
```

The integer overload `mine(transactions, min_count; ...)` uses an absolute
support count and accepts the optional length, deadline, and output limits used
by Fashion-MNIST. `mine_count` names that same count-based operation explicitly.
The floating-point overload keeps the relative fraction contract used by the
Groceries and benchmark runners.

For the floating-point overload, `minsup` is a relative threshold in `(0, 1]`
and is converted with `ceil(minsup * transaction_count)`. The result maps
sorted itemset tuples to support counts. The `:set` and `:bitvector` backends
have the same output.

## Kiểm thử tự động

Chạy từ thư mục gốc dự án:

```powershell
julia --project=. test/runtests.jl
```

`test/runtests.jl` kiểm tra Eclat Set/BitVector, SPMF I/O và nạp các file kiểm thử:

- [test_groceries.jl](test/test_groceries.jl): làm sạch tên, bỏ sản phẩm trùng trong một giỏ, giữ các giao dịch giống nhau, mã hóa ID và ghi mapping.
- [test_association_rules.jl](test/test_association_rules.jl): công thức support/confidence/lift, hai chiều của luật, các tập con hợp lệ, sinh luật và lọc confidence tại ngưỡng.
- [test_eclat_optimized.jl](test/test_eclat_optimized.jl): lọc singleton trước khi cấp BitVector và đối chiếu phép đếm vét cạn.
- [test_benchmark.jl](test/test_benchmark.jl): đọc toàn bộ Groceries, Chess, Mushroom, Retail và T10I4D100K đã chuẩn hóa trong `data/`, so sánh mọi itemset/support của Set và BitVector với đáp án SPMF đã lưu trong `results/`.

Auto test dùng Julia, không cần Python hoặc gọi Java. Cần có đủ năm CSDL đầy đủ
đã chuẩn hóa trong `data/`; thiếu file sẽ báo lỗi, không tự lấy mẫu hoặc bỏ qua
test. Dữ liệu lớn được Git-ignore và phải chuẩn bị trước trên máy chạy test.
Các đáp án SPMF cần được tạo trước trong `results/`; test chỉ đọc, không ghi đè kết quả.

Groceries đọc từ `data/processed/groceries_spmf.txt`; bốn CSDL còn lại đọc từ
`data/benchmark/processed/processes/`.

| CSDL | Giao dịch | Minsup | Itemsets SPMF |
| --- | ---: | ---: | ---: |
| Groceries | 9.835 | 1% | 333 |
| Chess | 3.196 | 87,5% | 1.386 |
| Mushroom | 8.124 | 70% | 31 |
| Retail | 88.162 | 4% | 18 |
| T10I4D100K | 100.000 | 1,5% | 237 |

Nếu chưa có input chuẩn hóa, chuẩn bị các file gốc theo
[benchmark_data.md](docs/benchmark_data.md), chạy demo Groceries để mã hóa, rồi
gọi bước chuẩn hóa bốn benchmark từ terminal PowerShell tại repo root:

```powershell
julia --project=. scripts/groceries_demo.jl
@'
include("scripts/benchmark_processes.jl")
foreach(prepare_input, DATASETS)
'@ | julia --project=. -
```

Đáp án Groceries lưu tại `results/groceries/groceries_spmf_0.01.txt`.
Notebook demo tạo mới cả năm đáp án SPMF trước khi chạy test.
Đáp án bốn benchmark nằm trong `results/benchmarks/peak_ram/spmf/`, dùng đúng
đầu vào và minsup được ghi trong metadata của phép đo Peak RAM.

Theo [đề bài](docs/itemset.md), auto test phải bao phủ ít nhất 5 CSDL, khớp SPMF, và output lần chạy cuối phải có trong README. File `test_benchmark.jl` trong cấu trúc gợi ý không có nghĩa là bắt buộc unit test từng hàm đo runtime, Peak RAM hoặc sinh CSV.

Lần chạy notebook local ngày 2026-11-27 trên Julia 1.13.3 / Linux: **569/569 assertions pass**.
Set và BitVector khớp toàn bộ itemset/support với SPMF trên năm CSDL đầy đủ.
Python release tests: **16/16 pass**; kiểm tra cấu trúc bốn notebook release: **PASS**.

<details>
<summary>Output tham khảo của julia --project=. test/runtests.jl (2026-11-24)</summary>

```text
Test Summary:                    | Pass  Total  Time
Eclat correctness and edge cases |   22     22  1.8s
Test Summary:                 | Pass  Total  Time
SPMF I/O and exact comparison |   11     11  1.2s
Test Summary:              | Pass  Total  Time
Groceries - xu ly gio hang |   10     10  0.2s
Test Summary:            | Pass  Total  Time
Luat ket hop - cong thuc |   11     11  0.1s
Test Summary:                 | Pass  Total  Time
Luat ket hop - tap con hop le |    7      7  0.4s
Test Summary:              | Pass  Total  Time
Luat ket hop - sinh va loc |   59     59  0.8s
Test Summary:                                 | Pass  Total  Time
BitVector singleton pruning before allocation |   18     18  0.4s
Test Summary:                                          | Pass  Total  Time
Pruned BitVector matches independent exhaustive oracle |  280    280  0.5s
Groceries / set: matched=333/333; missing=0; extra=0; support_mismatches=0
Groceries / bitvector: matched=333/333; missing=0; extra=0; support_mismatches=0
Chess / set: matched=1386/1386; missing=0; extra=0; support_mismatches=0
Chess / bitvector: matched=1386/1386; missing=0; extra=0; support_mismatches=0
Mushroom / set: matched=31/31; missing=0; extra=0; support_mismatches=0
Mushroom / bitvector: matched=31/31; missing=0; extra=0; support_mismatches=0
Retail / set: matched=18/18; missing=0; extra=0; support_mismatches=0
Retail / bitvector: matched=18/18; missing=0; extra=0; support_mismatches=0
T10I4D100K / set: matched=237/237; missing=0; extra=0; support_mismatches=0
T10I4D100K / bitvector: matched=237/237; missing=0; extra=0; support_mismatches=0
Test Summary:                | Pass  Total  Time
Correctness SPMF tren 5 CSDL |   22     22  2.6s
Test Summary:           | Pass  Total  Time
Fashion-MNIST IDX input |   17     17  0.6s
Test Summary:                    | Pass  Total  Time
Verified Fashion-MNIST downloads |    7      7  0.1s
Test Summary:                  | Pass  Total  Time
Stable Fashion-MNIST image IDs |   12     12  0.0s
Test Summary:                             | Pass  Total  Time
Fashion-MNIST dataset manifest round trip |   11     11  0.4s
Test Summary:                        | Pass  Total  Time
Fashion transaction input validation |    9      9  0.3s
Test Summary:            | Pass  Total  Time
Fashion-MNIST TC helpers |   39     39  3.8s
Test Summary:                         | Pass  Total  Time
Release Fashion-FIM transaction input |    9      9  0.4s
Test Summary:                | Pass  Total  Time
Fashion TC6 spatial encoding |    1      1  0.2s
Test Summary:                    | Pass  Total  Time
EDA2 input and mining invariants |   18     18  0.7s
Test Summary:                                   | Pass  Total  Time
Verified input download preserves existing data |    6      6  0.1s
```

</details>

## Demo Eclat, Groceries và benchmark trên Google Colab

Mở [notebook Julia](notebooks/eclat_groceries_benchmarks.ipynb) hoặc
[Open in Colab](https://colab.research.google.com/github/NguyenVoTanDuy2006/DataMining-FIM-Project/blob/master/notebooks/eclat_groceries_benchmarks.ipynb).
Link Colab dùng được sau khi notebook được push lên `master`. Trước đó, mở
Colab và dùng **File → Upload notebook** để tải file `.ipynb` từ máy lên.
Chọn **Runtime → Change runtime type → Julia**, runtime CPU, rồi chạy từ đầu
đến cuối. Có thể chạy tương đương bằng Jupyter/IJulia trên máy có Julia.

Notebook thực hiện:

1. Tải source ghim tại commit `c93fed0c436275e51f8672f6e7e8182d9b855040`
   vào checkout riêng, cài dependencies và tải benchmark từ Hugging Face với SHA-256.
2. Chuẩn hóa bốn benchmark và Groceries; chuẩn bị Java 25 và JAR SPMF có checksum.
3. Minh họa API/CLI Eclat, tạo mới năm đáp án SPMF rồi chạy toàn bộ test Julia.
4. Hiển thị 12 cấu hình Groceries và mười luật theo lift ở minsup 1%/minconf 50%.
5. Chạy runtime/count trên bốn CSDL × bảy minsup, Peak RSS, scalability Retail
   và thí nghiệm độ dài giao dịch; hiển thị bảng và biểu đồ.
6. Đóng gói CSV, biểu đồ, tham chiếu SPMF, log test và môi trường thành `.tar.gz`.
   Tải gói ngay trong `/content/` từ Files panel trước khi kết thúc runtime.

Mặc định `BENCHMARK_RUNS = 1` để kiểm tra toàn bộ luồng. Đổi thành `5` để đo
trung vị năm lượt như thiết kế báo cáo. Các phép đo chạy một luồng trong tiến
trình riêng. Thời gian toàn tiến trình gồm khởi động/JIT/đọc ghi; scalability
và độ dài giao dịch đo khai thác sau làm nóng. Peak RSS gồm cả môi trường thực thi.
Kết quả mới được lưu riêng trong `results/colab/eclat_*/`, không ghi đè số liệu báo cáo.

Các ô notebook dùng Julia. Bước vẽ gọi các script Python/matplotlib đã có trong
repo; Python chỉ đọc CSV và dựng biểu đồ. Notebook tự cài matplotlib vào môi trường Python riêng nếu chưa có.
Nếu bước vẽ lỗi sau khi đo xong, chạy lại ô benchmark đó để chỉ vẽ lại.
Source ghim chứa script chuẩn hóa cũ; notebook tải trước đúng bốn file từ bản
Hugging Face ghim, nên bước chuẩn hóa tái sử dụng các file đã xác minh mà không
cần tải lại từ FIMI. Ba notebook Fashion-MNIST riêng nằm ở phần tiếp theo.

Kiểm tra ngày 2026-11-27 trên Linux local/IJulia 1.13.3: **12/12 ô Julia
chạy thành công**, 569 assertions pass, 84 mẫu runtime, 8 mẫu Peak RAM,
10 mẫu scalability và 10 mẫu độ dài giao dịch. Cả bốn script kiểm tra/vẽ
biểu đồ và bước đóng gói kết quả đều hoàn tất. Đây là kiểm tra local với
một lượt đo mỗi cấu hình, đã kiểm tra nhánh tự tải Java 25 từ Java 21,
chưa phải xác nhận chạy trên Google Colab. Kiểm tra nhanh các nhánh phục hồi:
`python test/check_colab_notebook.py`.

## Demo Fashion-MNIST trên Google Colab

Ba notebook demo trình bày quy trình Fashion-MNIST bằng Julia, từ khảo sát ảnh
đến tạo giao dịch và khai thác tập mục. Mở từng notebook bằng Colab:

| Thứ tự | Notebook | Mở trên Colab |
|---|---|---|
| 1 | Khảo sát ảnh và quyết định tiền xử lý | [Notebook 1](https://colab.research.google.com/drive/1cyyfr4Yt410cpJJhl-rI7gDsCWOOXnLs) |
| 2 | Tạo giao dịch Fashion-MNIST | [Notebook 2](https://colab.research.google.com/drive/1sIsAmpG8UQRmVNxmj6TI6ENCvo7rd-zF) |
| 3 | Khám phá giao dịch và khai thác tập mục | [Notebook 3](https://colab.research.google.com/drive/1lxDm_OweS1I65y66Vs0qmTk2P3qTy_VK) |

### Cách chạy

1. Trong Colab, chọn runtime CPU rồi chạy từng notebook từ đầu đến cuối. Notebook
   tự tải source đã ghim và dữ liệu Fashion-MNIST khi cần; lần chạy đầu cần mạng.
2. Notebook 1 khảo sát 10 ảnh mẫu và minh họa lựa chọn kích thước vùng, lọc nền
   cùng descriptor. Đây là bước giải thích tiền xử lý; notebook 2 vẫn tự kiểm tra
   dữ liệu và cấu hình trước khi chạy pipeline.
3. Notebook 2 chạy pipeline trên 70.000 ảnh với cấu hình $K=32$, seed 123,
   dung sai 0,0001 và giới hạn tối đa 400 vòng. Khi hoàn tất, tải gói
   `fashion-demo-<run_id>.tar.gz` từ Files panel của Colab.
4. Mở notebook 3, tải gói `.tar.gz` vừa tạo lên Files panel (thư mục `/content`),
   rồi chạy notebook từ đầu đến cuối. Notebook xác minh gói đầu vào, đối chiếu
   Eclat Set/BitVector, tạo bảng và biểu đồ phân tích, rồi lưu toàn bộ kết quả
   vào một thư mục duy nhất và nén thành `fashion-demo-analysis.tar.gz`.
5. Tải `fashion-demo-analysis.tar.gz` về máy trước khi đóng hoặc khởi động lại
   runtime Colab. Nội dung trong `/content` bị xóa khi runtime kết thúc.

Notebook 3 đọc gói do notebook 2 tạo, không chạy lại bước tạo giao dịch. Nếu
chỉ muốn xem quy trình tiền xử lý, có thể chạy riêng notebook 1; để phân tích
đầy đủ cần chạy notebook 2 trước notebook 3.

## Notebook Fashion-MNIST lưu trữ

Bốn notebook dưới đây là quy trình release cũ để đối chiếu. Dùng ba notebook
Colab ở phần trên cho demo hiện tại.

<details>
<summary>Quy trình release cũ và yêu cầu môi trường</summary>


Run these notebooks in order from fresh Julia kernels. Notebook 01 creates a
run ID; notebooks 02–04 consume artifacts under the same
`results/fashion/release/<run_id>/` directory.

1. [01 — Dataset validation](notebooks/fashion-mnist/archive/release/01_dataset_validation.ipynb):
   downloads or reuses the four official archives, verifies SHA-256 and IDX
   dimensions/counts, displays one image per class, and writes
   `dataset/dataset_manifest.toml`.
2. [02 — Transaction construction](notebooks/fashion-mnist/archive/release/02_transaction_construction.ipynb):
   builds S0 using one B0 codebook with K=32 and seed 123 across all 70,000
   images. Its handoff is `transactions/tc7_manifest.toml`, containing hashes
   and paths for transactions, codebook, centroids, assignments, image mapping,
   metadata, config, and integrity report.
3. [03 — Frequent itemset mining](notebooks/fashion-mnist/archive/release/03_frequent_itemset_mining.ipynb):
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
4. [04 — Visual interpretation](notebooks/fashion-mnist/archive/release/04_visual_interpretation.ipynb):
   traces the automatically selected 3–4 patterns to centroids, source patches,
   images, and class counts, then writes a review sheet and a report marked
   `PENDING_REVIEW`.

Prerequisites are Julia 1.13, Python 3.10+, the `fashion-mnist-tc` Julia
kernel, and Linux `systemd --user` with cgroup memory accounting for mining.
For the first run, Notebook 01 downloads the official dataset if the archives
are absent; otherwise it checks the local files in `data/raw/fashion-mnist/`.
Large archives and generated run artifacts are not committed.

</details>

## Chạy ứng dụng Groceries

Dữ liệu đầu vào nằm tại `data/raw/groceries.csv`, lấy từ [nguồn CSV trong kế hoạch nhóm](https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/groceries.csv).

```powershell
julia --project=. scripts/groceries_demo.jl
```

Demo chạy qua `main()` theo bốn bước: đọc và mã hóa dữ liệu; xuất SPMF và mapping; sinh top 10 luật ở minsup 1%, minconf 50%; xuất bảng so sánh 12 cấu hình. File demo chỉ định nghĩa các hàm khi được `include` để kiểm thử.

Kết quả đã kiểm tra trên dữ liệu thật: 9.835 giao dịch, 169 sản phẩm, 333 frequent itemsets và 15 luật đạt ngưỡng của cấu hình chính. Hai bảng CSV giữ nguyên nội dung sau khi sắp xếp lại demo:

- `data/processed/groceries_spmf.txt`: giao dịch đã mã hóa.
- `data/processed/item_mapping.csv`: mapping ID sang tên.
- `results/groceries/top10_rules.csv`: 10 luật đứng đầu theo lift.
- `results/groceries/parameter_summary.csv`: 12 cấu hình.

[Báo cáo Groceries](docs/report_groceries.md) trình bày top 10, cách tính từng
chỉ số, ví dụ giải thích luật và các giới hạn khi áp dụng vào bán lẻ.
[Checklist TV2](docs/TV2_checklist.md) đối chiếu công việc với phân công và
liệt kê các bước tích hợp chung còn lại trước khi nộp.

## Đo runtime toàn bộ tiến trình Julia và SPMF

Chương trình điều khiển [benchmark_processes.jl](scripts/benchmark_processes.jl) chạy
Retail, Chess, Mushroom và T10I4D100K, mỗi bộ 7 ngưỡng minsup. Chuẩn bị bốn file
gốc theo [nguồn và checksum](docs/benchmark_data.md), đặt JAR SPMF tại
`data/benchmark/tools/spmf.jar` và bảo đảm `java` có trong PATH.

```powershell
julia --startup-file=no --project=. scripts/benchmark_processes.jl
python scripts/plot_process_benchmarks.py
```

Lệnh Python cần `matplotlib`, chỉ dùng để đọc/kiểm tra CSV và vẽ biểu đồ;
khai thác và đo thời gian thực hiện bằng Julia/Java. Mặc định đo 5 lần cho mỗi
backend/cấu hình, thêm một lượt chuẩn bị không ghi nhận và xoay vòng thứ tự chạy
Set, BitVector, SPMF giữa các lần. Mỗi mẫu tạo tiến trình mới, tính khởi động/JIT, đọc dữ liệu,
khai thác và ghi kết quả. Chương trình so sánh từng itemset và support count sau mỗi
nhóm ba chương trình, bên ngoài phần tính thời gian.

Kết quả nằm trong `results/benchmarks/processes/`:

- [Báo cáo runtime](docs/report_benchmark.md#runtime): phương pháp, kết quả và giới hạn.
- `results/benchmarks/processes/runs.csv`: từng lần đo.
- `results/benchmarks/processes/summary.csv`: median/min/max và tỉ số runtime.
- `results/benchmarks/processes/metadata.md`: cấu hình máy, phiên bản và checksum.
- `runtime_processes.png/.svg`, `itemset_counts.png/.svg`: biểu đồ để dùng trong báo cáo.

Đây là phép đo toàn bộ tiến trình, giữ riêng với các file `*_baseline.csv` đo
`mine` trên dữ liệu trong RAM sau warm-up. Lệnh chạy lại ghi đè bảng kết quả trong
thư mục mặc định; dùng `--output-dir` để giữ một lần đo riêng. Có thể chọn một bộ,
một ngưỡng và số lần đo, ví dụ:

```powershell
julia --startup-file=no --project=. scripts/benchmark_processes.jl --dataset T10I4D100K --minsup 0.02 --runs 5 --output-dir results/benchmarks/processes_T10_002
```

Phép đo runtime trên so sánh Set, BitVector và SPMF trên 28 cấu hình, 420 mẫu.
Phép đo RAM
Set/BitVector, Scalability và ảnh hưởng độ dài giao dịch được trình bày riêng
bên dưới. Colab tiếp tục được theo dõi trong [kế hoạch nhóm](docs/plan.md).

## Peak RAM: baseline và optimized

Theo [yêu cầu bộ nhớ](docs/itemset.md), đo toàn bộ 4 dataset tại điểm giữa của
dải 7 minsup hiện có: Retail 4%, Chess 87,5%, Mushroom 70%, T10I4D100K 1,5%.

Backend BitVector đếm support trước, chỉ cấp vector cho item đạt ngưỡng,
rồi điền TID trong lượt quét tiếp theo. Cách đếm xử lý đúng item trùng trong
một giỏ và giữ các giao dịch trùng nhau.

```powershell
julia --startup-file=no --project=. scripts/benchmark_peak_ram.jl
python scripts/plot_peak_ram.py
```

Mỗi backend (`:set`, `:bitvector`) chạy trong 5 tiến trình độc lập, một luồng,
đảo thứ tự giữa các lần. Worker warm-up trên cùng toy database rồi GC; đọc
input thật và GC trước mining. `Sys.maxrss()` lấy peak RSS của hệ điều hành
ngay sau `mine`, trước khi ghi output. Peak gồm Julia/JIT, warm-up, input và
mining; không phải allocation hay peak riêng của hàm `mine`. Bộ đếm peak không
reset sau warm-up, nên không trừ peak trước mining khỏi peak cuối.

Runner tạo tham chiếu SPMF mới từ đúng file chuẩn hóa ngoài phép đo RAM và so
sánh mọi itemset/support của mỗi lần chạy với tham chiếu. Cần Java, JAR tại
`data/benchmark/tools/spmf.jar` và bốn raw datasets như phép đo runtime.

Kết quả trong `results/benchmarks/peak_ram/`:

- [Báo cáo Peak RAM](docs/report_benchmark.md#peak-ram): bảng kết quả, phân tích và giới hạn.
- `results/benchmarks/peak_ram/peak_ram.png`: biểu đồ median và min–max; có bản SVG.
- `results/benchmarks/peak_ram/runs.csv`: từng peak RSS tính bằng byte và correctness.
- `results/benchmarks/peak_ram/summary.csv`: median/min/max theo MiB, tỉ số và phần trăm giảm.
- `results/benchmarks/peak_ram/metadata.md`: quy trình, máy, phiên bản và checksum.
- `spmf/`: tham chiếu mới cùng dữ liệu, minsup và mapping ID đã đo.

Runner từ chối ghi đè lần đo cũ. Ví dụ đo một bộ, lưu vào thư mục mới:

```powershell
julia --startup-file=no --project=. scripts/benchmark_peak_ram.jl --dataset retail --runs 5 --output-dir results/benchmarks/peak_ram_retail
python scripts/plot_peak_ram.py results/benchmarks/peak_ram_retail
```

Chạy bộ kiểm thử dự án:

```powershell
julia --startup-file=no --project=. test/runtests.jl
```

## Scalability: Retail 10%, 25%, 50%, 75%, 100%

Giữ minsup tương đối ở 4%, lấy năm tập con lồng nhau từ một hoán vị chỉ số dòng
với seed `20261116`. Kích thước dùng `floor(N × tỷ lệ)`: 8.816, 22.040, 44.081,
66.121 và 88.162 giao dịch. Giữ giao dịch trùng, cộng 1 vào ID Retail, và khôi
phục thứ tự dòng gốc trong mỗi tập con. File dữ liệu/chỉ số nằm trong
`data/benchmark/processed/scalability/`, không đưa vào Git.

```powershell
julia --startup-file=no --project=. scripts/benchmark_scalability.jl
python scripts/plot_scalability.py
```

Mỗi cấu hình Set/BitVector đo 5 lần trong các tiến trình mới, một luồng, đảo
thứ tự hai backend giữa các lần. Sau khi đọc input và warm-up trên đúng toàn
bộ tập con, chạy GC rồi dùng `@elapsed` đo một lần `mine`. Thời gian không tính
khởi động, đọc input, warm-up/JIT, GC trước đo, ghi output và correctness; GC
bên trong `mine` vẫn được tính. SPMF tạo tham chiếu cho từng tập con ngoài phần
đo và dùng để kiểm tra toàn bộ itemset/support của mỗi output.

Kết quả trong `results/benchmarks/scalability/`:

- [Báo cáo scalability](docs/report_benchmark.md#scalability): bảng kết quả và nhận xét tuyến tính/phi tuyến trong miền đo.
- `results/benchmarks/scalability/scalability.png`: runtime theo số giao dịch và đường chuẩn hóa; có bản SVG.
- `results/benchmarks/scalability/runs.csv`: từng thời gian `mine` và trạng thái correctness.
- `results/benchmarks/scalability/summary.csv`: median/min/max và throughput.
- `results/benchmarks/scalability/metadata.md`: mô tả tiếng Việt, seed, máy, phiên bản và checksum dữ liệu/source.
- `spmf/`: tham chiếu mới cho năm tập con.

Đây là thời gian `mine` sau warm-up, không ghép trực tiếp với thời gian toàn bộ
tiến trình của thí nghiệm Julia/SPMF. Minsup tương đối cố định khiến ngưỡng đếm
tăng theo N; số frequent itemset có thể thay đổi giữa các tập con.

Runner từ chối ghi đè kết quả. Để chạy một lần riêng:

```powershell
julia --startup-file=no --project=. scripts/benchmark_scalability.jl --runs 5 --minsup 0.04 --seed 20261116 --output-dir results/benchmarks/scalability_run
python scripts/plot_scalability.py results/benchmarks/scalability_run
```

Kiểm thử tự động bằng `julia --project=. test/runtests.jl`.

## Ảnh hưởng của độ dài giao dịch trung bình

Sinh một họ CSDL tổng hợp với **N = 5.000 giao dịch, M = 64 loại item, minsup
5% (min_count = 250)** giữ cố định. Mỗi giao dịch có đúng **4 / 8 / 12 / 16 / 20
item**, nên độ dài trung bình lần lượt bằng các mức đó. Mọi CSDL đều quan sát
đủ 64 item; giao dịch không chứa item trùng và các giỏ trùng nhau vẫn được giữ.

Mỗi TID dùng một hoán vị ngẫu nhiên riêng của 1:M với seed `20261116`. Các mức
độ dài lấy tiền tố của cùng hoán vị cho TID đó, nên mức dài chỉ thêm item vào
cùng giỏ; không nhân bản dữ liệu. Dữ liệu sinh được Git-ignore tại
`data/benchmark/processed/transaction_length/`.

```powershell
julia --startup-file=no --project=. scripts/benchmark_transaction_length.jl
python scripts/plot_transaction_length.py
```

Đo riêng `mine` sau warm-up bằng cùng worker scalability, 5 lần mỗi backend/CSDL,
một luồng, đảo thứ tự Set/BitVector. Mỗi output khớp toàn bộ itemset/support với
SPMF; các tham chiếu cũng được kiểm tra quan hệ support không giảm khi thêm item
vào từng giao dịch. Giữ N và minsup nên ngưỡng support tuyệt đối cố định.

Kết quả tại `results/benchmarks/transaction_length/`:

- [Báo cáo độ dài giao dịch](docs/report_benchmark.md#transaction-length): thiết kế, số liệu và phân tích cơ chế ảnh hưởng.
- `results/benchmarks/transaction_length/transaction_length.png`: runtime theo độ dài và số frequent itemsets; có bản SVG. Trục thời gian dùng thang log.
- `results/benchmarks/transaction_length/runs.csv`: từng mẫu thời gian và correctness.
- `results/benchmarks/transaction_length/summary.csv`: độ dài, mật độ, output, median/min/max.
- `results/benchmarks/transaction_length/metadata.md`: mô tả tiếng Việt, seed, máy, phiên bản và checksum.
- `spmf/`: tham chiếu mới của từng CSDL.

Tăng độ dài đồng thời tăng mật độ, số lần xuất hiện item và có thể tăng số ứng
viên/output. Thí nghiệm minh chứng tác động tổng hợp đó, chưa tách riêng đóng góp
của từng cơ chế; không suy rộng một seed sang mọi phân bố. Không đo lại Peak RAM
hoặc runtime SPMF trong phần này.

Runner từ chối ghi đè; chọn `--output-dir` mới khi chạy lại. Có thể thay
`--transactions`, `--items`, `--lengths`, `--minsup`, `--seed`, `--runs` và
`--timeout-seconds`; phải giữ đủ M item quan sát được ở mọi độ dài.

Kiểm thử tự động bằng `julia --project=. test/runtests.jl`.

Các phân tích được tập trung trong [docs/report_benchmark.md](docs/report_benchmark.md).
Các script Python chỉ đọc/kiểm tra CSV và vẽ PNG/SVG, không tạo hay sửa báo cáo.

## CLI

The minimal CLI reads and writes SPMF-compatible text files:

```sh
julia --project=. scripts/eclat_cli.jl \
    --input data/processed/groceries_spmf.txt \
    --minsup 0.01 \
    --backend bitvector \
    --output results/output.txt
```

Each output line has the form `1 2 3 #SUP: 4`. Use `--backend set` for the
baseline implementation.

## SPMF correctness verification

Keep external datasets and the SPMF jar outside this repository. For each
dataset, first generate an SPMF reference output and then compare every itemset
key and support count with both backends:

```sh
java -jar /path/to/spmf.jar run Eclat INPUT SPMF_OUTPUT MINSUP
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP set
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP bitvector
```

The automated verification set uses the full Groceries, Chess, Mushroom, Retail,
and T10I4D100K databases from `data/`. Counts and thresholds are recorded in
[the TV1 algorithm note](docs/TV1_algorithm.md); large inputs are not committed.
