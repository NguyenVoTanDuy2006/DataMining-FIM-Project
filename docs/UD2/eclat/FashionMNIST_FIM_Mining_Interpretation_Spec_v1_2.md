# SPEC v1.2 — Fashion-MNIST Frequent Visual Itemset Mining & Downstream Interpretation

**Tên ngắn:** Fashion-MNIST FIM — Production Mining, Pattern Analysis & Application 2  
**Trạng thái:** Đặc tả triển khai (chưa phải báo cáo kết quả thực nghiệm)  
**Phiên bản:** 1.2 — 19/11/2026  
**Thay đổi v1.2:** Khóa thứ tự P1 smoke → P2 production MCP, supervisor/worker và recovery, enum status duy nhất, kiểm chứng đầu vào 80%/60%, quy tắc chọn và review patterns, nghiệm thu theo từng trục. Giữ nguyên API Eclat và sáu ngưỡng v1.1.  
**Đối tượng:** Coding agent / thành viên phụ trách Ứng dụng 2 (Fashion-MNIST)  
**Tài liệu căn cứ:** `itemset.md` (Chương 3, Ứng dụng 2; các yêu cầu kỹ thuật), `TC_Transaction_Construction_Spec_v2.md`, `TC6_Spatial_Encoding_Extension_Spec_v1.md` (định nghĩa S0). Notebook `FashionMNIST_K32_seed123_S0_FIM_Input_Preparation.ipynb` là **tham khảo tùy chọn**, không phải đầu vào bắt buộc.  
**Quan hệ với EDA2:** Không phải EDA2, không chọn lại codebook; sử dụng quyết định cấu hình **đã được nhóm chốt**.

> **Mục tiêu duy nhất:** Dùng transaction database Fashion-MNIST đã tồn tại để chạy **Eclat do nhóm cài đặt**, phân tích các frequent visual itemsets tìm được, truy vết chúng đến ảnh/patches, và chứng minh hoặc thảo luận cụ thể giá trị của những patterns này cho phân tích ảnh hay làm đặc trưng của các mô hình khác.

---

## 0. Các quyết định đã khóa

| Thuộc tính | Giá trị / quy tắc | Mức độ |
|---|---|---|
| Dataset | Fashion-MNIST, tập 70.000 ảnh đã sử dụng trong TC | **LOCKED** |
| Construction | T2 foreground-filter + TC1–TC7 đã thực hiện | **LOCKED** |
| Codebook backend | **B0** — `raw_full_batch_kmeans` | **LOCKED** |
| `K` | **32** | **LOCKED** |
| `seed` | **123** | **LOCKED** |
| Transaction encoding | **S0 — Binary Bag of Visual Words** | **LOCKED** |
| Input production | `results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl` | **LOCKED** |
| Số giao dịch | **70.000**, người dùng xác nhận đã kiểm định | **LOCKED** |
| Giao dịch rỗng | **0**, người dùng xác nhận | **LOCKED** |
| Item IDs | visual words nguyên từ 1 đến 32; mỗi transaction là tập không lặp | **LOCKED** |
| Engine mining | **Eclat do thành viên khác đã triển khai**: `EclatFIM.mine(transactions, min_count)` | **LOCKED** |
| Ngưỡng minsup chính thức | **80%, 60%, 40%, 20%, 10%, 5%** | **LOCKED** |
| Quy tắc support | `support_count(X) = số ảnh chứa X`; mẫu số = 70.000 | **LOCKED** |
| Nguồn labels | Chỉ được dùng *sau khi mining* để giải thích/evaluate | **LOCKED** |

### 0.1. Ranh giới phạm vi tuyệt đối

**PHẢI LÀM:** tích hợp (chỉ gọi, không sửa) Eclat, chạy thực nghiệm trên 6 ngưỡng, lưu itemsets + support + tình trạng chạy, phân tích kết quả, minh họa bằng ảnh thật, phân tích ứng dụng và viết phần báo cáo Ứng dụng 2.

**KHÔNG LÀM:**

1. Không cài lại, sửa, tối ưu, refactor, benchmark lại hay thay đổi test của **Eclat core** mà thành viên khác phụ trách (giai đoạn 02 và 03 đã hoàn thành).
2. Không so sánh lại 15 codebooks/60 datasets, không tiếp tục EDA2, không chọn lại `K`, seed hay encoding.
3. Không chạy lại TC1–TC7, không fit K-means, không mã hóa lại transactions, không thay đổi hoặc ghi đè file input hay artifacts gốc.
4. Không dùng S1/S3/S6-B trong thực nghiệm chính này; không trộn các namespaces item.
5. Không chạy SPMF thay cho engine nhóm. SPMF/correctness benchmark thuộc phạm vi của thành viên khác.
6. Không bắt buộc huấn luyện thêm mô hình học máy; **bắt buộc** làm rõ ứng dụng và bằng chứng phân tích ảnh thật.

API `EclatFIM.mine(transactions, min_count)` đã được thành viên phụ trách cung cấp. Nếu có vấn đề khi gọi thực tế (module chưa load, khác phiên bản, xử lý deadline/giới hạn chưa rõ), chỉ tạo **adapter/runner ngoài thư mục Eclat core** hoặc trao đổi với thành viên phụ trách; không âm thầm tự sửa thuật toán. Khi không thể tích hợp, đánh dấu `BLOCKED`.

---

## 1. Câu hỏi nghiên cứu và bằng chứng cần trả lời

**RQ1 — Mining behavior:** Số lượng, phân bố độ dài và support của frequent itemsets thay đổi thế nào khi minsup giảm từ 80% xuống 5%? Chi phí chạy và kích thước kết quả thay đổi thế nào?

**RQ2 — Visual meaning:** Những tổ hợp visual words phổ biến nào được nhận diện và bằng chứng từ centroids, retained patches, supporting images cho phép diễn giải chúng ở mức nào? Những giới hạn nào phát sinh vì S0 không lưu quan hệ không gian?

**RQ3 — Image data analysis:** Những patterns tìm được giúp khám phá, so sánh và truy hồi ảnh thế nào? Có patterns phổ biến toàn cục, patterns được làm giàu ở một số lớp (class-enriched), hoặc patterns chia sẻ giữa nhiều lớp không?

**RQ4 — Downstream applicability:** Làm thế nào biến frequent patterns thành features để dùng với mô hình học máy khác? Lợi ích giả định, giới hạn và phương pháp kiểm chứng là gì? **Không tuyên bố cải thiện classification nếu chưa chạy đối chứng.**

**Đầu ra bắt buộc:** bảng sáu ngưỡng + tình trạng, tập itemsets chính xác của mọi lần chạy `COMPLETED`, charts/phân tích, gallery pattern có witnesses hợp lệ, thống kê theo lớp nếu có labels, use-case image retrieval mô tả bằng ví dụ thực, thảo luận feature engineering và reproducibility.

---

## 2. Input contract & provenance

### 2.1. Input mining duy nhất

```text
results/fashion/tc/tc6_configs/S0/
└── FashionMNIST_T2_S0_B0_K32_seed123/
    └── transactions.jsonl
```

Mỗi dòng JSONL là một transaction (theo chuẩn TC hiện có, có các trường như `tid`, `image_id`, `items`). Để mining, **chỉ lấy `items`**, không đưa `image_id`, `tid`, nhãn hay `split` thành items. `tid` dùng truy vết transaction; `image_id` dùng tìm ảnh gốc. **TID không được mặc định bằng image ID** khi chưa đối chiếu mapping chính thức.

**Đã xác nhận và không phải làm lại TC integrity:** `N=70_000`, empty transactions `=0`. Chỉ giữ các sanity assertions rẻ (nguồn path đúng, N đúng khi nạp, các item hợp lệ/unique, dòng không lỗi JSON) nhằm tránh chạy nhầm source; không làm lại validation pipeline TC7.

### 2.2. Nguồn phục vụ giải thích (không tham gia mining)

- `codebook.bin`: 32 centroids, giải mã mỗi centroid thành patch 4×4 theo quy tắc lưu column-major của TC.
- `patch_assignments.csv`: mapping ảnh/patch/vị trí với visual word; dùng để highlight **witness patches** trên ảnh.
- `tid_image_mapping.csv` hoặc metadata tương đương: join kết quả Eclat với ảnh gốc.
- `image_metadata.csv` và nguồn Fashion-MNIST gốc: lấy label và train/test split nếu có.
- `config_snapshot.toml`, `integrity_report.toml` (nếu cần ghi provenance): chỉ đọc.

