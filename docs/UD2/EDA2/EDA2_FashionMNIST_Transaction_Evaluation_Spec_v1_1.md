# SPEC — EDA2: Transaction Quality, Codebook Evaluation & Pilot Eclat

**Dự án:** Frequent Itemset Mining trên Fashion-MNIST bằng Eclat  
**Phiên bản:** 1.1 — phạm vi thực thi EDA2 v2 gồm S0, S1 và S3  
**Đối tượng:** Coding agent / nhóm thực nghiệm Julia  
**Trạng thái:** Đặc tả công việc, **không phải kết quả chạy thực nghiệm**  
**Nguồn hợp đồng:** `TC_Transaction_Construction_Spec_v2.md` (TC baseline, rev 2.1) và `TC6_Spatial_Encoding_Extension_Spec_v1.md` (TC6 extension, v1.0).  

> **Hiệu lực:** EDA2 v2 đánh giá **45 bộ transactions = 15 codebooks × 3 encodings (S0, S1, S3)**. S6-B nằm ngoài phạm vi EDA2 v2. Kết quả lượt trước nằm trong `results/fashion/eda2/v1/`.

---

## 0. Mục đích, câu hỏi nghiên cứu và kết quả cần bàn giao

### 0.1. Mục tiêu

Đánh giá có hệ thống chất lượng **15 codebooks B0** và **45 transaction databases**, kết hợp khai thác thử bằng **Eclat** để chọn cấu hình `(K, seed, encoding)` phù hợp với Frequent Itemset Mining; báo cáo rõ những đánh đổi về chất lượng phân cụm, cấu trúc transactions, giá trị mẫu phổ biến, độ ổn định, khả năng diễn giải và chi phí tính toán.

**Không** mặc định: K lớn hơn tốt hơn; distortion thấp nhất là tốt nhất; nhiều frequent itemsets hơn là tốt hơn; Spatial Encoding luôn tốt hơn S0; hoặc một điểm tổng hợp với trọng số tự đặt có thể quyết định khách quan.

### 0.2. Research questions (RQ)

- **RQ1 — Codebook size:** K=16/32/64/128/256 ảnh hưởng ra sao đến distortion, cluster occupancy, transaction structure và kết quả mining?
- **RQ2 — Seed stability:** Với cùng K, các seeds 42/123/2026 có ổn định về assignments, transaction metrics và kết quả Eclat không?
- **RQ3 — Encoding effect:** Khi **giữ cố định `(K,seed)`**, S0, S1, S3 khác nhau ra sao về độ thưa, support, diversity, mining utility và interpretability?
- **RQ4 — Spatial meaningfulness:** S1/S3 có tạo mẫu vị trí có ý nghĩa hơn baseline không?
- **RQ5 — Cost/quality trade-off:** Cấu hình nào cân bằng tốt giữa khả năng khai thác, tính diễn giải, độ ổn định và runtime/memory?
- **RQ6 — Class-conditional similarity (post-hoc):** Với cùng visual representation, các ảnh cùng lớp Fashion-MNIST có transactions tương tự nhau hơn các ảnh khác lớp không? S0/S1/S3 thay đổi khả năng bảo toàn cấu trúc lớp như thế nào? Đây là **đánh giá hậu nghiệm bằng nhãn**, không phải mục tiêu tối ưu chính của unsupervised FIM.

### 0.3. Đầu ra cuối cùng

1. Báo cáo chất lượng **15 codebooks**, thống kê cả theo K và theo seed.
2. Báo cáo EDA **đầy đủ 45 transaction databases**, gồm tất cả nhóm mô tả và biểu đồ; bổ sung **within-class vs between-class transaction similarity, separation gap, pairwise discrimination AUC** và phân tích theo lớp/cặp lớp (post-hoc).
3. Kết quả **Pilot Eclat khảo sát chung** có giới hạn tài nguyên, rồi **Pilot Eclat chuyên sâu** trên shortlist chọn minh bạch.
4. Gallery centroids, patches, ảnh và frequent itemsets tiêu biểu.
5. **Selection decision record**: một cấu hình cuối cùng `(K*,seed*,variant*)` *nếu có đủ bằng chứng*, hoặc một **shortlist có lý do** nếu chưa đủ; ghi cả ứng viên thay thế, trade-offs và giới hạn bằng chứng.
6. Toàn bộ số liệu, biểu đồ, configs, logs, manifests có thể kiểm tra và tái lập, không chỉ output trong notebook.

---

## 1. Phạm vi, nguồn dữ liệu và ranh giới cứng

### 1.1. Ma trận cấu hình phải tìm thấy

| Thành phần | Giá trị cố định |
|---|---|
| Dataset | Fashion-MNIST, 70.000 ảnh, 28×28, 49 patches 4×4 mỗi ảnh trước lọc |
| TC2 | T2: `any(pixel > 29)`; không tính lại Q10+ |
| TC3–TC5 | raw descriptors 16D, codebooks B0, hard assignment |
| K | `[16, 32, 64, 128, 256]` |
| Seeds | `[42, 123, 2026]` |
| Encodings | `S0`, `S1`, `S3` |
| Datasets | **45**: 15 S0 baseline + 30 spatial |
| Records / dataset | **70.000**, bao gồm transaction `items: []` |
| Tổng số logical records | 3.150.000 (70.000 ảnh được dùng lại giữa các cấu hình) |

**Nguồn baseline (source B0/S0):** `results/fashion/tc/tc6_configs/S0/`.  
**Nguồn spatial (TC6 full):** `results/fashion/tc/tc6_configs/`; các variants nằm riêng trong `S1/` và `S3/`.  

Các đường dẫn là **tham số cấu hình**, không phải khẳng định hai thư mục đang thực sự tồn tại trong môi trường coding agent. Không hardcode theo tên folder nếu metadata manifest cho phép nhận diện chính xác.

### 1.2. Input artifacts

**Mỗi B0 source run:** `transactions.jsonl`, `codebook.bin`, `patch_assignments.csv`, `tid_image_mapping.csv`, `image_metadata.csv` (nếu có), `tc4_metrics.toml`, `config_snapshot.toml`, `integrity_report.toml`, `checkpoint.toml`; file tổng hợp `tc4_metrics_summary.csv`, `tc4_seed_stability.toml`, `tc_v2_run_summary.toml` nếu sẵn có.

**Mỗi spatial run:** `transactions.jsonl`, `item_mapping.csv`, `tid_image_mapping.csv`, `config_snapshot.toml`, `source_artifacts.toml`, `encoding_stats.toml`, `integrity_report.toml`, `checkpoint.toml` (theo TC6 extension). S0 word IDs có thể giải mã trực tiếp bằng word ID/codebook và cần có mapping logic tương đương khi trực quan hóa.

Không được giả định `codebook.bin` hay `assignments.bin` là định dạng chuẩn liên ngôn ngữ; agent phải **tái sử dụng reader có trong project**, xác minh layout `K×16`/`16×K`, hoặc báo blocker khi không giải mã được.

