# Eclat Frequent Itemset Mining

Julia project for a from-scratch Eclat implementation, SPMF comparison, four benchmarks, and two applications: Groceries and Fashion-MNIST. See [the project plan](docs/plan.md) and [assignment](docs/itemset.md) for requirements.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy (TV3, Fashion-MNIST and demo).

## Current state

Baseline Eclat và ứng dụng Groceries đã có cài đặt. Groceries đọc giỏ hàng, tạo mapping, mã hóa giao dịch, khai thác luật, xuất top 10 theo lift và so sánh 12 cấu hình. Các test hiện tại áp dụng cho baseline và phần ứng dụng của TV2; không thay thế đối chiếu SPMF trên ít nhất 5 CSDL hoặc chạy demo Colab.

## Julia setup

Install Julia 1.9 or newer, then run:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EclatFIM'
```

Generate and commit `Manifest.toml` with the selected Julia dependencies so experiments can be reproduced. Chạy các lệnh bên dưới từ thư mục gốc dự án trong terminal PowerShell, không nhập vào dấu nhắc `julia>`.

Large source datasets belong outside Git. Place local copies under `data/raw/` or `data/benchmark/`, and document their download URLs, versions, and preparation steps. Keep reproducible summaries and selected plots under `results/`.

## Kiểm thử tự động

Chạy từ thư mục gốc dự án trong terminal PowerShell:

```powershell
julia --project=. test/runtests.jl
```

`test/runtests.jl` giữ các test baseline Eclat và nạp hai file kiểm thử ứng dụng:

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

Backend tối ưu, peak RSS, scalability, ảnh hưởng độ dài giao dịch và Colab tiếp tục
được theo dõi trong [kế hoạch nhóm](docs/plan.md). Runtime mới không thay thế các
phần thực nghiệm còn thiếu này.