**Không giả định** mọi artifact phụ nằm trong đúng một thư mục nếu chưa kiểm tra filesystem; cho phép cấu hình source paths riêng biệt. Khi không đọc được một artifact phụ, **không chặn mining**; đánh dấu đúng phần interpretation bị `BLOCKED_MISSING_ASSET` (không tạo ảnh hay tọa độ giả).

### 2.3. Input Preparation là tài liệu tham khảo **tùy chọn**

Có thể tận dụng loader từ `FashionMNIST_K32_seed123_S0_FIM_Input_Preparation.ipynb` nếu notebook này **thực sự có trong worktree/runtime**. Nếu không thấy, **tự triển khai loader JSONL tối thiểu ở module/notebook FIM được giao**, đọc trực tiếp `items` → `Vector{Vector{Int}}`; không chặn pipeline và không tạo lại toàn bộ Input Preparation notebook.

Notebook tham khảo có thể dùng dải minsup cũ `[10%,7%,5%,3%,2%,1%,0.5%]`; dải này **không có hiệu lực** trong thí nghiệm chính thức. Không sửa notebook tham khảo ngoài phạm vi nếu không cần thiết.

### 2.4. API Eclat đã được xác nhận — **bắt buộc dùng trực tiếp**

Theo thông tin nhóm cung cấp, API chính thức là:

```julia
# Sau khi nạp các transactions từ JSONL thành Vector{Vector{Int}}
# (chỉ lấy items; giữ nguyên mỗi dòng/giao dịch một phần tử vector)
min_count = 56000  # minsup = 80% × 70_000; ví dụ lần chạy đầu
patterns = EclatFIM.mine(transactions, min_count)
```

**Input contract:**

- `transactions`: vector giao dịch; mỗi phần tử là vector ID item số nguyên dương. Giao dịch rỗng hợp lệ (`Int[]`); transactions trùng nhau là các giao dịch độc lập.
- `min_count`: **số lượng giao dịch tuyệt đối** (`Int`), **không phải fraction/percent**. Với N=70.000 dùng chính xác các số ở §4.1, không truyền `0.8`, `80`, hoặc tự làm tròn sai.
- Item lặp bên trong một giao dịch chỉ đóng góp **một lần** cho support. Dữ liệu S0 hiện tại đã unique items; loader vẫn không được nhân số lần lặp thành support.
- `max_length`, `deadline`, `max_itemsets` là **giới hạn tùy chọn** mà core có thể nhận. Không sử dụng trong **production full run** trừ khi được ghi nhận như run bị giới hạn. Kiểu dữ liệu/ý nghĩa chính xác của `deadline`, cơ chế thông báo dừng, và exception của giới hạn **phải xem code/interface của thành viên phụ trách** trước khi kích hoạt; không suy đoán rằng `deadline` là số giây hay timestamp.

**Output contract:**

```julia
# Kiểu do nhóm công bố:
# Dict{Tuple{Vararg{Int}}, Int}
# Ví dụ minh họa:
# (1,) => 3, (2,) => 2, (3,) => 2, (1,2) => 2, (1,3) => 2
```

- **Key**: tuple item IDs **tăng dần**; phải unique và không rỗng; **value**: exact support count trong số transactions có chứa itemset.
- **Không giả định** hàm tự ghi file, tự trả TID-sets, tự tạo log runtime hoặc thông báo trạng thái thông qua một tuple thứ hai. Runner phải serialize `Dict` sang JSONL/CSV, tính runtime, ghi provenance và tự xây supporting TIDs cho phần visualization khi cần.
- `Dict` **không bảo đảm thứ tự lặp**: để xuất báo cáo/file reproducible, sort keys theo `(length(itemset), itemset)` trước khi ghi; không phụ thuộc thứ tự `pairs(patterns)`.

**Ví dụ chuẩn hóa sau khi có `patterns`:**

```julia
ordered_keys = sort!(collect(keys(patterns)); by=x -> (length(x), x))
for key in ordered_keys
    cnt = patterns[key]
    @assert issorted(collect(key)) && length(unique(key)) == length(key)
    @assert min_count <= cnt <= length(transactions)
    # Xuất: items = collect(key), length = length(key),
    # support_count = cnt, support_fraction = cnt / length(transactions)
end
```

**Loader requirements:** tạo đúng 70.000 phần tử `Vector{Int}` (hoặc kiểu vector tương thích thực tế), theo đúng thứ tự 70.000 dòng JSONL, không đẩy `tid`, `image_id`, nhãn vào items, không bỏ giao dịch, và giữ mapping từ vị trí Julia 1-based của dòng tới TID/image_id để truy vết. Input hash lấy từ chính `transactions.jsonl`, không coi `transactions_spmf.txt` là nguồn mining.

**Lưu ý về tính hoàn tất:** `Dict` chỉ chứa patterns/support, **không có metadata chứng minh run đã duyệt xong hay bị cắt**. Runner chỉ được gán `COMPLETED_FULL`/`COMPLETED_ZERO` khi `mine` kết thúc bình thường **và** không có bất cứ giới hạn enumerate/deadline/length nào đã kích hoạt, hoặc core cung cấp tín hiệu kiểm chứng rõ ràng giới hạn không hề cắt kết quả. Nếu có giới hạn được sử dụng mà không xác định được liệu chúng đã tác động hay chưa, đánh dấu `COMPLETION_UNVERIFIED` (không báo tổng pattern chính xác); nếu có ngoại lệ/dừng, phân loại theo bằng chứng thực tế. Không lấy `length(patterns) < max_itemsets` làm chứng minh tuyệt đối rằng không có truncation khi hành vi core chưa được xác minh.

---

## 3. Kiến trúc triển khai và thứ tự chạy

Pipeline trong phạm vi triển khai:

```text
transactions.jsonl  (read-only, N=70,000)
        │
        ▼
FIM-00 — Engine Integration / Data Handoff (no core edits)
        │
        ▼
FIM-01 — Six-minsup Mining Runs (group Eclat)
        │
        ▼
FIM-02 — Pattern Statistics & Representative Selection
        │
        ▼
FIM-03 — Visual Interpretation (centroids / witnesses / images)
        │
        ▼
FIM-04 — Dataset Insights & Downstream Applications
        │
        ▼
FIM-05 — Report / Reproducibility / Handoff
```

**Đề xuất notebooks** (không bắt buộc thay đổi repo cấu trúc có sẵn):

1. `FIM_Mining_Experiments.ipynb` — FIM-00, FIM-01, FIM-02. **Không** vẽ gallery lớn hay load toàn bộ ảnh không cần thiết.
2. `FIM_Visual_Interpretation.ipynb` — FIM-03, FIM-04; **chỉ đọc** các kết quả mining đã được lưu, không chạy lại Eclat để refresh biểu đồ/galleries.
3. Notebook Input Preparation **nếu hiện diện trong worktree thì giữ nguyên** và tùy chọn tái sử dụng loader JSONL đã kiểm chứng; nếu vắng mặt thì đọc trực tiếp JSONL bằng loader FIM mới. **Không cần chuyển SPMF để gọi API hiện tại**.

**Nguyên tắc code:** reuse các modules/mã nhóm đã có; notebooks điều phối, xuất bảng/figures và giải thích ngắn gọn từng bước. Có thể bổ sung module `src/fashion_fim/` cho parsing, report/visualization và adapter, **không chỉnh** `src/algorithm/` hay modules Eclat đã giao cho thành viên khác.

---

## 4. FIM-01 — Thiết kế thực nghiệm mining (CHỐT)

### 4.1. Chính xác sáu minsup chính thức

| Thứ tự chạy | `minsup_fraction` | `minsup_percent` | `minsup_count` (N=70.000) |
|---:|---:|---:|---:|
| 1 | **0.80** | **80%** | **56.000** |
| 2 | **0.60** | **60%** | **42.000** |
| 3 | **0.40** | **40%** | **28.000** |
| 4 | **0.20** | **20%** | **14.000** |
| 5 | **0.10** | **10%** | **7.000** |
| 6 | **0.05** | **5%** | **3.500** |

**Tính support:**

\[
\operatorname{supp}_{\mathrm{cnt}}(X)
= |\{t\in D:X\subseteq t\}|,\qquad
\operatorname{supp}_{\mathrm{frac}}(X)=\frac{\operatorname{supp}_{\mathrm{cnt}}(X)}{70{,}000}.
\]

