# Transaction Construction (TC) — Đặc tả cấu hình và kế hoạch thực nghiệm

**Dự án:** Visual Pattern Mining trên Fashion-MNIST bằng Frequent Itemset Mining (Eclat do nhóm triển khai)  
**Phiên bản:** TC design v1.0 — 15/11/2026  
**Trạng thái:** Đặc tả để triển khai và benchmark; **chưa phải kết quả TC đã chạy**.  
**Căn cứ:** `EDA1_Insights_For_Transaction_Construction.md` và các quyết định đã thống nhất sau EDA-1.

---

## 0. Mục tiêu, phạm vi và quyết định đã thống nhất

### 0.1. Mục tiêu

Chuyển mỗi ảnh Fashion-MNIST thành **một transaction gồm các Visual Word IDs phân biệt**, phục vụ thuật toán Eclat tìm các frequent visual itemsets. Bảo toàn ánh xạ ảnh → patch → descriptor → visual word để có thể truy vết và diễn giải các pattern.

Pipeline chính:

```text
Fashion-MNIST: train 60.000 / validation 10.000 (test gốc)
    ↓
TC0. Fit ngưỡng Q10+ trên train (chỉ train)
    ↓
TC1. Dense Patch Extraction: 4×4, stride 4, không overlap
    ↓
TC2. Patch Filtering: Q10+_train, α=0 (T2)
    ↓
TC3. Raw Pixel Descriptor: Float32 / 255, 16 chiều
    ↓
TC4. K-means Codebook: toàn bộ descriptors train; benchmark K và seeds
    ↓
TC5. Visual Word Assignment: nearest centroid, Euclidean²
    ↓
TC6. Binary Bag of Visual Words: unique + sort; không spatial
    ↓
TC7. Export, truy vết, kiểm tra dữ liệu và thí nghiệm
    ↓
EDA-2 / Pilot Eclat → chọn cấu hình TC → 70.000 transactions chính thức
```

### 0.2. Split và nguyên tắc tránh leakage

| Dataset | Ảnh | Vai trò | Có tham gia fit tham số không? |
|---|---:|---|---|
| `train` gốc | 60.000 | Fit ngưỡng Q10+; huấn luyện K-means | **Có** |
| `test` gốc, gọi `validation` | 10.000 | So sánh K/seeds; đánh giá encoding; không fit lại | **Không** |
| `full` = train + validation | 70.000 | Sản phẩm transaction cuối để khai thác mô tả toàn bộ dữ liệu | Không phải tập fit codebook trong cấu hình đã chốt |

- **Không lấy mẫu ảnh hoặc descriptors để fit K-means ở benchmark chính**; huấn luyện trên *toàn bộ descriptors còn lại* của 60.000 ảnh train.
- Các số liệu ngưỡng từ EDA-1 (`Q10+ = 29`, `Otsu = 97`) tính trên 70.000 ảnh chỉ là **tham chiếu**. Trong TC, `Q10+_train` phải được tính lại từ **60.000 ảnh train**.
- Việc EDA-1 trước đó đã khảo sát cả 70.000 ảnh có nghĩa validation 10.000 ảnh **không hoàn toàn độc lập với giai đoạn thiết kế pipeline**. Báo cáo phải gọi kết quả validation là kết quả *chọn cấu hình*; không tuyên bố đây là kiểm định khả năng tổng quát hóa hoàn toàn độc lập.
- Nếu dùng frequent patterns làm feature cho một bài toán classification có test độc lập về sau, phải fit ngưỡng/codebook/khai thác patterns **chỉ trên train của thí nghiệm downstream**.

### 0.3. Trạng thái các quyết định

| Thành phần | Giá trị chính | Nguồn/trạng thái |
|---|---|---|
| Patch size / stride | `4×4 / 4` | Đã chọn, dựa trên EDA-1 |
| Filtering chính | `Q10+_train`, `α=0` | Có bằng chứng EDA; xác nhận ngưỡng train tại TC0 |
| Filtering đối chứng | Không lọc; `τ=10`, `α=0` | Cấu hình đối chứng |
| Extraction strategy | Dense patch (lưới cố định) | Đã chọn làm chính |
| Descriptor | Raw pixel, Float32/255 | Đã chọn baseline |
| K-means | Lloyd full-batch, K-means++ | **Đề xuất triển khai**, chưa benchmark |
| Candidate K | `[16, 32, 64, 128, 256]` | Cần benchmark |
| Seeds | `[42, 123, 2026]` | Cần lặp để đo stability |
| Encoding | Binary Standard BoVW, không spatial | Baseline đã chọn |
| Spatial | Không dùng trong pipeline chính; lưu tọa độ để thử về sau | Chưa chốt lợi ích |
| MinSup | Không thuộc TC | Chọn ở EDA-2/pilot Eclat |

### 0.4. Những gì EDA-1 hỗ trợ (không phải kết quả TC)

Với **patch 4×4, α=0**, trên **70.000 ảnh** EDA-1 ghi nhận:

| Ngưỡng | Patch reduction | EdgeLoss | Ảnh không còn patch |
|---|---:|---:|---:|
| `τ=10` | 36,43% | 3,78% | 0 |
| `Q10+ = 29` | 37,50% | 4,41% | 0 |
| `Otsu = 97` | 43,30% | 8,90% | 0 |

