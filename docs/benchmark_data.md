# Dữ liệu benchmark

Auto test đọc toàn bộ Groceries từ `data/processed/groceries_spmf.txt` và bốn
CSDL chuẩn hóa từ `data/benchmark/processed/processes/`. Groceries được mã hóa
bởi `scripts/groceries_demo.jl`; bốn benchmark dùng `prepare_input` trong
`scripts/benchmark_processes.jl`. Không dùng Toy hoặc fixture lấy mẫu cho bước
đối chiếu 5 CSDL. Xem lệnh chuẩn bị và chạy test trong [README](../README.md).

Tải ngày 2026-11-16 từ [FIMI Repository](https://fimi.uantwerpen.be/data/).
Các file gốc nằm trong `data/benchmark/raw/`, được Git-ignore và chưa chỉnh sửa.
Thống kê dưới đây được đếm trực tiếp từ file đã tải, không chép từ bảng mô tả.

| File | Giao dịch | Item khác nhau | Độ dài trung bình | ID nhỏ nhất | ID lớn nhất |
| --- | ---: | ---: | ---: | ---: | ---: |
| chess.dat | 3196 | 75 | 37.0000 | 1 | 75 |
| mushroom.dat | 8124 | 119 | 23.0000 | 1 | 119 |
| retail.dat | 88162 | 16470 | 10.3058 | 0 | 16469 |
| T10I4D100K.dat | 100000 | 870 | 10.1023 | 0 | 999 |

Cả bốn file không có dòng trống hoặc item lặp trong một giao dịch.
Không loại bỏ các giao dịch giống nhau.

## Nguồn và checksum SHA-256

- [chess.dat](https://fimi.uantwerpen.be/data/chess.dat): `A12EA887DF58A396709430AF5BF0A9A32D1F6EBA8E7C13DD41F28B98572C5DB2`
- [mushroom.dat](https://fimi.uantwerpen.be/data/mushroom.dat): `6CF94BC482712C3936F0B40C921381AB2B776C3D9941880FECAC4D83CA5CBEB5`
- [retail.dat](https://fimi.uantwerpen.be/data/retail.dat): `D967431BA522E32F0FBB243F2EE113ECD4CB374CB0234C1B0858DAE1D499A055`
- [T10I4D100K.dat](https://fimi.uantwerpen.be/data/T10I4D100K.dat): `464D7B87AA7FDC0DC432DDAD0493515569B2968B0F229CE39399C454A8C62E0C`

Khi chuẩn bị báo cáo, ghi nhận nguồn gốc Retail theo phần acknowledgement của FIMI.
Chưa chuẩn bị bản lưu trữ Hugging Face/Kaggle cho notebook nộp bài.

## Chuẩn hóa khi chạy

Core của nhóm yêu cầu ID dương. Retail và T10I4D100K có ID 0 nên runner
cộng 1 vào mọi ID của từng bộ này và lưu thành file chuẩn hóa riêng.
Chess và Mushroom giữ nguyên ID. Phép đổi tên một-một này giữ nguyên support.
Cả Julia và SPMF phải dùng cùng dữ liệu đã chuẩn hóa khi so sánh.

`scripts/benchmark_processes.jl` và `scripts/benchmark_peak_ram.jl` dùng cùng
quy trình chuẩn hóa, ghi vào `data/benchmark/processed/processes/`. Kết quả
runtime nằm ở `results/benchmarks/processes/`; phép đo peak RSS Set/BitVector
tại minsup trung bình nằm ở `results/benchmarks/peak_ram/`. Metadata lưu SHA-256
của đầu vào đã chuẩn hóa để phân biệt các phiên bản/mapping khác nhau.

Tham chiếu SPMF Chess tại minsup 0,875 ở `results/benchmarks/spmf/` từ lần thực
hành cũ dùng mapping ID +1 so với Chess hiện tại. Runner Peak RAM không dùng lại các file tham chiếu
cũ: tạo tham chiếu mới từ đúng đầu vào chuẩn hóa và lưu trong thư mục kết quả
riêng. Hai cách gán ID bảo toàn support nhưng phải cùng mapping khi đối chiếu.

## Tập con Retail cho Scalability

`scripts/benchmark_scalability.jl` dùng Retail chuẩn hóa đầy đủ, tạo một hoán vị
chỉ số dòng với `MersenneTwister(20261116)` và lấy các tiền tố có kích thước
`floor(N × tỷ lệ)` cho 10%, 25%, 50%, 75%, 100%. Sắp lại chỉ số theo thứ tự dòng
gốc trước khi ghi file. Các tập con lồng nhau, giao dịch trùng vẫn được giữ;
mức 100% khớp toàn bộ file Retail chuẩn hóa.

File tập con và danh sách chỉ số nằm trong `data/benchmark/processed/scalability/`,
được Git-ignore. Metadata ở `results/benchmarks/scalability/metadata.md` ghi seed,
phiên bản Julia, SHA-256 từng tập con và chỉ số để kiểm chứng tái lập. Giữ minsup
tương đối 4% trên cả năm mức; ngưỡng support tuyệt đối thay đổi theo số giao dịch.

## CSDL tổng hợp thay đổi độ dài giao dịch

`scripts/benchmark_transaction_length.jl` sinh N = 5.000 giao dịch trên M = 64
item với `MersenneTwister(20261116)`. Mỗi giao dịch có một hoán vị riêng của 1:M;
chọn 4, 8, 12, 16, 20 item đầu rồi sắp tăng dần. Tái sử dụng cùng hoán vị cho
các mức của cùng TID, nên các giỏ được mở rộng theo quan hệ lồng nhau.

Mọi giao dịch của một CSDL có cùng độ dài L, nên trung bình bằng L. Giữ số giao
dịch, số item quan sát và minsup 5% cố định; min_count luôn bằng 250. Các item
trong một giỏ là duy nhất; giao dịch trùng không bị xóa. Mật độ bằng L/64 và
tổng số lần xuất hiện item bằng 5.000×L.

Dữ liệu sinh nằm trong `data/benchmark/processed/transaction_length/`, được
Git-ignore. `results/benchmarks/transaction_length/metadata.md` lưu seed,
phiên bản Julia, thiết kế, checksum từng file sinh và tham chiếu SPMF để tái lập.
