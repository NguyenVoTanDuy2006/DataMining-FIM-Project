# Kế hoạch benchmark nén vector cho TC4 — Fashion-MNIST (60.000 ảnh train)

**Trạng thái:** Đặc tả thí nghiệm, **chưa thực thi**. Mục tiêu của vòng này là đánh giá chất lượng và chi phí **ngay ở mức vector, trước khi huấn luyện K-means**. Không chạy K-means, TC5, TC6 hoặc Eclat trong vòng này.

## 1. Mục tiêu và ranh giới

**Mục tiêu:** Giảm chi phí tiềm năng của TC4 bằng (A) PCA giảm số chiều, (B) lượng tử hóa rồi gộp các vector trùng kèm tần suất để sử dụng Weighted K-means, hoặc (C) PCA + lượng tử hóa + gộp trùng + Weighted K-means. Chọn 2–3 cấu hình triển vọng dựa trên sự đánh đổi **chi phí tính toán ước tính – sai lệch vector – mức bảo toàn cấu trúc khoảng cách**; chỉ sau đó mới tiến hành fit K-means thật.

**Dữ liệu nguồn:** Toàn bộ **60.000 ảnh train gốc** của Fashion-MNIST, không image sampling hoặc descriptor sampling để xây dựng các cấu hình. Patch 4×4, stride 4, tối đa 49 patch/ảnh. TC0 tính ngưỡng Q10+ *chỉ từ train*, TC2 giữ patch nếu `max(pixel) > tau_train`. TC3 xây descriptor Raw Pixel 16D: `Float32.(vec(patch)) ./ 255f0`. Thứ tự flatten thống nhất với code Julia. Số descriptors thực tế đã ghi nhận: **N = 1.836.369** (kiểm tra lại trên dữ liệu cache đang dùng; nếu TC0 tính lại tau làm N thay đổi, dùng N mới). Duplicate rate raw đã đo: **0,00537038035 (~0,537%)**.

**Phạm vi thay đổi:** Chỉ nhánh **đầu vào huấn luyện codebook TC4**. **Không thay đổi** các Raw Pixel descriptors/patch ở TC5–TC7. Sau khi fit PCA-K-means, inverse-transform centroids về 16D; đối với Weighted K-means sau lượng tử hóa pixel, centroids sẵn có 16D. Tất cả cần được đánh giá bằng cùng không gian Raw 16D ở giai đoạn TC4 tiếp theo.

**Giữ nguyên split:** 10.000 ảnh test gốc vẫn là validation **cho bước fit codebook sau này**, không đưa vào phép fit PCA, xác định mức lượng tử hóa theo dữ liệu hay tính thống kê của vòng này. Thử nghiệm ở đây chỉ báo cáo trên 60.000 train (không gọi các chỉ số này là test/generalization).

## 2. Các cấu hình thí nghiệm

Tất cả dùng **chính xác cùng N retained descriptors sau TC2**. PCA chỉ fit **một lần** để lấy hệ trục đủ 16 thành phần (hoặc fit một lần lấy tối đa 12 thành phần) rồi cắt còn 12/8/4; `center=true`, `standardize=false`, `whiten=false`. Tính thống kê PCA qua 60.000 train, dùng Float64 cho tích lũy nếu cần; vector trung gian có thể lưu Float32.