\[
\operatorname{minsup}_{\mathrm{cnt}}=\left\lceil 70{,}000\cdot\operatorname{minsup}_{\mathrm{frac}}\right\rceil.
\]

Với grid đã chốt, ưu tiên lưu/passing **support count integer** trong runner để tránh sai khác do floating point, và quy đổi fraction nhất quán.

**Không tự ý đổi thành các ngưỡng nhỏ hơn (1%, 0,5%) hoặc chèn thêm ngưỡng**. Nếu 80%/60% không có patterns hoặc 5% quá nặng, vẫn giữ các dòng kết quả/status tương ứng; mọi nghiên cứu bổ sung phải có quyết định riêng, bảng tách biệt với grid chính.

### 4.2. Tính đầy đủ của khai thác

- Mục tiêu là **frequent itemsets đầy đủ** tại mỗi minsup được hoàn thành, **không giới hạn `max_itemset_length`** trong lần chạy chính nếu thuật toán không bắt buộc làm vậy.
- Nếu runtime/memory/output lớn: được phép dừng an toàn theo budget đã khai báo; **không được** coi số itemsets đang ghi dở là số đầy đủ.
- Phân biệt **giới hạn trình bày** (`max_display_patterns`) với **giới hạn enumeration** của thuật toán. Chỉ giới hạn trình bày thì vẫn có thể báo total exact nếu toàn bộ khai thác hoàn tất và có số đếm được xác nhận.
- Nếu `max_length` hoặc `max_itemsets` được truyền vào Eclat và giới hạn có tác động, ghi `LENGTH_CAPPED`/`ITEMSET_CAPPED`; không gắn `COMPLETED_FULL`. Với `deadline`, chỉ phân loại `TIMEOUT` khi có bằng chứng deadline thực sự được chạm. Trường hợp return bình thường nhưng không có tín hiệu đầy đủ từ API giới hạn, ghi `COMPLETION_UNVERIFIED`, không suy luận từ số entry của Dict.
- **Không bắt buộc** toàn bộ sáu ngưỡng hoàn tất bằng mọi giá khi hardware không đủ, nhưng bắt buộc báo trung thực kết quả và trạng thái từng ngưỡng.

### 4.3. Một enum duy nhất cho `mining/runs.csv`

**Per-run `status` ENUM** (giá trị chính thức, không phát sinh alias ngoài danh sách):

| Status | Điều kiện xác lập | Có được báo `total_frequent_itemsets` exact? |
|---|---|---|
| `NOT_RUN` | Đã tạo hàng kế hoạch nhưng chưa bắt đầu worker | Không |
| `COMPLETED_FULL` | Worker return bình thường, không có giới hạn cắt, serialize/read-back/audit PASS, Dict không rỗng | Có |
| `COMPLETED_ZERO` | Như trên nhưng Dict rỗng | Có: **0** |
| `TIMEOUT` | Supervisor/watchdog ghi nhận vượt wall-time và chấm dứt worker, hoặc tín hiệu deadline rõ ràng | Không |
| `MEMORY_LIMIT` | Có bằng chứng vượt giới hạn RAM/OOM được xác minh; không suy đoán từ exit code bất kỳ | Không |
| `OUTPUT_LIMIT` | Supervisor chặn do vượt giới hạn dung lượng xuất đã khai báo | Không |
| `ITEMSET_CAPPED` | `max_itemsets` hoặc cap enumeration đã kích hoạt, có exception/marker nhận diện được | Không |
| `LENGTH_CAPPED` | `max_length` được dùng và không có chứng minh độc lập kết quả đầy đủ | Không |
| `COMPLETION_UNVERIFIED` | Có Dict nhưng thông tin giới hạn/hoàn tất chưa đủ; không được coi full | Không |
| `INVALID_OUTPUT` | Worker return nhưng schema, exact supports, read-back, cross-threshold hoặc expected checks sai | Không |
| `FAILED` | Exception/exit failure khác, xác định được nguyên nhân | Không |
| `UNKNOWN_INTERRUPTED` | Worker/supervisor chết hoặc bị kill không rõ nguyên nhân và không có marker hoàn tất hợp lệ | Không |
| `BLOCKED` | Không thể khởi chạy vì thiếu input, API, kernel, MCP, resource policy ... | Không |

Các nguyên nhân chi tiết nằm ở **`reason_code`** (không tạo thêm status): `MCP_UNAVAILABLE`, `KERNEL_UNAVAILABLE`, `INPUT_INACCESSIBLE`, `ENGINE_IMPORT_FAILED`, `BUDGET_NOT_ENFORCEABLE`, `MISSING_ASSET`, `MISSING_LABELS`, `UNEXPECTED_RESULT`, `SUPERVISOR_LOST`, v.v. `reason_code` là chuỗi có định nghĩa trong manifest; có thể rỗng nếu không có blocker.

**Nullability:** với `COMPLETED_ZERO`, `total_frequent_itemsets=0`, `max_itemset_length=0`, `output_size_bytes=0` cho JSONL rỗng **0 dòng** (có thể xuất file rỗng và checksum). Với `COMPLETED_FULL`, total dương và max length ≥1. Với mọi status khác, `total_frequent_itemsets` và `max_itemset_length` là **NA**; `observed_partial_itemsets` nếu cần đặt cột **riêng**, không trộn vào exact total. `runtime_seconds`, `peak_rss_mb` chỉ điền khi đo được đúng process; khác thì NA.

**Guardrails đã được người dùng báo từ phép đếm singleton trên chính JSONL** (agent phải xác minh độc lập trước khi coi là bằng chứng):

- `max_singleton_support=48_922` nên tại **80% (56_000)** kết quả đúng là `COMPLETED_ZERO`, count=0 nếu chạy đầy đủ.
- Tại **60% (42_000)** có **đúng 2 frequent singleton items**. `EclatFIM.mine` hoàn tất phải trả đúng hai key độ dài 1 tương ứng sau khi xác minh từ JSONL. **Không khẳng định tổng patterns ở 60% là 2**: nếu hai singleton đồng xuất hiện ≥42_000 lần, pair của chúng cũng có thể frequent.
- Nếu kiểm tra singleton độc lập không ra các giá trị trên, tạm dừng công bố và kiểm tra **hash/path/loader**; không sửa engine để ép khớp. Nếu đầu vào được xác nhận đúng mà output Eclat mâu thuẫn, dùng `INVALID_OUTPUT`.

### 4.4. Ngân sách, supervisor/worker và cơ chế ngắt

