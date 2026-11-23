# SPEC v1.1 — Fashion-MNIST Frequent Visual Itemset Mining & Downstream Interpretation

**Tên ngắn:** Fashion-MNIST FIM — Production Mining, Pattern Analysis & Application 2  
**Trạng thái:** Đặc tả triển khai (chưa phải báo cáo kết quả thực nghiệm)  
**Phiên bản:** 1.1 — 19/11/2026  
**Thay đổi v1.1:** Khóa hợp đồng tích hợp theo API `EclatFIM.mine(transactions, min_count)` do nhóm cung cấp; bỏ nhánh SPMF đầu vào Eclat, thêm contract kết quả `Dict`, quản lý giới hạn và acceptance cho adapter.  
**Đối tượng:** Coding agent / thành viên phụ trách Ứng dụng 2 (Fashion-MNIST)  
**Tài liệu căn cứ:** `itemset.md` (Chương 3, Ứng dụng 2; các yêu cầu kỹ thuật), `TC_Transaction_Construction_Spec_v2.md`, `TC6_Spatial_Encoding_Extension_Spec_v1.md` (định nghĩa S0), notebook `FashionMNIST_K32_seed123_S0_FIM_Input_Preparation.ipynb`.  
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

### 2.3. Kế thừa notebook Input Preparation

Notebook `FashionMNIST_K32_seed123_S0_FIM_Input_Preparation.ipynb` đã được chuẩn bị để nạp JSONL, tính singleton supports và có thể xuất `transactions_spmf.txt`. **Eclat API hiện tại không yêu cầu file SPMF**: notebook/runner phải nạp JSONL thành vector các vector số nguyên trong Julia. Có thể tái sử dụng hàm loader nếu kiểm chứng được output types và thứ tự transactions; không chạy lại TC.

**Quan trọng:** Notebook cũ vẫn chứa dải minsup `[0.10, 0.07, 0.05, 0.03, 0.02, 0.01, 0.005]` theo quyết định trước đây. **Dải này đã hết hiệu lực đối với thí nghiệm hiện tại.** Runner/spec mới phải dùng đúng sáu ngưỡng được khóa ở §4; nếu cập nhật notebook cũ thì chỉ cập nhật phần cấu hình minsup và mô tả liên quan, không mở rộng sửa các phần khác.

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
3. Notebook Input Preparation đã có — **giữ**; có thể tái sử dụng loader JSONL và thống kê. **Không cần chuyển SPMF để gọi API hiện tại**.

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

### 4.3. Status contract

| `status` | Ý nghĩa | Cho phép dùng total pattern count làm kết quả chính xác? |
|---|---|---|
| `COMPLETED_FULL` | Đã duyệt toàn bộ không gian frequent itemsets và ghi kết quả đúng | **Có** |
| `COMPLETED_ZERO` | Chạy đầy đủ và không có frequent itemsets | **Có**, count=0 |
| `TIMEOUT` | Dừng theo thời gian | **Không** |
| `MEMORY_LIMIT` | Dừng do giới hạn bộ nhớ | **Không** |
| `ITEMSET_CAPPED` | Dừng vì output/enumeration cap | **Không** |
| `LENGTH_CAPPED` | Chỉ khai thác đến một độ dài xác định | **Không** (không phải kết quả đầy đủ) |
| `FAILED` | Lỗi/exit code không thành công | **Không** |
| `BLOCKED` | Không gọi được Eclat hoặc thiếu điều kiện tiên quyết | **Không** |
| `COMPLETION_UNVERIFIED` | Có Dict trả về nhưng không chứng minh được run không bị cắt bởi giới hạn hoặc cơ chế dừng | **Không** |

Nếu tiến trình bị kill mà không tạo báo cáo chuẩn, runner phải ghi trạng thái kết quả **không rõ/không hoàn tất** (`FAILED`/`UNKNOWN_INTERRUPTED`), không đoán là hoàn thành. Kết quả bị cắt có thể được giữ phục vụ chẩn đoán nhưng không đưa vào chart `#itemsets` chính xác.

### 4.4. Kế hoạch chạy và đo tài nguyên