Đây là số liệu toàn tập, **không được dùng làm số liệu TC train/validation** sau khi tính lại Q10+. Tỷ lệ bị loại và số descriptors thực tế phải báo cáo lại trên từng split.

---

## TC0 — Fit các tham số preprocessing từ Train

### TC0.1. Cấu hình

| Tham số | Giá trị |
|---|---|
| `method` | `q10_positive` |
| `fit_split` | `train` (60.000 ảnh) |
| `apply_splits` | `train`, `validation` |
| `pixel_selection` | Các pixel có giá trị **> 0** |
| `quantile` | `0.10` |
| `quantile_definition` | Ghi rõ cách tính empirical quantile (nội suy/làm tròn) trong metadata |
| `threshold_comparison` | Foreground nếu `pixel > tau` (dấu `>` nghiêm ngặt) |
| `reference_eda_threshold` | 29, tham chiếu, **không áp đặt** |
| `tau10_control` | 10, ngưỡng cố định của thí nghiệm đối chứng |

### TC0.2. Thao tác

1. Chỉ đọc các pixel từ 60.000 ảnh `train`.
2. Lọc các pixel **> 0** và tính phân vị 10% để tìm `tau_train`.
3. Lưu `tau_train`, định nghĩa quantile, số pixel dùng fit, checksum nguồn và phân phối số lượng pixel.
4. Cố định `tau_train` cho tất cả lần fit/đánh giá T2, mọi K và seeds; không tính lại trên validation.
5. So với ngưỡng EDA-1 `29`; ghi `same_as_eda = true/false`. Nếu khác, dùng giá trị mới.

### TC0.3. Output và điều kiện nghiệm thu

- `preprocessing/threshold_fit.toml` (có `tau_train`, `train_only=true`, định nghĩa quantile).
- Không đọc ảnh validation để tính ngưỡng.
- Thực thi lặp lại với cùng nguồn cho cùng ngưỡng.

---

## TC1 — Dense Patch Extraction

### TC1.1. Cấu hình

| Tham số | Giá trị |
|---|---|
| `image_shape` | `28×28`, grayscale uint8 (0–255) |
| `patch_height`, `patch_width` | `4`, `4` |
| `stride_y`, `stride_x` | `4`, `4` |
| `overlap` | `false` |
| `padding` | `none` |
| `patch_rows`, `patch_cols` | `7`, `7` |
| `patches_per_image` | `49` |
| `patch_order` | Row-major theo **vị trí patch**: trái→phải, trên→dưới |
| `patch_id_base` | `1` |
| `patch_coordinates_base` | `1` (Julia) |
| `preserve_original_split` | `true` |
| `preserve_original_pixels` | `true` |

**Quy ước ID:** `patch_id = (patch_row - 1) * 7 + patch_col`, với `patch_row,patch_col ∈ 1:7`. Pixel của patch ở hàng `4*(patch_row-1)+1 : 4*patch_row`, cột tương tự.

### TC1.2. Dữ liệu giữ lại

`image_id`, `original_split`, `patch_id`, `patch_row`, `patch_col`, `top_left_y`, `top_left_x`, `raw_pixels` (hoặc chỉ lưu ảnh nguồn + vị trí để trích xuất lại không mất mát). Có thể giữ `class_label` trong bảng metadata **chỉ để phân tích/đánh giá**, không đưa vào descriptor hoặc transactions.

### TC1.3. Quy mô dự kiến chính xác trước lọc

| Split | Số ảnh | Tổng patch |
|---|---:|---:|
| Train | 60.000 | 2.940.000 |
| Validation | 10.000 | 490.000 |
| Full | 70.000 | 3.430.000 |

### TC1.4. Kiểm tra nghiệm thu

- Mọi ảnh có đúng 49 patch (trước lọc), mỗi patch đúng 16 pixel.
- Các patch phủ kín ảnh 28×28 đúng một lần, không trùng hay thiếu vùng.
- Ghép 49 patch đúng vị trí khôi phục chính xác ảnh đầu vào.
- ID ảnh/patch duy nhất và nhất quán giữa các lần chạy.

**Output:** Bảng index patch và khả năng đọc patch grayscale gốc; chưa lọc, chưa nhị phân hóa giá trị pixels.

---

## TC2 — Patch Filtering

### TC2.1. Cấu hình các thí nghiệm chính

| Thí nghiệm | Patch size | Filter | Ngưỡng `tau` | `alpha` | Mục đích |
|---|---|---|---:|---:|---|
| **T1** | 4×4 | `none` | — | — | Baseline không lọc |
| **T2** | 4×4 | `foreground_ratio` | `tau_train` từ TC0 | `0` | **Ứng viên chính** |
| **T3** | 4×4 | `foreground_ratio` | `10` (cố định) | `0` | Lọc nhẹ hơn |

Tùy chọn sau khi có EDA-2: `alpha = 0.0625` (loại patch có ≤1 pixel foreground) và đối chứng `7×7`; **không thuộc vòng triển khai TC chính đầu tiên**.

