# Checklist TV3 (Duy) — Data Mining: Eclat trên Fashion-MNIST

**Căn cứ:** [`plan.md`](plan.md), phần phân công TV3 và mục 7. **Bắt đầu:** 08/11/2026. **Hạn chính thức:** 28/11/2026, 11:59 PM. **Hạn bàn giao nội bộ:** 26/11; dành 27–28/11 để xử lý lỗi hoặc nộp lại.

**Phạm vi của Duy:** dữ liệu Fashion-MNIST → patch/descriptor → K-means codebook → visual-word transactions → Eclat chung của Trung → pattern theo class, hình và ablation. Duy phụ trách phần Fashion-MNIST trong báo cáo, notebook Colab/README về tái lập, và review phần Groceries của Khang. Trung sở hữu Eclat; Khang sở hữu benchmark và luật giỏ hàng.

**Cập nhật 09/11:** Julia 1.13.3 đã chạy được. Loader/checksum Fashion-MNIST và hai notebook kiểm tra/EDA nằm trong repo chính. Julia tests và notebook được xác nhận chạy từ kernel mới. Patch extraction, codebook và mining chưa thuộc phạm vi nhánh EDA này.

## Tuần 1 — 08–10/11: môi trường và dữ liệu nhỏ

- [ ] **08/11 — Chốt phụ thuộc với Trung:** xác nhận `mine(transactions, minsup; backend=...)`, input `Vector{Vector{Int}}`, output itemset → support count, quy tắc minsup và cách import `EclatFIM`. Ghi quyết định vào PR hoặc tài liệu nhóm. **Bàn giao:** một ví dụ input/output mà cả hai cùng xác nhận.
- [ ] **08/11 — Cài và kiểm tra Julia ≥ 1.9:** chạy `julia --version` và `julia --project=. -e 'using Pkg; Pkg.instantiate(); using EclatFIM'`. Nếu chưa cài được, báo nhóm trong ngày; vẫn tiếp tục thiết kế dữ liệu/kiểm tra ảnh độc lập. Chốt seed và xin TA xác nhận package cho đọc ảnh, K-means, plotting trước khi phụ thuộc vào chúng.
- [x] **09/11 — Tải Fashion-MNIST:** dùng nguồn trong `plan.md`; ghi URL, cách tải và checksum/phiên bản nếu có. Kiểm tra ảnh grayscale 28×28, nhãn 0–9, số mẫu train/test. Giữ dữ liệu thô trong `data/raw/`, không commit vào Git.
- [x] **09/11 — EDA:** lưu một hình có ảnh đại diện của cả 10 class, bảng số ảnh/class và nhận xét sơ bộ về nền đen vào `results/fashion/`.
- [ ] **10/11 — MVP 100 ảnh:** viết `src/applications/FashionMNIST.jl` để đọc ảnh và cắt **16 patch 7×7** theo lưới 4×4. Viết test về kích thước, thứ tự patch và việc không mất/lặp pixel; chạy trên 100 ảnh.

**Mốc 10/11:** đọc được dữ liệu thật, có hình EDA và patch extraction chạy/test được trên 100 ảnh. Nếu Julia vẫn chưa chạy, báo blocker rõ cho Trung và ghi những phần đã chuẩn bị độc lập.

## Tuần 2 — 11–16/11: codebook và transaction

- [ ] **11/11 — Descriptor:** chọn một cách biểu diễn patch dễ giải thích (intensity chuẩn hóa hoặc thống kê `mean`/`std`/gradient). Viết hàm trong `src/applications/VisualCodebook.jl`; kiểm tra mỗi patch cho vector cùng chiều, giá trị hữu hạn và cùng thang đo.
- [ ] **11/11 — Nền đen:** thử ngưỡng lọc patch gần như toàn nền, đo tỷ lệ bị lọc theo class. Lưu ngưỡng trong tham số; xử lý rõ ảnh không còn patch sau lọc.
- [ ] **12–13/11 — Codebook `K=32`:** dùng train split và seed cố định; chạy K-means trên mẫu nhỏ trước, kiểm tra cluster rỗng và centroid chỉ biểu diễn nền. Ghi cách chọn package hoặc cách cài đặt đã được nhóm/TA chấp thuận. Không fit codebook bằng test split.
- [ ] **13/11 — Mẫu chính:** chọn **5.000 ảnh train cân bằng, 500 ảnh/class**; lưu danh sách chỉ số chọn và seed để chạy lại đúng tập ảnh.
- [ ] **14/11 — Image → transaction:** trong `src/applications/VisualMining.jl`, gán patch vào visual-word ID gần nhất, biến mỗi ảnh thành vector ID dương, duy nhất, tăng dần. Lưu nhãn class riêng; giữ nguyên số giao dịch kể cả khi hai ảnh cho cùng transaction. Lưu mapping ID ↔ centroid/patch mẫu.
- [ ] **15/11 — Test 100–1.000 ảnh:** kiểm tra 16 patch/ảnh trước lọc, ID thuộc `1:K`, không trùng item trong transaction, số transaction bằng số ảnh và kết quả lặp lại được với cùng seed. Thêm test vào `test/` và nối với `test/runtests.jl`.
- [ ] **15–16/11 — Tích hợp Eclat:** gọi API của Trung trên 100–1.000 transaction; đối chiếu support của vài itemset bằng phép đếm trực tiếp. Nếu core chưa sẵn, bàn giao file giao dịch và test contract để Trung tích hợp sau; không viết Eclat riêng.
- [ ] **16/11 — Review đầu tiên:** gửi PR hoặc diff cho ba module Fashion-MNIST, codebook, transaction kèm lệnh chạy, test, seed và EDA; nhờ Trung review API, Khang review khả năng tái lập dữ liệu.