1. **P1 chỉ tạo loader, adapter, supervisor/worker scripts và chạy smoke trên toy dataset**, kiểm thử đường output `COMPLETED_ZERO`, lỗi và recovery. **Không** chạy cả sáu ngưỡng production trong P1, không cần sáu hàng hoàn tất ở đây (có thể tạo 6 hàng `NOT_RUN` để khởi tạo).
2. **P2 mới thực thi production một lần** qua MCP, từ Julia kernel sạch. Notebook phải điều phối **supervisor ngoài kernel**, và supervisor chạy **worker Julia riêng cho mỗi ngưỡng** (vẫn `EclatFIM.mine(transactions,min_count)` của nhóm). Mục đích: notebook kernel chết không tự xóa chứng cứ trạng thái và supervisor có thể chủ động dừng worker. Nếu runtime không hỗ trợ tiến trình độc lập/supervision hoặc phép đo/enforcement như đã khai báo, đánh dấu `BLOCKED` với `reason_code=BUDGET_NOT_ENFORCEABLE`, không ngụy tạo enforce.
3. Trước P2, khai báo và ghi vào config: `wall_time_seconds_per_run`, `memory_limit_mb_per_worker`, `output_limit_bytes`, runtime/kernel environment, cách **thực sự enforce** từng budget (OS ulimit/cgroup/process monitor+kill hoặc tương đương). Không có giá trị mặc định được suy ra từ spec; agent phải chọn theo tài nguyên thực tế và ghi thành số cụ thể **trước khi chạy**. Không sửa chính sách giữa các ngưỡng mà không tạo một run revision mới.
4. Notebook MCP **khởi động/kiểm tra supervisor và đọc persisted status theo đợt**; không bắt notebook mở một cell chờ vô hạn. Supervisor ghi `started_at`, `last_heartbeat`, `pid`, `deadline_at`, exit signal/cause, `end_at`, resource observations và `reason_code` vào file sidecar của run. Ghi trạng thái ban đầu trước khi spawn worker; **atomic write** (temp file rồi rename) sau mỗi chuyển trạng thái. Worker chỉ xuất `Dict` sau khi `mine` return; output tạm không được đặt tên exact.
5. Khi vượt wall-time, supervisor kill worker và chỉ ghi `TIMEOUT` nếu có bằng chứng watchdog trigger. Vượt memory: `MEMORY_LIMIT` chỉ khi có evidence rõ ràng (counter/OS OOM). Vượt output bytes: `OUTPUT_LIMIT`. **Kernel chết** nhưng supervisor/worker vẫn chạy hợp lệ: dùng MCP reconnect/restart và **reconcile file status**; không chạy lại threshold completed. Supervisor chết/worker mất mà không có final evidence: `UNKNOWN_INTERRUPTED` và phải xử lý orphan worker bằng biện pháp an toàn đã khai báo.
6. **Semantics core theo thông tin từ người kiểm tra (xác nhận lại bằng mã thật trước dùng):** `deadline` là **absolute Unix timestamp so với `time()`**, không phải duration; `max_itemsets` **throw error** khi vượt cap; `max_length` có thể **return Dict đã bị giới hạn độ dài mà không báo incomplete**. Vì vậy production full ưu tiên gọi **chỉ 2 positional args**, để **supervisor bên ngoài** enforce resource limits. Nếu cố tình bật optional limits, ghi lại chính xác keyword/effective value và trạng thái `ITEMSET_CAPPED`/`LENGTH_CAPPED`/`COMPLETION_UNVERIFIED` theo bằng chứng; không đánh dấu full mặc định.
7. Sau mỗi worker hoàn thành: kiểm tra Dict keys/support, soát line counts, xác minh persisted JSONL/read-back, guardrails độc lập, audit cross-threshold khi có hai completed runs. **Chỉ sau khi audit PASS** mới atomic rename output tạm thành `minsup_XX.jsonl`, ghi final status `COMPLETED_FULL/ZERO`, checksum và cập nhật `runs.csv` chính thức. `runs.csv` phải luôn đọc được **đúng sáu hàng** sau P2, mỗi threshold một hàng, không phải đợi notebook kết thúc mới sinh bảng.
8. Nếu MCP không khả dụng, **không nói đã chạy qua MCP**. Giữ code/smoke evidence có thật; `BLOCKED`/`reason_code=MCP_UNAVAILABLE` cho các ngưỡng chưa chạy; phần output được tạo bằng terminal (nếu có và được phép) ghi riêng, **không được coi là nghiệm thu MCP**.

### 4.5. Kiểm tra đầu ra ở tầng ứng dụng (không tái làm correctness của core)

- `N=70_000`, item IDs 1–32, tính **độc lập** support 32 singleton từ loader và so với guardrails ở §4.3; ghi provenance/hash, không dựa vào dict Eclat làm chuẩn độc lập.
- Đối với completed runs: itemsets không rỗng (trừ completed-zero), items sorted/unique 1..32, integer support trong `[min_count, 70000]`, JSONL line-count = `length(patterns)`.
- Với các completed thresholds a>b: frequent sets(a) ⊆ frequent sets(b); cùng itemset phải có cùng support count. Trượt kiểm tra → `INVALID_OUTPUT`, không công bố exact totals.
- Audit deterministic một tập patterns (~20 nếu có) bằng scan trực tiếp `transactions`; ghi selection seed, sample IDs và mismatch count. Không đụng vào tests Eclat core.
- `Dict()` hoàn tất ở 80% là **đúng theo baseline singleton đã báo**, nhưng phải chứng minh input support độc lập; tại 60% output **phải có hai singleton** đúng IDs, còn số pairs phụ thuộc dữ liệu thực tế.

### 4.6. MCP evidence, khả năng phục hồi và một lần chạy production

- MCP notebook/Jupyter: **khám phá tên công cụ đang có thật**, chọn Julia kernel, restart, chạy cells P2, lưu và reopen notebook; ghi MCP tool/server, kernel/session, timestamp, cell execution status và artifact paths vào `report/mcp_execution_log.md`. Không ghi giả API tool hay nhầm chạy terminal với MCP.
- Khi notebook/kernel crash: sau khi MCP reconnect, đọc supervisor sidecars, đối chiếu `pid`, heartbeat, checksum và final marker; chỉ **resume ngưỡng chưa completed**, không chạy lại cả sáu theo mặc định. Nếu không rõ tiến trình cũ đang chạy, không spawn worker trùng ngưỡng cho đến khi được reconcile.
- Kiểm thử recovery trong **P1 smoke** bằng worker giả/nhỏ có thể được stop; không làm crash/kill thật kernel production để thử. Nếu không thể kiểm tra năng lực giám sát an toàn, đánh dấu test tương ứng `BLOCKED`, không tự khẳng định recovery đã chạy.
- Notebook interpretation chỉ đọc mining output đã lưu; MCP chạy nó trong phiên riêng từ kernel sạch sau khi đã có ít nhất một pattern hoàn chỉnh. Các output không có pattern thì phải được xử lý như kết quả 0, không bịa gallery.

## 5. FIM-02 — Pattern Statistics & Representative Selection

### 5.1. Thống kê bắt buộc

Đối với mỗi ngưỡng `COMPLETED_FULL` hoặc `COMPLETED_ZERO`:

- Tổng số frequent itemsets (gồm length ≥1), `count_by_length` và `max_itemset_length`.
- Support fraction distribution: min/Q25/median/Q75/max hoặc histogram trên tập đã mine đủ; với empty output báo rõ NA và count=0.
- Biểu đồ **minsup giảm vs số itemsets**; chú thích log-scale nếu dùng và xử lý count=0 hợp lý.
- Biểu đồ **minsup vs runtime**; không so sánh kết quả resource-censored như một completed runtime bình thường (đánh dấu timeout rõ).
- Heatmap/stacked bar **phân bố độ dài** theo minsup; không so với các ngưỡng chưa hoàn tất như thể đủ itemsets.
- Tỷ lệ singleton / pair / length≥3; mô tả các mức minsup có những mẫu dài hơn.

**Phân biệt bắt buộc:** support fraction của một itemset là tỷ lệ **ảnh** chứa nó, không phải tỷ lệ patches; trục hình phải ghi rõ `minsup`, `#itemsets`, `seconds`, `support fraction`.

### 5.2. Không đánh giá dựa trên số lượng patterns đơn thuần

- Nhiều frequent itemsets có thể phản ánh transactions dày hoặc combinations dư thừa; không đánh giá “nhiều hơn = ý nghĩa hơn”.
- **Không** xem cặp/tập items có support cao là bằng chứng về vị trí/tương quan không gian; S0 chỉ cho biết cùng xuất hiện trong ảnh.
- Phân tích optional về độ dư thừa (support equality, containment, top-k representative diversity). `closed` hoặc `maximal` chỉ được gắn nhãn khi tính theo định nghĩa chính xác và có dữ liệu cần thiết; **không** suy ra closed/maximal từ top-k hay output bị giới hạn.
- Nếu dùng lift so với giả thuyết independence của các items: báo rõ đó là **thước đo tham khảo** không chứng minh quan hệ nhân quả hoặc hình học.

### 5.3. Master pattern catalog

Cùng một frequent itemset xuất hiện ở nhiều minsup. **Không nhân đôi** khi tính số unique patterns xuyên các ngưỡng. Tạo `pattern_id` ổn định từ canonical sorted item IDs, lưu support count/fraction và các minsup mà pattern được tìm thấy (chỉ dùng completed outputs).

`master_patterns.csv` hoặc `.jsonl`: `pattern_id`, `items`, `length`, `support_count`, `support_fraction`, `observed_at_minsup`, `source_run_ids`.

### 5.4. Protocol chọn representative patterns có thể tái lập

**Mục tiêu tối đa 16, chấp nhận 12–20 nếu người chạy khai báo trước và đủ dữ liệu.** Chọn trên **master catalog của các completed runs**, sau khi xác định support và deduplicate. Thuật toán:

1. **Nguồn:** unique canonical itemsets, chỉ từ `COMPLETED_FULL` (completed-zero không có candidates). Sort ổn định theo `(length, -support_count, items lexicographic)`; ghi input hash, selection seed=42, catalog checksum.
2. **Stratify:** length buckets `1`, `2`, `>=3` khi có; support buckets **low / mid / high** theo các quantiles tertile của `support_count` trên eligible catalog. Các bucket rỗng được bỏ qua, ties ở ranh giới dùng quy tắc xếp ổn định/quantile đã khai báo (không chia ngẫu nhiên).
3. **Chọn round-robin** giữa các ô (length × support), ưu tiên candidate xếp hạng ổn định và cho phép đảo ưu tiên support trong bucket nếu cần diversity. Mỗi itemset mới phải có **Jaccard trên item IDs ≤0.80** với mọi itemset đã chọn (trừ singleton khác ID vốn J=0). Nếu quá ít candidates, ghi nguyên nhân và có thể **nới ngưỡng một lần lên 0.90**; phải lưu phiên bản và ngưỡng thực tế.
4. **Dừng:** đạt target hoặc hết candidates; không ép đủ 12 khi data không có. Nhãn class chỉ dùng hậu nghiệm để bình luận; không lọc lựa dựa trên test labels hay ép có đủ ba kiểu common/enriched/cross-class.
5. Ghi `selection_order`, `support_bucket`, `length_bucket`, `diversity_max_jaccard`, `rule_version`, `selection_seed`, `selection_notes` trong `representative_patterns.csv`. Khi tie, dùng `items lexicographic` để kết quả không phụ thuộc thứ tự lặp Dict.

**Acceptance:** cùng input/master catalog + policy phải cho ra cùng danh sách itemsets; không dùng gallery đẹp để sửa lại selection mà không lưu revision. Việc *tự động chọn pattern* khác với *con người đánh giá ý nghĩa thị giác* ở §6.3.

## 6. FIM-03 — Visual Pattern Interpretation

### 6.1. Giải mã pattern

Với mỗi `pattern_id`:

1. Lấy item IDs đã sort; tra đúng codebook **B0/K32/seed123** (không dùng nhầm seed hoặc K khác).
2. Hiển thị 4×4 centroid patch cho từng visual word; áp dụng đúng quy tắc reshape column-major (không transpose nhầm).
3. Lấy một tập **real patch exemplars** gần các centroids nếu `patch_assignments.csv`/raw pixels cho phép; nêu rõ đây là patches thật hay centroid tổng hợp.
4. Tìm supporting TIDs bằng kiểm tra `X ⊆ transaction.items`, join sang image IDs qua mapping authoritative; tính lại support với các ví dụ có chọn.
5. Từ mỗi supporting image, đánh dấu **các patches thực tế** có assignments tương ứng từng word. Một word có thể xuất hiện ở nhiều vị trí; highlight đúng những positions được ghi nhận, không tùy ý suy đoán.
6. Xem vài ảnh không chứa đầy đủ X như contrast examples nếu có, cùng cách chọn mẫu.
7. Ghi nhận những gì ảnh **thật sự cho thấy**, kể cả khi không thể gán mô tả ngữ nghĩa nhất quán.

### 6.2. Gallery minh họa bắt buộc

Cho mỗi pattern được chọn, tạo **pattern card** gồm:

- Canonical itemset, support count/fraction, length và minsup xuất hiện.
- Centroid thumbnails + actual patch exemplars (nếu có).
- Ít nhất vài supporting images với highlight witness patches; có thể lấy mẫu cố định bằng seed và lựa chọn đa dạng labels, **không** chỉ hiển thị một lớp nếu pattern phổ biến nhiều lớp.
- Ít nhất một contrast image nếu tồn tại.
- Một caption ngắn: đặc điểm quan sát, độ nhất quán, bất định và giới hạn diễn giải.

Có thể lưu `pattern_gallery/` dạng PNG/SVG/PDF tùy renderer. **Không dùng ảnh tự tạo, ảnh stock hoặc patch giả làm chứng cứ thực nghiệm.** Khi ảnh nguồn không sẵn có, phần gallery phải báo thiếu chứ không bịa ví dụ.

### 6.3. Annotation, reviewer và trạng thái nghiệm thu

Gallery tự sinh (centroids, supporting TIDs, patch witness, ảnh thật) **chỉ chứng minh rendering và provenance**, không được tự nhận `visual_coherence=2` hoặc “đã được reviewer duyệt”.

**`pattern_annotations.csv` schema bắt buộc**: `pattern_id,decodable,witness_valid,review_status,visual_coherence,interpretation,limitations,reviewer,reviewed_at,evidence_paths`.

- `review_status`: `PENDING_REVIEW` (mặc định), `APPROVED`, `NEEDS_REVISION`, `REJECTED`.
- `visual_coherence`: `NA` khi chưa review; khi được review mới là `0`, `1` hoặc `2` (0: bằng chứng không nhất quán; 1: một phần/mơ hồ; 2: nhất quán ở nhiều ảnh/patches). Rating không bắt buộc ≥1 để phê duyệt: reviewer có thể phê duyệt một **kết luận âm tính có bằng chứng**.
- `reviewer`: người thật được giao kiểm duyệt, ghi định danh trong báo cáo; agent **không tự impersonate** hoặc chấm thay reviewer. `reviewed_at` chỉ ghi thời điểm reviewer thực sự đánh giá; `interpretation` là mô tả quan sát có dẫn chứng.
- `witness_valid` phải PASS cho pattern nào được dùng làm visual evidence; mismatch → `NEEDS_REVISION`/`INVALID_EVIDENCE` trong audit và **không** được công bố như minh họa hợp lệ.
- Khi tất cả galleries đã sinh nhưng còn `PENDING_REVIEW`, hoàn thành kỹ thuật phần gallery được ghi **PASS**, còn phần **manual interpretability review = PENDING**, status chung không thể là `COMPLETE` (xem §9.2). Người dùng/nhóm có thể cung cấp review sau, không cần chạy lại mining.

**Nghiệm thu định tính:** trước khi công bố “visual pattern có ý nghĩa” như kết luận đã xác thực, cần ít nhất một người review thực tế mỗi pattern được đưa vào nhóm bằng chứng; lưu cả kết quả 0/negative findings, không chỉ các pattern đẹp.

### 6.4. Giới hạn nhận thức của S0 — bắt buộc nêu trong báo cáo

- S0 là **binary bag**: không giữ số lần xuất hiện của một visual word trong ảnh và không mã hóa **vị trí hoặc thứ tự**.
- `X={w3,w7,w12}` chỉ có nghĩa: ảnh chứa ít nhất một patch được gán vào từng word trong X.
- Không suy ra các words kề nhau, nằm cùng bộ phận quần áo, tạo một hình dạng hay graph liên thông nếu chưa kiểm tra witnesses.
- Class labels là công cụ **post-hoc** để thống kê/diễn giải, không tham gia tạo items hoặc mining.

---

## 7. FIM-04 — Phân tích dữ liệu hình ảnh & downstream application

### 7.1. Phần **bắt buộc triển khai thực tế**: class-conditional insights

**Input:** các frequent patterns đã được xác nhận; `tid_image_mapping.csv` và labels hợp lệ (được xác minh join 1:1 với images). Không dùng nhãn để chọn itemset **trong mining**.

Với mỗi pattern X, lớp c:

\[
P(X) = \frac{n(X)}{70{,}000},\qquad
P(X\mid c)=\frac{n(X,c)}{N_c},\qquad
\operatorname{enrichment}(X,c)=\frac{P(X\mid c)}{P(X)}.
\]

- `N_c`: số ảnh thực tế thuộc lớp c; **không giả định 7.000** nếu metadata không xác minh.
- `n(X,c)`: số ảnh thuộc c chứa toàn bộ items của X.
- `enrichment > 1` cho biết pattern xuất hiện trong lớp c **tương đối thường hơn mức nền**; không có nghĩa là pattern đặc hữu hoặc có tác dụng phân loại tốt.
- Chỉ tính khi mẫu số >0; báo pattern có support thấp và kích thước mẫu nhỏ; không dùng enrichment một mình để gắn nhãn ngữ nghĩa.

**Outputs:**

- `pattern_class_support.csv`: `pattern_id,class_id,N_c,n_X_c,p_X_given_c,p_X,enrichment` (chọn toàn bộ catalog khi chi phí hợp lý hoặc representative patterns khi quá lớn, nêu rõ phạm vi).
- Heatmap `P(X|c)` cho representative patterns; có thể kèm enrichment để đối chiếu.
- **Ba kiểu phân tích**, nếu dữ liệu có minh chứng: `common across dataset`, `class-enriched`, `cross-class`. Không bắt buộc phải có cả ba kiểu nếu không thấy bằng chứng.
- Một đoạn thảo luận rằng **frequent ≠ discriminative**: pattern cực phổ biến có thể có ít giá trị phân biệt lớp.