### TC2.2. Công thức

Với patch `P` 4×4 chứa 16 pixel:

```text
F(P, tau)  = số pixel trong patch có intensity > tau
FR(P,tau) = F(P,tau)/16
Keep(P)   = FR(P,tau) > alpha
```

Với `alpha=0`: `Keep(P) ⇔ max(P) > tau`. Patch được giữ **nguyên giá trị grayscale**; mask chỉ quyết định giữ/loại, không chỉnh/sửa intensity.

### TC2.3. Kiểm tra chất lượng và lưu vết

- `retained_count`, `discarded_count` theo ảnh và split; reduction %, empty-image count.
- Báo cáo cả trước/sau lọc, khác biệt giữa T1/T2/T3.
- Nếu một ảnh không còn patch: vẫn giữ `image_id`, gán transaction rỗng về sau; **không được loại ảnh khỏi mẫu số support**.
- Đối chiếu thống kê train/validation; có thể báo cáo phân bố theo lớp (labels chỉ dùng để kiểm tra).

**Output:** `patch_filter_status` có `image_id, patch_id, keep, tau, alpha, experiment_id`; index của tất cả patch đã giữ; thống kê theo split.

---

## TC3 — Feature Extraction / Descriptor Construction

### TC3.1. Cấu hình chính

| Tham số | Giá trị |
|---|---|
| `extraction_strategy` | `dense_patches` |
| `descriptor_type` | `raw_pixels` |
| `descriptor_dim` | `16` |
| `dtype` | `Float32` |
| `normalization` | `Float32(pixel)/255f0` |
| `extra_standardization` | `none` |
| `flatten_order` | `column_major` **cho pixel trong một patch** (quy ước Julia `vec`) |
| `include_class_label` | `false` |
| `include_coordinates_in_descriptor` | `false` |
| `descriptor_source` | Chỉ các patch `keep=true`, từ pixel grayscale gốc |

**Phân biệt hai thứ tự:** Các patch trong một ảnh được duyệt row-major theo tọa độ; **16 pixel bên trong patch** được trải column-major. Cần thống nhất ở cả lúc fit và lúc assignment.

```julia
# Giả sử patch là ma trận 4×4 kiểu UInt8
raw_descriptor = Float32.(vec(patch)) ./ 255f0  # length = 16
```

### TC3.2. Ma trận và cache

- Backend CPU/CUDA dùng cùng quy ước `X_train ∈ Float32^(16 × N_train_descriptors)`: mỗi cột là một descriptor.
- Không cần giữ 3,43 triệu ma trận patch Julia dạng từng object trong RAM; trích xuất/ghi vào ma trận dense hoặc cache nhị phân theo index.
- Cache train/validation riêng, gắn với checksum ảnh nguồn, ngưỡng thực tế, layout, preprocessing code version.
- Tránh lặp lại phần trích xuất descriptors cho mỗi K; **cache một lần rồi tái sử dụng**.

### TC3.3. Kiểm tra nghiệm thu

- Mỗi descriptor đúng 16 chiều; mọi giá trị hữu hạn, thuộc `[0,1]`.
- Raw descriptor chỉ khác raw pixels bởi đổi kiểu và chia 255; không dùng mask giá trị nhị phân.
- `descriptor_count == retained_patch_count` tại mỗi split.
- `image_id`, `patch_id` truy ngược được từ từng descriptor.

**Output:** `train_descriptors`, `validation_descriptors`, `descriptor_index`, thống kê số lượng và checksum.

---

## TC4 — Codebook Construction và K Benchmark (trọng tâm thực nghiệm)

### TC4.1. Mục tiêu

Huấn luyện **một codebook chung cho tất cả ảnh trong từng run**, so sánh nhiều K và random seeds để chọn số Visual Words phù hợp cho **transactions và Eclat**, không chỉ chọn inertia nhỏ nhất.

### TC4.2. Cấu hình fit

| Tham số | Giá trị đề xuất |
|---|---|
| `algorithm` | K-means (Lloyd, full-batch) |
| `training_split` | Train gốc — 60.000 ảnh |
| `fit_data` | **Tất cả** descriptors `keep=true` của T2 Train |
| `image_sampling` | `false` |
| `descriptor_sampling` | `false` |
| `validation_split` | 10.000 ảnh test gốc, **không fit centroids** |
| `k_candidates` | `[16, 32, 64, 128, 256]` |
| `random_seeds` | `[42, 123, 2026]` |
| `initialization` | K-means++ |
| `max_iterations` | `300` (trần, dừng nếu hội tụ trước) |
| `tolerance` | `1e-4`, ngưỡng tuyệt đối của độ đổi objective giữa hai vòng Lloyd; hội tụ khi `abs(Δobjective) < tolerance` và objective không tăng quá tolerance |
| `distance` | Squared Euclidean |
| `dtype` | Float32 cho descriptor; tích lũy centroid/score có thể dùng Float64 nếu implementation hỗ trợ |
| `runs` | 5 K × 3 seeds = **15 runs** cho T2 ở vòng benchmark |
| `run_order` | Tuần tự từng run; không chạy 15 runs song song |
| `checkpoint` | Lưu kết quả sau từng run; không bắt buộc resume giữa iteration |

