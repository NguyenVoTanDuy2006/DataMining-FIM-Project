# CHECKLIST — Implement Notebook Transaction Construction (TC1–TC7)

**Nguồn yêu cầu:** `TC_Transaction_Construction_Spec_v2.md`  
**Trạng thái:** Implementation checklist; không thay thế specification  
**Mục tiêu:** Notebook Julia thực thi được **luồng chính TC1 → TC7 với TC4 `raw_full_batch_kmeans` (B0)** để tạo các bộ **70.000 transactions S0 Binary BoVW** từ Fashion-MNIST, tương ứng từng codebook `(tc4_method, K, seed)`. `q20_weighted_kmeans` là **lựa chọn TC4 tùy chọn**, không phải bước bắt buộc.

> **Ranh giới cứng:** Không chạy TC0; không chia train/validation; không tính lại Q10+; không triển khai EDA2/Pilot Eclat; không triển khai TC6-S1/S2 (Spatial Encoding); không tự chọn K/seed cuối cùng. **Mặc định chạy B0; không triển khai hoặc tự chạy Q20 như điều kiện hoàn thành notebook.**

## A. Chuẩn bị notebook và hợp đồng dữ liệu

- [ ] **A01 — Khảo sát hiện trạng.** Đọc các modules/notebooks xử lý Fashion-MNIST, EDA, Pre-KMeans và cấu trúc thư mục output hiện có. Liệt kê phần có thể tái sử dụng; tránh viết lại thuật toán nếu implementation đã đúng.
- [ ] **A02 — Tạo notebook Julia duy nhất** để điều phối TC1–TC7 (tên file theo quy ước dự án); dùng các Markdown cells để mô tả mục đích, inputs, outputs, và acceptance checks của từng phần. Code dùng modules/functions tái sử dụng nếu có, không nhồi toàn bộ thuật toán vào notebook.
- [ ] **A03 — Thiết kế thứ tự cell rõ ràng:** Imports/Environment → Config → Load 70k → TC1 → TC2 → TC3 → TC4 → TC5 → TC6 → TC7 → Summary. Cell chạy lại không được vô tình dùng dữ liệu/biến `K`, `seed` từ lượt trước.
- [ ] **A04 — Đọc cấu hình tập trung.** Các tham số quan trọng: threshold `29`, T2, patch `(4,4)`, stride `(4,4)`, descriptor `Float32` 16D, `tc4_codebook.training_method="raw_full_batch_kmeans"` mặc định, `K=[16,32,64,128,256]`, seeds `[42,123,2026]`, S0, output_root, run_id, `fail_fast=true`.
- [ ] **A05 — Không có TC0.** Không tạo cell fit threshold, không tính phân vị trên 70k; TC2 sử dụng `29` cố định từ EDA.
- [ ] **A06 — Nạp đủ 70.000 ảnh** 28×28 grayscale `UInt8`, ghép 60k original train + 10k original test theo thứ tự cố định; **không** sinh train/validation split mới.
- [ ] **A07 — Metadata ảnh.** Lưu `image_id` duy nhất ổn định `1:70000`, `original_split`, `original_index`; `class_label` chỉ trong metadata riêng, không tham gia TC1–TC6 hoặc K-means.
- [ ] **A08 — Kiểm tra đầu vào.** Đúng 70k ảnh, kích thước 28×28, miền pixel 0–255; không thiếu/lặp image ID; thông tin nguồn ảnh có thể truy vết.
- [ ] **A09 — Quy ước data layout/ID.** Ghi rõ `patch_id` theo row-major, cố định từ 1 đến 49 mỗi ảnh trước lọc; descriptor `vec` column-major; ma trận Julia có thể dùng `16×N` (descriptor là cột) nếu hợp thư viện.
- [ ] **A10 — Quản lý tài nguyên.** Dùng representation/batching hợp lý cho hàng triệu patches; không giữ các bản sao dữ liệu lớn không cần thiết; checkpoint tách biệt với dữ liệu đang ghi dở.

## B. TC1 — Patch Extraction

- [ ] **TC1.01 — Trích 49 patches/ảnh**, patch 4×4, stride 4×4, không overlap, không padding; duyệt lưới 7×7 theo row-major.
- [ ] **TC1.02 — Giữ nguyên 16 pixel UInt8** trong mỗi patch; không nhị phân hóa/làm mịn/chỉnh sửa pixel.
- [ ] **TC1.03 — Gắn metadata patch:** `image_id`, `patch_id`, `patch_row`, `patch_col` và/hoặc `top_left_y`, `top_left_x`.
- [ ] **TC1.04 — Không đánh lại patch ID sau lọc** (TC2 sẽ chỉ tạo subset).
- [ ] **TC1.05 — Kiểm tra:** 49 patches/ảnh, **3.430.000 patches** trước lọc; phủ kín 28×28, không overlap, reconstruct ảnh/lưới patch đúng; pixel không đổi.