### 1.3. Không thuộc phạm vi

- Không chạy lại TC0, TC1–TC5; không fit lại codebooks; không đổi patch/filter/descriptor.
- Không sinh lại hay ghi đè 15 bộ S0 và 30 bộ spatial trong phạm vi; EDA2 chỉ **đọc** artifacts. Không sửa `K`, seed, variant, thresholds.
- Không triển khai S2/S4/S5/S7/S8 hay Q20.
- Không đổi định nghĩa item IDs, spatial boundaries.
- Không dùng class labels để tạo transactions, xếp cụm, chọn frequent itemsets bằng phép lọc theo nhãn, hoặc tính support trong Eclat. **Nhãn chỉ được dùng để đánh giá hậu nghiệm, bao gồm mục B5 class-conditional similarity và diễn giải mẫu ở EDA2-D**. Nếu tham chiếu các kết quả nhãn trong quyết định cuối cùng, phải ghi minh bạch đó là *label-aware model selection*, không trình bày như quy trình chọn hoàn toàn unsupervised.
- Không làm bài toán phân loại Fashion-MNIST dưới danh nghĩa EDA2; không chạy final production FIM/association-rule pipeline ở giai đoạn này.

### 1.4. Đơn vị so sánh

- **Codebook ID:** `(method=B0, K, seed)` — 15 ID.
- **Transaction database ID:** `(B0, K, seed, variant)` — 45 ID.
- **Eclat experiment ID:** `(database ID, minsup, mining parameters, repetition)`.
- Support tính theo **70.000 images/TIDs**, **không** lấy số patches, số retained patches hay số nonempty transactions làm mẫu số.
- S0, S1, S3 có **item namespaces khác nhau**: không so sánh cùng số nguyên ID giữa variants, K hoặc seeds.

---

## 2. Architecture và thứ tự thực hiện

```
15 B0 codebooks + 45 completed transaction databases
                   │
                   ▼
EDA2-00  Discovery / lineage / independent read-back / validation
                   │
                   ▼
EDA2-A   Intrinsic codebook analysis — 15 codebooks
                   │
                   ▼
EDA2-B   Transaction structural EDA + post-hoc class similarity — all 45 databases
                   │
                   ▼
EDA2-C1  Bounded common Pilot Eclat — all 45 databases
                   │
                   ▼
EDA2-C2  Predeclared shortlist, balanced across encoding variants
                   │
                   ▼
EDA2-C3  Deeper Pilot Eclat + runtime/memory + pattern analysis
                   │
                   ▼
EDA2-D   Spatial interpretability
                   │
                   ▼
EDA2-E   Multi-criteria comparison / decision / reproducible report
```

**Tất cả 45** có EDA2-A/B liên quan và một kết quả C1 (completed/limited/timeout/failure có lý do), nhưng **không nhất thiết có khai thác toàn bộ itemsets chuyên sâu**.

---

## 3. EDA2-00 — Discovery, data integrity, provenance

### 3.1. Manifest chung

Tạo manifest **45 rows**, mỗi row gồm tối thiểu:

`database_id, method, K, seed, variant, source_root, run_path, transactions_path, codebook_path_or_ref, item_mapping_path_or_ref, tid_mapping_path, integrity_path, config_path, source_sha256_or_equivalent, record_count, status`.

S0 nối về source run của TC; S1/S3 phải có `source_artifacts.toml` chỉ về **đúng** `(K,seed)` S0. Tham chiếu codebook có thể chia sẻ file; **không yêu cầu copy lại**.

### 3.2. Các validation gate (phải PASS trước khi đánh giá)

- Exactly 15 distinct codebook IDs và exactly 45 distinct database IDs, không trùng `(K,seed,variant)`.
- B0 completed/integrity PASS; spatial completed/integrity PASS. Nếu thiếu/malformed: nêu danh sách blocker, **không giả lập 45 results**; có thể làm partial trên nhóm hợp lệ nhưng **không kết luận full selection**.
- Parse lại **70.000 JSONL records/dataset** từ đĩa: `tid`, `image_id`, `items`, `items` sorted strict ascending, unique integer, ranges đúng: `S0:1..K`, `S1:1..4K`, `S3:1..3K`.
- 70k TIDs unique, TID–image mapping one-to-one, **cùng population/TIDs** ở mọi database. Record `items:[]` được giữ.
- Codebook centroids finite, `K×16`; metadata `K/seed/method/data/threshold=29` khớp artifacts nguồn. Đọc từng format theo schema thực tế; không tự đoán offset/column base.
- S1/S3: giải mã words theo mapping và kiểm tra projection về S0 cho **từng image/TID**; empty status khớp S0.
- Ghi SHA-256 hoặc digest tương đương cho nguồn đầu vào, config EDA2, version notebook/code; không làm thay đổi nguồn.

**Output:** `input_manifest.csv`, `validation_report.toml`, `input_issues.csv` (có thể rỗng), `environment.toml`. Nếu checksum mismatch hay schema không tương thích: đánh dấu `BLOCKED`, không tự sửa source.

---

## 4. EDA2-A — Intrinsic Codebook Quality (15 codebooks)

### 4.1. Dữ liệu sử dụng

`tc4_metrics.toml`, `tc4_metrics_summary.csv`, `tc4_seed_stability.toml`, `codebook.bin`, `patch_assignments.csv` nếu cần để đối chứng. Không chạy lại K-means. **Không** cố tái tính distortion từ raw descriptors nếu TC3 descriptors không được xuất; sử dụng đúng giá trị đã lưu và báo metadata về metric definition. Nếu metrics khác nhau định nghĩa/normalization, không so sánh trực tiếp.

### 4.2. Metrics bắt buộc

| ID | Metric | Quy tắc đánh giá |
|---|---|---|
| A01 | Mean squared Euclidean distortion / inertia đã lưu | Cùng data/normalization, vẽ theo K và 3 seeds; không so sánh tổng inertia nếu số descriptors khác |
| A02 | Elbow / relative improvement | Tính mức giảm phần trăm distortion khi tăng K; không coi elbow là phép chọn K tự động |
| A03 | Cluster occupancy | `#cluster có assignment / K`; số cụm rỗng, rất nhỏ nếu có |
| A04 | Cluster size distribution | Min/median/max, P5/P95, normalized entropy, top-1/top-5 share; tính từ patch assignments nếu metrics thiếu |
| A05 | Seed variability của distortion/occupancy | Mean, std, min/max theo K trên 3 seeds; không trộn K |
| A06 | Assignment ARI giữa seeds | Dùng cùng fixed descriptor sample nếu TC4 đã lưu; đối chiếu 3 cặp seed/K và provenance, **không** so raw word IDs |
| A07 | Convergence & degenerate flags | Iterations, converged status, empty cluster, `FAILED`, `NON_CONVERGED`, `DEGENERATE_WARNING`; báo sự khác biệt giữa warning và invalid |
| A08 | Visual inspection | Gallery centroid 4×4, near-centroid real patches nếu có lineage/raw image reader; nhận xét duplicate-looking/border/background patterns dựa trên ảnh, không tự gán ngữ nghĩa |