**Quy ước hiện thực:** Backend CPU dùng Clustering.jl; backend CUDA dùng extension CUDA.jl. Cả hai dùng K-means++ và full-batch Lloyd. CUDA xử lý descriptor theo batch để giới hạn VRAM nhưng chỉ cập nhật tâm sau khi quét hết train. Lịch sử CUDA lưu objective, delta có dấu, centroid shift và cảnh báo objective tăng; max iteration không được ghi là hội tụ.

### TC4.3. Full-batch và chunking

- **Full-batch Lloyd**: ở mỗi iteration, toàn bộ `N_train` descriptors phải được dùng để cập nhật centroids.
- **Chunked full-batch** (nếu cần tối ưu bộ nhớ): đọc nhiều batch (GPU mặc định `65_536` descriptors/batch), gán cụm, cộng dồn tổng/tần suất, rồi **chỉ cập nhật centroids sau khi duyệt hết toàn bộ dữ liệu**. Đây vẫn là Full-batch, ngoại trừ sai số số thực/chi tiết implementation.
- **Mini-batch K-means**: cập nhật centroids thường xuyên từ batch nhỏ, là thuật toán gần đúng khác; **không dùng làm baseline nếu chưa quyết định đổi phương pháp**.
- Với CPU, dùng Clustering.jl và đo RAM/thời gian. Với CUDA, tái sử dụng buffer khoảng cách giữa các batch/vòng lặp; `batch_size` không làm thành mini-batch K-means. `chunk_size` trong TC5 không tự động điều khiển việc fit TC4.

### TC4.3.1. Đo thời gian CUDA

- Làm nóng GPU bằng một fit nhỏ trước khi bắt đầu benchmark để loại thời gian biên dịch kernel khỏi phép đo chính.
- Đồng bộ bằng `CUDA.synchronize()` trước và sau đoạn cần đo; nếu không, phép đo có thể chỉ ghi thời gian gửi công việc bất đồng bộ.
- Báo riêng thời gian upload descriptor, khởi tạo K-means++, fit, assignment, tạo TAR và chép checkpoint/TAR lên Drive. Không gộp tốc độ Drive vào tốc độ K-means.
- So CPU/GPU trên cùng tập con, cùng K, cùng seed points khởi tạo và cùng số vòng lặp; chỉ so objective/assignment trong sai số số học phù hợp.
- Không kết luận tăng tốc T4 trước khi có số đo trên T4.

### TC4.4. Lịch benchmark

1. Trên T4, chạy `configs/tc_smoke_cuda.toml` bằng cùng notebook TC0–TC7 để kiểm tra driver, VRAM và pipeline.
2. Khi smoke đạt, chọn `configs/tc_full_cuda.toml` để chạy 15 runs (K × seed), từng run một; ghi errors/OOM nếu có.
3. Với mỗi run, tính validation metrics bằng **toàn bộ validation descriptors** (không fit lại).
4. Tạo validation transactions của run để có transaction-level metrics; chạy pilot Eclat có kiểm soát cho các K triển vọng.
5. Lập bảng tổng hợp mean ± std theo K, chọn 2–3 K triển vọng, so sánh visual centroids/pattern interpretability rồi chọn K cho pipeline chính.
6. Nếu K hoặc codebook thay đổi, file artifacts và transactions phải có `run_id`; không trộn IDs giữa hai codebook.

### TC4.5. Codebook Quality metrics

| Metric | Định nghĩa / cách dùng | Ghi chú |
|---|---|---|
| `train_distortion` | Trung bình khoảng cách Euclidean² tới centroid gần nhất trên train | Training objective, thiên về dữ liệu fit |
| `validation_distortion` | Trung bình Euclidean² trên validation descriptors | **Metric quan trọng** để chọn K |
| `occupancy_count[k]` | Số descriptors assigned vào cluster k | Phát hiện clusters ít dùng/chiếm ưu thế |
| `vocabulary_utilization` | Số word ID có xuất hiện / K | Đo cả train và validation |
| `runtime`, `iterations`, `peak_ram` | Chỉ số thực thi | Đo thực nghiệm, không suy diễn từ lý thuyết |
| `centroid_gallery` | Trực quan hóa K centroid như patch 4×4 | Kiểm tra dễ diễn giải; centroid không nhất thiết là cấu trúc có tên |

**Không chọn K chỉ bằng min inertia**: K tăng thường giảm training distortion. Phải đánh đổi với mức độ sử dụng vocabulary, support, độ dài transaction, chất lượng pattern và chi phí Eclat.

### TC4.6. Codebook Stability — đo tại đâu và như thế nào?

**Vị trí:** Sau khi đã fit các codebook cho mỗi K/seed, trong **TC4 Benchmark**; cần sử dụng dữ liệu gán cụm từ **TC5/TC6 trên cùng validation** để có thêm stability ở mức transaction.