## C. TC2 — Foreground Patch Filtering, T2

- [ ] **TC2.01 — Dùng đúng ngưỡng cố định `τ=29`** từ EDA, không gọi lại TC0.
- [ ] **TC2.02 — Áp dụng `keep(P) = any(pixel > 29)`**, tương đương foreground ratio `> 0` (`alpha=0`); tuyệt đối không dùng `>=29`.
- [ ] **TC2.03 — Chỉ chọn/bỏ patch**, không đổi pixels của các patch được giữ; giữ nguyên `image_id`, `patch_id`, tọa độ.
- [ ] **TC2.04 — Thống kê số retained/removed patches** trên 70k, retention rate, số ảnh không còn patch; không lấy số retained của benchmark 60k làm expected value.
- [ ] **TC2.05 — Kiểm tra:** retained + removed = 3.430.000; patch giữ có ít nhất 1 pixel `>29`; patch loại có mọi pixel `≤29`.
- [ ] **TC2.06 — Test biên:** patch toàn `29` phải bị loại; patch có một pixel `30` phải được giữ; không chạy biến thể T1/T3.

## D. TC3 — Raw Pixel Descriptors

- [ ] **TC3.01 — Với mỗi retained patch**, tạo `Float32.(vec(P)) ./ 255f0`, flatten **column-major**, vector đúng **16D**.
- [ ] **TC3.02 — Bảo toàn raw descriptors 16D** làm dữ liệu chuẩn cho TC4-B0 và TC5; không thay đổi descriptors TC5 nếu về sau chọn nhánh TC4 tùy chọn.
- [ ] **TC3.03 — Không đưa nhãn, vị trí, image ID** vào giá trị 16D; metadata tách riêng và không mất mapping.
- [ ] **TC3.04 — Document physical matrix layout** cho Julia/Clustering.jl (`16×N` nếu descriptor theo cột); các thao tác transpose phải nhất quán.
- [ ] **TC3.05 — Kiểm tra:** số descriptors bằng số retained patches; mọi vector finite, 16 chiều, trong `[0,1]`; test patch có pixel phân biệt theo hàng/cột để xác nhận `vec` column-major.

## E. TC4 — Codebook Learning & Codebook Metrics

- [ ] **TC4.00 — Cấu hình chọn method.** Đọc `tc4_codebook.training_method`; giá trị mặc định **`raw_full_batch_kmeans` (B0)**. Chỉ chạy **một** backend được chọn cho một lượt TC; không tự chạy Q20. Với giá trị không hỗ trợ, báo lỗi rõ ràng, không fallback âm thầm.
- [ ] **TC4.01 — Fit B0 trên toàn bộ retained descriptors raw 16D của 70k ảnh**, không image sampling, không descriptor sampling; không nạp lại codebook benchmark cũ trên 60k để thay thế.
- [ ] **TC4.02 — Vòng lặp đúng `K=[16,32,64,128,256]` × `seed=[42,123,2026]`**, 15 fits cho **B0 theo luồng chính**; thực thi tuần tự, không ghi đè state K/seed giữa các lượt.
- [ ] **TC4.03 — K-means++**, `maxiter=300`, `tol=1e-4`, squared Euclidean, deterministic seed/initialization theo implementation hiện có.
- [ ] **TC4.04 — Triển khai/tái sử dụng B0**: full-batch K-means trực tiếp trên raw descriptors 16D với implementation dự án/Clustering.jl; đây là backend **bắt buộc** để hoàn thành notebook.
- [ ] **TC4.05 — Giao diện codebook thống nhất**: mọi backend TC4 được chọn phải xuất K centroids raw 16D trong `[0,1]`, cùng metadata `method/K/seed`; không truyền dữ liệu lượng tử hóa/PCA sang TC5.
- [ ] **TC4.06 — Lưu checkpoint mỗi fit** với `method/K/seed`, config, trạng thái fit; không đánh dấu completed khi fit lỗi hoặc artifacts chưa đầy đủ.
- [ ] **TC4.07 — Lưu codebook** đúng `K` centroids × `16D` raw space; document matrix orientation, word IDs `1:K`, finite centroids.
- [ ] **TC4.08 — Đánh giá distortion** trên **cùng toàn bộ raw descriptors 16D** của 70k cho mọi codebook; có kết quả theo K để lập elbow analysis/relative improvement.
- [ ] **TC4.09 — Đánh giá occupancy và cluster-size distribution** trên assignments của raw descriptors: used/unused clusters, counts, quantiles, top-cluster share, normalized entropy.
- [ ] **TC4.10 — Đánh giá seed stability** cho cùng K/method: mean/std distortion, occupancy, phân bố clusters qua seeds; ARI trên tập raw descriptors đánh giá **cố định chung** nếu đủ tài nguyên (chỉ sampling để đánh giá, không sampling fit).
- [ ] **TC4.11 — Ghi convergence, iterations, elapsed time**, warnings; có thể ghi memory nếu backend hỗ trợ. Không dùng train/validation split và không chốt K cuối cùng.