1. Thiết lập **trước khi chạy** chính sách ngân sách (`time_limit_seconds`, `memory_limit_mb`, `output_storage_limit` nếu runner có khả năng enforce), hardware/OS/Julia version và process/thread settings. API `mine` được cung cấp không xác nhận tham số `threads` hay `seed` riêng; không tự truyền các keyword đó vào core. Khi chạy full, ưu tiên gọi chỉ với 2 positional arguments. Các con số phụ thuộc máy; không giả định giới hạn được enforce nếu runner không thực hiện được.
2. Chạy từ **80% → 5%**; lần nào chưa thể hoàn thành thì ghi status và lý do. Không có nhu cầu lặp lại những runs mà không thay đổi điều kiện.
3. Mỗi ngưỡng: **một run có kết quả** là bắt buộc; **tùy chọn** 1 warm-up và 3 measured repetitions để đo timing ổn định (cân nhắc cache/re-use output, không xuất lặp file khổng lồ nếu không cần). Không trộn số liệu warm-up với measured runs.
4. Ghi thời gian tổng và (nếu có) peak RSS chính xác của process; với notebook/kernel, ghi rõ memory được đo trên process nào. Nếu không đo được RAM, để `NA` thay vì tự ước lượng.
5. Với từng run hoàn thành, runner nhận `Dict{Tuple{Vararg{Int}},Int}` **trong bộ nhớ** rồi serialize đầy đủ mọi entry sang file `minsup_XX.jsonl` theo thứ tự canonical. Có thể lưu bản `Dict` gốc dưới dạng Julia serialization nếu thật sự cần và bảo đảm có manifest phiên bản; không giả định core tự sinh file.
6. Với một lần chạy thiếu output vì crash/giới hạn lưu trữ, ghi `FAILED` hoặc `ITEMSET_CAPPED` phù hợp, không giả tạo tập itemsets hoàn chỉnh.

**Bảng điều khiển bắt buộc:** `minsup_fraction`, `minsup_count`, `status`, `total_frequent_itemsets` (nullable), `max_itemset_length` (nullable), `runtime_seconds`, `peak_rss_mb` (nullable), `output_size_bytes`, `notes`, `engine_revision`, `input_sha256`.

### 4.5. Kiểm tra kết quả ở tầng orchestration (không thay phần unit tests Eclat)

- **Không parse SPMF hoặc output text của engine**: xử lý trực tiếp Dict keys là tuple tăng dần, values là absolute support integer, rồi serialize ra format output ở §8.2. Kiểm tra `length(patterns)` bằng số dòng xuất và soát không có keys trùng/empty/ngoài miền 1..32.
- Chuẩn hóa itemset bằng **sort ascending** và sử dụng canonical tuple để phát hiện trùng trong **cùng một lần chạy**; không tự âm thầm bỏ items để “sửa” kết quả Eclat.
- Với completed runs, mọi pattern có `support_count >= minsup_count` và `0 < support_count <= 70_000`; assert canonical sorted tuple IDs 1..32, positive count. Với ngưỡng 80% và 60%, `Dict()` trống vẫn là kết quả hợp lệ **nếu core hoàn tất đầy đủ**.
- Nếu cả hai ngưỡng a>b đều `COMPLETED_FULL`, tập itemsets tại a phải là tập con của tập itemsets tại b, với **support của cùng itemset không đổi**. Nếu lỗi, đánh dấu `INVALID_OUTPUT`/`FAILED`, không báo chart hợp lệ.
- Đối chiếu **một mẫu pattern cố định** (ví dụ 20 patterns chọn deterministic theo length/support bands) bằng scan/intersection lại `transactions.jsonl` để phát hiện lỗi parser, TID alignment hoặc reporting. Đây là **sanity audit output ứng dụng**, không phải thực hiện lại test correctness của thuật toán.
- Khi `COMPLETED_ZERO`, xác minh không có frequent singleton ở threshold bằng bảng support đầu vào (nếu có). Nếu bất nhất, điều tra trước khi diễn giải.

---

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

### 5.4. Quy tắc chọn patterns để diễn giải

**Target đề xuất:** 12–20 representative patterns nếu kết quả cho phép; không bắt buộc ép đủ số lượng khi data thiếu. Chọn **deterministically** theo:

1. Nhiều khoảng support (cao/vừa/thấp trong vùng patterns thực tế hoàn thành).
2. Nhiều độ dài (`1`, `2`, `>=3` nếu có), ưu tiên một số tập nhiều items khi chứng minh được bằng witnesses.
3. Hạn chế patterns gần giống nhau (chung nhiều items) để gallery có đa dạng.
4. Có ít nhất vài patterns để minh họa **common**, **class-enriched** và **cross-class** *chỉ nếu dữ liệu hậu nghiệm thực sự hỗ trợ*; tuyệt đối không gán nhãn trước khi tính.
5. Nếu có ngưỡng có rất ít patterns, ghi nhận kết quả thực tế; không thêm patterns không phổ biến để đủ quota.