**Normalized entropy:** nếu `n_j` là patch count cluster j, `p_j=n_j/M`, dùng `H_norm=-Σ_{p_j>0} p_j log(p_j)/log(K)` (K>1). Occupancy **theo patches**, khác hoàn toàn support theo **ảnh** ở EDA2-B.

**ARI:** nếu có đúng assignments của **cùng 10.000 descriptors** với cố định `stability_sampling_seed=2026`, dùng lại metric. Nếu stability file không đủ evidence về sample/cohort, đánh dấu `UNVERIFIED`; chỉ tính lại ARI bằng assignment vào centroids nếu **có cùng descriptors được lưu hoặc tái dựng đúng** và không refit. Không lấy 10k image IDs thay cho 10k descriptors hoặc so assignments theo các codebooks có IDs không tương ứng.

**Centroid plots:** khi reshape vector theo column-major của TC3; tránh transpose hình ảnh. Nếu muốn near-centroid real patches, cần dùng đúng patch nguồn và pixel gốc; không hiển thị synthetic patch như real patch.

### 4.3. Screening policy

- **Loại khỏi các bước mining** chỉ khi artifact không hợp lệ về số chiều/finite, lineage hoặc ID, assignment lỗi, không đọc được, hoặc integrity FAIL.
- `NON_CONVERGED`, `DEGENERATE_WARNING`, occupancy thấp bất thường, ARI thấp, distortion cao: **flag để phân tích**, không tự loại. Nếu không đạt tính hợp lệ do nguyên nhân cụ thể, ghi reason code.
- **Không chọn một seed/K từ distortion trước khi nhìn transactions**. Không tự ép còn 5 codebooks trước EDA2-B.

**Output:** `codebook_metrics_15.csv`, `codebook_metrics_by_k.csv`, `seed_stability_by_k.csv`, centroid galleries và intrinsic plots, `codebook_flags.csv`.

---

## 5. EDA2-B — Structural Transaction EDA (đủ 45 databases)

### 5.1. B1 — Transaction length, density và empty rate

Với mỗi `T_i`:

- `length_i=|T_i|`; report mean, std, median, min/max, P5/P25/P75/P95/P99, fraction `length=0`, nonempty count, share `length=1`.
- `observed_universe_size` = số item IDs xuất hiện ≥1 lần; `theoretical_universe_size = K,4K,3K,2K²` theo variant.
- `density_theoretical = Σ_i |T_i| / (70000×theoretical_universe_size)`; tính thêm utilization theo item universe observed. **Không dùng density một mình để chọn variant** vì kích thước item universe thay đổi theo encoding.
- `length_capacity_ratio`: S0 ≤ `min(K,49)`, S1 ≤ `min(4K,49)`, S3 ≤ `min(3K,49)`; chỉ dùng như mô tả, **không diễn giải như cùng một thang ý nghĩa**.
- So sánh **paired by TID** giữa variants tại cùng K/seed, vẽ phân bố độ dài và tỷ lệ empty.

### 5.2. B2 — Item support distribution

Với mỗi item `j` và toàn bộ 70k records, tính count `n_j=#{i:j∈T_i}` rồi `support_j=n_j/70000`.

- Histograms/ECDF/log-scaled distribution, min/median/mean/P5/P95/max **trên observed items**; số theoretical-but-unused IDs ghi riêng để tránh hàng loạt zero làm sai ấn tượng.
- `#items_at_minsup`, `% observed items_at_minsup`, `% theoretical items_at_minsup` cho các ngưỡng chung ở §6; quy đổi fractional minsup → absolute count với `ceil(70000×minsup)` và quy tắc ≥.
- Report thresholds mô tả **hiếm/rất phổ biến** dựa trên config (`rare_support_max`, `ubiquitous_support_min`) chứ không coi chúng là tiêu chí loại cứng; tuyệt đối không đặt lại threshold theo từng variant để ưu ái một phương pháp.
- S1: support theo R1/R2/R3/R4, lưu kèm số vị trí patch khả dĩ **9/12/12/16**; S3: TOP/MIDDLE/BOTTOM tương ứng **14/21/14**. So sánh support theo vùng cần lưu ý cơ hội quan sát khác nhau; không kết luận vùng nào "quan trọng" từ support thô.

**Chú ý:** `cluster_size` ở TC4 là số *patches*, còn `item support` ở EDA2-B là số *images* chứa item; không được dùng thay nhau.

### 5.3. B3 — Transaction diversity

- `unique_transaction_count` và `unique_ratio=unique_count/70000`; `duplicate_ratio=1-unique_ratio`; phân bố multiplicity của identical transactions; top repeated transactions (decode trước khi diễn giải).
- Pairwise **Jaccard similarity** trên bộ cặp TID cố định, sampled deterministic dùng chung trên 45 datasets; report mean/median/P5/P95 và empty-pair shares. Nếu cả hai transactions rỗng, định nghĩa `J(empty,empty)=1` và báo riêng số cặp đó; một rỗng/một không rỗng thì J=0. Không bỏ empty records.
- Chọn `pair_sample_size` (ví dụ 20.000 unique TID pairs) với fixed `pair_sampling_seed`; không lấy các cặp mới cho từng variant. Ghi chính xác số cặp hợp lệ.
- **Không** tính direct Jaccard giữa S0 và S1/S3 theo numeric item IDs; so sánh **phân bố Jaccard** và paired effects, không giả định namespaces tương đương.
- Nếu cần so diversity giữa seeds của cùng K+variant, **không** so trực tiếp words theo ID; chỉ dùng summary distributions, hoặc phải match centroids/labels một cách có tài liệu.

### 5.4. B4 — Sanity/semantic invariants

- S1/S3 projection xuống global words khớp S0 **100% TIDs**, là test validity chứ không phải quality metric.
- So sánh theo **paired `(K,seed)`** các chỉ số, sau đó aggregate theo K và variant (mean/min/max across seeds), không ghép các datasets thành 3,15 triệu quan sát độc lập cho suy luận thống kê.

### 5.5. B5 — Class-Conditional Transaction Similarity (BẮT BUỘC, post-hoc)

**Mục đích:** Kiểm tra biểu diễn transactions có làm các ảnh **cùng nhãn Fashion-MNIST** có xu hướng giống nhau hơn các ảnh **khác nhãn** không. Không dùng class labels trong TC1–TC7, Eclat, tính support, hoặc lựa chọn frequent itemsets. Đây là một **chỉ số bổ trợ về tính phân biệt theo nhãn**, không chứng minh một biểu diễn tốt hơn cho unsupervised FIM.

**Đầu vào và điều kiện hợp lệ:**