### TC4-OPT — Phương pháp `q20_weighted_kmeans` tùy chọn (KHÔNG thuộc DoD luồng chính)

Các mục dưới đây **chỉ áp dụng nếu người dùng chủ động chọn** `tc4_codebook.training_method="q20_weighted_kmeans"` và muốn tích hợp/chạy backend này. **Không đánh dấu chúng là blocker** cho notebook B0 → TC7.

- [ ] **OPT.01 — Kích hoạt bằng cấu hình, không bằng thay đổi flow:** dùng cùng vòng lặp K/seeds của TC4; một lượt chạy chỉ chọn B0 **hoặc** Q20, không tự thực hiện cả hai.
- [ ] **OPT.02 — Tái sử dụng implementation benchmark Q20 có sẵn**, không viết thuật toán thay thế nếu đã có. Quy tắc quantize pixel UInt8 với `q=20`, rounding/clipping phải khớp benchmark.
- [ ] **OPT.03 — Integer quantization keys → dedup → integer weights**; kiểm tra `sum(weights) == N_retained`, chạy Weighted K-means trên dữ liệu lượng tử hóa chuẩn hóa. Không thay bằng unweighted K-means.
- [ ] **OPT.04 — Chuẩn hóa output về raw 16D `[0,1]`**, giữ nguyên input TC5, ghi metadata về cách weighted K-means++ và phương pháp lượng tử hóa thực tế.
- [ ] **OPT.05 — Nếu method Q20 được chọn nhưng backend chưa khả dụng**, báo lỗi trực tiếp; không tự fallback sang B0 hoặc coi là fit Q20 thành công.

## F. TC5 — Hard Visual Word Assignment

- [ ] **TC5.01 — Với mỗi codebook `(method,K,seed)`**, nhận đúng raw descriptors 16D từ TC3 và codebook 16D từ TC4.
- [ ] **TC5.02 — Nearest-centroid hard assignment** theo squared Euclidean, một word ID cho mỗi retained patch; `word_id_base=1`.
- [ ] **TC5.03 — Tính theo batch `16.384` descriptors** để kiểm soát RAM; tie-breaking deterministic và nhất quán (ví dụ centroid ID nhỏ nhất).
- [ ] **TC5.04 — Lưu ánh xạ `image_id, patch_id, coordinates, word_id`**; không làm mất vị trí dù TC6-S0 không sử dụng vị trí làm item.
- [ ] **TC5.05 — Kiểm tra:** tất cả retained patches được assign đúng một lần; mọi word ID thuộc `1:K`; `N_assignments=N_retained`; không dùng nhầm codebook/K/seed.

## G. TC6 — Transaction Encoding: S0 only

- [ ] **TC6.01 — Gom patch assignments theo image_id** trên cùng codebook; một ảnh → một transaction.
- [ ] **TC6.02 — `S0_binary_bovw`:** `sort(unique(word_ids_per_image))`; không giữ frequency của word, không mã hóa coordinates/spatial IDs, không dùng labels.
- [ ] **TC6.03 — Giữ transaction rỗng** cho ảnh không còn retained patch, vẫn tạo TID và image mapping.
- [ ] **TC6.04 — Xuất đúng 70.000 transactions mỗi codebook** (15 bộ nếu 1 TC4 method × 5 K × 3 seeds được thực hiện đầy đủ).
- [ ] **TC6.05 — Kiểm tra:** items tăng dần, unique, nằm trong `1:K`; `0 ≤ length(T_i) ≤ min(K,49)`; `tid ↔ image_id` một-một, không thiếu ảnh.
- [ ] **TC6.06 — Không triển khai S1 Spatial 2×2/S2 Spatial Pyramid** ở notebook hiện tại.

## H. TC7 — Export & Integrity Validation