- Với **một K cố định**, so sánh các seeds `42, 123, 2026` trên **cùng training descriptors** và **cùng validation descriptors**.
- `validation_distortion`: báo cáo **mean ± std** theo seed.
- `ARI` (Adjusted Rand Index): so sánh hai vector cluster assignments trên **cùng descriptors validation** (không bị ảnh hưởng bởi việc đổi tên cluster); báo cáo 3 cặp seed và mean ± std. Tính trên toàn bộ validation nếu tài nguyên cho phép; không lấy mẫu descriptors cho việc fit.
- `occupancy_distribution`: so sánh mức tập trung của cluster frequencies, không so sánh trực tiếp `V1` với `V1` giữa runs.
- `transaction_length_distribution`, `singleton_support_distribution`: so sánh thống kê qua seeds; có thể dùng histogram distance hoặc độ biến thiên các summary statistics.
- **Không tính Jaccard giữa các transactions của hai runs theo raw word ID** nếu chưa ánh xạ cluster IDs, vì hoán vị nhãn cụm khiến phép so sánh vô nghĩa.
- Việc stability cao không chứng minh các itemsets có ý nghĩa; xem thêm pattern gallery/pilot Eclat.

### TC4.7. Chọn K — Quy tắc ra quyết định

- Loại run lỗi, không hội tụ đáng kể, hoặc vocabulary cực kỳ mất cân bằng khi có phương án khác tốt hơn.
- Ưu tiên vùng K mà tăng K chỉ cải thiện ít validation distortion nhưng làm tăng đáng kể độ phức tạp/support fragmentation.
- Kiểm tra kết quả có ổn định qua seeds hay không (distortion, ARI, transaction statistics).
- Kiểm tra các K triển vọng qua pilot Eclat: support, số itemsets, runtime, khả năng diễn giải bằng centroids và ảnh gốc.
- Không dùng một **ngưỡng điểm tổng hợp tự đặt** như tiêu chí tuyệt đối nếu chưa giải thích được trọng số; ghi rõ trade-off và quyết định cuối.

**Output:** `codebook`/centroids cho từng `run_id`, `benchmark_codebook.csv`, `stability.csv`, `centroid_gallery`, `selected_k_decision.md` và một codebook đã chọn.

---

## TC5 — Visual Word Assignment

### TC5.1. Cấu hình

| Tham số | Giá trị |
|---|---|
| `method` | Hard assignment (1 centroid/descriptor) |
| `metric` | Squared Euclidean |
| `word_id_base` | `1` trong Julia |
| `batch_size` | `16_384` descriptors/chunk (đề xuất ban đầu) |
| `codebook_scope` | Codebook của **đúng run K/seed** được chọn |
| `same_codebook_train_validation` | `true` |
| `preserve_coordinates` | `true` trong mapping, không nhét vào raw descriptor |
| `process_all_retained_patches` | `true` |

Với descriptor `d` và centroids `c_k`:

`word_id(d) = argmin_k ||d-c_k||²`.

### TC5.2. Processing

- Áp dụng cùng codebook học từ train lên cả train và validation.
- Process thành chunks để kiểm soát RAM; **không** update codebook trong quá trình assignment.
- Ghi mọi assignment về `image_id`, `patch_id`, `word_id`, `patch_row`, `patch_col`, `split`, `run_id`.
- Với patches bị loại, có `keep=false`, `word_id=missing` hoặc không xuất hiện trong bảng assignment kèm một bảng `filter_status` đầy đủ; không được gán nhãn item 0 giả tạo.

### TC5.3. Kiểm tra

- Mỗi retained descriptor có đúng một word, thuộc `[1,K]`.
- Tổng số assignments = tổng số retained descriptors.
- Chunked assignment và assignment một lượt cho cùng kết quả (cho phép xử lý khoảng cách hòa nhau có tie-break xác định).

**Output:** `patch_assignments`, `word_frequency_by_split`, assignment timing.

---

## TC6 — Transaction Encoding

### TC6.1. Cấu hình chính

| Tham số | Giá trị |
|---|---|
| `encoding` | `binary_bovw` |
| `unit_of_transaction` | Một ảnh = một transaction |
| `deduplicate` | `true` |
| `sort` | `ascending` |
| `spatial_encoding` | `false` |
| `include_class_label` | `false` |
| `include_split_as_item` | `false` |
| `include_coordinates_as_item` | `false` |
| `preserve_empty` | `true` |
| `item_universe` | `1..K` |
| `tid_order` | Cố định theo `original_split`, rồi `image_id` hoặc thứ tự dataset có tài liệu hóa |

Ví dụ assignments `[5, 12, 5, 31, 12]` → transaction `[5, 12, 31]`.

### TC6.2. Spatial — chỉ lưu khả năng mở rộng

- **Không bật Spatial BoVW trong baseline.** Tuy nhiên luôn giữ `patch_row, patch_col` trong TC5.
- Nếu EDA-2 / pattern interpretation phát hiện lợi ích rõ, có thể encode lại từ **cùng patch assignments**, ví dụ `V12_top`/`V12_middle`/`V12_bottom`, không cần fit lại codebook.
- Muốn so sánh spatial công bằng phải giữ nguyên patch filter, descriptor và codebook.

### TC6.3. Chỉ số kiểm tra