Lưu `representative_patterns.csv` với `pattern_id`, rule lựa chọn, `support_count`, `length`, ngưỡng tham chiếu, `selection_notes`; không chủ quan chỉ chọn ví dụ đẹp để khái quát toàn bộ dữ liệu.

---

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

### 6.3. Chất lượng diễn giải (đánh giá thủ công minh bạch)

Đề xuất annotation schema:

| Field | Ý nghĩa |
|---|---|
| `decodable` | Có tra được IDs → codebook/patch không |
| `witness_valid` | Supporting TIDs và patch assignments khớp với itemset không |
| `visual_coherence` | `0` không nhất quán; `1` một phần/mơ hồ; `2` nhất quán ở nhiều ảnh/patchs |
| `interpretation` | Mô tả có bằng chứng (không gán nhãn quá mức) |
| `limitations` | Điều không thể suy ra từ S0 |
| `reviewer` | Người kiểm tra, nếu chấm thủ công |

Không tự động gán mức `2` chỉ vì support cao. Nếu có hai reviewers càng tốt nhưng không phải điều kiện bắt buộc; không báo điểm chủ quan như chân lý định lượng.

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
│   ├── runs/                          # log + metadata của từng run
│   └── itemsets/
│       ├── minsup_80.jsonl            # normalized exact output khi completed
│       ├── minsup_60.jsonl
│       ├── minsup_40.jsonl
│       ├── minsup_20.jsonl
│       ├── minsup_10.jsonl
│       └── minsup_05.jsonl
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
run_id,configuration,minsup_fraction,minsup_count,status,total_frequent_itemsets,max_itemset_length,runtime_seconds,peak_rss_mb,output_size_bytes,engine_revision,input_sha256,notes
```

- `total_frequent_itemsets` và `max_itemset_length` **phải null/NA** nếu `status` không phải `COMPLETED_FULL` hoặc `COMPLETED_ZERO`.
- Nếu có multiple measured repeats: lưu `mining/repeats.csv` riêng; `runs.csv` tham chiếu một run đại diện/canonical, không ghi nhiều hàng trùng ngưỡng mà không có lý do.
- Lưu `minsup_count` là integer và `minsup_fraction` là fraction, không nhập lẫn `80` với `0.80`.

**`mining/itemsets/minsup_XX.jsonl`** — mỗi dòng một object được **runner chuyển đổi từ `Dict`** (không có output file tự động từ Eclat):

```json
{"items":[3,7,12],"length":3,"support_count":42000,"support_fraction":0.6}
```

Dòng trên **chỉ là minh họa schema**, không phải kết quả mine thực tế. `support_fraction` phải khớp `support_count / 70000`, `items` sorted unique và IDs 1..32. Giữ lại raw output gốc của engine khi thích hợp.

**`analysis/representative_patterns.csv`**:

```text
pattern_id,items,length,support_count,support_fraction,selection_rule,reference_minsup,selection_notes
```

**`interpretation/pattern_annotations.csv`**:

```text
pattern_id,decodable,witness_valid,visual_coherence,interpretation,limitations,reviewer
```

**`interpretation/retrieval_examples.csv`**:

```text
pattern_id,retrieved_count,example_image_ids,contrast_image_ids,notes
```

**`report/experiment_manifest.toml`**: source/engine version, environment (Julia + OS + CPU/RAM nếu biết), effective thread count, minsup grid, source checksums, timestamps, policy cho time/memory limits, paths thực sự được dùng, completion statuses, seed ngẫu nhiên cho sampling/gallery.

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
- [ ] Có 6 dòng trong bảng kết quả với trạng thái trung thực kể cả khi `TIMEOUT`, `FAILED`, `COMPLETED_ZERO`, `COMPLETION_UNVERIFIED`; không coi return Dict từ một lần gọi có giới hạn là bằng chứng tự động cho full mining.
- [ ] Chuyển `Dict{Tuple{Vararg{Int}},Int}` thành JSONL có thứ tự deterministic; với `COMPLETED_FULL`, xuất **mọi** entry, khớp `length(patterns)` và support counts trong 70k; không lẫn truncated counts.
- [ ] So sánh anti-monotonic giữa các runs completed; chạy audit support theo mẫu; không lờ đi lỗi output.
- [ ] Có biểu đồ/bảng số patterns theo minsup, phân bố pattern lengths và runtime; các điểm bị censored được phân biệt.
- [ ] Có master pattern catalog tránh đếm trùng across minsup, representative selection được lưu rule.
- [ ] Pattern gallery có centroids/patches/ảnh từ artifacts thật với source TID/image mapping đã xác nhận, không gán vị trí S0 không cung cấp.
- [ ] Có ít nhất **một** retrieval minh họa bằng pattern đã mine, support count đối chiếu số ảnh truy hồi.
- [ ] Nếu labels hợp lệ: có thống kê class conditional, enrichment và interpretation có giới hạn. Nếu không: báo `BLOCKED_MISSING_LABELS` đúng nguyên nhân.
- [ ] Có thảo luận cụ thể về downstream pattern features (`BoVW`, `pattern-only`, `augmented`) và leakage; không báo accuracy khi chưa thí nghiệm.
- [ ] Có `config_snapshot`, `experiment_manifest`, README/chỉ dẫn chạy notebook và phần báo cáo Ứng dụng 2.

### 9.2. Điều kiện phân loại kết quả

- `COMPLETE`: Tất cả sáu ngưỡng hoàn tất (bao gồm completed-zero), output được kiểm tra, và toàn bộ outputs interpretation/report bắt buộc hiện hữu.
- `PARTIAL_RESOURCE_LIMITED`: Có một hoặc nhiều ngưỡng không thể mine đầy đủ vì tài nguyên, nhưng các completed runs được phân tích trung thực và phần interpretation có dữ liệu hợp lệ.
- `BLOCKED`: Không chạy được core hoặc không có transactions nguồn; nêu chính xác điều kiện thiếu.
- `PARTIAL_INTERPRETATION`: Mining chạy được nhưng thiếu nguồn codebook/patch/images/labels cần để hoàn tất các gallery hoặc đánh giá theo lớp.

Không tự tuyên bố đã thực hiện tính toán nếu chỉ có spec; file này chỉ quy định cách thực thi.

---

## 10. Triển khai cho coding agent — ưu tiên và hướng dẫn bàn giao

**P0 — Integration & run configuration**
- API đã xác nhận: `EclatFIM.mine(transactions, min_count)` → `Dict{Tuple{Vararg{Int}},Int}`. Xác nhận cách import/load module thực tế của repo, chuẩn hóa JSONL → `Vector{Vector{Int}}`; không cần thiết kế CLI/SPMF cho bước này.
- Nếu tương thích, dùng lại output input preparation; không đụng thuật toán.
- Chạy từ 80% xuống 5% và ghi logs/manifest mỗi lần.

**P1 — Analysis**
- Nhận Dict output trực tiếp, serialize theo thứ tự canonical và xử lý các file JSONL đã lưu theo kiểu stream-friendly; thống kê, charts, phân biệt completed và partial. Chú ý chính bản thân Dict có thể tiêu thụ RAM lớn trước khi serialize.
- Chọn patterns theo quy tắc đã định, không chỉ lấy top-support.

**P2 — Interpretation & application**
- Dựng gallery bằng artifacts thật, join labels post-hoc, phân tích support theo lớp.
- Thực hiện query-based retrieval và thảo luận pattern feature engineering.

**P3 — Report & clean handoff**
- Báo đủ kết quả hoàn tất/thất bại, paths và instructions; giữ notebook gọn, giải thích mỗi code cell vừa đủ chức năng, tránh các mô tả thừa hoặc giả định kết quả.
- Nếu tạo visualization cho report, lưu ảnh/tables tái sử dụng; không cần chạy lại Eclat khi thay wording hoặc chỉnh biểu đồ.

### 10.1. Các điều kiện cần đồng bộ (không tự giả định)

1. **Giao diện Eclat đã biết:** `EclatFIM.mine(transactions, min_count)` với `min_count` là absolute count, trả Dict tuple→count. Chỉ còn cần xác nhận cách import, phiên bản code, và semantics cụ thể của giới hạn tùy chọn `max_length`, `deadline`, `max_itemsets` trước khi sử dụng. Không đoán cách module báo giới hạn đã kích hoạt.
2. **Nguồn đường dẫn centroid, patch assignments, Fashion-MNIST images và metadata** phải resolve từ repo hoặc config; thiếu thì phản ánh blocker ở phần phụ thuộc, không tạo stub giả số liệu.
3. **Budget phần cứng** được người chạy thiết lập trong config trước các thí nghiệm; không âm thầm đổi minsup theo hardware.
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
# Set budget values according to actual hardware before running.
# time_limit_seconds = <integer>
# memory_limit_mb = <integer>
# threads = <integer>
measure_repetitions = 1
sampling_seed = 42

[analysis]
representative_patterns_min = 12
representative_patterns_max = 20
interpretation_requires_true_witness = true

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