| ID | Phương pháp | Tham số | Vector đưa vào K-means tương lai | Số chiều | Weighted? |
|---|---|---|---|---:|---|
| B0 | Raw baseline | không biến đổi | `N` | 16 | Không |
| P12 | PCA | 12 thành phần | `N` | 12 | Không |
| P08 | PCA | 8 thành phần | `N` | 8 | Không |
| P04 | PCA | 4 thành phần | `N` | 4 | Không |
| Q05 | Pixel Quantization | `q=5` | `U_Q05` vector duy nhất | 16 | Có, weight=count |
| Q10 | Pixel Quantization | `q=10` | `U_Q10` | 16 | Có |
| Q20 | Pixel Quantization | `q=20` | `U_Q20` | 16 | Có |
| Q32 | Pixel Quantization | `q=32` | `U_Q32` | 16 | Có |
| PQ12_A10 | PCA → Quantization | 12D, `alpha=0.10` | `U_PQ12_A10` | 12 | Có |
| PQ12_A25 | PCA → Quantization | 12D, `alpha=0.25` | `U_PQ12_A25` | 12 | Có |
| PQ12_A50 | PCA → Quantization | 12D, `alpha=0.50` | `U_PQ12_A50` | 12 | Có |
| PQ08_A10 | PCA → Quantization | 8D, `alpha=0.10` | `U_PQ08_A10` | 8 | Có |
| PQ08_A25 | PCA → Quantization | 8D, `alpha=0.25` | `U_PQ08_A25` | 8 | Có |
| PQ08_A50 | PCA → Quantization | 8D, `alpha=0.50` | `U_PQ08_A50` | 8 | Có |

Tổng **14 cấu hình, 0 K-means fits**. PCA 4D là stress test; có thể dừng sớm các cấu hình có mức suy giảm quá lớn. Nếu mức alpha nhỏ không giúp gộp vector đáng kể, có thể khảo sát thêm `alpha=1.0` trên PCA 8D, nhưng chỉ dưới dạng mở rộng được ghi nhận riêng.

### 2.1. Quantization trực tiếp trên pixel

Làm tròn **trên thang UInt8 0–255** trước khi chuẩn hóa, không lượng tử hóa ngưỡng TC2:

`b_j = clamp(q * round(Int, pixel_j / q), 0, 255)`; vector key để đếm trùng là tuple **16 giá trị nguyên** `b_j` (không so sánh vector float bằng epsilon). Vector fit weighted tương lai là `Float32.(b) ./ 255f0`; weight là số patch thuộc cùng key. `q=5/10/20/32` là bước cường độ pixel, không phải số bit nén file.

### 2.2. PCA → Quantization

Sau khi chiếu PCA không whitening: `z = W_D'ᵀ (x - μ)` với `x∈[0,1]^16`, `D'∈{12,8}`. Các tọa độ PCA **không thuộc 0–255** và có thể âm. Với thành phần `j`, dùng bước lượng tử hóa `h_j = alpha * σ_j`, trong đó `σ_j` là độ lệch chuẩn PCA score tính từ **train**. Chỉ số nguyên: `b_j = round(Int, z_j / h_j)`; giá trị giải lượng tử `ẑ_j = b_j * h_j`; vector hồi phục `x̂ = μ + W_D' ẑ`. Nếu `σ_j≈0`, áp dụng quy tắc ổn định được cố định trước (ví dụ `b_j=0`, `ẑ_j=0`) và ghi vào metadata. **Unique** dựa trên tuple các `b_j` nguyên; weight=count. Không áp dụng `q=10` pixel cho PCA scores.

### 2.3. Nguyên tắc công bằng

- Cả 14 cấu hình nhận đúng cùng bộ retained descriptors raw 16D; **không lọc thêm patch vì kết quả lượng tử hóa**.
- PCA chỉ fit trên train; mỗi cấu hình dùng cùng PCA basis (cắt số chiều) để tránh confound.
- Không thay đổi nhãn lớp, thứ tự/tập ảnh, cách flatten, TC0–TC2, hoặc chuẩn hóa.
- Không gọi gộp trùng không-weighted là phương án Weighted K-means: **phải lưu counts**.
- PCA có `D'` nhỏ hơn nhưng không giảm số vector `N` trong bản thử PCA thuần. Quantization chỉ giảm `N` **nếu có dedup**.

## 3. Metrics trước K-means

### 3.1. Hiệu quả giảm tải (ưu tiên)

