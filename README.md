# Khai thác tập phổ biến bằng Eclat

Đồ án cài đặt Eclat bằng Julia, đối chiếu với SPMF, đánh giá hiệu năng và áp dụng
cho Groceries cùng Fashion-MNIST.

| Thành viên | Phụ trách |
|---|---|
| Nguyễn Thành Trung | Thuật toán và tối ưu hóa |
| Lê Phúc Khang | Thực nghiệm và ứng dụng Groceries |
| Nguyễn Võ Tấn Duy | Ứng dụng Fashion-MNIST và demo |

[Báo cáo nhóm](docs/Report.pdf) · [Đề bài](https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/)

## Cấu trúc thư mục

```text
.
├── Project.toml, Manifest.toml   # Môi trường Julia
├── src/
│   ├── algorithm/               # Eclat cơ bản và tối ưu
│   ├── applications/            # Groceries, luật kết hợp, Fashion-MNIST
│   └── utils/                   # Đọc và ghi định dạng SPMF
├── scripts/                     # Chuẩn bị dữ liệu, CLI, thực nghiệm và vẽ hình
├── test/                        # Kiểm thử tự động
├── data/                        # Dữ liệu tải về và đã chuẩn hóa
├── notebooks/                   # Demo Colab và notebook lưu trữ
├── results/                     # Kết quả sinh khi chạy
└── docs/
    ├── Report.pdf               # Báo cáo nộp
    └── report/                  # Nguồn LaTeX và hình của báo cáo
```

Dữ liệu lớn và kết quả sinh khi chạy không đưa vào Git. Hình và bảng đã chọn
được trình bày trong báo cáo; notebook cũ nằm trong
`notebooks/fashion-mnist/archive/`.

## Cài đặt và dữ liệu

Cần Julia từ 1.9 trở lên. Chạy các lệnh sau từ thư mục gốc repo:

```powershell
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EclatFIM'
julia --project=. scripts/prepare_data.jl
```

