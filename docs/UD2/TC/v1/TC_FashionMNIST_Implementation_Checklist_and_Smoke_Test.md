# Checklist triển khai TC + Smoke Test — Fashion-MNIST

**Phiên bản:** 1.0 — 15/11/2026  
**Tài liệu gốc:** `TC_FashionMNIST_Configuration_Detailed.md` (TC0–TC7).  
**Trạng thái:** Smoke CPU `T2_K8_seed42` đã chạy bằng notebook fresh-kernel và PASS; bộ test TC CPU đã chạy trong môi trường local. Chưa chạy production/15 fits.
**Mục tiêu:** Hoàn thiện **notebook TC0–TC7, mỗi TC là một cell code riêng**, giữ trạng thái giữa các bước trong cùng phiên kernel và lưu artifacts vào thư mục smoke; kiểm tra chạy từ đầu đến cuối bằng **01 cấu hình smoke nhỏ**. **Không dùng kết quả smoke để chọn K hay kết luận chất lượng mô hình.**

> **Nguyên tắc tiết kiệm thời gian/tài nguyên và lượt sửa bằng AI:** Trong giai đoạn phát triển, chỉ cần 01 smoke run `T2_K8_seed42` cho luồng chính. Không thực thi 15 K-means runs, không chạy toàn bộ 70k ảnh, không sinh mọi T1/T2/T3, không tạo centroid gallery toàn bộ và không quét nhiều minsup. Chỉ mở khóa full benchmark sau khi smoke end-to-end PASS.

**Bằng chứng triển khai hiện tại:** `src/applications/FashionTC.jl`, các config CPU và `notebook/UD2/03_fashion_mnist_transaction_construction_cpu.ipynb`. CPU smoke dùng Clustering.jl 0.15.8, có `status=PASS`. Mục E (full data/benchmark) chưa chạy.

---

## A. Cố định phạm vi: smoke khác production

| Thành phần | **Smoke test** (để phát triển, chỉ 1 run) | **Production/benchmark** (chạy sau) |
|---|---|---|
| Nguồn dữ liệu | Fashion-MNIST, giữ nguyên split gốc | Giữ nguyên split gốc |
| Train | **100 ảnh**, đúng 10 ảnh/lớp từ **train gốc** | **60.000 ảnh** train gốc |
| Validation | **20 ảnh**, đúng 2 ảnh/lớp từ **test gốc** | **10.000 ảnh** test gốc |
| Chọn ảnh | Deterministic, `sample_seed=42`, lưu image IDs | **Không sampling** ảnh hoặc descriptor để fit |
| TC0 — Q10+ | Tính từ **100 ảnh smoke-train**, tuyệt đối không dùng smoke-validation | Tính lại từ **60.000 ảnh train** |
| TC1 | Patch 4×4, stride 4, 49 patch/ảnh | Giống smoke |
| TC2 | **Chỉ T2:** Q10+_smoke_train, `alpha=0` | T2 benchmark; T1/T3 đối chứng về sau |
| TC3 | Raw pixel, `Float32/255`, 16 chiều | Giống smoke |
| TC4 | **K=8, seed=42, 1 fit**, full-batch Lloyd, K-means++, maxiter=20 | K∈{16,32,64,128,256}, seeds {42,123,2026}, maxiter=300; **15 fits** |
| TC4 stability | **BỎ QUA** (1 seed không đủ đo stability) | Mean±std, ARI giữa seeds ở cùng K, occupancy/transaction statistics |
| TC5 | Hard assignment; `chunk_size=128` để kiểm tra nhiều chunk | `chunk_size=16_384` |
| TC6 | Binary BoVW, unique + sort, không spatial | Giống smoke |
| TC7 | Xuất **100 train + 20 validation = 120 transactions logic** | Xuất **60k + 10k = 70k transactions logic** |
| Eclat integration | **1 pilot nhỏ** trên 120 transactions, không quét minsup | Pilot 2–3 K triển vọng, sau đó Eclat chính thức |
| Vùng output | `results/fashion/tc/smoke/T2_K8_seed42/` | `results/fashion/tc/runs/`, `benchmark/`, `final/` |