| Metric | Công thức | Diễn giải |
|---|---|---|
| `N` | số retained descriptors | Mốc dữ liệu ban đầu |
| `D_eff` | 16, 12, 8 hoặc 4 | Số chiều đưa vào phép tính khoảng cách |
| `U` | số vector *duy nhất* sau transform + quantization, hoặc N khi không dedup | Số điểm Weighted K-means sẽ duyệt |
| `unique_ratio` | `U/N` | Tỷ lệ vector còn lại |
| `duplicate_rate` | `1-U/N` | Tỷ lệ loại trùng sau lượng tử hóa |
| **`compute_proxy`** | **`(U × D_eff)/(N × 16)`** | Tỷ lệ phép tính khoảng cách *mỗi iteration* nếu K không đổi |
| `theoretical_speedup_proxy` | `1 / compute_proxy` | Chỉ là tỷ lệ công việc lý thuyết, **không phải speedup đo được** |
| `prep_time_s` | PCA fit + transform + quantize + unique/count (đo rõ phần chia sẻ) | Chi phí chuẩn bị trước K-means |
| `peak_ram_mib`, `output_bytes` | đo thực tế | RAM và kích thước dữ liệu fit dự kiến |

Ví dụ: P08 luôn có `compute_proxy=8/16=0.5`. Q10 chỉ có `compute_proxy=U_Q10/N`, không được gán 50% nếu chưa đo. PQ08_A25 có `compute_proxy=(U_PQ08_A25/N)×0.5`. Công thức này bỏ qua khác biệt thời gian khởi tạo, hashing, xử lý trọng số, tốc độ thư viện và số iteration.

### 3.2. Mức mất thông tin vector (ưu tiên)

**Không dùng PSNR hoặc file-size compression ratio làm tiêu chí chính:** mục tiêu của vòng này là codebook K-means, không phải nén ảnh để lưu trữ.

Mọi cấu hình tạo vector tái tạo `x̂ ∈ R^16` để so với Raw Descriptor `x∈R^16`:

- **PCA:** `x̂ = μ + W_D' z`.
- **Quant:** `x̂ = Q_pixel(x)` sau khi quy về `[0,1]`.
- **PCA+Quant:** `x̂ = μ + W_D' ẑ`.

| Metric | Công thức / phương pháp | Ý nghĩa |
|---|---|---|
| **`raw_vector_mse`** | `Σ_i ||x_i−x̂_i||² / (N×16)` | Độ méo bình quân trên vector gốc |
| **`normalized_distortion`** | `raw_vector_mse / mean_feature_variance_raw` | Tỷ lệ méo so với biến thiên tự nhiên dữ liệu, dễ so sánh |
| `patch_rmse_p95` | P95 của `sqrt(mean((x_i−x̂_i)^2))` | Tránh trường hợp trung bình thấp nhưng một số patch méo nặng |
| `distance_rank_spearman` | Tương quan Spearman giữa khoảng cách cặp vector raw và biến đổi, trên danh sách cặp cố định | Kiểm tra bảo toàn cấu trúc khoảng cách (metric bổ trợ) |
| `PCA_explained_variance_ratio` | tổng tỷ lệ phương sai của D' thành phần | Chẩn đoán riêng cho PCA |

**Tính `mean_feature_variance_raw`** bằng `Σ_i ||x_i−μ||²/(N×16)` trên 60k train, cùng một mẫu số cho toàn bộ 14 cấu hình. `normalized_distortion` và `patch_rmse_p95` nhỏ hơn là tốt. `distance_rank_spearman` cao hơn là tốt (không phải bằng chứng bảo toàn cluster). Để đo Spearman hiệu quả, dùng cùng 30.000 cặp chỉ số (i,j) lấy từ training descriptors với seed cố định, **chỉ lấy mẫu cho metric phụ, không lấy mẫu khi xây dựng/nén toàn bộ dữ liệu**. Không dựng ma trận khoảng cách N×N.

### 3.3. Chẩn đoán phân phối weights (Quant/PQ)

Ghi `max_weight`, `mean_weight`, `median_weight`, `weight_p95`, `fraction_singleton_keys` và `sum(weights)`. Một mức q có `U` thấp nhưng một số ít key chứa phần lớn dữ liệu sẽ là cảnh báo gộp quá mạnh. `sum(weights)` **phải đúng bằng N**.

