# SPEC — Fashion-MNIST Transaction Construction (TC1–TC7)

**Trạng thái:** Bản đặc tả triển khai (TC chính: Raw K-means + S0; Q20 là phương pháp TC4 tùy chọn)  
**Đối tượng nhận:** Coding agent / nhóm triển khai Julia  
**Mục tiêu:** Biểu diễn **toàn bộ 70.000 ảnh Fashion-MNIST** thành các transaction nhị phân dựa trên Bag of Visual Words (BoVW), phục vụ EDA2 và Frequent Itemset Mining bằng Eclat.

## 1. Quyết định thiết kế đã thống nhất

1. **Loại bỏ TC0.** Không fit/tính lại threshold. Dùng cố định **Q10+ threshold = 29** từ EDA.
2. Không chia train/validation trong TC: sử dụng cả 60.000 ảnh *original train* và 10.000 ảnh *original test* cho **học codebook** và tạo transactions. Nguồn train/test gốc chỉ là metadata truy vết; nhãn lớp không được tham gia học hoặc mã hóa.
3. TC1: patch **4×4**, stride **4×4**, không overlap, không padding; lưu tọa độ.
4. TC2: chỉ dùng **T2**, giữ patch nếu **có ít nhất một pixel > 29**; không thay đổi pixel. Không tự chạy T1/T3.
5. TC3: raw grayscale pixels, `Float32`, chia `255`, descriptor **16D**, flatten column-major.
6. TC4 thử `K = [16, 32, 64, 128, 256]`, seeds `[42, 123, 2026]`, không sampling; **luồng chính dùng `raw_full_batch_kmeans` (B0)**. `q20_weighted_kmeans` là **phương pháp lựa chọn qua cấu hình**, không phải bước bắt buộc trong flow TC; không chốt K chỉ dựa trên distortion.
7. TC5 hard assignment các raw descriptors 16D vào codebook raw 16D, dùng bình phương khoảng cách Euclidean.
8. TC6 giai đoạn này chỉ triển khai **S0 — Binary BoVW không mã hóa vị trí**; loại trùng, sắp xếp tăng dần, mỗi ảnh một transaction (kể cả rỗng).
9. TC7 xuất artifacts và kiểm tra tính toàn vẹn; **“validation” trong TC7 là integrity validation, không phải validation split**.
10. **EDA2 + Pilot Eclat** là giai đoạn tiếp theo để đánh giá các bộ transactions và chọn cấu hình cuối cùng; **S1 Spatial 2×2 và S2 Spatial Pyramid** là phần mở rộng TC6 **sau EDA2**, chưa triển khai trong scope này.

### Ranh giới giữa luồng TC chính và phương pháp TC4 tùy chọn

- **Luồng chính/giá trị mặc định:** `tc4_codebook.training_method = "raw_full_batch_kmeans"` (B0). Fit K-means trên toàn bộ raw descriptors 16D của 70.000 ảnh, sau đó đi tiếp TC5 → TC6-S0 → TC7.
- **Tùy chọn cấu hình:** `tc4_codebook.training_method = "q20_weighted_kmeans"`. Khi *được chọn tường minh*, chỉ thay **cách huấn luyện codebook trong TC4**; các bước TC1–TC3 và TC5–TC7, định dạng centroids raw 16D, các kiểm tra dữ liệu và outputs vẫn giữ nguyên.
- **Không thêm Q20 vào chuỗi TC như một bước bắt buộc**, không fit B0 rồi tự chạy tiếp Q20 trong cùng lượt TC, không tự chuyển sang Q20 dựa trên kết quả benchmark 60k.
- **Scope triển khai cốt lõi:** notebook TC1–TC7 chạy được với B0 và có trường `training_method` để chọn backend TC4. Q20 là **tích hợp tùy chọn**: ưu tiên tái sử dụng implementation từ benchmark hiện có nếu cần kích hoạt; **không phải điều kiện nghiệm thu (DoD) của luồng chính**. Nếu người dùng chọn Q20 nhưng implementation tương thích chưa được kết nối, báo lỗi rõ ràng, không tự fallback sang B0/unweighted.
- Kết quả benchmark Q20 trên 60k chỉ để tham khảo lựa chọn phương pháp, **không được dùng codebook 60k thay cho fit 70k**.