**Nếu metadata labels chưa có hoặc join không chính xác:** đánh dấu hạng mục này `BLOCKED_MISSING_LABELS`, không bịa thống kê. Mining + galleries vẫn tiếp tục được.

### 7.2. Phần **bắt buộc minh họa**: pattern-based image retrieval

Triển khai ít nhất một **query pattern thực tế**:

1. Chọn một itemset đã mine có support được xác nhận.
2. Tìm ảnh thỏa `X⊆T(image)` từ transaction database.
3. Báo `retrieved_count = support_count(X)` (nếu source/mapping đồng nhất) và minh họa một gallery ảnh truy hồi.
4. Hiển thị các ảnh không chứa X để đối chiếu nếu có; nhận xét mức độ đa dạng và mức độ tương đồng thị giác quan sát được.
5. Nếu labels sẵn có, báo class distribution trong tập retrieved so với class prior (chỉ descriptive).

**Cách diễn giải:** Đây là *retrieval theo tổ hợp visual words*, không phải hệ thống image search dựa trên pixel distance hay semantic embedding. Không khẳng định đã cải thiện precision/recall nếu chưa có ground-truth relevance và thiết kế đánh giá truy hồi chính thức.

### 7.3. Phần **bắt buộc thảo luận kỹ thuật**: dùng patterns làm features cho mô hình khác

Giả sử codebook S0 có `K=32`, với một ảnh I, biểu diễn ban đầu:

\[
\mathbf{x}_{\mathrm{BoVW}}(I)\in\{0,1\}^{32}.
\]

Chọn một tập `m` frequent itemsets đại diện `P_1,...,P_m`. Tạo **pattern activation features**:

\[
\phi_j(I)=\mathbb{1}[P_j\subseteq T(I)],\quad
\mathbf{x}_{\mathrm{pattern}}(I)=[\phi_1(I),\ldots,\phi_m(I)],
\]

\[
\mathbf{x}_{\mathrm{aug}}(I)=[\mathbf{x}_{\mathrm{BoVW}}(I),\mathbf{x}_{\mathrm{pattern}}(I)]
\in\{0,1\}^{32+m}.
\]

**Ứng dụng có thể thảo luận:**

- Binary Logistic Regression / Linear SVM với tương tác tổ hợp được biểu diễn tường minh; dự đoán class trong nghiên cứu minh họa.
- Phân nhóm hoặc mô tả ảnh theo *pattern signature* thay vì từng visual word đơn lẻ.
- Tìm kiếm ảnh theo một tập patterns có ý nghĩa được chỉ định trước.

**Giới hạn bắt buộc nêu:** Các feature `φ_j` là hàm xác định của 32 BoVW bits ban đầu; **không làm tăng lượng thông tin của ảnh**. Chúng có thể giúp mô hình hạn chế (đặc biệt tuyến tính) biểu diễn tương tác dễ hơn, nhưng không bảo đảm cải thiện dự đoán.

### 7.4. **Optional**, không mặc định triển khai: downstream classifier PoC

Nếu nhóm chủ động muốn có thêm bằng chứng định lượng:

| Experiment | Features | Model | Đánh giá |
|---|---|---|---|
| E0 | 32 BoVW bits | Logistic Regression | Accuracy, macro-F1, per-class F1 |
| E1 | m pattern activations | Logistic Regression | Như E0 |
| E2 | 32 BoVW + m pattern activations | Logistic Regression | Như E0 |

- Dùng **original train/test split** đúng metadata; fit classifier chỉ trên train, đánh giá trên test.
- **Tránh label leakage trong selection:** chọn patterns/điều chỉnh hyperparameters bằng train/validation, không dùng labels test. Với PoC nghiêm túc, các frequent patterns dùng làm features cần được **mine hoặc chọn chỉ từ train**; không chọn trên toàn bộ 70k rồi tuyên bố đánh giá generalization độc lập.
- **Quan trọng:** Codebook B0 hiện tại được fit từ toàn bộ 70k ảnh; classifier PoC với codebook này chỉ có thể gọi là **transductive/exploratory**. Muốn đánh giá inductive sạch cần một thí nghiệm độc lập refit codebook từ train — **ngoài phạm vi và không được tự ý thay artifacts đã chốt**.
- Không tự động bật/triển khai PoC trong pipeline chính. Nếu chưa chạy, mục báo cáo ghi **proposed experiment / future work**, không báo accuracy hoặc “cải thiện”.

---

## 8. FIM-05 — Báo cáo, cấu trúc artifacts & reproducibility

### 8.1. Cấu trúc đầu ra đề xuất

```text
results/fashion/fim/B0_K32_seed123_S0/
├── config_snapshot.toml                # locked source/minsup/engine/runtime
├── input_manifest.toml                 # input path, sha256, N, K, no refit
├── input_preparation/                 # nguồn notebook đã có, nếu dùng
├── mining/
│   ├── runs.csv                       # 6 rows tương ứng 6 mức minsup (tối thiểu)
│   ├── runs/                          # supervisor/worker sidecars, log, heartbeat, exit evidence
│   └── itemsets/
│       ├── minsup_80.jsonl            # normalized exact output khi completed
│       ├── minsup_60.jsonl
│       ├── minsup_40.jsonl
│       ├── minsup_20.jsonl
│       ├── minsup_10.jsonl
│       └── minsup_05.jsonl
├── report/mcp_execution_log.md       # MCP tool/kernel/session + evidence (chỉ khi thực thi)
├── analysis/
│   ├── count_by_length.csv
│   ├── pattern_support_summary.csv
│   ├── master_patterns.jsonl
│   ├── representative_patterns.csv
│   └── pattern_statistics.md
├── interpretation/
│   ├── pattern_annotations.csv
│   ├── pattern_class_support.csv
│   ├── retrieval_examples.csv
│   ├── pattern_gallery/
│   └── visual_interpretation.md
├── figures/
│   ├── minsup_vs_itemset_count.png
│   ├── minsup_vs_runtime.png
│   ├── itemset_lengths_by_minsup.png
│   └── pattern_class_heatmap.png
└── report/
    ├── fashion_fim_application_report.md
    └── experiment_manifest.toml
```

**Lưu ý:** Các tên file là đề xuất thống nhất để agent triển khai, **không có nghĩa các file đã tồn tại**. Chỉ tạo output cho phần thực tế hoàn thành; file `minsup_XX.jsonl` của run thất bại phải được **đánh dấu partial hoặc không tồn tại**, tuyệt đối không mang tên như output exact.

### 8.2. Hợp đồng tối thiểu cho từng output

**`mining/runs.csv`** — mỗi ngưỡng đúng một bản ghi status chính. Bổ sung vào manifest `api_call = "EclatFIM.mine(transactions, min_count)"`, `returned_type` và `used_optional_limits` (không được che giấu):

```text
run_id,configuration,minsup_fraction,minsup_count,status,reason_code,total_frequent_itemsets,max_itemset_length,observed_partial_itemsets,runtime_seconds,peak_rss_mb,output_size_bytes,engine_revision,input_sha256,used_optional_limits,worker_log_path,notes
```

- `total_frequent_itemsets` và `max_itemset_length` **phải null/NA** nếu `status` không phải `COMPLETED_FULL` hoặc `COMPLETED_ZERO`; `COMPLETED_ZERO` có **total=0, max_length=0**, output JSONL chính thức được phép rỗng 0 dòng. Trạng thái chi tiết chỉ dùng enum §4.3; `reason_code` lưu nguyên nhân cụ thể.
- Nếu có multiple measured repeats: lưu `mining/repeats.csv` riêng; `runs.csv` tham chiếu một run đại diện/canonical, không ghi nhiều hàng trùng ngưỡng mà không có lý do.
- Lưu `minsup_count` là integer và `minsup_fraction` là fraction, không nhập lẫn `80` với `0.80`.

**`mining/itemsets/minsup_XX.jsonl`** — mỗi dòng một object được **runner chuyển đổi từ `Dict`** (không có output file tự động từ Eclat):

```json
{"items":[3,7,12],"length":3,"support_count":42000,"support_fraction":0.6}
```

Dòng trên **chỉ là minh họa schema**, không phải kết quả mine thực tế. `support_fraction` phải khớp `support_count / 70000`, `items` sorted unique và IDs 1..32. Giữ lại raw output gốc của engine khi thích hợp.

**`analysis/representative_patterns.csv`**:

```text
pattern_id,items,length,support_count,support_fraction,selection_rule,reference_minsup,selection_order,support_bucket,length_bucket,diversity_max_jaccard,rule_version,selection_seed,selection_notes
```