## 4. Quy trình thực thi (không K-means)

1. **Freeze input:** Tái sử dụng cache TC0–TC3 của **đủ 60.000 ảnh train**; xác minh N, D=16, finite, min/max chuẩn hóa, Q10+ train, checksum và raw duplicate rate.
2. **Tính raw statistics:** mean, phương sai, `mean_feature_variance_raw` và PCA basis; fit PCA **một lần** trên toàn train (với D=16 có thể dùng covariance 16×16 tích lũy theo chunk).
3. **Baseline B0:** đo số điểm, kích thước, metric loss=0, chia sẻ hàm đánh giá.
4. **PCA P12/P08/P04:** transform đầy đủ N descriptors, inverse, đo lỗi và `compute_proxy`; **không chạy K-means**.
5. **Quant Q05/Q10/Q20/Q32:** thực hiện quantize trên pixel và unique+count toàn N, đo U, weights, lỗi và thời gian.
6. **PCA+Quant PQ***: transform PCA, lượng tử hóa hệ số theo `α × σ_j`, unique+count trên integer bins, inverse, đo cùng metrics.
7. **Xuất report:** CSV 14 dòng, scatter `compute_proxy vs normalized_distortion`, scatter `prep_time_s vs normalized_distortion`, báo cáo Pareto frontier và top 2–3 ứng viên. **Không chạy K-means ở vòng này.**

**Chú ý bộ nhớ:** Baseline descriptors Float32 16D với N=1.836.369 cần `N×16×4 = 117.527.616 bytes` (≈112,08 MiB), chưa tính metadata. PCA 8D lưu Float32 toàn N ≈56,04 MiB. Dedup bằng hash/tuple có thể tiêu tốn RAM lớn hơn ma trận đặc Float32; nên chunk input, dùng integer bin keys, đo peak RSS và tránh giữ tất cả 14 biểu diễn trong RAM đồng thời. PCA fitting trên 16 chiều là phần tương đối nhẹ, nhưng transform toàn N vẫn có chi phí.

## 5. Quy tắc chọn Pareto và thẩm định

**Không quyết định trước PCA hay Quant tốt hơn.** Dùng hai trục chính:

- **Chi phí tính khoảng cách kỳ vọng:** `compute_proxy` **càng thấp càng tốt**.
- **Vector distortion:** `normalized_distortion` **càng thấp càng tốt**.

Một cấu hình bị *dominated* nếu tồn tại cấu hình khác có cả hai metric không tệ hơn và ít nhất một metric tốt hơn. Chỉ đề cử ứng viên **không bị dominated**, sau đó xem thêm `prep_time_s`, `patch_rmse_p95`, `distance_rank_spearman`, sự tập trung weights và RAM.

**Ngưỡng gợi ý để sàng lọc, KHÔNG phải tiêu chuẩn đã xác nhận:** `normalized_distortion ≤ 0.05` (méo không quá 5% phương sai raw) và `compute_proxy ≤ 0.75` (giảm ≥25% công việc tính khoảng cách theo mô hình). Nếu quá ít ứng viên, nới ngưỡng; nếu quá nhiều, xét Pareto và tính ổn định khoảng cách. Đừng tự động loại một ứng viên chỉ vì vượt một ngưỡng minh họa.

**Giới hạn của kết luận trước K-means:** `compute_proxy` **không chứng minh** tốc độ fit thực tế; `raw_vector_mse` **không chứng minh** codebook K-means tốt. Sau bước này, chỉ chọn tối đa 2–3 ứng viên để chạy **K=64, seed=42** và so sánh `Total TC4 Runtime` cùng `Raw-space Validation Distortion` trên cùng 10.000 ảnh validation (TC5 vẫn gán từ raw 16D). Không được kết luận cấu hình tối ưu cuối cùng chỉ từ metrics tiền K-means.

## 6. Cấu hình TOML đề xuất