- `transaction_count` train=60.000, validation=10.000, full=70.000.
- `empty_count`, phân phối `transaction_length`, `mean/median/p95`, `unique_item_count`.
- Mỗi item thuộc `1..K`, không trùng trong cùng transaction, sắp xếp tăng dần.
- Với binary BoVW, `len(transaction) <= min(retained_patch_count, K)`; cho patch 4×4 là tối đa `min(49,K)`.

**Output:** `train_transactions`, `validation_transactions`, `full_transactions` và `tid_image_mapping`. Kết quả của các K/seeds **không được trộn vào một cơ sở giao dịch**.

---

## TC7 — Export, Validation và Reproducibility

### TC7.1. Format / quy ước

| Hạng mục | Cấu hình |
|---|---|
| `canonical_transactions` | Định dạng nhị phân/columnar giữ **đúng 70.000 giao dịch logic**, gồm cả giao dịch rỗng |
| `eclat_text_export` | Mỗi dòng: các item ID cách nhau bằng dấu cách, không duplicate |
| `empty_transaction_policy` | Phải được hỗ trợ rõ ràng trong loader Eclat |
| `support_denominator` | Số ảnh thực tế của split được mining: `N=60000/10000/70000` |
| `codebook` | Centroids, dtype, descriptor spec, K, seed, library version |
| `config` | File TOML, ngưỡng thực TC0, experiment/run ID, checksum |
| `patch_mapping` | Ghi tọa độ và visual word để truy vết patterns |
| `validation_report` | JSON/CSV có checks pass/fail, số lượng, phân phối |

**Cảnh báo về TXT và empty transactions:** Một số bộ đọc transaction bỏ qua dòng trắng. Khi đó phải sửa loader hoặc bảo toàn tổng số transaction qua metadata/mapping và bảo đảm **support denominator đúng**. Không coi việc có 70.000 dòng văn bản là đủ nếu parser tự bỏ dòng rỗng.

### TC7.2. Kiểm thử nghiệm thu bắt buộc

1. Có 60k train, 10k validation, 70k full transactions logic; TID truy về đúng image_id và split.
2. Mọi item ID hợp lệ thỏa `1 <= item_id <= K`; không dùng `0` làm pseudo-item.
3. Mọi transaction unique/sorted, không có nhãn lớp hay vị trí như item khi `spatial=false`.
4. Toàn bộ retained patches được gán word; mọi assignments truy ngược được ảnh gốc; mọi discarded patches không tham gia itemset.
5. Tính support của vài singleton/pair bằng cách đếm trực tiếp transactions rồi so với loader Eclat.
6. Đọc lại codebook/config/artifacts trả về cùng assignments/transactions trong phép kiểm tra tái lập.
7. Validation không bị dùng để fit ngưỡng hoặc centroids trong benchmark.
8. Toàn bộ validation/benchmark metrics lưu theo `experiment_id`, `K`, `seed`, `split`, không ghi đè run khác.

### TC7.3. Cấu trúc thư mục kết quả đề xuất

```text
results/fashion/tc/
├── preprocessing/
│   └── threshold_fit.toml
├── cache/
│   ├── train_descriptors.bin
│   ├── validation_descriptors.bin
│   └── descriptor_index.*
├── benchmark/
│   ├── codebook_metrics.csv
│   ├── stability_metrics.csv
│   ├── transaction_metrics.csv
│   ├── runtime_memory.csv
│   └── selected_k_decision.md
├── runs/
│   ├── T2_k16_seed42/
│   │   ├── codebook.jld2
│   │   ├── config.toml
│   │   ├── validation_transactions.jld2
│   │   └── metrics.json
│   └── ...
└── final/
    ├── final_tc_config.toml
    ├── codebook.jld2
    ├── train_transactions.jld2
    ├── validation_transactions.jld2
    ├── full_transactions.jld2
    ├── full_transactions.txt
    ├── tid_image_mapping.csv
    ├── patch_assignments.*
    └── validation_report.json
```

Dấu `*` chỉ biểu thị chọn định dạng thực tế (CSV/Arrow/Parquet/JLD2) khi triển khai, không phải file bắt buộc phải có tên có dấu sao.

---

## 8. Bộ thí nghiệm và thứ tự triển khai

### 8.1. Vòng chính — Chọn K trên T2

- Giữ `patch=4×4`, `filter=Q10+_train`, `alpha=0`, `descriptor=raw/255`, `spatial=false`.
- Chạy K ∈ `{16,32,64,128,256}` × seed `{42,123,2026}` trên **toàn bộ retained train descriptors**.
- Đánh giá bằng **toàn bộ validation descriptors** và validation transactions tạo từ cùng codebook.
- Đánh giá stability trong TC4; dùng TC5/TC6 để bổ sung thống kê transaction.
- Chọn 2–3 K triển vọng → pilot Eclat có cùng tập ảnh và `minsup` thích hợp → chốt K có căn cứ.

### 8.2. Vòng đối chứng Filtering — T1 / T2 / T3

- So sánh ở **cùng K** và **cùng codebook cố định** để cô lập tác động lọc patch; có thể đóng băng codebook T2 rồi gán cả patch không lọc, nhưng cần ghi nhận các patch ngoài phân phối fit có thể bị gán không tối ưu.
- Nếu mục đích là so sánh hiệu quả pipeline hoàn chỉnh, **huấn luyện codebook riêng cho từng chế độ filtering** (chi phí lớn hơn). Không dùng kết quả phương án này để khẳng định riêng filtering tạo khác biệt.
- T2 là ứng viên chính; không bắt buộc xây dựng tất cả thí nghiệm mở rộng nếu vòng đầu đã đủ bằng chứng.