**Quan trọng:** Dùng nhãn Fashion-MNIST **chỉ để lấy mẫu cân bằng trong smoke**, không đưa label vào descriptor, K-means, Visual Word ID hoặc itemset. Smoke Q10+ không được tái sử dụng cho production. Bởi tính toán trên 100 ảnh, ngưỡng smoke **không cần bằng 29** và không cần bằng ngưỡng train 60k.

**Giới hạn chính xác trước lọc cho smoke:** 100×49 = **4.900 patch train**, 20×49 = **980 patch validation**, tổng **5.880**. Với raw 16D Float32, nếu không lọc, tổng descriptor data ≤ **376.320 bytes** (≈367,5 KiB). Đây là kích thước dữ liệu thô, **không phải peak RAM của Julia/Jupyter**.

---

## B. Cấu hình smoke test đang dùng

```toml
# SMOKE-ONLY — KHÔNG DÙNG ĐỂ CHỌN K HAY PHÁT HÀNH FINAL
[run]
mode = "smoke"
run_id = "T2_K8_seed42"
output_root = "results/fashion/tc/smoke/T2_K8_seed42"
overwrite_production_artifacts = false
fail_fast = true

[dataset]
name = "Fashion-MNIST"
train_source = "original_train"
validation_source = "original_test"
selection = "stratified_deterministic"
sample_seed = 42
train_per_class = 10
validation_per_class = 2
expected_train_images = 100
expected_validation_images = 20
expected_class_count = 10
save_selected_image_ids = true

[tc0_preprocessing]
method = "q10_positive"
fit_split = "smoke_train_only"
quantile = 0.10
positive_pixel_only = true
foreground_comparison = "strict_greater"
save_threshold = true

[tc1_patch_extraction]
patch_size = [4, 4]
stride = [4, 4]
padding = "none"
patch_order = "row_major"
patch_id_base = 1
preserve_coordinates = true
expected_patches_per_image = 49

[tc2_patch_filtering]
experiment = "T2"
method = "foreground_ratio"
threshold_source = "tc0_smoke_train"
alpha = 0.0
keep_comparison = "strict_greater"
modify_raw_pixel_values = false
run_other_filter_variants = false

[tc3_feature_extraction]
strategy = "dense_patches"
descriptor = "raw_pixels"
dtype = "Float32"
dimension = 16
normalization = "divide_by_255"
flatten_order = "column_major"
include_labels = false
include_position = false

[tc4_codebook]
algorithm = "Clustering.jl_full_batch_kmeans"
initialization = "kmeans++"
k = 8
seed = 42
max_iterations = 20
tolerance = 0.0001
fit_split = "smoke_train"
fit_all_retained_descriptors = true
number_of_fits = 1
run_stability_benchmark = false
run_k_grid = false

[tc5_word_assignment]
method = "nearest_centroid"
distance = "squared_euclidean"
word_id_base = 1
chunk_size = 128
apply_to = ["smoke_train", "smoke_validation"]

[tc6_transactions]
encoding = "binary_bovw"
deduplicate = true
sort = true
spatial = false
preserve_empty = true
one_image_one_transaction = true

[tc7_export]
expected_train_transactions = 100
expected_validation_transactions = 20
expected_full_transactions = 120
save_codebook = true
save_assignments = true
save_mapping = true
save_config = true
save_validation_report = true
assert_production_output_is_untouched = true

[eclat_smoke]
enabled = true
use_full_smoke_transactions = true
minsup_type = "absolute"
minsup_count = 2
run_parameter_grid = false

[execution]
execute_all_tc_notebooks_in_order = true
fresh_kernel_per_notebook = true
run_without_manual_cell_edits = true
save_executed_notebook_logs = true
stop_on_first_failure = true
```

Đây là cấu hình smoke thực tế được notebook đọc và đã chạy PASS. `src/applications/Fashion-Mnist/configs/transactions/split_full.toml` đi qua cùng `prepare_run` và các hàm TC0–TC7; config quyết định mode, quy mô dữ liệu, K/seed và output. Notebook mặc định smoke; chọn full bằng `FASHION_TC_CONFIG=src/applications/Fashion-Mnist/configs/transactions/split_full.toml`. Smoke đã chạy fresh-kernel; full mới được xác nhận ở bước đọc/chuẩn bị config, chưa chạy các bước trên 70.000 ảnh.