Lệnh cuối tải và chuẩn hóa Groceries, Chess, Mushroom, Retail và T10I4D100K,
đồng thời tạo các bảng luật Groceries. Nguồn bốn benchmark được lưu trên
[Hugging Face](https://huggingface.co/datasets/Yelgsef/fimi-eclat-benchmarks);
script kiểm tra SHA-256 trước khi dùng. Xem
[nguồn dữ liệu và checksum](docs/benchmark_data.md).

Java và JAR SPMF cần cho bước tạo kết quả tham chiếu và so sánh hiệu năng.
Notebook Colab tự chuẩn bị các phụ thuộc này.

## Chương 1 — Cài đặt và sử dụng Eclat

Hai phiên bản dùng `Set` và `BitVector` để lưu tập định danh giao dịch.

```julia
using EclatFIM
transactions = [[1, 2, 3], [1, 2], [2, 3]]
mine(transactions, 0.5; backend=:bitvector)
```

Ngưỡng số thực là tỷ lệ hỗ trợ, đổi thành `ceil(minsup * N)`; ngưỡng số nguyên
là số giao dịch tối thiểu. Kết quả ánh xạ tập mục đã sắp thứ tự sang số hỗ trợ.
Dùng `backend=:set` để chạy phiên bản cơ bản.

CLI đọc và xuất file SPMF:

```powershell
julia --project=. scripts/eclat_cli.jl --input data/processed/groceries_spmf.txt --minsup 0.01 --backend bitvector --output results/output.txt
```

Mỗi dòng kết quả có dạng `1 2 3 #SUP: 4`.

## Chương 2 — Thực nghiệm

Sau khi chuẩn bị dữ liệu, đặt JAR tại `data/benchmark/tools/spmf.jar` và bảo đảm
`java` có trong PATH. Mỗi lệnh sau chạy một nhóm thực nghiệm:

```powershell
julia --startup-file=no --project=. scripts/benchmark_processes.jl
julia --startup-file=no --project=. scripts/benchmark_peak_ram.jl
julia --startup-file=no --project=. scripts/benchmark_scalability.jl
julia --startup-file=no --project=. scripts/benchmark_transaction_length.jl
```

| Thực nghiệm | Phạm vi |
|---|---|
| Thời gian và số tập mục | 4 CSDL × 7 minsup; Set, BitVector và SPMF |
| Đỉnh bộ nhớ (Peak RSS) | Set và BitVector tại minsup giữa mỗi dải |
| Khả năng mở rộng | Retail: 10%, 25%, 50%, 75%, 100% |
| Độ dài giao dịch | 5.000 giao dịch, 64 mục; độ dài 4, 8, 12, 16, 20 |

Mặc định đo năm lượt mỗi cấu hình. Thời gian toàn tiến trình gồm khởi động,
JIT và đọc ghi; hai thí nghiệm cuối đo khai thác sau làm nóng. Peak RSS bao gồm
môi trường Julia và dữ liệu đầu vào. CSV và biểu đồ được tạo trong
`results/benchmarks/`. Git chỉ nhận `runs.csv`, `summary.csv` và `metadata.md`
của mỗi thí nghiệm khi chúng có mặt. Bộ số liệu gốc dùng trong báo cáo chưa
có ở bốn thư mục kết quả chính của workspace này; các file trong `tmp/` là
bản thử, không dùng thay thế. Xem [phương pháp và kết quả](docs/report_benchmark.md).

## Chương 3 — Ứng dụng

### Groceries: phân tích giỏ hàng

```powershell
julia --project=. scripts/groceries_demo.jl
```

Dữ liệu gồm 9.835 giỏ và 169 sản phẩm. Với minsup 1%, minconf 50%, Eclat sinh
333 tập phổ biến và 15 luật. Hai bảng `results/groceries/top10_rules.csv` và
`parameter_summary.csv` lần lượt chứa top 10 luật theo lift và 12 cấu hình
ngưỡng. Xem [phân tích Groceries](docs/report_groceries.md).

### Fashion-MNIST: khai thác mẫu ảnh

Quy trình gồm khảo sát ảnh, chuyển ảnh thành giao dịch túi từ thị giác nhị phân
và khai thác các tổ hợp từ thị giác. Chạy ba notebook theo thứ tự ở phần demo.

## Demo trên Google Colab

### Eclat, Groceries và benchmark

| Notebook | Mở trên Colab |
|---|---|
| [Eclat, Groceries và benchmark](notebooks/eclat_groceries_benchmarks.ipynb) | [Mở notebook](https://colab.research.google.com/github/NguyenVoTanDuy2006/DataMining-FIM-Project/blob/master/notebooks/eclat_groceries_benchmarks.ipynb) |

1. Chọn runtime Julia CPU rồi chạy từ đầu đến cuối. Notebook tự tải source,
   dữ liệu, Java và SPMF; kiểm thử, sinh luật Groceries và chạy benchmark.
2. Mặc định `BENCHMARK_RUNS = 1` để kiểm tra luồng; đặt `5` để đo trung vị
   năm lượt như báo cáo.
3. Tải gói kết quả `.tar.gz` từ Files panel trước khi kết thúc runtime.
   Kết quả lưu trong `results/colab/eclat_*/`.

Lần chạy ngày 27/11/2026 hoàn tất 12/12 cell trên VM Colab CPU, Julia 1.12.6,
qua Colab CLI/Jupyter. Chưa xác minh nút Run all trên giao diện web.

### Fashion-MNIST

| Thứ tự | Notebook | Mở trên Colab |
|---|---|---|
| 1 | [Khảo sát ảnh](notebooks/fashion-mnist/demo/01_image_exploration.ipynb) | [Notebook 1](https://colab.research.google.com/drive/1cyyfr4Yt410cpJJhl-rI7gDsCWOOXnLs) |
| 2 | [Tạo giao dịch](notebooks/fashion-mnist/demo/02_transaction_construction.ipynb) | [Notebook 2](https://colab.research.google.com/drive/1sIsAmpG8UQRmVNxmj6TI6ENCvo7rd-zF) |
| 3 | [Khám phá và khai thác](notebooks/fashion-mnist/demo/03_transaction_exploration_and_mining.ipynb) | [Notebook 3](https://colab.research.google.com/drive/1lxDm_OweS1I65y66Vs0qmTk2P3qTy_VK) |

1. Chọn runtime CPU, chạy từng notebook từ đầu đến cuối; lần đầu cần mạng.
2. Notebook 1 minh họa tiền xử lý. Notebook 2 tạo giao dịch từ 70.000 ảnh,
   với K=32, seed 123, dung sai 0,0001 và tối đa 400 vòng.
3. Tải `fashion-demo-<run_id>.tar.gz` từ notebook 2, đưa vào thư mục
   `/content` của notebook 3 rồi chạy phân tích.
4. Tải `fashion-demo-analysis.tar.gz` về máy trước khi đóng runtime.

## Kiểm thử và kết quả đối chiếu

```powershell
julia --project=. test/runtests.jl
```

Bộ test cần đủ năm CSDL đã chuẩn hóa và năm file tham chiếu SPMF; thiếu file
sẽ báo lỗi. Notebook Eclat tạo các tham chiếu trước khi chạy test. Khi chạy
local, xem [cách chuẩn bị tham chiếu](docs/testing.md).

| CSDL | Giao dịch | Minsup | Số tập mục khớp SPMF |
|---|---:|---:|---:|
| Groceries | 9.835 | 1% | 333 |
| Chess | 3.196 | 87,5% | 1.386 |
| Mushroom | 8.124 | 70% | 31 |
| Retail | 88.162 | 4% | 18 |
| T10I4D100K | 100.000 | 1,5% | 237 |

Lần kiểm thử đã lưu ngày 27/11/2026 trên VM Colab CPU, Julia 1.12.6:
**569/569 phép kiểm tra đạt**. Cả Set và BitVector khớp từng tập mục và số hỗ trợ
với SPMF. Source của lần chạy được ghim tại
`c93fed0c436275e51f8672f6e7e8182d9b855040`.

<details>
<summary>Output test Julia trên Colab ngày 2026-11-27 (phần kết quả kiểm thử)</summary>

```text
Test Summary:                    | Pass  Total  Time
Eclat correctness and edge cases |   22     22  5.3s
Test Summary:                 | Pass  Total  Time
SPMF I/O and exact comparison |   11     11  3.6s
Test Summary:              | Pass  Total  Time
Groceries - xu ly gio hang |   10     10  0.8s
Test Summary:            | Pass  Total  Time
Luat ket hop - cong thuc |   11     11  0.3s
Test Summary:                 | Pass  Total  Time
Luat ket hop - tap con hop le |    7      7  2.0s
Test Summary:              | Pass  Total  Time
Luat ket hop - sinh va loc |   59     59  2.4s
Test Summary:                                 | Pass  Total  Time
BitVector singleton pruning before allocation |   18     18  0.9s
Test Summary:                                          | Pass  Total  Time
Pruned BitVector matches independent exhaustive oracle |  280    280  1.6s
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
Correctness SPMF tren 5 CSDL |   22     22  8.6s
Test Summary:           | Pass  Total  Time
Fashion-MNIST IDX input |   17     17  1.9s
Test Summary:                    | Pass  Total  Time
Verified Fashion-MNIST downloads |    7      7  0.3s
Test Summary:                  | Pass  Total  Time
Stable Fashion-MNIST image IDs |   12     12  0.0s
Test Summary:                             | Pass  Total  Time
Fashion-MNIST dataset manifest round trip |   11     11  4.5s
Test Summary:                        | Pass  Total  Time
Fashion transaction input validation |    9      9  0.8s
Test Summary:            | Pass  Total   Time
Fashion-MNIST TC helpers |   39     39  11.9s
Test Summary:                         | Pass  Total  Time
Release Fashion-FIM transaction input |    9      9  1.7s
Test Summary:                | Pass  Total  Time
Fashion TC6 spatial encoding |    1      1  0.7s
Test Summary:                    | Pass  Total  Time
EDA2 input and mining invariants |   18     18  3.0s
Test Summary:                                   | Pass  Total  Time
Verified input download preserves existing data |    6      6  0.2s
```

</details>

## Báo cáo và tài liệu

- [Báo cáo nhóm — Report.pdf](docs/Report.pdf).
- [Nguồn LaTeX và hướng dẫn biên dịch](docs/report/README.md).
- [Phương pháp thực nghiệm](docs/report_benchmark.md) và [phân tích Groceries](docs/report_groceries.md).