1. Lấy `image_id → class_label` từ `image_metadata.csv` hoặc metadata nguồn có provenance xác thực; join bằng `image_id`/TID mapping, **không** dựa vào thứ tự file hoặc suy đoán nhãn. Kiểm tra 70.000 image IDs, 10 nhãn hợp lệ, mapping 1–1, label không mâu thuẫn giữa 45 databases. Ghi nguồn labels, version/hash và split gốc ở metadata. Không dùng label trong bước tạo transaction hay mining.
2. Nếu metadata thiếu/không nhất quán, gắn `CLASS_LABELS_BLOCKED`, **không tự tạo labels** và không tuyên bố B5 hoàn tất; EDA2-A/B1–B4/C có thể chạy tiếp nếu independent input gates vẫn PASS. Báo cáo tỷ lệ dữ liệu gắn nhãn hợp lệ; coverage thấp phải được coi là hạn chế mẫu.
3. Sử dụng **cùng một danh sách cặp TID không thứ tự, phân biệt** cho tất cả 45 databases; không thay đổi cặp mẫu theo K/seed/variant. Lấy mẫu có hạt giống cố định, tránh cặp `(i,i)`, tránh cặp lặp, lưu danh sách cặp và nhãn quan hệ để reproduce.

**Thiết kế lấy mẫu chuẩn:**

- Mặc định đề xuất `within_pair_count=50000`, `between_pair_count=50000`, `class_pair_sampling_seed=2026`; đây là các **giá trị cấu hình**, không khẳng định kết quả thực đo.
- **Within-class:** phân bổ mục tiêu đều cho **10 lớp** (5.000 cặp/lớp khi đủ ảnh), lấy ngẫu nhiên không hoàn lại trong từng lớp.
- **Between-class:** phân bổ mục tiêu đều theo **45 cặp lớp không thứ tự** (`10 choose 2`, khoảng 1.111–1.112 cặp/cặp lớp), lấy cặp ảnh ngẫu nhiên không hoàn lại. Không để các cặp lớp đông hơn lấn át kết quả trung bình.
- Nếu không thể đạt quota vì coverage hoặc số cặp khả dĩ, ghi actual counts, sampling constraints và **không giả báo đã lấy đủ**. Cặp mẫu B5 là phép lấy mẫu riêng có phân tầng, không thay thế bộ cặp generic B3 (`pair_sample_size=20000`).

**Định nghĩa similarity & metrics:**

Với hai transactions `T_i,T_j` (cùng **database**), tính `J(T_i,T_j)=|T_i∩T_j|/|T_i∪T_j|` nếu hợp khác rỗng. Tuân thủ quy tắc B3 cho pairs rỗng: nếu **cả hai rỗng**, lưu `J=1` để tương thích nhưng **loại khỏi các aggregate chính** của B5 và báo riêng tỷ lệ `both_empty`; nếu một rỗng thì `J=0` và vẫn tính. Tránh báo within cao giả tạo vì empty–empty.

| Metric | Định nghĩa / output |
|---|---|
| `within_mean_jaccard` | Mean của các pair Jaccard cùng lớp, trên các cặp không `both_empty` (kèm median/P5/P25/P75/P95 và valid-pair count) |
| `between_mean_jaccard` | Mean của các pair Jaccard khác lớp, trên các cặp không `both_empty` (kèm median/quantiles và valid-pair count) |
| `separation_gap` | `within_mean_jaccard − between_mean_jaccard`, dùng hai tập cặp không `both_empty` theo cùng sampling design |
| `pair_discrimination_auc` | AUC dùng điểm Jaccard để phân biệt *same-class pair* vs *different-class pair*: `P(J_within>J_between)+0.5 P(tie)`; dùng chỉ các pair hợp lệ; nếu thiếu một nhóm → `UNDEFINED`, không đặt 0 |
| `empty_pair_rates` | Tỷ lệ `both_empty` và `one_empty` riêng trong từng nhóm, cộng số mẫu thực tế/valid |
| `classwise_within` | 10 hàng: thống kê within-class cho từng lớp, sample size và empty rate |
| `class_pair_between` | 45 hàng: between-class theo từng cặp lớp và sample size; ma trận đối xứng 10×10 là **diễn giải mô tả**, không phải ma trận confusion |

**Cách tổng hợp và diễn giải:**

- Tính B5 **cho đủ 45 databases** và lưu phân bố Jaccard within/between; biểu đồ paired theo `(K,seed)` và so sánh theo `K × variant`. Báo cáo macro-by-class / macro-by-class-pair thêm bên cạnh pooled estimates, vì thiết kế lấy mẫu cân bằng khác với phân bố cặp tự nhiên.
- Các cặp ảnh tái sử dụng cùng image IDs, nên **không** coi 100.000 pairs là quan sát thống kê độc lập khi tính p-value/CI. Nếu có khoảng tin cậy, dùng quy trình bootstrap thích hợp theo **image ID** với sampling design cố định và trình bày phương pháp; nếu chưa có thì chỉ báo thống kê mô tả.
- Jaccard giữa S0/S1/S3 là **so sánh phân bố và khả năng tách nhóm**, không phải độ gần trực tiếp giữa item IDs; không được so raw item ID xuyên variants/seeds. `separation_gap`/AUC phải đọc cùng empty rates, sparsity và other metrics.
- **Không** chọn codebook/variant chỉ vì AUC hoặc gap lớn nhất; chúng đo liên hệ với nhãn Fashion-MNIST, không nhất thiết đo pattern-mining utility. Nếu dùng B5 để điều chỉnh shortlist hoặc tie-break final, phải ghi đó là lựa chọn có tham chiếu nhãn và báo cả kết quả lựa chọn không dùng nhãn khi khả thi.

**Output B5:** `class_similarity_summary_45.csv`, `classwise_similarity.csv`, `class_pair_similarity.csv`, `class_similarity_pair_manifest.csv` (TID pairs, class IDs, sampling stratum, seed, hash), các hình `class_similarity_distributions`, `class_similarity_heatmaps`, `class_similarity_by_k_variant`. **Không** lưu raw labels như item trong `transactions.jsonl`.

**Output EDA2-B:** `transaction_metrics_45.csv`, `item_support_summary_45.csv`, `item_support_by_database` (parquet/CSV dạng tiết kiệm), `transaction_diversity_45.csv`, `region_support_summary.csv`, **B5 class similarity artifacts**, figures, B flags.

---

## 6. EDA2-C — Pilot Eclat, hai vòng

### 6.1. Quy tắc chung

- Tái sử dụng **Eclat implementation** của repository nếu đúng/support, không tự thay bằng Apriori/FP-Growth. Nếu không có Eclat engine hợp lệ, báo blocker và không tuyên bố đã xong EDA2-C.
- Eclat nhận các transactions **theo từng database riêng**, chỉ dùng `items`; `tid/image_id` là khóa truy xuất, nhãn lớp không là item.
- Tính `support_count(X)=|{T_i:X⊆T_i}|`, `support_fraction=support_count/70000` với **70k kể cả empty**.
- Định nghĩa frequent: `support_count >= ceil(minsup_fraction × 70000)`; ghi rounding rõ. Giữ nguyên 70k population cả ba variants.
- Số lượng item universe khác nhau nên **không** chấm điểm bằng `#frequent itemsets` độc lập; cần diversity, support shape, novelty, interpretability, stability và cost.
- Mining status mỗi run ∈ `{COMPLETED, COMPLETED_LENGTH_CAPPED, TIMEOUT, MEMORY_LIMIT, ITEMSET_LIMIT, FAILED, SKIPPED_BLOCKED}`. **TIMEOUT ≠ 0 frequent itemsets**; không biến truncated counts thành full counts.
- Chuẩn hóa `minsup` theo **fraction of 70k images** để có cùng ý nghĩa across variants. Khảo sát độ nhạy ở C3 với cùng lưới ngưỡng.
- Thời gian/peak RAM: cùng engine version, Julia environment, hardware, threads, warm-up protocol và thuật toán; ghi các yếu tố này. Quy ước resource caps phải ghi trước khi chạy toàn bộ grid.

