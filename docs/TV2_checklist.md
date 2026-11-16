# Kiểm tra bàn giao TV2 — Groceries và benchmark

Đối chiếu [phân công TV2, mục 6](plan.md) và [đề bài](itemset.md).
Phạm vi bảng này là code, dữ liệu kết quả và phần báo cáo của TV2;
không thay thế kiểm tra nộp bài của cả nhóm.

| Yêu cầu TV2 | Chứng cứ |
| --- | --- |
| Groceries: parser giỏ hàng, bỏ item lặp, giữ giao dịch trùng, mapping xác định | `src/applications/Groceries.jl`, `scripts/groceries_demo.jl`, `test/test_groceries.jl`; 9.835 giỏ, 169 sản phẩm |
| Mining nhiều minsup và minconf, sinh luật bằng code nhóm | `src/applications/AssociationRules.jl`, `test/test_association_rules.jl`, `results/groceries/parameter_summary.csv`: 4 minsup × 3 minconf |
| Top 10 theo lift, số đếm và ý nghĩa bán lẻ | `results/groceries/top10_rules.csv`, [báo cáo Groceries](report_groceries.md) |
| 4 CSDL, mỗi CSDL 7 minsup, Set/BitVector/SPMF cùng điều kiện | `scripts/benchmark_processes.jl`, `results/benchmarks/processes/`: 28 cấu hình, 420 mẫu ghi nhận, khớp toàn bộ itemset/support |
| Runtime và itemset count theo minsup | `runtime_processes.png/.svg`, `itemset_counts.png/.svg` trong thư mục trên |
| Peak RAM baseline và optimized tại minsup trung bình | `results/benchmarks/peak_ram/`: 4 CSDL × 2 backend × 5 lần; phân biệt RSS với allocation |
| Scalability Retail 10%, 25%, 50%, 75%, 100% | `results/benchmarks/scalability/`: 50 mẫu; phân tích xu hướng và giới hạn suy luận |
| CSDL tổng hợp với độ dài giao dịch tăng dần | `results/benchmarks/transaction_length/`: 50 mẫu; cố định N, M, minsup; tăng L = 4, 8, 12, 16, 20 |
| Tính đúng đắn tự động trên ít nhất 5 CSDL | `test/test_benchmark.jl`: toàn bộ Groceries, Chess, Mushroom, Retail, T10I4D100K; cả Set và BitVector |
| Cách đo, seed, phiên bản, checksum, kết quả gốc | Metadata và CSV trong từng thư mục; [nguồn dữ liệu](benchmark_data.md) |
| Giải thích dense/sparse và ít nhất 2 hướng tối ưu tiếp | [báo cáo benchmark](report_benchmark.md), mục 6 |

Các phép đo có cùng điều kiện trong từng thí nghiệm; không trộn thời gian toàn
tiến trình với thời gian riêng `mine` sau warm-up. Mọi kết luận chỉ áp dụng cho
cấu hình đã đo. Python chỉ đọc/kiểm tra CSV và vẽ; auto test dùng Julia.

## Kiểm chứng trước khi bàn giao

Lần kiểm chứng ngày 2026-11-16: `julia --project=. test/runtests.jl` đạt
439/439 assertions; cả hai backend khớp SPMF trên 5 CSDL đầy đủ. Demo Groceries
chạy lại cho hai CSV có SHA-256 không đổi. Cả bốn CLI vẽ đã đọc và kiểm tra
CSV thành công: 420 + 40 + 50 + 50 = 560 mẫu; các CLI chỉ xuất PNG/SVG.
Output auto test cuối được đính kèm trong README. Chưa chạy Colab ở lần này.

## Việc tích hợp chung còn lại trước khi nộp

- Ghép Groceries và benchmark vào notebook chung, chạy Colab từ runtime sạch
  và đặt link công khai trong README (TV3 điều phối, TV2 hỗ trợ).
- Bổ sung bản lưu trữ benchmark trên Hugging Face/Kaggle và link công khai theo
  chính sách dữ liệu của đề. Hiện có nguồn FIMI và checksum, chưa có bản lưu trữ đó.
- Ghép nội dung báo cáo TV2 vào PDF IEEE của nhóm; hoàn tất review chéo/PR
  trước khi merge. Push nhánh không đồng nghĩa đã merge hoặc nộp bài.
