# Checklist EDA-1 — So sánh patch 4×4 và 7×7 cho TC

Nguồn: [plan EDA-1](../EDA_plan/EDA1_Image_Level_Fashion_MNIST_Plan.md).
Notebook: `notebook/UD2/02_fashion_mnist_image_eda.ipynb`.

**Trạng thái bản refactor:** code đã triển khai; chưa chạy toàn bộ notebook với 70.000 ảnh. Các dấu tick của bản EDA cũ không áp dụng cho cấu hình mới. Output trong thư mục cha `results/fashion/eda1/` là lịch sử; chỉ output mới trong `question_driven/` được dùng nghiệm thu.

## 1. Code và cấu hình

- [x] Giữ nạp PNG theo image_index, checksum, nhãn/split nguồn và kiểm tra dataset.
- [x] Hai size 4/7, stride bằng size, 49/16 patch mỗi ảnh.
- [x] Alpha chung 0, 0.0625, 0.125; cutoff count tương ứng 0/1/2 và 0/3/6.
- [x] Sobel grayscale gốc dùng chung hai size; magnitude sum được định nghĩa rõ.
- [x] Bảng patch metrics 4.550.000 dòng dự kiến; xuất gzip ngoài Git và provenance.
- [x] Phân tích vùng mỗi ảnh được tính cùng lượt Sobel, không quét lại toàn tập.
- [x] Pilot 200 ảnh cân bằng, seed 42, manifest và thông số extractor.
- [x] Khung insight tiếng Việt; code hỗ trợ mới trong notebook, không đổi public API.
- [x] Report dữ kiện, decision template không ghi đè, run metadata và output manifest.

## 2. Theo dõi 15 câu hỏi

“Code” chỉ xác nhận đã có phần triển khai. “Chạy/bằng chứng” chỉ tick sau khi cell chạy thành công và output khớp; “Insight” cần nhận xét có số liệu/ID.

| Câu hỏi | Công việc | Code | Chạy/bằng chứng toàn tập hoặc pilot quy định | Insight |
|---|---|---|---|---|
| Q1.1 | Mean/variance; nhóm tối/sáng/gần đồng nhất | [x] | [ ] | [ ] |
| Q1.2 | Mean gradient và tổng magnitude; gallery p05/p95 | [x] | [ ] | [ ] |
| Q1.3 | Heatmap vị trí patch toàn tập/theo lớp | [x] | [ ] | [ ] |
| Q2.1 | Patch FR và near-empty mỗi ảnh | [x] | [ ] | [ ] |
| Q2.2 | 14 phương án; cutoff/masks/retention/volume | [x] | [ ] | [ ] |
| Q2.3 | EdgeLoss/foreground loss, sweep và gallery | [x] | [ ] | [ ] |
| Q2.4 | Class impact và chênh lệch giữa lớp | [x] | [ ] | [ ] |
| Q3.1 | Scatter variance–gradient và gallery nhóm | [x] | [ ] | [ ] |
| Q3.2 | Histogram hướng, entropy và dịch 1 pixel | [x] | [ ] | [ ] |
| Q3.3 | Raw/255, diversity/RMS và trước/sau lọc | [x] | [ ] | [ ] |
| Q4.1 | SIFT/ORB pilot và zero-rate/theo lớp | [x] | [ ] | [ ] |
| Q4.2 | Coverage fixed grid và gallery | [x] | [ ] | [ ] |
| Q5.1 | Thống kê/phân phối vùng pixel | [x] | [ ] | [ ] |
| Q5.2 | Mean/variance/gradient/occupancy maps theo lớp | [x] | [ ] | [ ] |
| Q5.3 | Mapping patch→region và K/3K/4K | [x] | [ ] | [ ] |

## 3. Kiểm tra kỹ thuật

- [x] Notebook JSON/nbformat hợp lệ; mọi code cell parse Julia thành công.
- [x] Ảnh tổng hợp: partition không overlap, reconstruction, foreground/gradient conservation.
- [x] Ảnh tổng hợp: cutoff 0/1/2 pixel, dấu >, no-filter khác alpha=0, retained đơn điệu.
- [x] Ảnh tổng hợp: gzip roundtrip, descriptor dimension/normalization, coverage 0 và missing.
- [x] Kiểm tra giao diện OpenCV ORB/SIFT trên ảnh tổng hợp.
- [ ] Chạy notebook từ kernel Julia mới trên dữ liệu thật; không có error/assertion failure.
- [ ] Đủ 70.000 ảnh và 4.550.000 dòng patch metrics; checksum metadata khớp.
- [ ] Có đúng 14 phương án, số keep masks thực tế được công bố.
- [ ] Kiểm tra hình/gallery đủ lớp, đúng hướng, ID/cutoff đúng và chữ không bị cắt.
- [ ] So điểm gần reduction có reduction_gap, không gọi hai mức khác nhau là bằng nhau.
- [ ] Ghi thời gian/RAM và phiên bản thực thi; xác minh output manifest.

## 4. Chốt bàn giao TC

- [ ] TC1: viết bằng chứng/giới hạn cho size4/size7; giữ cả hai nếu chưa đủ phân biệt.
- [ ] TC2: chọn no-filter và ứng viên tau/alpha, kèm loss/empty rate/class impact.
- [ ] TC3 descriptor: baseline raw và ứng viên gradient/histogram hướng có bằng chứng.
- [ ] TC3 strategy: dense so với SIFT/ORB, ghi rõ giới hạn pilot.
- [ ] TC6: no-spatial/bands3/quadrants, mapping và mức tăng item universe.
- [ ] Điền decision template có observation → evidence → interpretation → candidate → validation.
- [ ] Không dùng nhãn làm item; chưa chọn K/minsup hoặc suy luận support từ ảnh.

## Bằng chứng kiểm tra bản refactor

- 78 code cell parse Julia thành công; nbformat và cell IDs hợp lệ; output cũ đã bỏ.
- 33 kiểm tra logic trên 20 ảnh tổng hợp 28×28, gồm ảnh toàn đen/toàn trắng, đã qua.
- 41 cell phân tích Q1–Q5 và báo cáo đã chạy nối tiếp trên bộ tổng hợp nhỏ; không chạy loader hay 70.000 ảnh thật.
- 36 SVG của luồng tổng hợp parse XML hợp lệ. Gallery hai size và bố cục heatmap/nhãn dài đã render và xem bằng ảnh PNG tổng hợp.
- Kiểm tra bố cục tổng hợp không thay cho kiểm tra hình Fashion-MNIST thực tế. Các ô “Chạy/bằng chứng” và “Insight” ở trên vẫn để trống.