### 6.2. C1 — Common bounded pilot trên **45 databases**

**Mục đích:** Có bằng chứng mining sơ bộ trên **tất cả** `(K,seed,variant)` với giới hạn tài nguyên chung.

**Thiết kế mặc định đề xuất:**

- `screening_minsup_fraction = 0.03` (2.100 ảnh/70k); cấu hình được phép đổi **trước khi bắt đầu** vòng C1, không tự điều chỉnh theo variant/K sau khi xem kết quả.
- `screening_max_itemset_length = 2` (frequent singletons và pairs); đây là **bounded pilot**, không phải khai thác frequent itemsets đầy đủ.
- Giới hạn per-run runtime/memory/output items bằng config phù hợp máy thật. Nếu tool không hỗ trợ dừng an toàn, implement supervisor ở phạm vi thực thi thay vì sửa semantics của Eclat.
- Metrics C1: counts length=1,2, support distribution cho phần được mining hoàn tất, max completed length, runtime, peak RSS (nếu đo được), status/truncation, throughput và count of active singleton support >=minsup.
- **Nếu engine không thể tìm toàn bộ pairs trước cap**, gắn `partial`/status tương ứng; đừng dùng số đếm partial để xếp hạng trực tiếp với completed runs.

### 6.3. C2 — Shortlist selection, minh bạch và cân bằng

Chỉ sau A + B + C1 mới shortlist codebooks; **shortlist chọn theo `(K,seed)`**, và **giữ đủ ba variants** cho từng cặp được chọn.

**Tiêu chí:** (a) đầu vào hợp lệ; (b) không có suy biến nghiêm trọng; (c) phân bố support/length/diversity có thông tin; (d) pilot có bằng chứng mining không tầm thường hoặc thể hiện trade-off đáng nghiên cứu; (e) seed stability; (f) chi phí và đa dạng theo K. *Không chọn theo distortion thấp nhất hay số itemsets nhiều nhất.*

**Chính sách mặc định đề xuất:** mục tiêu **6–9 codebooks** (18–27 databases deep pilot) nếu có đủ ứng viên; giữ **ít nhất một `(K,seed)` hợp lệ cho mỗi K** để bảo toàn xu hướng K, trừ khi K đó bất khả thi được chứng minh và ghi exception; giữ các seed khác nhau cho một số K để kiểm định ổn định. Nếu không thể shortlist công bằng, tăng phạm vi hoặc nêu limitations.

**Shortlist artifact:** `shortlist_decision.csv` có `selected`, `reason_codes`, `metrics_used`, `rejected_for_invalidity` và `selection_protocol_version`. Không tự loại im lặng.

### 6.4. C3 — Deep pilot & sensitivity analysis trên shortlist

**Ngưỡng tham chiếu đề xuất:** `[0.01,0.03,0.05,0.10]`, tương ứng counts `[700,2100,3500,7000]` trên 70k; tất cả variants cùng ngưỡng. Mở rộng `[0.005]` (350 ảnh) chỉ là sensitivity **được khai báo tường minh, áp dụng công bằng và resource-aware**; không lấy riêng ngưỡng dễ cho một variant làm kết luận chính.

**Metrics:**

1. Frequent itemsets count theo `minsup` và độ dài `1,2,3,...`; largest mined length; support_count/fraction distribution; top items/itemsets.
2. Frequent **closed** và **maximal** itemsets (số lượng, length, support) **chỉ khi full frequent family đủ để xác định chính xác** hoặc Eclat backend có chế độ mine closed/maximal chính xác. Nếu chỉ chạy với `max_itemset_length` hoặc timeout, bắt buộc ghi `closed_maximal_status=NOT_EXACT` và không quảng cáo con số partial là exact.
3. Runtime, peak RSS/allocations (nếu đo được), run status, resource caps; 1 warm-up + tối thiểu 3 measured repetitions cho các cấu hình được dùng so performance; báo median/P95 nếu phù hợp và variance.
4. Top itemsets tránh chỉ chọn theo support cao nhất; thêm trường `novelty/redundancy annotation`, visual coherence, witness availability, và số itemsets không tầm thường theo **định nghĩa được công bố trước**.
5. Sensitivity plots theo minsup: số frequent itemsets/length, support structure, runtime/memory, rank consistency của candidates. Không coi itemsets count quá lớn là dấu hiệu tự động tốt.
6. Tính toán stability giữa seeds (đối với K có ≥2 seeds shortlist) bằng summary distributions và **các pattern tương ứng đã ghép nhãn nếu có**; không so item IDs thô giữa seeds.

**Quy tắc đúng/sai Eclat:** chạy unit tests trên toy transaction DB đã biết đáp án; kiểm tra anti-monotonicity `#F(minsup cao) ≤ #F(minsup thấp)` cho **cùng độ dài/cùng mining mode hoàn chỉnh**; cross-check exact support của mẫu itemsets bằng intersection TID sets/scan; đảm bảo `minsup` dùng integer ceil. Không quy kết những violations do censored runs là lỗi tính toán khi chưa kiểm tra.

**Output:** `pilot_common_45.csv`, `pilot_deep_runs.csv`, `pilot_itemset_counts.csv`, `pilot_itemsets` (tách theo database/minsup), `performance_summary.csv`, `pilot_validation_report.toml`, logs/checkpoints.

---

## 7. EDA2-D — Visual Interpretability & Spatial Meaningfulness

### 7.1. Chọn patterns để minh họa

- Chọn representatives theo **độ dài, support bands, variant, K**, không chỉ top support. Định nghĩa selection rule trước khi xem ảnh và lưu `pattern_selection_manifest.csv`.
- Với mỗi frequent itemset được minh họa: decode item IDs theo `item_mapping.csv` hoặc codebook; ghi exact support_count, support_fraction, database, minsup, TID examples, pixel/patch coordinates và nguồn ảnh.
- Hiển thị **centroid 4×4** và patches thật; hiển thị ví dụ ảnh có/không có pattern (negative controls minh họa, không tạo negative transactions để mine).
- S1/S3: overlay vùng và matched patch positions; hiển thị tất cả witness positions liên quan đến itemset nếu có.
- Nhãn Fashion-MNIST chỉ dùng sau khai thác để báo tỷ lệ theo lớp / enrichment mô tả; support vẫn tính trên 70k. Phân biệt nhãn descriptive với bằng chứng nhân quả hay khả năng dự đoán.