**Điểm giới hạn an toàn:** Một notebook khi chạy với config smoke **không được âm thầm dùng cấu hình full mặc định** nếu thiếu một trường bắt buộc; phải fail fast. Chỉ cho phép production khi người chạy chủ động chọn config full và xác nhận chế độ full.

---

## C. Checklist triển khai theo giai đoạn

### C0. Hạ tầng notebook / orchestration — làm trước

- [x] Xác định danh sách notebook TC thực tế và thứ tự dependency: một notebook điều phối TC0–TC7.
- [x] Notebook đọc config được chọn qua `FASHION_TC_CONFIG` (mặc định `src/applications/Fashion-Mnist/configs/transactions/split_smoke.toml`); smoke/full cùng đi qua các cell TC0–TC7.
- [x] Logic pipeline nằm trong `src/applications/FashionTC.jl`; notebook gọi module và hiển thị report.
- [x] Đường dẫn dataset/config/output được resolve tương đối từ project root.
- [x] Các cell dùng chung `run_state` trong kernel tuần tự; cache và kết quả cần lưu được ghi vào output theo config.
- [x] Notebook chạy top-to-bottom bằng fresh Julia kernel; lần chạy mới nhất lưu execution count/output, không có cell error.
- [x] `jupyter execute` là cách chạy tự động cho notebook TC duy nhất; lỗi làm lệnh thất bại và notebook lưu outputs làm log.
- [x] Có config smoke/full và output riêng; full chưa được chạy. Cùng notebook và kernel dùng cho hai config.
- [x] Lưu run ID, effective config, seed, ảnh đã chọn, phiên bản Julia/Clustering.jl và SHA-256 trong artifacts.

**Gate C0:** Có thể chạy từ một cấu hình smoke duy nhất mà không phải sửa thủ công từng notebook.

### C1. TC0 — Ngưỡng Q10+ (fit trên train)

- [x] Lấy đúng **100 ảnh smoke train** từ train gốc; validation lấy 20 ảnh test và không tham gia fit.
- [x] Lọc pixel dương từ smoke train rồi tính empirical 10th percentile; định nghĩa quantile lưu trong metadata.
- [x] Lưu `tau_smoke`, số positive pixels, split nguồn, checksum archive và config.
- [x] Dùng cùng tau train-fit cho filtering train và validation.
- [x] Smoke tự fit Q10+ (kết quả tau=34), không gán cứng EDA1 tau=29.

**Gate C1:** Fit train-only, ngưỡng hữu hạn/hợp lệ, tái chạy trên cùng ảnh cho cùng giá trị.

### C2. TC1 — Dense Patch Extraction

- [x] Ảnh đúng `28×28`; duyệt 4×4 stride 4, **49 patch/ảnh**.
- [x] Smoke tạo **4.900 patch train + 980 patch validation** trước lọc.
- [x] `patch_id = (row-1)*7+col`, row/col từ 1 đến 7; thứ tự row-major.
- [x] Ghép lại patch theo tọa độ khôi phục ảnh train và validation chính xác từng pixel.
- [x] Lưu ánh xạ split/image/patch/tọa độ trong bảng status và assignment.

**Gate C2:** Patch count và reconstruction pass.

### C3. TC2 — Filtering T2 (smoke chỉ T2)

- [x] Dùng `Keep(P) ⇔ max(P)>tau_smoke` vì `alpha=0`.
- [x] Giữ raw pixel values; filtering chỉ quyết định patch nào được đưa sang descriptor.
- [x] Bảng filter status giữ image/patch ID, tau, alpha, split và experiment.
- [x] Đếm retained + discarded bằng tổng patch gốc cho cả train và validation.
- [x] Giữ lại mọi image ID khi tổng hợp patch; encoder tạo transaction rỗng nếu không còn word.
- [x] Smoke chỉ chạy T2; không chạy T1/T3.

**Gate C3:** Mask đúng, đếm được retained/discarded, không làm mất image records.

### C4. TC3 — Descriptors

- [x] Trích đúng **mỗi patch giữ lại → một descriptor 16D**.
- [x] Dùng `Float32.(vec(patch)) ./ 255f0`; pixel flatten **column-major**, patch order row-major.
- [x] Không thêm label/spatial vào vector descriptor.
- [x] Giá trị hữu hạn, trong `[0,1]`; số descriptor khớp patch được giữ.
- [x] Cache train/validation riêng, kèm descriptor index và SHA-256 trong metadata.