**`interpretation/pattern_annotations.csv`**:

```text
pattern_id,decodable,witness_valid,review_status,visual_coherence,interpretation,limitations,reviewer,reviewed_at,evidence_paths
```

**`interpretation/retrieval_examples.csv`**:

```text
pattern_id,retrieved_count,example_image_ids,contrast_image_ids,notes
```

**`report/experiment_manifest.toml`**: source/engine version, environment (Julia + OS + CPU/RAM nếu biết), effective thread count, minsup grid, source checksums, timestamps, **giá trị số và phương thức enforce của từng resource budget**, supervisor/worker scripts và provenance, paths thực sự được dùng, completion statuses/reason codes, seed ngẫu nhiên cho sampling/gallery.

**`report/mcp_execution_log.md`**: MCP provider/tool name thực tế, notebook path, Julia kernel/session, restart/run/save/reopen timestamps, logs/retries và liên kết artifact audit; nếu MCP không khả dụng ghi blocker trung thực, không ghi evidence giả.

**`mining/runs/<run_id>/`**: `status.toml`, `worker_stdout.log`, `worker_stderr.log`, heartbeat/event journal, exit code/signal, output checksum. `runs.csv` được supervisor tổng hợp atomic từ các sidecars theo đúng grid 6; dùng các file này để reconcile sau crash.

### 8.3. Báo cáo Ứng dụng 2: outline bắt buộc

1. **Bài toán và dữ liệu** — Fashion-MNIST, ảnh→transaction S0; ngắn gọn trích dẫn pipeline TC, chỉ rõ quyết định B0/K32/seed123 và N=70k.
2. **Thực nghiệm Eclat** — nhóm tự cài, sáu ngưỡng, cùng environment và policy, bảng runs/status.
3. **Kết quả FIM** — itemset counts vs minsup, lengths, support, runtime, điều kiện full/partial.
4. **Diễn giải patterns** — centroid + real patches + supporting images + witnesses, những gì có/không thể suy ra từ S0.
5. **Giá trị ứng dụng** — class conditional enrichment, retrieval ví dụ thực, thảo luận pattern features và cách kiểm tra downstream model.
6. **Hạn chế và kết luận** — sự phổ biến không đảm bảo tính phân biệt, thiếu spatial semantics trong S0, lựa chọn codebook chốt trước, giới hạn computation và transductive codebook nếu bàn đến predictive evaluation.

Báo cáo Fashion-MNIST này là **một phần** của báo cáo đồ án tổng hợp IEEE 10–15 trang (theo `itemset.md`); không tự tạo một báo cáo IEEE 10–15 trang khác thay cho nhóm nếu chưa được yêu cầu.

---

## 9. Kiểm tra chất lượng và Definition of Done

### 9.1. Điều kiện nghiệm thu HARD

- [ ] Đọc đúng path `results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl`; không dùng alias `v2_full_s0` cũ; ghi input hash.
- [ ] Không thay bất kỳ file TC, codebook, Eclat core, tests, benchmark hay code của thành viên khác.
- [ ] `N=70_000`, `K=32`, S0; không biến `tid`/`image_id`/label thành item.
- [ ] Gọi đúng `EclatFIM.mine(transactions, min_count)` với `transactions` là vector các vector `Int`, `min_count` là absolute support integer; **không** tạo SPMF để làm đầu vào mặc định, không sửa core.
- [ ] Có chính xác 6 mức: 80%, 60%, 40%, 20%, 10%, 5%; support counts 56000/42000/28000/14000/7000/3500.
- [ ] Sau **P2 production MCP** có 6 dòng trong bảng kết quả với status theo enum §4.3, đúng `reason_code`; **P1 chỉ smoke** và không chạy 6 lần production.
- [ ] Chuyển `Dict{Tuple{Vararg{Int}},Int}` thành JSONL có thứ tự deterministic; với `COMPLETED_FULL`, xuất **mọi** entry, khớp `length(patterns)` và support counts trong 70k; không lẫn truncated counts.
- [ ] So sánh anti-monotonic giữa các runs completed; chạy audit support theo mẫu; không lờ đi lỗi output.
- [ ] Có biểu đồ/bảng số patterns theo minsup, phân bố pattern lengths và runtime; các điểm bị censored được phân biệt.
- [ ] Có master pattern catalog tránh đếm trùng across minsup, representative selection tái lập theo buckets + Jaccard và lưu rule/seed.
- [ ] Pattern gallery có centroids/patches/ảnh từ artifacts thật với source TID/image mapping đã xác nhận; annotation mặc định `PENDING_REVIEW` cho đến khi có người duyệt, không tự gán điểm coherence.
- [ ] Có ít nhất **một** retrieval minh họa bằng pattern đã mine, support count đối chiếu số ảnh truy hồi.
- [ ] Nếu labels hợp lệ: có thống kê class conditional, enrichment và interpretation có giới hạn. Nếu không: báo `BLOCKED_MISSING_LABELS` đúng nguyên nhân.
- [ ] Có thảo luận cụ thể về downstream pattern features (`BoVW`, `pattern-only`, `augmented`) và leakage; không báo accuracy khi chưa thí nghiệm.
- [ ] Có `config_snapshot`, `experiment_manifest`, `mcp_execution_log.md` (có evidence hoặc blocker thật), README/chỉ dẫn chạy notebook và phần báo cáo Ứng dụng 2.

### 9.2. Nghiệm thu theo trục và trạng thái tổng thể

Phải báo cáo **ba trục** riêng, tránh ép một status duy nhất che các blocker đồng thời:

- `mining`: `PASS` khi 6 ngưỡng completed+audited; `PARTIAL_RESOURCE` nếu bị timeout/RAM/output cap nhưng có completed evidence; `BLOCKED` nếu không có run nào được hoàn tất; `FAIL` nếu output sai.
- `execution_mcp`: `PASS` chỉ khi **MCP thật** đã chạy, lưu và reopen notebooks từ kernel sạch; `BLOCKED` nếu MCP/kernel/runtime không có; `UNVERIFIED` nếu chỉ có artifact từ terminal/cache mà chưa kiểm chứng MCP.
- `interpretation`: `PASS` khi gallery/witness, retrieval, labels nếu có, và **human review đã chốt**; `PENDING_REVIEW` nếu máy dựng galleries đầy đủ nhưng chưa được người review; `PARTIAL_MISSING_ASSET` nếu không có ảnh/patch/label cần thiết; `BLOCKED` nếu không có patterns hoàn chỉnh để diễn giải.

**Overall enum** và precedence:

| Tổng thể | Khi dùng |
|---|---|
| `COMPLETE` | `execution_mcp=PASS`, `mining=PASS`, `interpretation=PASS`, report/artifact audit PASS |
| `BLOCKED` | Chưa thể thực hiện/kiểm tra công việc cốt lõi vì source/engine/MCP/kernel thiếu; nêu reason_code và những phần có thể đã hoàn thành |
| `PARTIAL_EXECUTION_UNVERIFIED` | Có kết quả hoặc notebook nhưng **chưa có bằng chứng thực thi MCP hợp lệ**; không công bố COMPLETE |
| `PARTIAL_MIXED` | Đồng thời có ≥2 nhóm vấn đề (mining incomplete, thiếu assets/review, v.v.); ghi từng nhóm dưới các trục riêng |
| `PARTIAL_RESOURCE_LIMITED` | MCP đã chạy, ≥1 run resource-limited, các phần diễn giải có thể làm được đã nghiệm thu |
| `PARTIAL_INTERPRETATION` | Mining đã hoàn thành, nhưng thiếu asset/label/witness khiến phần diễn giải cần thiết chưa đầy đủ |
| `PENDING_HUMAN_REVIEW` | Mining/MCP/artifacts/galley đều đủ, **chỉ còn review định tính**; không tuyên bố điểm coherence đã được duyệt |

Precedence thực thi: nếu không có MCP và không thể thực hiện chính → `BLOCKED`; nếu chỉ thiếu evidence MCP nhưng có artifacts → `PARTIAL_EXECUTION_UNVERIFIED`; nếu nhiều trục không đạt → `PARTIAL_MIXED`; nếu chỉ còn review → `PENDING_HUMAN_REVIEW`; nếu chỉ còn resource/interpretation → trạng thái partial tương ứng; chỉ `COMPLETE` khi mọi gate đều PASS. Nêu **tất cả blocker** dưới trục riêng ngay cả khi tổng thể chọn một nhãn.