### 7.2. Rubric diễn giải (cố định trước khi chấm)

Áp dụng rubric có thể tái lập, ví dụ ghi các trường: `decodable`, `visual_coherence`, `nontriviality`, `redundancy`, `annotator_notes`. Với nhận xét chủ quan, ghi ai đánh giá, ví dụ ảnh, tiêu chuẩn cụ thể và bất đồng; không biến điểm chủ quan thành ground truth.

- **S0:** có biểu diễn visual motifs lặp lại không?
- **S1:** vị trí R1–R4 có ý nghĩa hơn co-occurrence toàn ảnh không? Cân nhắc kích thước vùng 9/12/12/16.
- **S3:** TOP/MIDDLE/BOTTOM (14/21/14 slots) có mô tả cấu trúc theo trục dọc không?

**Output:** `pattern_gallery/`, `pattern_interpretability.csv`, minh họa/plots.

---

## 8. EDA2-E — So sánh cuối cùng và chọn cấu hình

### 8.1. Những tầng ra quyết định

1. **Validity gate:** loại khỏi final nếu source bất hợp lệ, mapping không tái lập được, Eclat sai support, hoặc lineage lỗi. Timeout không đồng nghĩa cấu hình kém chất lượng; là ràng buộc tài nguyên riêng.
2. **Intrinsic codebook evidence:** distortion/elbow, occupancy, cluster balance, ARI/seed stability, centroids. Chỉ là bằng chứng ở tầng codebook.
3. **Transaction quality evidence:** lengths, support, diversity, empty rate, observed universe, per-region support.
4. **Mining utility & cost:** frequent patterns không tầm thường, support shape, độ dài mẫu, closed/maximal **khi xác định chính xác**, runtime/memory, độ nhạy minsup.
5. **Interpretability & robustness:** visually verifiable patterns, seed robustness và limitations.
6. **Post-hoc class similarity (bằng chứng bổ trợ):** within/between Jaccard, gap, AUC và phân tích theo lớp trên **cùng 45 datasets**; trình bày riêng khỏi unsupervised mining utility. Không biến B5 thành điều kiện loại cứng hoặc điểm thắng tuyệt đối.

### 8.2. Fair comparison rules

- Đầu tiên so sánh variants **paired trong cùng `(K,seed)`**; sau đó so các K/seeds theo metric phù hợp. Không lấy numerical word ID trùng nhau làm bằng chứng semantic trùng nhau giữa codebooks.
- Báo theo **K × variant** bằng mean/range across 3 seeds; khi chọn final seed cần ghi vì sao seed đó phù hợp. Không coi 3 seeds là 3 datasets độc lập.
- `#itemsets`, transaction lengths và density giữa S0/S1/S3 **không cùng thang ý nghĩa**; không kết luận trực tiếp từ độ lớn mà thiếu normalization và interpretability.
- Nếu B5 được dùng để hỗ trợ lựa chọn hoặc tie-break, phải chú thích **label-aware selection**; không tuyên bố quy trình chọn hoàn toàn không giám sát. Nếu muốn giữ lựa chọn strict-unsupervised, dùng B5 để mô tả/đối chứng hậu nghiệm mà **không dùng để xếp hạng/shortlist**.
- Không gộp mọi metric thành score weighted tùy ý. Thay bằng bảng **trade-off/Pareto candidates**, loại các cấu hình rõ ràng bị dominated trên **các metrics có thể so sánh**, và lập luận định tính kèm số liệu.
- Nếu resource censoring khiến không thể so sánh công bằng, report `INCONCLUSIVE` và những phép thử cần thiết thay vì tự chọn một winner.

### 8.3. Final decision deliverable

`final_selection.md` gồm:

1. **Chosen** `(B0, K*, seed*, variant*)` hoặc `INCONCLUSIVE` với shortlist.
2. Bảng ứng viên cạnh tranh và evidence theo 6 nhóm metrics + intrinsic quality; kèm **phần riêng cho B5 class similarity**, chỉ rõ chỉ số này có/không ảnh hưởng đến quyết định.
3. Điều kiện minsup, miner version, environment, resource caps và tình trạng completion của pilots.
4. Lý do không chọn các ứng viên cạnh tranh; hạn chế/selection bias nếu có.
5. Paths + checksums đến source artifacts, selected `transactions.jsonl`, codebook, item mapping, configuration snapshot.
6. Khuyến nghị downstream Eclat production **chỉ sau** selection; không chạy final production mining trong scope này.

**Không chỉnh sửa hay tạo “selected codebook” mới:** lựa chọn phải tham chiếu **artifact gốc tương ứng**; không tự fit codebook khác hoặc ghép các centroids từ nhiều seeds.

---

## 9. Notebook / modules / execution strategy

### 9.1. Notebook điều phối

Dùng **một notebook điều phối** `EDA2_FashionMNIST_Transaction_Evaluation.ipynb` cho toàn bộ luồng EDA2. Notebook giữ thứ tự structural analysis → common pilot → human shortlist → deep pilot/interpretation → decision report. C2 vẫn là cổng duyệt thủ công trước C3/D; gộp notebook không đồng nghĩa tự chọn cấu hình.

Tách reader, validators, statistics, mining adapter và report writer vào `src/eda2/...` để notebook giữ vai trò điều phối, progress và hiển thị kết quả. Mỗi phase có thể chạy riêng theo thứ tự; không chạy toàn bộ 45×grid trong một cell không thể resume.

### 9.2. Cell sections nên có

**Notebook sections:** `00 Environment/Config` → `01 Discovery` → `02 Read-back/Validation` → `03 TC4 Intrinsic` → `04 Codebook visualization` → `05 Length/Density` → `06 Item Support` → `07 Diversity` → `08 Class-Conditional Similarity (post-hoc)` → `09 Spatial EDA` → `10 Analysis pass` → `11 Outputs/Status` → `12 Eclat input gate` → `13 Eclat adapter & tiny check` → `14 Common pilot 45` → `15 Shortlist rationale` → `16 Deep Pilot/Sensitivity` → `17 Performance` → `18 Pattern interpretation` → `19 Final comparison` → `20 Decision Report`.

Mỗi code cell phải có mô tả **mục đích/input/output/checks** ngắn gọn; không thêm code/giải thích thừa. Không dùng thực thi notebook để tự mutate source TC.

### 9.3. Kỹ thuật thực thi

- Streaming/iterator đọc JSONL; không cần giữ mọi transactions của 45 databases trong RAM đồng thời. Có thể dùng vertical TID lists/bitsets theo từng database để tính support và Eclat.
- Deterministic seeds, sort stable, fixed pair sample.
- Checkpoints theo `(phase, database_id, minsup, mode)`; resume chỉ trên config/source hash trùng. Không tự skip một run chưa `COMPLETED`.
- Log từng unit với start/end time, elapsed, RSS nếu đo, status, warnings, source hashes, output hashes.
- `fail_fast` trên sai hợp đồng dữ liệu/logic; resource timeout/memory censoring ghi trạng thái riêng cho mỗi pilot run và tiếp tục theo policy cấu hình (không giấu failures).
- Cố gắng tái sử dụng Julia/Clustering.jl version từ TC; version môi trường Eclat ghi riêng, không ngầm thay đổi semantics.