- [ ] **TC7.01 — Output độc lập theo `(run_id, method, K, seed)`**; không ghi đè production artifacts và không trộn word IDs/codebooks giữa các lượt.
- [ ] **TC7.02 — Lưu `transactions`** (70k hàng/TIDs, bao gồm rỗng) và `codebook` (K×16, raw space).
- [ ] **TC7.03 — Lưu `patch_assignments`** và `tid_image_mapping` gồm original split/index; labels (nếu xuất) chỉ trong metadata.
- [ ] **TC7.04 — Lưu `config_snapshot`, `tc4_metrics`, `integrity_report`** cùng định danh dữ liệu, method, K, seed, `threshold=29`; ghi trạng thái checkpoint.
- [ ] **TC7.05 — Integrity assertions:** số ảnh/TIDs/transactions đều **70.000**; mỗi ảnh ↔ đúng 1 TID; sorted unique; item IDs `1:K`; centroids đúng 16D/finite; assignments đủ; artifact khớp method/K/seed.
- [ ] **TC7.06 — Kiểm tra support denominator `70.000`**, kể cả transactions rỗng (không phải số patches hay số nonempty transactions).
- [ ] **TC7.07 — Fail-fast nếu check lỗi**, báo chính xác run_id/K/seed/cell và lý do; không gắn trạng thái `completed` cho dữ liệu chưa hợp lệ.
- [ ] **TC7.08 — Có khả năng load lại artifacts** và tái kiểm tra các điều kiện quan trọng mà không phải fit lại K-means.

## I. Test strategy và chạy notebook

- [ ] **I01 — Unit/smoke tests nhanh** với các patches/ảnh nhân tạo: patch 29/30, row-major patch order, column-major descriptor, unique/sort, empty transaction, word ID boundaries, deterministic tie-break, `training_method` selector và lỗi method không hợp lệ. Đây là dữ liệu test của hàm, **không thay thế fit thật trên 70k**.
- [ ] **I02 — End-to-end smoke** trên subset nhỏ chỉ để kiểm tra dây chuyền TC1→TC7 và lỗi schema/I-O; đánh dấu rõ `SMOKE`, tuyệt đối không xuất dưới nhãn production benchmark 70k.
- [ ] **I03 — Full-data TC1–TC3 check** đủ 70k và các cardinality checks; đo/ghi footprint tài nguyên hợp lý trước 15 fits.
- [ ] **I04 — Full-data TC4→TC7 với B0 mặc định** khi môi trường sẵn sàng; duyệt tuần tự từng K, seed, checkpoint, export, validate; không bắt buộc triển khai/chạy nhánh Q20 để hoàn thành luồng chính và không tự chọn codebook tốt nhất.
- [ ] **I05 — Sau khi notebook chạy xong**, nêu rõ số codebooks completed/failed, số transaction databases đã xuất, artifacts, tổng thời gian và danh sách assertions pass/fail.
- [ ] **I06 — Khả năng chạy lại/resume:** ghi nhận trạng thái từng `(method,K,seed)`; chỉ sử dụng checkpoint hợp lệ khi resume và không tự ghi đè outputs đã hoàn tất. Đây là yêu cầu về độ tin cậy, không thay đổi mục tiêu thí nghiệm.

## J. Definition of Done (DoD)

- [ ] **J01 — Notebook chạy theo thứ tự TC1–TC7** và không có TC0.
- [ ] **J02 — Toàn bộ 70k ảnh tham gia TC; threshold cố định 29; không chia train/validation.**
- [ ] **J03 — TC1–TC3 thỏa mọi checks** về 49 patches/ảnh, T2 foreground, raw descriptors 16D.
- [ ] **J04 — TC4 B0 mặc định:** tạo đủ 15 codebooks từ 5 K × 3 seeds, với metrics và checkpoints hợp lệ; các mục TC4-OPT không bắt buộc.
- [ ] **J05 — TC5–TC6 tạo đủ 15 bộ transactions, mỗi bộ 70k**, không nhãn/spatial, mappings nhất quán.
- [ ] **J06 — TC7 lưu và kiểm tra đúng toàn bộ artifacts**, không ghi đè production, support denominator là 70k.
- [ ] **J07 — Không triển khai/chạy EDA2, Pilot Eclat, S1/S2, hoặc tự chốt K.**
- [ ] **J08 — Có báo cáo bàn giao**: notebook/modules/config liên quan, cách chạy, logs và checks, đường dẫn output, blockers nếu có.

### Ghi chú phạm vi và lựa chọn phương pháp

**Phạm vi hoàn thành bắt buộc:** notebook TC1–TC7 chạy với `tc4_codebook.training_method = "raw_full_batch_kmeans"` (B0), TC6-S0 và đầy đủ 5 K × 3 seeds. **Không yêu cầu thêm Q20, không huấn luyện đồng thời B0/Q20 và không thay đổi flow TC chính.**

**Tùy chọn:** người dùng có thể chủ động đặt `training_method = "q20_weighted_kmeans"` để dùng nhánh TC4 đã benchmark **nếu backend tương thích được kết nối**. Khi đó, các mục TC4-OPT trở thành checklist của **lượt chạy Q20 đó**, không phải điều kiện nghiệm thu B0. Nếu chưa tích hợp Q20, thông báo rõ và không fallback. Dù phương pháp nào được chọn, TC5/TC6/TC7 chỉ nhận codebook raw 16D cùng metadata tương ứng.