### 8.3. Mở rộng tùy kết quả

- Patch 7×7 làm đối chứng kích thước (descriptor raw 49 chiều, codebook riêng).
- Gradient / histogram hướng: descriptor có quy tắc trích xuất và chiều khác, **phải fit codebook riêng**.
- Spatial top/middle/bottom: có thể giữ codebook T2 và **chỉ re-encode** từ assignments đã lưu.

### 8.4. Điều kiện chốt final TC

- Đã chọn K bằng *nhiều tiêu chí* (distortion + stability + transaction quality + pilot mining).
- Có validation/transaction metrics theo run và báo cáo lý do loại các K khác.
- Có final codebook học **trên train** với cấu hình đã chọn, không fit lại trên validation.
- Có đủ 70.000 transactions và metadata; Eclat đọc được mà không sai số transaction/support.
- Có ví dụ Visual Words và ảnh chứa frequent patterns để giải thích ý nghĩa ứng dụng 2.

---

## 9. Ước lượng tài nguyên trước khi chạy

**Các số sau là ước lượng từ tỷ lệ reduction EDA-1 trên toàn tập 70.000 ảnh; không phải số đếm TC đã chạy.**

### 9.1. Dữ liệu

- Train: `60.000 × 49 = 2.940.000` patch chưa lọc.
- Validation: `10.000 × 49 = 490.000` patch chưa lọc.
- Nếu giảm 37,50%: train còn khoảng **1.837.500 descriptors**; validation khoảng **306.250**; toàn tập khoảng **2.143.750**.
- Raw descriptor `16 × Float32 (4 byte)`:
  - Train khoảng `1.837.500 × 16 × 4 = 117,6 MB` (≈112,15 MiB).
  - Validation khoảng `306.250 × 16 × 4 = 19,6 MB` (≈18,69 MiB).
- Dữ liệu ảnh gốc uint8: `70.000 × 784 ≈ 54,88 MB` không tính container/header.

### 9.2. Chi phí assignment / khoảng cách

Nếu implementation lưu ma trận khoảng cách `K × N_train` bằng Float32 trên train T2 (ước lượng N≈1.837.500):

| K | Memory ma trận khoảng cách | N × K × 16 (phép tính theo chiều) cho 1 lượt gán |
|---:|---:|---:|
| 16 | 117,6 MB | 0,4704 tỷ |
| 32 | 235,2 MB | 0,9408 tỷ |
| 64 | 470,4 MB | 1,8816 tỷ |
| 128 | 940,8 MB | 3,7632 tỷ |
| 256 | 1.881,6 MB (~1,75 GiB) | 7,5264 tỷ |

- Kích thước ma trận là **ví dụ theo implementation cụ thể**, không phải mọi thư viện K-means đều cấp phát ma trận này.
- Với batch CUDA `65_536`, buffer khoảng cách Float32 cho K=256 tối đa khoảng **64 MiB**; vẫn phải duyệt đủ dữ liệu mỗi vòng.
- Chi phí một vòng Lloyd xấp xỉ `O(N × K × D)`; nếu 30 vòng thực tế thì nhân 30. Không thể xác định thời gian chạy cụ thể nếu không benchmark trên thiết bị thực tế.

### 9.3. Mức tài nguyên khuyến nghị

| Tài nguyên | Khuyến nghị |
|---|---|
| RAM | **16 GB** để bắt đầu; **32 GB** dễ xử lý các cấp phát trung gian với K lớn hơn |
| CPU | 4–8 cores hoặc hơn; đo scaling threads thay vì giả định tuyến tính |
| GPU | T4 Colab cho lưới full; CPU giữ làm backend đối chiếu và fallback |
| Disk | Dự phòng khoảng 2–5 GB cho cache, codebooks, assignments, logs, các runs; tăng nếu lưu nhiều bản chi tiết |
| Scheduling | Chạy tuần tự từng K/seed; cache train/validation descriptors, lưu metrics sau mỗi run |

**Chốt tài nguyên thực nghiệm:** Trên T4 chạy smoke CUDA trước để xác nhận GPU và luồng TC. Khi cần benchmark full, đổi sang config full trong cùng notebook; không cần config pilot riêng.

---

## 10. Cấu hình TOML mẫu — T2 / Benchmark chính

> TOML dưới đây là **đặc tả tham số cho hệ thống TC**, không phải bảo đảm có thể truyền nguyên xi vào một API Julia. Khi triển khai, phải ánh xạ và kiểm thử tên tham số theo thư viện thực tế.