---

## 10. Output directory, schemas và báo cáo

### 10.1. Cấu trúc đề xuất

```text
results/fashion/eda2/v2/
├── input_manifest.csv
├── validation_report.toml
├── environment.toml
├── config_snapshot.toml
├── codebook/
│   ├── codebook_metrics_15.csv
│   ├── codebook_metrics_by_k.csv
│   ├── seed_stability_by_k.csv
│   ├── codebook_flags.csv
│   └── figures/
├── transactions/
│   ├── transaction_metrics_45.csv
│   ├── item_support_summary_45.csv
│   ├── transaction_diversity_45.csv
│   ├── class_similarity_summary_45.csv
│   ├── classwise_similarity.csv
│   ├── class_pair_similarity.csv
│   ├── class_similarity_pair_manifest.csv
│   ├── region_support_summary.csv
│   ├── item_support_by_database/
│   └── figures/
├── pilot_eclat/
│   ├── pilot_common_45.csv
│   ├── shortlist_decision.csv
│   ├── pilot_deep_runs.csv
│   ├── pilot_itemset_counts.csv
│   ├── performance_summary.csv
│   ├── pilot_validation_report.toml
│   ├── itemsets/
│   └── figures/
├── interpretability/
│   ├── pattern_selection_manifest.csv
│   ├── pattern_interpretability.csv
│   ├── pattern_gallery/
│   └── figures/
├── final/
│   ├── comparative_summary.csv
│   ├── tradeoff_candidates.csv
│   ├── final_selection.md
│   └── EDA2_summary_report.md
└── execution/
    ├── checkpoints/
    ├── logs/
    └── run_summary.toml
```

Không phải mọi file bắt buộc dùng CSV; có thể Parquet/JLD2 để tránh rất nhiều rows nếu project đã dùng. **Bắt buộc** giữ bảng summary có schema rõ, nguồn tính toán truy vết được, có read-back.

### 10.2. Schema bắt buộc cho summary

**`codebook_metrics_15.csv`:** `method,K,seed,codebook_id,source_path,distortion_definition,distortion,occupancy,empty_clusters,cluster_entropy_norm,top1_cluster_share,convergence_status,flags` và fields liên quan nếu có.

**`transaction_metrics_45.csv`:** `database_id,method,K,seed,variant,N,empty_count,mean_length,median_length,std_length,p5_length,p95_length,max_length,observed_universe,theoretical_universe,density,integrity_status`.

**`item_support_summary_45.csv`:** `database_id,K,seed,variant,N,observed_items,theoretical_items,item_support_min,median,max,quantiles,rare_count,ubiquitous_count,frequent_singletons_by_minsup` (có thể tách bảng long format cho thresholds).

**`class_similarity_summary_45.csv`:** `database_id,K,seed,variant,N_labeled,within_mean_jaccard,between_mean_jaccard,separation_gap,pair_discrimination_auc,within_valid_pairs,between_valid_pairs,within_both_empty_rate,between_both_empty_rate,sampling_seed,pair_manifest_hash,status,missing_reason`. Các quantiles bổ sung bằng columns hoặc bảng chi tiết. `classwise_similarity.csv`: `database_id,K,seed,variant,class_id,within_mean,within_median,within_p5,within_p95,valid_pairs,both_empty_pairs`. `class_pair_similarity.csv`: `database_id,K,seed,variant,class_a,class_b,between_mean,between_median,valid_pairs,both_empty_pairs`. `class_similarity_pair_manifest.csv`: `tid_a,tid_b,class_a,class_b,pair_type,sampling_stratum,seed`; một bộ mẫu dùng lại cho cả 45 databases.

**`pilot_common_45.csv`:** `database_id,K,seed,variant,minsup_fraction,minsup_count,max_length,completed_length,frequent_1_count,frequent_2_count,runtime_s,peak_rss_bytes,status,censored,engine_version,limit_reason`.

**`pilot_deep_runs.csv`:** `database_id,K,seed,variant,minsup_fraction,minsup_count,mode,max_length,completion_status,runtime_s,peak_rss_bytes,repetition,output_ref`.

**`shortlist_decision.csv`:** `K,seed,codebook_id,selected,decision_reason,flags,pilot_evidence_summary`, không shortlist theo từng variant đơn lẻ.

**`final/comparative_summary.csv`:** một row / candidate tương ứng hoặc long format với source references, six metric groups, performance status, interpretability evidence, **B5 class similarity fields (nếu hợp lệ)**, `eligible`, `label_informed_selection` và reason codes.

Với bất kỳ metric không tính được do artifacts/version/timeout, ghi `missing_reason/status`, **không điền zero thay cho missing**. Báo phân biệt số liệu thực đo, con số tính được từ metadata và nhận xét định tính.

---

## 11. Cấu hình TOML tham chiếu

Đây là **config đề xuất để implement**, không phải các keys notebook TC đã hỗ trợ sẵn. Values runtime/memory phải xác nhận theo máy chạy thực tế trước khi bắt đầu benchmark.

```toml
[run]
run_id = "FashionMNIST_EDA2_B0_S0_S1_S3_v2"
output_root = "results/fashion/eda2/v2"
overwrite_source_artifacts = false
fail_fast_on_invalid_input = true
resume = true

[input]
baseline_root = "results/fashion/tc/tc6_configs/S0"
spatial_root = "results/fashion/tc/tc6_configs"
method = "raw_full_batch_kmeans"
k_candidates = [16, 32, 64, 128, 256]
random_seeds = [42, 123, 2026]
variants = ["S0", "S1", "S3"]
expected_codebooks = 15
expected_databases = 45
expected_transactions_per_database = 70000
require_completed_integrity = true

[codebook_evaluation]
use_saved_tc4_metrics = true
require_same_descriptor_sample_for_ari = true
visualize_centroids = true
visualize_nearest_real_patches_when_available = true

[transaction_eda]
pair_sampling_seed = 2026
pair_sample_size = 20000
rare_support_max = 0.001
ubiquitous_support_min = 0.95
jaccard_empty_empty = 1.0
common_minsup_fractions = [0.01, 0.03, 0.05, 0.10]

[class_similarity]
enabled = true
posthoc_labels_only = true
require_all_70000_label_mappings = true
class_pair_sampling_seed = 2026
within_pair_count = 50000
between_pair_count = 50000
balance_within_by_class = true
balance_between_by_unordered_class_pair = true
exclude_both_empty_from_primary_aggregates = true
record_empty_pair_rates = true
save_pair_manifest = true
use_for_shortlist = false  # mặc định: tránh label-aware selection

[pilot_eclat]
engine = "reuse_repository_eclat"
support_denominator = 70000
common_screening_minsup = 0.03
common_screening_max_length = 2
deep_minsup_fractions = [0.01, 0.03, 0.05, 0.10]
deep_optional_sensitivity_minsup = 0.005
# Các limits phải được chốt theo máy thực tế.
per_run_timeout_seconds = 600  # giá trị GỢI Ý, phải rà soát môi trường
max_memory_gb = 8              # giá trị GỢI Ý, phải rà soát môi trường
max_reported_itemsets = 100000 # chỉ giới hạn report/storage, không được lén cắt search rồi báo exact
performance_repetitions = 3

[shortlist]
target_min_codebooks = 6
target_max_codebooks = 9
preserve_three_variants_per_codebook = true
preserve_k_coverage_where_valid = true

[interpretability]
representative_itemsets_per_variant = 12
example_images_per_itemset = 8
labels_for_posthoc_analysis_only = true

[execution]
backend = "cpu"
```