**Gate C4:** Tính đúng 16D, đúng số descriptor và mapping.

### C5. TC4 — K-means Codebook (smoke chỉ 1 fit)

- [x] Chạy duy nhất `T2_K8_seed42`, **K=8, seed=42, maxiter=20**, full-batch; toàn bộ retained smoke-train descriptors được fit.
- [x] Dùng Clustering.jl `0.15.8`, API `kmeans(...; init=:kmpp)`; ghi thư viện và version vào metadata.
- [x] Fit chỉ nhận train descriptors; validation chỉ được gán sau khi codebook hoàn tất.
- [x] Centroids có shape **16×8** và hữu hạn.
- [x] Lưu iterations, objective, convergence, wall time và peak RSS trong `run_metadata.toml`.
- [x] Chỉ chạy một lần fit; không chạy grid K, ba seed, ARI, mean±std hay gallery trong smoke.
- [x] `fit_kmeans` từ chối đầu vào có ít hơn K descriptors.

**Gate C5:** 01 codebook hợp lệ được tạo và reload thành công, không chạy thừa 14 fits.

### C6. TC5 — Visual Word Assignment

- [x] Dùng cùng codebook **16×8** cho train và validation.
- [x] Gán theo chunks **128 descriptors**; assignment không cập nhật centroids.
- [x] `word_id ∈ 1:8`; mỗi retained patch có đúng một word.
- [x] So chunked assignment với direct assignment trên toàn bộ train smoke; tie-break giữ ID nhỏ hơn.
- [x] Bảng assignment có image/patch/tọa độ/word/split/run ID; patch bị loại không thành item `0`.

**Gate C6:** Số assignments khớp retained patch count; ID và tọa độ truy vết đúng.

### C7. TC6 — Binary Transactions

- [x] Mỗi ảnh tạo một transaction logic; ảnh không có patch giữ lại vẫn được giữ thành transaction rỗng.
- [x] Output có **100 train + 20 validation = 120 transactions**.
- [x] Encoder tạo `sort(unique(word_ids))`; item thuộc `1:8`, không lặp.
- [x] Mỗi transaction không dài hơn số patch giữ lại hay K.
- [x] Label/tọa độ/split chỉ nằm trong metadata, không thành transaction item.
- [x] Lưu `tid → split, image_id`.

**Gate C7:** Đúng số lượng transactions và invariants, không lẫn metadata vào item.

### C8. TC7 — Export + Reload + Eclat integration

- [x] Chỉ ghi vào `results/fashion/tc/smoke/T2_K8_seed42/`.
- [x] Lưu config hiệu lực, threshold, codebook, assignments, 120 transactions, TID mapping và metadata metrics.
- [x] Reload codebook/assignments/transactions trong subprocess/kernel và so nội dung với trước khi ghi.
- [x] Giữ mỗi dòng trống là một transaction rỗng; Eclat nhận vector transaction nên denominator gồm đủ 120 bản ghi. Unit test kiểm tra round-trip dòng trống.
- [x] Chạy đúng một Eclat pilot `minsup_count=2` trên 120 transactions.
- [x] Fixture 4 transactions kiểm tra N=4, support 1=3, 2=2, {1,2}=2, {2,3}=1 trực tiếp; {2,3} bị loại khỏi frequent itemsets.
- [x] Đối chiếu support các singleton/pairs được chọn trên dữ liệu smoke bằng đếm trực tiếp.
- [x] Báo cáo JSON có trạng thái pipeline/notebook, counts, config, run ID, checks và elapsed time; trạng thái tổng chỉ PASS khi notebook đã chạy.

**Gate C8:** Đọc/ghi đúng, Eclat integration không sai denominator/support, đủ 120 transactions.

---

## D. Checklist chạy smoke test end-to-end (một lần sau khi hoàn thiện code)