## 2. Phạm vi & data contracts xuyên suốt

**Dataset:** 70.000 ảnh grayscale 28×28, pixel `UInt8` trong [0,255]. Không dùng class labels trong TC1–TC6 hoặc quá trình fit TC4. Giữ `original_split`, `original_index`, `class_label` (nếu có) **chỉ ở metadata**, không ghi nhãn vào transaction.

**ID:** Gán `image_id` toàn cục ổn định `1:70000`: ảnh train gốc `1:60000`, test gốc `60001:70000` theo thứ tự dataset, trừ khi dự án đang dùng ánh xạ tương đương ổn định thì tái sử dụng và lưu lại. `tid` cũng phải ánh xạ một-một với ảnh. `patch_id` bắt đầu từ 1, đánh theo thứ tự duyệt row-major trước lọc (1–49/ảnh); sau lọc **không đánh lại patch_id**. Tọa độ nên lưu `patch_row`, `patch_col` (chỉ số ô 1–7) và/hoặc `top_left_y`, `top_left_x` (pixel index 1,5,…,25).

**Khả năng tái lập:** Mọi artifacts phải ghi `run_id`, `K`, `seed`, `tc4_method`, mã/phần cấu hình đầu vào, threshold=29 và hash hoặc định danh dữ liệu phù hợp. Tách artifacts theo từng bộ codebook; không trộn item IDs giữa các codebooks.

**Phạm vi triển khai bắt buộc:** TC1–TC7 với TC4 `raw_full_batch_kmeans` và TC6-S0, các báo cáo chất lượng TC4 cơ bản, một bộ codebooks cho các K/seeds. **Q20 chỉ là lựa chọn TC4 tùy chọn**; không yêu cầu huấn luyện hoặc tích hợp Q20 để hoàn thành luồng chính. Không tự chạy EDA2, Pilot Eclat, không tự kết luận K tối ưu, không triển khai spatial encoding tại TC6.

## 3. TC1 — Patch Extraction

**Đầu vào:** 70.000 ảnh 28×28.  
**Cấu hình:** patch_size=(4,4), stride=(4,4), overlap=false, padding=none, traversal=row-major, patch_id_base=1.

**Thao tác:** Với mỗi ảnh, tạo `7×7=49` patches **nguyên bản**, không thay đổi giá trị pixel. Theo thứ tự duyệt ô hàng trước cột, lưu `image_id`, `patch_id`, tọa độ và mảng pixel 4×4.

**Đầu ra:** 3.430.000 patches trước TC2, cùng mapping ảnh/vị trí.

**Acceptance checks:** mọi ảnh đúng 49 patches; các patches không overlap, phủ kín 28×28; có thể phục hồi lưới 7×7 theo mapping; không sai khác giá trị grayscale.

## 4. TC2 — Foreground Patch Filtering (T2)

**Đầu vào:** patches từ TC1 và **threshold τ = 29 cố định lấy từ EDA**.  
**Không có TC0; không tính quantile ở đây.**

Đối với patch P gồm 16 pixels:

\[
r(P) = \frac{\#\{p\in P: p>29\}}{16},\qquad \operatorname{keep}(P)\iff r(P)>0.
\]

Tương đương: giữ patch nếu `any(pixel > 29)`. Dùng toán tử `>` (không phải `>=`). Không chỉnh sửa những pixel còn lại trong patch.

**Đầu ra:** retained patches và mapping với `image_id`, `patch_id`, coordinates; thống kê retained/removed, tỷ lệ lọc và số ảnh không còn retained patches.

**Acceptance checks:** retained + removed = 3.430.000; từng patch giữ lại thỏa `any(p > 29)`; mỗi patch bị loại thỏa `all(p <= 29)`; pixel gốc không bị thay đổi. Không áp đặt số retained descriptors của bộ 60k lên 70k.

## 5. TC3 — Raw Pixel Descriptor Extraction

Với retained patch P:

\[
x=\operatorname{Float32}(\operatorname{vec}_{\text{column-major}}(P))/255f0 \in [0,1]^{16}.
\]

**Cấu hình:** `descriptor=raw_pixels`, dimension=16, dtype=`Float32`, normalization=divide_by_255, `flatten_order=column_major`; không thêm nhãn, tọa độ hay thông tin không gian vào **vector feature**.

**Đầu ra:** descriptor cho mọi retained patch và metadata liên kết. Trong Julia có thể lưu ma trận **16×N (mỗi descriptor một cột)** nếu thuận tiện cho Clustering.jl; mô tả rõ layout vật lý để tránh transpose nhầm. Giữ bản descriptors 16D gốc để TC5 sử dụng ngay cả khi TC4 học trên dữ liệu biến đổi.

**Acceptance checks:** số descriptors bằng số retained patches; mọi vector 16 phần tử, finite, trong [0,1]; flatten và normalization nhất quán; metadata không bị mất.

## 6. TC4 — Codebook Learning & Codebook-Level Evaluation

### 6.1. Mục tiêu

Học visual vocabulary để mã hóa patches. Với mỗi `K∈{16,32,64,128,256}` và mỗi seed `∈{42,123,2026}`, học một codebook độc lập. **Luồng chính tạo 15 codebooks bằng B0**; nếu chọn Q20 trong cấu hình thì **thay thế B0 trong lượt chạy đó**, không tự nhân đôi thành 30 fits. Không chia train/validation; fit dùng **tất cả retained descriptors của 70k ảnh**, không image/descriptor sampling.

### 6.2. Thuật toán & phương pháp fit

Các tham số K-means mục tiêu: init=kmeans++, maxiter=300, tolerance=1e-4, squared Euclidean, chạy tuần tự, checkpoint mỗi fit. Ghi nhận số iterations, convergence, runtime và cảnh báo.

**Method mặc định — `raw_full_batch_kmeans` (B0; LUỒNG CHÍNH):** huấn luyện full-batch K-means trên raw 16D; dùng implementation phù hợp với `Clustering.jl` và code dự án.

**Method tùy chọn — `q20_weighted_kmeans` (KHÔNG THUỘC LUỒNG CHÍNH):** chỉ kích hoạt khi `tc4_codebook.training_method = "q20_weighted_kmeans"`. Trên *nhánh huấn luyện TC4*, lượng tử hóa raw `UInt8` pixel với bước `q=20` **đúng quy tắc rounding/clip của benchmark đã có**, tạo integer quantization keys, deduplicate và đếm số lần xuất hiện làm trọng số nguyên, rồi chạy **Weighted K-means** trên các vector lượng tử hóa chuẩn hóa. Bảo đảm `sum(weights) = N_retained` và output là centroids **raw 16D, thang [0,1]**. Không biến đổi dữ liệu đầu vào TC5. Khi tích hợp phương pháp tùy chọn này, tái sử dụng implementation benchmark; không thay bằng unweighted K-means. Giữ quy ước weighted K-means++ hiện có và ghi vào metadata.

**Điều phối:** một lượt TC chỉ dùng **một** `training_method` được chọn qua cấu hình; các backend phải xuất cùng hợp đồng codebook raw 16D. Nếu `training_method` không hợp lệ hoặc Q20 được chọn nhưng chưa có backend tương thích, phải **fail rõ ràng**, tuyệt đối không tự fallback/đổi phương pháp. Việc tồn tại block cấu hình Q20 không đồng nghĩa phải fit Q20.

**Lưu ý:** Q20 là một *cách huấn luyện codebook thay thế*, không phải một công đoạn TC độc lập và không phải cách mã hóa transactions. Phương pháp TC6 hiện hành luôn là `S0`.

### 6.3. Metrics ở cấp codebook

Với mỗi codebook, đánh giá trên **cùng raw descriptors 16D của 70k ảnh**:

1. **Raw-space distortion:** `mean(min_j ||x_i-c_j||²)` và tỷ lệ cải thiện khi K tăng; trình bày elbow/giảm distortion theo K.
2. **Cluster occupancy:** số và tỷ lệ centroids nhận ít nhất một descriptor khi assign raw descriptors.
3. **Cluster size distribution:** counts, min/max, quantiles, tỷ trọng top clusters, normalized entropy; không tối đa hóa entropy một cách máy móc.
4. **Seed stability:** trung bình/độ lệch chuẩn distortion, occupancy, phân bố clusters qua 3 seeds; assignment ARI trên một tập raw descriptors đánh giá **cố định, chung giữa các seeds** nếu chi phí cho phép (mẫu này chỉ dùng cho đánh giá stability, **không dùng để fit**). Không so sánh trực tiếp word IDs giữa các seeds.

Có thể ghi nhận tốc độ, iterations và peak memory nếu implementation có hỗ trợ; không xem runtime hay distortion là tiêu chí duy nhất chọn K.

### 6.4. Đầu ra & ranh giới quyết định

- Lưu codebook **K×16** theo schema chung (hoặc **16×K** trong Julia, có ghi layout), K/seed/**training_method thực tế được chọn**, params, metrics, metadata.
- Không lấy codebook đã fit trên 60k trước đó để thay cho lượt fit mới trên 70k.
- **Không chốt K/seed cuối cùng tại TC4**. Những bộ transactions ứng viên sẽ được so sánh trong EDA2/Pilot Eclat.

## 7. TC5 — Hard Visual Word Assignment

**Đầu vào:** toàn bộ raw descriptors 16D từ TC3 và **một** codebook raw 16D cụ thể (K, seed, method). Với mỗi raw vector x, tính:

\[
w(x)=\arg\min_{j=1,\ldots,K}\|x-c_j\|_2^2.
\]

**Cấu hình:** hard assignment, squared Euclidean, `word_id_base=1`, `batch_size=16384`. Tie-breaking phải deterministic (ví dụ centroid ID nhỏ nhất) và nhất quán giữa runs. Dữ liệu descriptors **không PCA/Quantization ở TC5**.

**Đầu ra:** mapping `(image_id, patch_id, coordinates, word_id)` cho mỗi retained patch, đối với từng codebook. Bảo toàn thứ tự patch và thông tin vị trí **trong metadata** dù S0 không đưa chúng vào item ID.

**Acceptance checks:** mỗi retained patch gán đúng một word ID `1..K`; không missing assignment; tổng số assignments bằng retained descriptors; không dùng codebook khác K/seed.

## 8. TC6 — Transaction Encoding (S0 baseline only)

**Method:** `S0_binary_bovw` — với ảnh i, lấy tập word IDs phân biệt từ các patch đã gán:

\[
T_i=\operatorname{sort}\big(\operatorname{unique}(\{w(p):p\in I_i\})\big).
\]

Ví dụ patch assignments `[5,12,5,31,12,8]` → transaction `[5,8,12,31]`.

**Cấu hình:** `spatial=false`, deduplicate=true, sort_items=true, labels=false, one_image_one_transaction=true, preserve_empty=true. Mỗi codebook tạo đúng **70.000 transactions** tương ứng **một bộ dữ liệu độc lập**. Các ảnh không còn retained patches phải có transaction rỗng nhưng vẫn có TID.

**Acceptance checks:** đúng 70k transactions; mỗi item trong `1..K`, tăng dần, không trùng; mapping TID→image_id đầy đủ; nhãn không xuất hiện trong itemsets.

**Ngoài scope hiện tại:** `S1 Spatial BoVW 2×2`, `S2 Spatial Pyramid (1×1 + 2×2)`; **không triển khai** cho đến sau EDA2. Chỉ lưu tọa độ ở TC1/TC5 để tiện mở rộng sau này.

## 9. TC7 — Export & Integrity Validation

**Mục tiêu:** lưu trữ, truy vết và kiểm tra tính hợp lệ của từng bộ transactions từ TC6; không học lại K-means, không mã hóa lại, không lựa chọn K.

**Artifacts tối thiểu cho mỗi (tc4_method, K, seed):**

- `transactions`: 70k dòng (TID → sorted unique word IDs), bao gồm transaction rỗng.
- `codebook`: K centroids raw 16D.
- `patch_assignments`: image_id, patch_id, coordinates, word_id.
- `tid_image_mapping`: TID ↔ image_id ↔ original split/index; nhãn (nếu cần) **chỉ** ở metadata riêng.
- `config_snapshot`: các tham số thực tế, threshold=29, data provenance, method/K/seed.
- `tc4_metrics`: distortion, occupancy, size distribution, convergence, seeds/stability và runtime (nếu có).
- `integrity_report`: tổng hợp pass/fail và các counts kiểm tra.

**Integrity checks bắt buộc:**

1. Tổng số ảnh = **70.000**; mỗi ảnh ↔ đúng một TID; tổng transactions = **70.000**.
2. `0 ≤ |T_i| ≤ min(K,49)`; giữ transaction rỗng; item ID 1..K.
3. Transaction sorted unique, không chứa labels hoặc spatial IDs trong S0.
4. Patch-to-word assignments đúng cardinality; mỗi word nằm trong codebook hiện hành.
5. Centroids đúng K×16, numeric/finite; không lẫn K/seed/method.
6. **Support denominator = 70.000 transactions**, kể cả transactions rỗng. Không sử dụng tổng patches hay số assignments làm mẫu số.
7. Các file output được ghi theo từng `(tc4_method,K,seed)`, không ghi đè artifacts production.

**Run behavior:** `fail_fast=true` khi integrity check thất bại; checkpoint và lưu trạng thái rõ ràng; dữ liệu tạo dở không được đánh dấu completed.

## 10. Đánh giá sau TC — EDA2 và Pilot Eclat (KHÔNG nằm trong implementation TC lần này)

Các artifacts của TC phải đủ để triển khai **đầy đủ 6 nhóm đánh giá đã thống nhất**, nhưng agent **chưa cần code/chạy** EDA2/Eclat trong phạm vi spec TC này:

1. **Transaction length:** mean, median, std, min/max, P5/P95, empty rate, mức sử dụng vocabulary.
2. **Item support distribution:** min/max, mean/median, quantiles, histogram, tỷ lệ item đạt các minsup, tỷ lệ quá hiếm/quá phổ biến.
3. **Transaction diversity:** unique/duplicate transaction ratios; sampled pairwise Jaccard.
4. **Frequent itemset statistics:** counts theo độ dài/minsup, support distribution, closed/maximal itemsets, max length.
5. **Mining performance & interpretability:** runtime, peak memory, representative frequent itemsets, patch/ảnh minh họa, phân tích nhãn sau khai thác (không dùng nhãn để mine).
6. **Codebook stability:** distortion/occupancy/cluster sizes qua seeds, assignment ARI, transaction stability khi so sánh giữa seeds (so sánh bất biến hoán vị nhãn, không so ID trực tiếp).

**Quy tắc quyết định:** EDA2 + Pilot Eclat trên S0 để chọn codebook/K/seed cuối cùng; **sau EDA2** mới thực nghiệm S1/S2 trên codebook được giữ cố định. Không mặc định K=64/128/256 là tốt nhất.

## 11. TOML cấu hình đề xuất (không có TC0)

```toml
[run]
mode = "full"
run_id = "FashionMNIST_T2_S0_70k"
output_root = "results/fashion/tc/baseline_s0"
overwrite_production_artifacts = false
fail_fast = true

[dataset]
name = "Fashion-MNIST"
image_shape = [28, 28]
expected_images = 70000
use_all_images = true
use_train_validation_split = false
preserve_original_split_as_metadata = true
preserve_class_labels_as_metadata = true

[tc1_patch_extraction]
patch_size = [4, 4]
stride = [4, 4]
overlap = false
padding = "none"
patch_order = "row_major"
patch_id_base = 1
preserve_coordinates = true

[tc2_patch_filtering]
experiment_id = "T2"
enabled = true
method = "foreground_ratio"
threshold_source = "eda_q10_positive_fixed"
foreground_threshold = 29
alpha = 0.0
threshold_comparison = "strict_greater"
keep_comparison = "strict_greater"
modify_grayscale_pixels = false

[tc3_feature_extraction]
descriptor = "raw_pixels"
normalization = "divide_by_255"
dtype = "Float32"
dimension = 16
flatten_order = "column_major"
include_labels = false
include_coordinates_in_descriptor = false

[tc4_codebook]
# Luồng chính: B0 trên raw 16D. Thay bằng "q20_weighted_kmeans" nếu chủ động chọn tùy chọn Q20.
training_method = "raw_full_batch_kmeans"
fit_scope = "all_retained_descriptors_70k"
image_sampling = false
descriptor_sampling = false
k_candidates = [16, 32, 64, 128, 256]
random_seeds = [42, 123, 2026]
initialization = "kmeans++"
max_iterations = 300
tolerance = 0.0001
distance = "squared_euclidean"
sequential_runs = true
checkpoint_after_each_run = true
selection_stage = "after_eda2_pilot_eclat"

# Chỉ là định nghĩa tham số cho backend TÙY CHỌN; không tự kích hoạt Q20.
[tc4_methods.q20_weighted_kmeans]
quantization_step = 20
quantization_rule = "reuse_exact_benchmark_rounding_and_clipping"
deduplicate = true
use_integer_frequency_weights = true
reuse_existing_weighted_kmeans_implementation = true

[tc5_word_assignment]
method = "hard_assignment"
input_descriptor_space = "raw_16d"
codebook_space = "raw_16d"
distance = "squared_euclidean"
word_id_base = 1
batch_size = 16384
preserve_coordinates = true

[tc6_transaction_encoding]
method = "binary_bovw"
variant = "S0"
spatial = false
deduplicate = true
sort_items = true
include_labels = false
preserve_empty = true
one_image_one_transaction = true

[tc7_export_validation]
expected_full_transactions = 70000
save_codebook = true
save_patch_assignments = true
save_tid_image_mapping = true
save_config = true
save_tc4_metrics = true
save_integrity_report = true
verify_eclat_support_denominator = true

[execution]
backend = "cpu"
```

## 12. Hướng dẫn coding agent: phạm vi thực hiện

1. Đọc code/notebooks/config và kết quả EDA hiện có. **Tận dụng cấu phần đã triển khai**, không viết lại pipeline nếu không cần.
2. Implement/điều chỉnh **TC1–TC7 theo hợp đồng ở spec này**. Xóa phụ thuộc chạy TC0; threshold được lấy trực tiếp từ config EDA cố định =29.
3. Phải bảo đảm không phát sinh split train/validation ở bất cứ bước fit codebook hoặc transaction encoding nào.
4. Luồng chính TC4 dùng `raw_full_batch_kmeans`. Đọc `tc4_codebook.training_method` làm phương pháp **được chọn**; giữ ranh giới TC4 training branch khác TC5 raw assignment branch. Không chạy hai phương pháp TC4 trong cùng một lượt chỉ vì hai cấu hình có sẵn.
5. K-means chạy cho từng `K × seed` với **một method được chọn** trong cấu hình, lưu checkpoint; các bước TC5–TC7 tạo và lưu riêng bộ transactions tương ứng.
6. Viết/giữ các integrity assertions & tests, với một sample ảnh/patch nhỏ để kiểm chứng mapping, flatten order, foreground rule, unique/sort và output 70k. Không lấy mẫu để thay thế quá trình fit đầy đủ.
7. Không tự thêm features spatial, không chạy EDA2/Pilot Eclat, không đổi K/seeds/threshold/method im lặng, không chọn K cuối cùng.
8. Kết thúc bằng báo cáo file thay đổi, cách thực thi, danh sách artifacts và kết quả checks. **Không yêu cầu triển khai hay chạy Q20 để nghiệm thu luồng chính.** Nếu lựa chọn Q20 được kích hoạt nhưng backend hiện có chưa tương thích, báo blocker; **không thay bằng B0 hoặc unweighted K-means**.

## 13. Completion criteria

- [ ] Không chạy TC0, ngưỡng TC2 lấy cố định từ EDA `29`.
- [ ] Toàn bộ 70k ảnh được xử lý, không chia train/validation.
- [ ] TC1: 49 patches/ảnh trước lọc; total 3.430.000.
- [ ] TC2: lọc đúng `any(pixel>29)`, giữ nguyên grayscale.
- [ ] TC3: raw 16D Float32 column-major, `/255`.
- [ ] TC4: **luồng chính B0** học 5 K × 3 seeds = 15 codebooks trên toàn bộ retained descriptors, không sampling, checkpoint đầy đủ; selector `training_method` không tự kích hoạt Q20.
- [ ] TC5: mỗi retained patch được hard assign vào word ID 1..K trên raw16D.
- [ ] TC6: S0 Binary BoVW, mỗi ảnh có một transaction sorted unique (kể cả rỗng).
- [ ] TC7: mỗi codebook tạo 70k transactions, artifacts riêng và integrity checks đạt; **không yêu cầu kết quả Q20** để nghiệm thu luồng chính.
- [ ] Chưa triển khai EDA2/Pilot Eclat hay TC6-S1/S2.

**End of specification.**