**Quan trọng:** `max_reported_itemsets` chỉ là giới hạn số dòng **được lưu/hiển thị**, không phải sự bảo đảm đếm chính xác frequent itemsets. Nếu engine phải ngừng enumeration do limit thì phải ghi `ITEMSET_LIMIT` và counts là censored. Tương tự, `max_memory_gb` chỉ là limit khi có cơ chế đo/cưỡng chế thực sự; nếu không hỗ trợ, phải log `memory_limit_unenforced`, không tuyên bố giới hạn đã được áp dụng.

---

## 12. Verification strategy và acceptance tests

### 12.1. Tests bắt buộc trước full EDA2

1. JSONL parser: giữ transaction `items=[]`, không nhân đôi TIDs; 70k denominator.
2. S0/S1/S3: projection S1/S3→S0 cho mỗi TID; verify patch mapping.
3. Support test: toy 5–10 transactions gồm empty; item support và multi-item support biết trước; `ceil(minsup*N)` đúng.
4. Eclat adapter: đối chiếu kết quả toy database với enumeration thủ công; monotonicity và exact support cross-check.
5. Jaccard: empty-empty, empty-nonempty, identical, disjoint; pairs sampling fixed.
5a. B5 class similarity: test join TID→image_id→label; balanced within 10 lớp và between 45 cặp lớp; manifest cố định tái sử dụng 45 databases; không chứa `(tid,tid)` hoặc duplicate pairs; `separation_gap`, AUC (ties tính 0.5), `both_empty` excluded from primary estimates; test mọi pair giống nhau cho identical transactions, và `UNDEFINED` khi thiếu một nhãn pair group.
6. Seed stability: không so cluster raw IDs giữa các seeds; ARI từ cùng descriptors; permuted-label synthetic test phải cho ARI=1.
7. Resource censoring: mô phỏng timeout/itemset cap; các counts phải có censored status và không tham gia rankings như complete.
9. Read-back summary tables, source hash/config/provenance, rerun idempotency; nguồn TC phải không bị thay đổi (hash trước/sau nếu khả thi).

### 12.2. Smoke → full execution

- **Smoke:** 1 codebook × 3 variants, subset TIDs chỉ để kiểm tra logic; output smoke riêng, không gắn nhãn production 70k và không dùng smoke support để chọn config.
- **Full A/B:** đọc và đánh giá toàn bộ 45 datasets, bao gồm B5 class similarity trên một pair manifest duy nhất; nếu labels không hợp lệ thì B5 phải báo `CLASS_LABELS_BLOCKED`, không làm sai các metric không dùng nhãn.
- **C1:** common bounded pilot trên cả 45 datasets với status rõ.
- **C2:** shortlist kèm decision record.
- **C3/D:** chạy sâu theo shortlist, xử lý resource censoring và render gallery.
- **E:** lập bảng tổng hợp, quyết định có chứng cứ hoặc `INCONCLUSIVE`.

### 12.3. Definition of Done (DoD)

- [ ] Input manifest chính xác 15 codebooks/45 databases, 70k transactions mỗi bộ; mọi integrity/lineage checks PASS, hoặc có blockers minh bạch và **không** tuyên bố đã hoàn tất scope 45 nếu thiếu.
- [ ] Báo cáo intrinsic codebook (distortion, occupancy, cluster sizes, ARI khi verified, convergence, centroid visualization) cho cả 15.
- [ ] Đầy đủ transaction EDA cơ bản 45 datasets: length/density/empty, support, diversity, region/stripe analysis và figures.
- [ ] B5 class-conditional similarity được thực hiện hậu nghiệm **cho 45 datasets** với verified labels + common balanced pair manifest; có within/between Jaccard, gap, pairwise AUC, classwise/cross-class tables, empty rates và figures. Nếu thiếu labels, ghi `CLASS_LABELS_BLOCKED`, không tuyên bố EDA2-B5 đã hoàn tất và không dùng chỉ số này để chọn cấu hình.
- [ ] Pilot Eclat common tất cả 45 có status và counts chỉ khi complete; có kiểm tra support/anti-monotonicity trên samples/test datasets.
- [ ] Shortlist `(K,seed)` rõ reason codes, giữ cả 3 variants trong deep pilot; không chọn chỉ trên distortion hoặc số itemsets.
- [ ] Deep Eclat các ngưỡng declared, itemset stats theo length/support, closed/maximal khi exact, runtime/memory có environment/censoring; performance repeated khi xếp hạng theo chi phí.
- [ ] Pattern galleries kiểm chứng centroids/patches/ảnh.
- [ ] Comparative report cân nhắc 6 nhóm metrics + intrinsic quality, **B5 hậu nghiệm như diagnostic riêng** và tradeoffs; chọn final `(K,seed,variant)` **hoặc** `INCONCLUSIVE` có lý do.
- [ ] Artifacts xuất đủ, reproducible, configs/logs/checkpoints/read-back; source TC production không bị sửa; không chạy production FIM hoặc refit K-means.

---

## 13. Hướng dẫn coding agent

1. Đọc hai nguồn TC spec và kiểm tra **đúng schema files hiện có**; không giả định filenames/columns binary loader nếu chưa xác nhận.
2. Triển khai module đọc, validator, EDA metrics và Eclat adapter; chỉ orchestrate trong notebooks, tái sử dụng code repository.
3. Thực thi theo thứ tự 00 → A → B (bao gồm B5) → C1 → C2 → C3 → D → E; checkpoint chi tiết và fail-fast khi source sai.
4. **Không tự điều chỉnh ngưỡng minsup, shortlist criteria, encoding definitions hoặc chọn winner để hợp thức hóa kết quả**; mọi deviation phải ghi config, lý do và flag exploratory.
5. Không tạo thêm transactions, sửa codebook, change IDs, đào tạo lại K-means hoặc chạy spatial encoding trong EDA2.
6. Tóm tắt results theo số datasets hợp lệ, codebook metrics, transaction EDA, pilot status/censoring, report và blockers; nếu resource caps ngăn full analysis thì bàn giao đúng trạng thái, không giả hoàn tất.

**End of specification.**