**Tình huống bắt buộc mô tả:** (i) khai thác xong nhưng MCP không dùng được ≠ COMPLETE; (ii) thiếu cả RAM lẫn assets → PARTIAL_MIXED; (iii) gallery auto không có human review → PENDING_HUMAN_REVIEW nếu phần khác đủ; (iv) `COMPLETED_ZERO` ở 80% là bình thường, max_length=0.

## 10. Triển khai cho coding agent — ưu tiên và hướng dẫn bàn giao

**P0 — Integration & run configuration**
- API đã xác nhận: `EclatFIM.mine(transactions, min_count)` → `Dict{Tuple{Vararg{Int}},Int}`. Xác nhận cách import/load module thực tế của repo, chuẩn hóa JSONL → `Vector{Vector{Int}}`; không cần thiết kế CLI/SPMF cho bước này.
- Nếu tương thích, dùng lại output input preparation; không đụng thuật toán.
- Xây supervisor/worker và smoke trong P1; **chỉ P2 mới chạy sáu mức 80% xuống 5% qua MCP**. Ghi logs/manifest sau mỗi ngưỡng.

**P3 — Analysis**
- Nhận Dict output trực tiếp, serialize theo thứ tự canonical và xử lý các file JSONL đã lưu theo kiểu stream-friendly; thống kê, charts, phân biệt completed và partial. Chú ý chính bản thân Dict có thể tiêu thụ RAM lớn trước khi serialize.
- Chọn patterns theo quy tắc đã định, không chỉ lấy top-support.

**P4 — Interpretation & application**
- Dựng gallery bằng artifacts thật, join labels post-hoc, phân tích support theo lớp.
- Thực hiện query-based retrieval và thảo luận pattern feature engineering.

**P5 — Report & clean handoff**
- Báo đủ kết quả hoàn tất/thất bại, paths và instructions; giữ notebook gọn, giải thích mỗi code cell vừa đủ chức năng, tránh các mô tả thừa hoặc giả định kết quả.
- Nếu tạo visualization cho report, lưu ảnh/tables tái sử dụng; không cần chạy lại Eclat khi thay wording hoặc chỉnh biểu đồ.

### 10.1. Các điều kiện cần đồng bộ (không tự giả định)

1. **Giao diện Eclat đã biết:** `EclatFIM.mine(transactions, min_count)` với `min_count` là absolute count, trả Dict tuple→count. Chỉ còn cần xác nhận cách import, phiên bản code, và semantics cụ thể của giới hạn tùy chọn `max_length`, `deadline`, `max_itemsets` trước khi sử dụng. Không đoán cách module báo giới hạn đã kích hoạt.
2. **Nguồn đường dẫn centroid, patch assignments, Fashion-MNIST images và metadata** phải resolve từ repo hoặc config; thiếu thì phản ánh blocker ở phần phụ thuộc, không tạo stub giả số liệu.
3. **Budget phần cứng** phải có giá trị số và cơ chế enforce thực sự của supervisor trước P2; nếu không enforce được thì báo blocker, không âm thầm đổi minsup. Quy tắc audit 80%/60% dựa trên phép đếm người dùng cung cấp, phải xác minh độc lập.
4. Các ngưỡng trong notebook Input Preparation cũ **không còn là grid chính thức**; dùng grid ở §4.

---

## 11. Cấu hình tham khảo (proposed TOML, không phải file đã triển khai)

```toml
[dataset]
configuration_id = "B0_K32_seed123_S0"
transactions_jsonl = "results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl"
expected_transaction_count = 70000
expected_empty_count = 0
k = 32
encoding = "S0"
method = "raw_full_batch_kmeans"
seed = 123

[mining]
minsup_counts = [56000, 42000, 28000, 14000, 7000, 3500]
minsup_fractions = [0.80, 0.60, 0.40, 0.20, 0.10, 0.05]
run_order = "descending_minsup"
require_complete_itemsets = true
engine = "EclatFIM.mine"
api_input = "Vector{Vector{Int}}, absolute_min_count"
api_output = "Dict{Tuple{Vararg{Int}},Int}"
optional_limits_enabled = false
# Cách import EclatFIM lấy từ repo thực tế; không viết lại core.

[execution]
mode = "production_mcp_supervised"
# REQUIRED BEFORE P2: set concrete hardware-dependent numeric values:
# wall_time_seconds_per_run = <positive integer>
# memory_limit_mb_per_worker = <positive integer>
# output_limit_bytes = <positive integer>
# enforcement_method = "actual OS/process-supervisor mechanism"
measure_repetitions = 1
sampling_seed = 42

[analysis]
representative_patterns_min = 12
representative_patterns_max = 20
representative_patterns_target = 16
diversity_jaccard_max = 0.80
diversity_relax_once_to = 0.90
interpretation_requires_true_witness = true
manual_review_required_for_complete = true

[downstream]
class_analysis = true
pattern_retrieval = true
train_optional_classifier = false

[output]
base_dir = "results/fashion/fim/B0_K32_seed123_S0"
```

**Ghi chú:** `representative_patterns_min=12` là mục tiêu chọn mẫu, không buộc phải tạo 12 patterns khi không có đủ frequent itemsets. Các giới hạn tài nguyên là placeholders cho người thực thi, không phải values hợp lệ có thể chạy ngay.

---

## 12. Phân loại bắt buộc / tùy chọn (tóm tắt)

| Hạng mục | Mức |
|---|---|
| Gọi đúng API `EclatFIM.mine(transactions, min_count)` và sáu minsup đã khóa | **BẮT BUỘC** |
| Log trạng thái/chi phí, xuất exact supports khi completed | **BẮT BUỘC** |
| Biểu đồ mining và phân tích patterns | **BẮT BUỘC** |
| Centroid/patch/gallery thật và chú thích giới hạn S0 | **BẮT BUỘC** |
| Class analysis sau mining (nếu labels hợp lệ) | **BẮT BUỘC KHI CÓ DỮ LIỆU** |
| Truy hồi ảnh theo ít nhất một frequent itemset | **BẮT BUỘC** |
| Thảo luận ứng dụng patterns để tạo features cho ML | **BẮT BUỘC** |
| Train 3 classifier đối chứng / chứng minh predictive gains | **TÙY CHỌN; NGOÀI PHẠM VI MẶC ĐỊNH** |
| So sánh SPMF, sửa/tối ưu Eclat | **KHÔNG THUỘC PHẠM VI** |
| EDA2/chọn lại codebook/spatial encodings | **KHÔNG THUỘC PHẠM VI** |

**Điều kiện thành công:** Người đọc có thể đi từ **một frequent itemset Eclat thực sự xuất ra** → **support đã kiểm tra** → **các ảnh/patch chứng minh nó tồn tại** → **một nhận xét đúng giới hạn của S0** → **một ví dụ sử dụng thực tế hoặc bản thiết kế downstream rõ ràng**; và có thể tái lập thí nghiệm ở sáu minsup với engine của nhóm.


---

## Changelog v1.1 — Integration contract (so với v1.0)

- Đã xác định API chính thức `EclatFIM.mine` (in-memory transactions, absolute support count) và kiểu output Dict.
- Không chuyển SPMF để gọi engine; `transactions_spmf.txt` chỉ là artifact tham khảo từ notebook cũ nếu còn cần cho các công việc độc lập khác.
- Quy định cách serialize Dict deterministic và cách tự quản lý provenance/log/status, vì return value không có metadata run.
- Quy định không sử dụng tùy tiện `max_length`, `deadline`, `max_itemsets` trong main full runs; các lần chạy có giới hạn phải ghi trạng thái và không báo kết quả truncated như complete.
- Không thay đổi 6 minsup, codebook, nguồn transaction, phạm vi interpretation/downstream hay quyền sở hữu Eclat core.


## Changelog v1.2 — Protocol & acceptance contract

- Quy định một quy trình duy nhất: P1 smoke/implement, P2 MCP production; giám sát worker ngoài kernel, atomic persistence và resume sau gián đoạn.
- Enum run statuses và reason_code thống nhất; `COMPLETED_ZERO` có total/max_length bằng 0; kiểm tra singleton 80%/60% do người dùng báo cần tự xác minh.
- Input Preparation notebook tùy chọn; loader trực tiếp JSONL là chính.
- Chốt stratified deterministic representative selection, human `PENDING_REVIEW`, và báo cáo tổng thể theo ba trục để giải quyết nhiều blockers đồng thời.