- [x] **S1 — Prepare:** Giữ split gốc; lấy 100/20 ảnh theo seed 42, lưu IDs.
- [x] **S2 — Execute:** Chạy notebook TC duy nhất bằng `jupyter execute` trên fresh kernel, từ đầu đến cuối, không sửa cell.
- [x] **S3 — Assert TC0–TC3:** Q10+ train-only; 4.900/980 patch; T2 only; descriptor 16D và mapping khớp.
- [x] **S4 — Assert TC4–TC6:** Một fit K=8 seed 42; chunk 128; 100/20 transactions và word ID hợp lệ.
- [x] **S5 — Assert TC7/Eclat:** Export/reload, fixture support, pilot 120 transactions và denominator đúng.
- [x] **S6 — Assert isolation:** Chỉ có thư mục smoke trong `results/fashion/tc`; không có benchmark/full output nào được tạo.
- [x] **S7 — Report:** Notebook đã lưu outputs làm log; JSON tổng hợp có pipeline/notebook status PASS và từng check PASS.
- [x] **S8 — Idempotency:** Hai lượt smoke fresh-kernel trên cùng seed/config có cùng image IDs, tau, transactions và assignment SHA-256; kiểm tra lại cũng giữ nguyên threshold SHA-256.

**Không cần điều kiện smoke:** K=8 có distortion tốt; mining tìm patterns có ý nghĩa; 3 seed có ARI cao; chạy hết 70k, 15 benchmark runs hoặc T1/T3. Đây là **integration smoke test**, không phải nghiên cứu kết quả.

### D.1. Ví dụ report (schema mong đợi, không phải kết quả đã chạy)

```json
{
  "run_id": "T2_K8_seed42",
  "mode": "smoke",
  "status": "NOT_RUN",
  "train_images": null,
  "validation_images": null,
  "train_patches_before_filter": null,
  "validation_patches_before_filter": null,
  "train_retained_descriptors": null,
  "validation_retained_descriptors": null,
  "fitted_q10_positive": null,
  "kmeans_fit_count": null,
  "kmeans_k": 8,
  "transaction_counts": null,
  "checks": {
    "tc0_train_only": "NOT_RUN",
    "tc1_patch_reconstruction": "NOT_RUN",
    "tc2_filter_invariants": "NOT_RUN",
    "tc3_descriptor_mapping": "NOT_RUN",
    "tc4_codebook_shape": "NOT_RUN",
    "tc5_chunked_assignment": "NOT_RUN",
    "tc6_transaction_invariants": "NOT_RUN",
    "tc7_reload_and_eclat_support": "NOT_RUN",
    "all_tc_notebooks_fresh_kernel": "NOT_RUN",
    "production_artifacts_untouched": "NOT_RUN"
  }
}
```

---

## E. Sau khi smoke PASS — checklist chạy thật (KHÔNG bắt buộc cho lần bàn giao code đầu)

### E1. Production preparation

- [ ] Chuyển sang config production **một cách tường minh**; kiểm tra `mode=full` và output paths riêng.
- [ ] TC0 tính lại Q10+ từ **60.000 train**; lưu ngưỡng này, không dùng ngưỡng smoke hoặc EDA1=29 để fit.
- [ ] Chạy TC1–TC3 **60.000 train + 10.000 validation**, cache toàn bộ retained descriptors; ghi nhận reduction thực tế.
- [ ] Chạy `src/applications/Fashion-Mnist/configs/transactions/split_smoke.toml` qua notebook TC0–TC7; chỉ khi smoke đạt mới chạy `src/applications/Fashion-Mnist/configs/transactions/split_full.toml`.

### E2. Main K benchmark

- [ ] `T2_K16_seed42`  - [ ] `T2_K16_seed123`  - [ ] `T2_K16_seed2026`
- [ ] `T2_K32_seed42`  - [ ] `T2_K32_seed123`  - [ ] `T2_K32_seed2026`
- [ ] `T2_K64_seed42`  - [ ] `T2_K64_seed123`  - [ ] `T2_K64_seed2026`
- [ ] `T2_K128_seed42` - [ ] `T2_K128_seed123` - [ ] `T2_K128_seed2026`
- [ ] `T2_K256_seed42` - [ ] `T2_K256_seed123` - [ ] `T2_K256_seed2026`
- [ ] Với từng K, đo validation distortion, occupancy, transaction statistics; tính stability trên các seeds (ARI cùng validation descriptors, không đối chiếu raw word IDs).
- [ ] Chạy tuần tự và lưu checkpoint sau từng fit; chỉ tiếp tục từ checkpoint khớp backend, dữ liệu, descriptors, K, seed và cấu hình.

