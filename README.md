# Eclat Frequent Itemset Mining

Julia project for a from-scratch Eclat implementation, SPMF comparison, four benchmarks, and two applications: Groceries and Fashion-MNIST. See [the project plan](docs/plan.md) and [assignment](docs/itemset.md) for requirements.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy (TV3, Fashion-MNIST and demo).

## Current state

Eclat baseline (`:set`), optimized (`:bitvector`) và ứng dụng Groceries đã có cài đặt. Groceries đọc giỏ hàng, tạo mapping, mã hóa giao dịch, khai thác luật, xuất top 10 theo lift và so sánh 12 cấu hình. Các test áp dụng cho hai backend, SPMF I/O và phần ứng dụng của TV2; xem thêm kết quả đối chiếu của TV1 trong [tài liệu thuật toán](docs/TV1_algorithm.md). Demo Colab vẫn cần hoàn tất.

## Julia setup

Install Julia 1.9 or newer, then run:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EclatFIM'
```

Generate and commit `Manifest.toml` with the selected Julia dependencies so experiments can be reproduced. Chạy các lệnh bên dưới từ thư mục gốc dự án trong terminal PowerShell, không nhập vào dấu nhắc `julia>`.

Large source datasets belong outside Git. Place local copies under `data/raw/` or `data/benchmark/`, and document their download URLs, versions, and preparation steps. Keep reproducible summaries and selected plots under `results/`.

The core API is:

```julia
using EclatFIM
transactions = [[1, 2, 3], [1, 2], [2, 3]]
mine(transactions, 0.5; backend = :bitvector)
```

`minsup` is a relative threshold in `(0, 1]` and is converted with
`ceil(minsup * transaction_count)`. The result maps sorted itemset tuples to
support counts. The `:set` and `:bitvector` backends have the same output.

## Kiểm thử tự động

Chạy từ thư mục gốc dự án trong terminal PowerShell:

```powershell
julia --project=. test/runtests.jl
```

`test/runtests.jl` kiểm tra Eclat Set/BitVector, SPMF I/O và nạp hai file kiểm thử ứng dụng:

- [test_groceries.jl](test/test_groceries.jl): làm sạch tên, bỏ sản phẩm trùng trong một giỏ, giữ các giao dịch giống nhau, mã hóa ID và ghi mapping.
- [test_association_rules.jl](test/test_association_rules.jl): công thức support/confidence/lift, hai chiều của luật, các tập con hợp lệ, sinh luật và lọc confidence tại ngưỡng.

Các test ứng dụng không chạy script demo, không cần mạng hoặc file Groceries thật, và không ghi đè kết quả thật.

Theo đề bài, trước khi nộp nhóm cần chạy toàn bộ bộ test và dán output của lần chạy cuối trực tiếp vào README. Nhóm sẽ bổ sung output sau khi hoàn tất mã nguồn; không cần tạo file log riêng.

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

## Đo runtime toàn bộ tiến trình Julia và SPMF

Chương trình điều khiển [benchmark_processes.jl](scripts/benchmark_processes.jl) chạy
Retail, Chess, Mushroom và T10I4D100K, mỗi bộ 7 ngưỡng minsup. Chuẩn bị bốn file
gốc theo [nguồn và checksum](docs/benchmark_data.md), đặt JAR SPMF tại
`data/benchmark/tools/spmf.jar` và bảo đảm `java` có trong PATH.

```powershell
julia --startup-file=no --project=. scripts/benchmark_processes.jl
python scripts/plot_process_benchmarks.py
```

Lệnh Python cần `matplotlib`, chỉ dùng để kiểm tra CSV, vẽ biểu đồ và tạo báo cáo;
khai thác và đo thời gian thực hiện bằng Julia/Java. Mặc định đo 5 lần cho mỗi
backend/cấu hình, thêm một lượt chuẩn bị không ghi nhận và đảo thứ tự chạy hai
backend giữa các lần. Mỗi mẫu tạo tiến trình mới, tính khởi động/JIT, đọc dữ liệu,
khai thác và ghi kết quả. Chương trình so sánh từng itemset và support count sau mỗi
cặp chạy, bên ngoài phần tính thời gian.

Kết quả nằm trong `results/benchmarks/processes/`:

- [report.md](results/benchmarks/processes/report.md): phương pháp, kết quả và giới hạn.
- [runs.csv](results/benchmarks/processes/runs.csv): từng lần đo.
- [summary.csv](results/benchmarks/processes/summary.csv): median/min/max và tỉ số runtime.
- [metadata.md](results/benchmarks/processes/metadata.md): cấu hình máy, phiên bản và checksum.
- `runtime_processes.png/.svg`, `itemset_counts.png/.svg`: biểu đồ để dùng trong báo cáo.

Đây là phép đo toàn bộ tiến trình, giữ riêng với các file `*_baseline.csv` đo
`mine` trên dữ liệu trong RAM sau warm-up. Lệnh chạy lại ghi đè bảng kết quả trong
thư mục mặc định; dùng `--output-dir` để giữ một lần đo riêng. Có thể chọn một bộ,
một ngưỡng và số lần đo, ví dụ:

```powershell
julia --startup-file=no --project=. scripts/benchmark_processes.jl --dataset T10I4D100K --minsup 0.02 --runs 5 --output-dir results/benchmarks/processes_T10_002
```

Phép đo runtime trên chỉ so sánh Set với SPMF tại thời điểm chạy. Phép đo RAM
Set/BitVector và Scalability được trình bày riêng bên dưới. Ảnh hưởng độ dài
giao dịch và Colab tiếp tục được theo dõi trong [kế hoạch nhóm](docs/plan.md).

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

- [report.md](results/benchmarks/peak_ram/report.md): bảng kết quả, phân tích và giới hạn.
- [peak_ram.png](results/benchmarks/peak_ram/peak_ram.png): biểu đồ median và min–max; có bản SVG.
- [runs.csv](results/benchmarks/peak_ram/runs.csv): từng peak RSS tính bằng byte và correctness.
- [summary.csv](results/benchmarks/peak_ram/summary.csv): median/min/max theo MiB, tỉ số và phần trăm giảm.
- [metadata.md](results/benchmarks/peak_ram/metadata.md): quy trình, máy, phiên bản và checksum.
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

- [report.md](results/benchmarks/scalability/report.md): bảng kết quả và nhận xét tuyến tính/phi tuyến trong miền đo.
- [scalability.png](results/benchmarks/scalability/scalability.png): runtime theo số giao dịch và đường chuẩn hóa; có bản SVG.
- [runs.csv](results/benchmarks/scalability/runs.csv): từng thời gian `mine` và trạng thái correctness.
- [summary.csv](results/benchmarks/scalability/summary.csv): median/min/max và throughput.
- [metadata.md](results/benchmarks/scalability/metadata.md): mô tả tiếng Việt, seed, máy, phiên bản và checksum dữ liệu/source.
- `spmf/`: tham chiếu mới cho năm tập con.

Đây là thời gian `mine` sau warm-up, không ghép trực tiếp với thời gian toàn bộ
tiến trình của thí nghiệm Julia/SPMF. Minsup tương đối cố định khiến ngưỡng đếm
tăng theo N; số frequent itemset có thể thay đổi giữa các tập con.

Runner từ chối ghi đè kết quả. Để chạy một lần riêng:

```powershell
julia --startup-file=no --project=. scripts/benchmark_scalability.jl --runs 5 --minsup 0.04 --seed 20261116 --output-dir results/benchmarks/scalability_run
python scripts/plot_scalability.py results/benchmarks/scalability_run
```

Kiểm thử bằng `julia --startup-file=no --project=. test/runtests.jl` và
`python -B test/test_plot_scalability.py`.

## CLI

The minimal CLI reads and writes SPMF-compatible text files:

```sh
julia --project=. scripts/eclat_cli.jl \
    --input data/toy/example.txt \
    --minsup 0.4 \
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
java -jar /path/to/spmf2.64.jar run Eclat INPUT SPMF_OUTPUT MINSUP
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP set
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP bitvector
```

The TV1 verification set is the toy database, Chess, Mushroom, Retail, and
T10I4D100K. The downloaded reference versions and chosen thresholds are recorded
in [the TV1 algorithm note](docs/TV1_algorithm.md); large datasets are not
committed.
