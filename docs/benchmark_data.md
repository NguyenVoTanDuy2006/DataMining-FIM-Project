# Dữ liệu benchmark

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