### E3. Chọn K và kiểm tra pipeline

- [ ] Chọn 2–3 K triển vọng; chạy **2–3 pilot Eclat** cùng tập ảnh và minsup có thể so sánh.
- [ ] Chốt K theo distortion, stability, transaction quality, mining suitability và runtime; ghi `selected_k_decision.md`.
- [ ] Dùng **một codebook cố định** để so sánh 3 cấu hình filtering **T1/T2/T3**; tái dùng T2 output nếu đã có.
- [ ] Nếu dự định đánh giá tối ưu riêng từng pipeline T, lên kế hoạch fit codebook khác (không coi đó là phép cô lập filtering).

### E4. Xuất final và nghiệm thu

- [ ] Chốt final codebook và TC configuration; không fit centroids trên validation.
- [ ] Sinh **60.000 + 10.000 = 70.000 transactions logic**, đúng ID và đầy đủ metadata.
- [ ] Eclat loader duy trì 70.000 transactions logic, kể cả empty; hỗ trợ kiểm chứng support với brute force vài itemsets.
- [ ] Lưu `results/fashion/tc/final/` với config, threshold, codebook, patch assignments, transactions, TID mapping, validation report.
- [ ] Viết báo cáo benchmark/stability/đối chứng filtering và giới hạn validation (EDA-1 từng tham khảo toàn 70k).

---

## F. Cách giao nhiệm vụ cho coding agent để tiết kiệm token

Giao công việc theo **mốc nghiệm thu nhỏ**, không yêu cầu agent chạy full experiments khi chỉ cần xác nhận code:

1. **Build:** Implement TC0–TC7 theo tài liệu cấu hình gốc; tất cả tham số nhận từ cùng TOML, hỗ trợ `mode=smoke` và đường dẫn output riêng.
2. **Test:** Chạy **duy nhất** smoke `T2_K8_seed42` trên 100 train + 20 validation, kèm fixture Eclat N=4; chạy tất cả notebooks từ fresh kernel, ghi log.
3. **Fix:** Chỉ sửa phần lỗi và chạy lại smoke. Không chạy 15 fits, không generate 70k transactions, không T1/T3, không tính ARI; những việc đó thuộc checklist E.
4. **Hand-off:** Trả `smoke_test_report.json`, log notebook, đường dẫn artifacts smoke, mọi test PASS/FAIL và hướng dẫn một lệnh để người dùng tự chạy full sau này.

**Điều kiện bàn giao lượt 1:** `C0–C8` và `S1–S8` PASS, hoặc ghi trung thực blocker. **Không nhầm "not run" với "passed".**

---

## G. Các lưu ý kỹ thuật cần giữ đúng

- **Cùng codebook giữa splits:** train và validation cùng K/seed luôn sử dụng chung centroids; visual word IDs từ hai codebook khác nhau không thể trộn.
- **Full-batch khác Mini-batch:** TC4 Lloyd full-batch dù TC5 assignment theo chunk; không tự đổi thuật toán.
- **Dấu so sánh:** Foreground `pixel > tau`, patch giữ khi `FR > alpha`; với alpha=0 tương đương `max(P)>tau`.
- **Thứ tự:** Patch order row-major, pixel flatten column-major (Julia); giữ đúng khi reload.
- **TID và support:** Transaction rỗng không thể làm giảm denominator logic của Eclat; phải kiểm cả khi export TXT/reader bỏ dòng trắng.
- **Không leakage khi benchmark:** threshold production fit train-only, centroids fit train-only; validation chỉ đánh giá. Smoke chỉ kiểm tra cách triển khai điều này.
- **Trung thực với kết quả:** Báo cáo smoke là kiểm tra khả năng vận hành pipeline, tuyệt đối không đưa vào bảng chọn K cuối cùng.

**Kết quả mong đợi của checklist này:** Sau khi hoàn thiện code, chỉ cần **01 lượt smoke duy nhất** để chứng minh các notebooks kết nối, lưu/đọc dữ liệu, K-means, encoding và Eclat hoạt động ở quy mô nhỏ; **full experiments là một công việc chạy riêng**.