```toml
[experiment]
name = "tc4_vector_tradeoff_60k"
phase = "pre_kmeans_only"
run_kmeans = false
train_images = 60000
use_all_retained_descriptors = true
random_seed = 42

[input]
source = "tc3_raw_descriptors_train"
patch_size = 4
stride = 4
filter = "q10_positive_train_alpha0"
raw_dimension = 16
raw_dtype = "Float32"
pixel_scale = 255.0
expected_n_reference = 1836369  # xác minh lại sau TC0

[pca]
enabled = true
components = [12, 8, 4]
fit_split = "train"
center = true
standardize = false
whiten = false
fit_once = true

[quantization]
enabled = true
input_space = "pixel_0_255"
steps = [5, 10, 20, 32]
deduplicate = true
preserve_frequency_weights = true
key_type = "integer_tuple"

[pca_quantization]
enabled = true
pca_dimensions = [12, 8]
alphas = [0.10, 0.25, 0.50]
step_rule = "alpha_times_train_pca_score_std_per_component"
deduplicate = true
preserve_frequency_weights = true
key_type = "integer_tuple"

[metrics]
calculate_compute_proxy = true
calculate_normalized_distortion = true
calculate_raw_vector_mse = true
calculate_patch_rmse_p95 = true
calculate_distance_rank_spearman = true
pair_sample_size = 30000
calculate_unique_ratio = true
calculate_weight_statistics = true
measure_preparation_time = true
measure_peak_ram = true

[selection]
method = "pareto"
screen_max_normalized_distortion = 0.05
screen_max_compute_proxy = 0.75
max_candidates_for_actual_kmeans = 3

[output]
results_csv = "results/fashion/tc/tc4_vector_tradeoff_60k/tc4_vector_tradeoff_60k.csv"
summary_md = "results/fashion/tc/tc4_vector_tradeoff_60k/tc4_vector_tradeoff_60k_summary.md"
figures_dir = "results/fashion/tc/tc4_vector_tradeoff_60k"
```

## 7. Bảng kết quả bắt buộc

Một dòng cho mỗi cấu hình với các cột:

`config_id, method, n_input, n_unique, unique_ratio, d_eff, compute_proxy, theoretical_speedup_proxy, raw_vector_mse, normalized_distortion, patch_rmse_p95, distance_rank_spearman, pca_evr, prep_time_s, peak_ram_mib, max_weight, fraction_singleton_keys, passes_sanity_checks`.

Tạo thêm:

- Biểu đồ `compute_proxy` (x) vs `normalized_distortion` (y), ghi nhãn điểm và Pareto frontier.
- Biểu đồ `prep_time_s` vs `normalized_distortion` (không gọi đây là K-means runtime).
- Bảng top 2–3 candidates và giải thích chọn/bỏ dựa trên số liệu thực tế.

## 8. Checklist nghiệm thu vòng vector

- [ ] Sử dụng đủ 60.000 ảnh train, **không** dùng validation/test trong fit PCA hoặc thống kê ngưỡng.
- [ ] Chỉ sử dụng retained patches từ TC2; Raw Pixel 16D đã cache giữ nguyên.
- [ ] Xác nhận N thực tế, đối chiếu 1.836.369 descriptors và duplicate rate 0,537% đã đo.
- [ ] 14 cấu hình chạy thành công; không fit K-means.
- [ ] Mọi biến đổi đều cho phép tái tạo xấp xỉ về không gian 16D để đo cùng MSE.
- [ ] Với Quant/PQ: `sum(weights)==N`; n_unique>0; integer key ổn định.
- [ ] PCA 12/8/4 dùng cùng cơ sở PCA, không whitening.
- [ ] `compute_proxy` đúng: B0=1, P12=0,75, P08=0,5, P04=0,25.
- [ ] Baseline distortion=0 (chấp nhận sai số số học không đáng kể).
- [ ] Báo cáo nêu rõ `theoretical_speedup_proxy` **không** phải tốc độ đo được.
- [ ] Có CSV, 2 biểu đồ, Pareto shortlist, thời gian/RAM thực tế.
- [ ] Kết thúc vòng này **không** tự chạy K-means, TC5, Eclat hoặc 15 fits.