```toml
[dataset]
name = "Fashion-MNIST"
image_shape = [28, 28]
train_images = 60000
validation_images = 10000
validation_source = "original_test"
use_original_split = true
preserve_class_labels_as_metadata = true

[tc0_preprocessing]
threshold_method = "q10_positive"
fit_split = "train"
quantile = 0.10
positive_pixel_only = true
threshold_comparison = "strict_greater"
eda_q10_reference = 29
save_fitted_threshold = true

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
threshold_source = "tc0_q10_train"
alpha = 0.0
keep_comparison = "strict_greater"
modify_grayscale_pixels = false
benchmark_variants = ["T1_no_filter", "T2_q10_train", "T3_tau10"]

[tc3_feature_extraction]
strategy = "dense_patches"
descriptor = "raw_pixels"
normalization = "divide_by_255"
dtype = "Float32"
dimension = 16
flatten_order = "column_major"
include_labels = false
include_coordinates_in_descriptor = false

[tc4_codebook]
algorithm = "lloyd_full_batch_kmeans"
training_split = "train"
validation_split = "validation"
image_sampling = false
descriptor_sampling = false
fit_data = "all_retained_train_descriptors"
k_candidates = [16, 32, 64, 128, 256]
random_seeds = [42, 123, 2026]
initialization = "kmeans++"
max_iterations = 300
tolerance = 0.0001
distance = "squared_euclidean"
sequential_runs = true
checkpoint_after_each_run = true

[tc4_stability]
enabled = true
evaluation_split = "validation"
metrics = ["validation_distortion", "adjusted_rand_index", "cluster_occupancy", "transaction_length", "singleton_support"]
compare_same_k_across_seeds = true

[tc4_resources]
fit_mode = "full_batch"
chunked_lloyd_fallback = false
fallback_chunk_size = 16384
cache_descriptors = true
save_runtime_memory_metrics = true

[tc5_word_assignment]
method = "hard_assignment"
distance = "squared_euclidean"
word_id_base = 1
batch_size = 16384
same_codebook_train_validation = true

[tc6_transaction_encoding]
method = "binary_bovw"
spatial = false
deduplicate = true
sort_items = true
include_labels = false
preserve_empty = true
one_image_one_transaction = true

[tc7_export_validation]
expected_train_transactions = 60000
expected_validation_transactions = 10000
expected_full_transactions = 70000
save_codebook = true
save_patch_assignments = true
save_tid_image_mapping = true
save_config = true
save_benchmark_results = true
save_validation_report = true
verify_eclat_support_denominator = true
```

---

## 11. Bàn giao cuối cùng

Đầu ra TC sau vòng chọn cấu hình gồm ba nhóm:

1. **Final Configuration:** `final_tc_config.toml`, giá trị Q10+ fit train, K đã chọn, seed/run được chọn, tất cả tham số TC1–TC7, giải thích trade-off.
2. **Final Artifacts:** codebook/centroids, `train_transactions`, `validation_transactions`, `full_transactions` (70k), ánh xạ TID–image và patch→word, metadata/changelog/checksums.
3. **Evaluation Report:** benchmark K, stability, train/validation distortion, transaction statistics, runtime/memory, pilot Eclat, quyết định chọn pipeline.

### Phân định TC và các giai đoạn sau

- **EDA-1:** Cung cấp bằng chứng và cấu hình ứng viên.
- **TC:** Fit ngưỡng train-only; trích patch; filtering; descriptors; huấn luyện/đánh giá codebook; tạo transactions và artifacts.
- **EDA-2:** Phân tích chất lượng transactions, lựa chọn dải `minsup`, phản hồi để chốt TC khi cần.
- **Eclat:** Khai thác frequent itemsets trên transactions cuối và giải thích mẫu trực quan.
- **`minsup` không phải tham số của TC.** Có thể dùng các mức pilot nhất quán để đánh giá các TC candidates nhưng không trộn vào codebook configuration.

### Checklist trước khi chạy TC chính thức

- [ ] TC0 đã fit và lưu `Q10+_train`; không dùng validation để fit.
- [ ] TC1 có đúng 49 patch/ảnh, ánh xạ ID và tọa độ chính xác.
- [ ] TC2 có T1/T2/T3 và số lượng giữ/loại từng split.
- [ ] TC3 tạo Float32/255, 16 chiều, không mất ID.
- [ ] Chạy smoke CUDA trên T4 trong notebook TC0–TC7; xác nhận counts, word IDs, transactions và checkpoint.
- [ ] TC4 benchmark K×seeds, đánh giá stability đúng cách và lưu đầy đủ logs.
- [ ] TC5 gán đúng một word/retained descriptor; batch không đổi output.
- [ ] TC6 tạo 1 transaction/ảnh, item unique và sort, không dùng label/spatial.
- [ ] TC7 kiểm tra 70.000 transactions logic và mẫu số support Eclat.
- [ ] Đã có báo cáo lý do chọn K và cấu hình TC cuối cùng.

---

**Kết luận:** Đặc tả hiện tại chốt **TC0 train-only Q10+ → dense patch 4×4 → foreground filter α=0 → raw descriptor 16D → Full-batch K-means benchmark toàn bộ train descriptors → nearest-centroid → binary BoVW → 70.000 transactions**. Những phần **phải quyết định sau benchmark** gồm K cuối cùng, seed/run cuối cùng, độ ổn định codebook, có giữ Q10+ hay phương án lọc đối chứng và có cần mở rộng spatial/descriptor hay không.