**Mốc 16/11:** pipeline ảnh → transaction chạy được trên ít nhất 1.000 ảnh, có test và hướng dẫn chạy. Bản 5.000 ảnh đã được chọn cố định.

## Tuần 3 — 17–22/11: kết quả ứng dụng và báo cáo nháp

- [ ] **17–18/11 — Chạy 5.000 ảnh:** train codebook `K=32`, tạo giao dịch, ghi thời gian và kích thước từng bước. Chạy Eclat của Trung theo từng class và toàn tập; thử minsup từ cao xuống thấp để chọn mức có số pattern phân tích được.
- [ ] **18–19/11 — So sánh class:** tính `support_class(P) = số ảnh class chứa P / số ảnh class` và support ở các class còn lại. Lập bảng pattern nổi bật gồm itemset, support count, tỷ lệ theo class và chênh lệch. Trình bày như mẫu đồng xuất hiện; không suy ra khả năng phân loại hay quan hệ nhân quả.
- [ ] **19/11 — Hình minh họa:** lưu ảnh đại diện chứa pattern, patch/centroid tương ứng visual words và biểu đồ support theo class trong `results/fashion/`; caption giải thích ID và ý nghĩa hình.
- [ ] **20/11 — Ablation:** dùng cùng tập ảnh và seed để thử `K=16, 32, 64` hoặc một descriptor thứ hai. Ghi số pattern, runtime và mức dễ diễn giải; giải thích ảnh hưởng của codebook/nền đen. Test split chỉ dùng để đánh giá ổn định nếu còn thời gian, không dùng để fit.
- [ ] **20/11 — Khóa số liệu:** lưu bảng kết quả, tham số, seed, Julia/package versions, cấu hình máy và lệnh tạo hình. Gửi kết quả chính cho Trung/Khang để tích hợp báo cáo.
- [ ] **21–22/11 — Viết mục ứng dụng 2:** mô tả dữ liệu, 16 patch, descriptor, K-means, transaction, Eclat, support theo class, hình, ablation, giới hạn và nguồn. Gửi Trung review phần API; đọc và góp ý mục Groceries của Khang.

**Mốc 22/11:** có kết quả thật từ Eclat của nhóm, hình/bảng tái tạo được và bản nháp mục Fashion-MNIST. Nếu chạy 5.000 ảnh quá nặng, giữ subset cân bằng nhỏ hơn, ghi lý do, số mẫu và giới hạn; ưu tiên pipeline đúng và chạy lại được.

## Tuần 4 — 23–28/11: demo, kiểm tra và bàn giao

- [ ] **23/11 — Notebook chung:** bổ sung phần Fashion-MNIST vào `notebooks/demo.ipynb`: tải dữ liệu công khai, thiết lập Julia/seed, tạo codebook/giao dịch, gọi Eclat và hiển thị pattern/hình. Phối hợp Trung/Khang ghép luồng toy data, Groceries và benchmark; không dùng đường dẫn cá nhân.
- [ ] **24/11 — Colab sạch:** chạy toàn bộ notebook từ runtime mới, ghi thời gian chạy và sửa lỗi. Cập nhật README với cách tải dữ liệu, phiên bản Julia/package, lệnh chạy, seed và link Colab công khai. Chốt mục Fashion-MNIST cho PDF IEEE; kiểm tra hình/bảng có caption, được dẫn trong văn bản.
- [ ] **25/11 — Review chéo và QA:** hoàn tất góp ý phần Groceries của Khang; nhận phản hồi của Trung cho phần visual mining. Kiểm tra script tạo lại hình/bảng và không commit dữ liệu thô lớn.
- [ ] **26/11 — Bàn giao:** nhờ Trung hoặc Khang chạy phần Fashion-MNIST từ môi trường sạch; tự chạy lại notebook chung; kiểm tra link công khai. Gửi PR cuối gồm mã, test, hình, số liệu, mục báo cáo và README cho người tích hợp.
- [ ] **27–28/11 — Dự phòng:** chỉ sửa lỗi tích hợp, tái lập hoặc nộp bài; kiểm tra repo và notebook công khai trước hạn 28/11, 11:59 PM.

## Điều kiện hoàn thành của Duy

- [ ] `FashionMNIST.jl`, `VisualCodebook.jl`, `VisualMining.jl` có lệnh chạy/test rõ ràng; chỉ dùng core Eclat chung.
- [ ] Transaction có item ID dương, duy nhất; nhãn class tách riêng; seed/codebook và nguồn dữ liệu được ghi để tái lập.
- [ ] Có pattern theo class, support count/tỷ lệ, hình đại diện và một ablation có bảng số liệu.
- [ ] Notebook Colab chạy từ đầu đến cuối, README có link công khai; mục báo cáo ứng dụng 2 và review Groceries được nhóm duyệt trước 26/11.
