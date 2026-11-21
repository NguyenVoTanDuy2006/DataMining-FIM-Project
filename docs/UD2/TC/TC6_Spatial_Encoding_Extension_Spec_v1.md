# SPEC — Fashion-MNIST TC6 Spatial Encoding Extension (S0, S1, S3, S6-B)

**Version:** 1.0 — đặc tả triển khai mở rộng, chưa phải báo cáo kết quả thực nghiệm  
**Đối tượng:** Coding agent / nhóm triển khai Julia  
**Tài liệu nền:** `TC_Transaction_Construction_Spec_v2.md` (revision 2.1) và `TC1_TC7_Notebook_Implementation_Checklist.md` (revision 2.1)  
**Mục tiêu:** Tái sử dụng 15 bộ output TC hiện có để tạo ba biến thể **spatial transactions** bổ sung, đưa cả **S0, S1, S3, S6-B** vào EDA2 + Pilot Eclat để so sánh ảnh hưởng của cách biểu diễn không gian.

> **Quan hệ với TC v2.1:** Spec này là **extension/amendment cho TC6, TC7 và hợp đồng đầu vào EDA2**. Nó không thay thế định nghĩa TC1–TC5, không yêu cầu huấn luyện lại TC4, không sửa hoặc ghi đè 15 bộ S0 production. Những câu “S1/S2 ngoài scope” của spec v2.1 vẫn đúng đối với **baseline notebook v2.1**, nhưng **không hạn chế extension run mới** được định nghĩa tại đây. S2 Spatial Pyramid **không** thuộc extension hiện tại.

---

## 1. Quyết định thiết kế và phạm vi

### 1.1. Các phương pháp được chốt

| ID | Tên | Bản chất item | Vai trò |
|---|---|---|---|
| **S0** | Binary Bag of Visual Words (BoVW) | `word_id` | **Baseline hiện có; chỉ đọc, không tạo lại bắt buộc** |
| **S1** | Spatial Grid 2×2 | `(region_id, word_id)` | Mã hóa vị trí tuyệt đối theo 4 vùng |
| **S3** | Horizontal Stripes 1×3 | `(stripe_id, word_id)` | Mã hóa vùng trên / giữa / dưới |
| **S6-B** | Local Relative Spatial Relations | `(relation_type, word_a, word_b)` | Mã hóa quan hệ vị trí cục bộ giữa hai visual words |

**Không thuộc phạm vi:** S2 Spatial Pyramid, S4/S5/S7/S8, thay đổi K/seed, Q20, chọn K tối ưu trong TC6, thay đổi luật TC2, tính lại Q10+, tự chạy EDA2 hoặc Pilot Eclat trong notebook encoding (trừ khi người dùng giao một tác vụ riêng).

### 1.2. Input giữ nguyên

- Dataset nền: Fashion-MNIST **70.000 ảnh** 28×28 grayscale, chia thành **49 patches/ảnh** kích thước 4×4, lưới patch **7×7**.
- TC2: T2, patch được giữ khi `any(pixel > 29)`; các patches bị lọc **không** tham gia spatial encoding.
- TC3: raw pixel descriptor 16D; TC4 B0 full-batch K-means; TC5 hard assignments 1..K; không thay đổi bất kỳ bước nào trong TC1–TC5.
- 15 codebooks đã fit: `K = [16,32,64,128,256] × seed = [42,123,2026]`, cùng phương pháp `raw_full_batch_kmeans` (B0).
- Nguồn production B0/S0: `results/fashion/tc/tc6_configs/S0/`. Hệ thống phải cho phép cấu hình path; **không** giả định đã kiểm tra được nội dung thật của những files chỉ mới được mô tả bằng cây thư mục.
- Mỗi source run hiện có các files như `patch_assignments.csv`, `transactions.jsonl`, `codebook.bin`, `config_snapshot.toml`, `tid_image_mapping.csv`, `integrity_report.toml`, `checkpoint.toml` và các file phụ trợ. Chỉ dùng những fields/data thực sự được kiểm tra và xác nhận khi đọc file.

### 1.3. Kết quả dự kiến

- **15 bộ S0 hiện có:** tiếp tục giữ nguyên như baseline.
- **45 bộ spatial mới:** 15 bộ S1 + 15 bộ S3 + 15 bộ S6-B.
- **Tổng nguồn dữ liệu để EDA2:** **60 bộ** (`15 codebooks × 4 encoding variants`).
- **Mỗi bộ:** đúng **70.000 records** (bao gồm `items: []`); tổng logic 60 × 70.000 = **4.200.000 transaction records**. Trong đó extension **chỉ tạo mới 45 × 70.000 = 3.150.000 records**.
- Tất cả dùng **cùng TID/image_id và cùng codebook** theo mỗi cặp `(K, seed)`; khác biệt duy nhất giữa S0/S1/S3/S6-B là quy tắc encoding.

### 1.4. Nguyên tắc bất biến

1. Không fit lại TC4, không chạy lại TC1–TC5 và không thay đổi B0 codebooks, assignments hoặc transactions S0 gốc.
2. Không dùng nhãn lớp để tạo items. Labels/original split chỉ là metadata cho phân tích hậu khai thác.
3. Mỗi image tạo **đúng một** transaction trong từng variant, kể cả rỗng; không thay denominator 70.000.
4. Items là **số nguyên dương, unique, sorted ascending**. Mỗi `(variant, K)` có namespace item ID riêng. Không so sánh trực tiếp item IDs giữa variants hoặc giữa codebooks.
5. Không tự thêm global visual words vào S1/S3/S6-B; đây là **ba biến thể encoding thuần túy**, không phải union với S0 hay S2.
6. Mã hóa và mapping phải deterministic; cùng source artifacts + config phải sinh cùng dữ liệu.

---

## 2. Hợp đồng đầu vào và điều kiện kiểm tra source

### 2.1. Những dữ liệu cần đọc

Đối với mỗi source run `(K,seed)`:

- **Bắt buộc:** `patch_assignments.csv` (đủ cho từng retained patch: `image_id`, `patch_id`, `word_id` và coordinates patch); `tid_image_mapping.csv`; `config_snapshot.toml`; `transactions.jsonl` S0 (để kiểm tra đối chứng); `integrity_report.toml` và trạng thái completed từ checkpoint/run summary.
- **Phục vụ lineage/EDA2:** `codebook.bin`, `tc4_metrics.toml` và file stability/summary ở root; **không** dùng các files này để học lại hoặc đổi assignments.
- `assignments.bin` có thể dùng để đọc nhanh **chỉ khi** định dạng nhị phân đã được xác nhận tương đương `patch_assignments.csv`; CSV là điểm đối chiếu dễ kiểm tra.

### 2.2. Quy tắc tọa độ

- Mỗi patch có vị trí trên lưới `(r,c)`, với **`r,c ∈ {1,…,7}`**, `r` là row (trên xuống), `c` là column (trái sang phải).
- Ưu tiên đọc cột `patch_row`, `patch_col` nếu có. Nếu nguồn chỉ có pixel top-left, ánh xạ theo patch_size=4: `r = ((top_left_y - 1) ÷ 4) + 1`, `c = ((top_left_x - 1) ÷ 4) + 1` với tọa độ pixel base=1; nếu file dùng base=0, phải xác minh và áp dụng đúng base được ghi trong metadata.
- Nếu chỉ có `patch_id` và metadata xác nhận duyệt **row-major trước TC2**, có thể phục hồi: `r = ((patch_id-1) ÷ 7)+1`, `c = ((patch_id-1) % 7)+1`. Không gán lại patch_id sau lọc. Kiểm tra các nguồn tọa độ (nếu nhiều nguồn cùng có) phải nhất quán.
- Không tự suy luận một schema column/unit không có chứng cứ trong metadata. Không thể phục hồi/đối chiếu tọa độ thì **FAIL**, không cho chạy S1/S3/S6-B trên source đó.

### 2.3. Preflight validation

Trước khi tạo bất cứ artifact production nào, xác nhận từng source:

- `K`, `seed`, `method=B0`, `image_count=70000`, `patch_size=4×4`, `patch order=row-major`, `TC2 threshold=29`, `TC6 source=S0` khớp metadata.
- Source `integrity_report` và checkpoint cho biết run đạt/hoàn thành; không nhận run dở dang.
- `transactions.jsonl` S0 đủ 70k records, các TIDs đầy đủ, items sorted unique `1..K`.
- `patch_assignments.csv`: mỗi retained patch có `image_id` hợp lệ, `patch_id` trong 1..49, `(r,c)` trong 1..7, `word_id` trong 1..K; không có duplicate `(image_id, patch_id)`.
- Bản đồ image IDs/TIDs là một-một và **khớp từng ảnh giữa 15 source runs**.
- Có thể xây dựng image→list of `(r,c,w)` theo source, kể cả ảnh không có retained patches.
- Nếu một source bị lỗi, dừng theo `fail_fast`; không tự sửa hay âm thầm bỏ run.

---

## 3. Định nghĩa chung về transaction

Với mỗi image `i`, từ TC5 có tập retained patch observations:

\[
P_i = \{(r_p,c_p,w_p)\mid p\text{ là retained patch của image }i\}.
\]

- `(r_p,c_p)` là **tọa độ patch trên lưới 7×7**, không phải tọa độ pixel 28×28.
- `w_p ∈ {1,…,K}` là word ID từ **cùng** codebook `(K, seed)`.
- Một item xuất hiện trong transaction nếu tồn tại ít nhất một observation hoặc cặp observations thỏa mãn quy tắc encoding của variant đó.
- Với mọi variant, `T_i = sort(unique(encoded_item_ids(P_i)))`.
- `tid=image_id` theo convention baseline 1..70000 (nếu source đang có ánh xạ one-to-one khác, dùng **đúng ánh xạ source** và không tự đổi ID).

**Schema transaction chung:** `transactions.jsonl` UTF-8, đúng một JSON object mỗi dòng:

```jsonl
{"tid":1,"image_id":1,"items":[5,8,12]}
{"tid":2,"image_id":2,"items":[]}
```

Không thêm nhãn lớp/spatial metadata vào `items` dưới dạng JSON object/string; toàn bộ ý nghĩa semantic của item IDs được lưu riêng ở `item_mapping.csv` và trong quy tắc mapping được version hóa.

---

## 4. S0 — Binary BoVW (baseline, không thay đổi)

\[
T_i^{S0}=\operatorname{sort}\big(\operatorname{unique}(\{w_p:(r_p,c_p,w_p)\in P_i\})\big).
\]

- Item universe: **`1..K`**.
- Transaction length: `0 ≤ |T_i| ≤ min(K,49)`.
- Extension loader **chỉ đọc** các file S0 hiện có; không tự tạo lại hoặc thay thế file production.
- Dùng S0 làm oracle cho các phép kiểm tra projection của S1/S3.

---

## 5. S1 — Spatial Grid 2×2

### 5.1. Chia lưới 7×7 cố định

Chia **3+4** hàng và **3+4** cột, với chỉ số 1-based:

| Region | Patch rows | Patch cols | Số ô |
|---|---|---|---:|
| R1 — top-left | 1–3 | 1–3 | 9 |
| R2 — top-right | 1–3 | 4–7 | 12 |
| R3 — bottom-left | 4–7 | 1–3 | 12 |
| R4 — bottom-right | 4–7 | 4–7 | 16 |

```text
R1 R1 R1 | R2 R2 R2 R2
R1 R1 R1 | R2 R2 R2 R2
R1 R1 R1 | R2 R2 R2 R2
---------+------------
R3 R3 R3 | R4 R4 R4 R4
R3 R3 R3 | R4 R4 R4 R4
R3 R3 R3 | R4 R4 R4 R4
R3 R3 R3 | R4 R4 R4 R4
```

Lưu ý: phân chia có kích thước vùng không đều do lưới 7×7 lẻ; đây là **quy ước cố định** của S1, không được thay bằng 4+3 hoặc một phép chia khác mà không đổi version.

### 5.2. Mã hóa item

Với `rgn ∈ {1,2,3,4}`, `w ∈ {1,…,K}`:

\[
\operatorname{ID}_{S1}(rgn,w)=(rgn-1)K+w.
\]

- Item universe `1..4K`.
- Mỗi retained patch đóng góp **một** `(region,word)`; nếu nhiều patches cùng region/word, chỉ giữ một item.
- Example K=64: `(R1,w5)→5`, `(R2,w12)→76`, `(R3,w5)→133`.
- Transaction length: `0 ≤ |T_i^{S1}| ≤ min(4K,49)`.

### 5.3. Acceptance invariant riêng

Giải mã tất cả item `(rgn,w)` của S1 thành `w`, rồi lấy unique:

\[
\operatorname{sort}(\operatorname{unique}(\operatorname{words}(T_i^{S1})))=T_i^{S0},\quad \forall i.
\]

S1 rỗng **khi và chỉ khi** S0 rỗng. Đây là đối chiếu bắt buộc theo từng ảnh của cả 15 codebooks.

---

## 6. S3 — Horizontal Stripes 1×3

### 6.1. Chia lưới 7×7 theo trục dọc

Chia ba dải **2–3–2 hàng**; mỗi dải trải hết 7 cột:

| Stripe | Rows | Số ô |
|---|---|---:|
| 1 = TOP | 1–2 | 14 |
| 2 = MIDDLE | 3–5 | 21 |
| 3 = BOTTOM | 6–7 | 14 |

```text
T T T T T T T
T T T T T T T
-------------
M M M M M M M
M M M M M M M
M M M M M M M
-------------
B B B B B B B
B B B B B B B
```

Không tự chọn cách chia 3–2–2 hoặc 2–2–3; dùng đúng 2–3–2 để vùng giữa được phân biệt và đối xứng theo chiều cao.

### 6.2. Mã hóa item

Với `stripe ∈ {1,2,3}`:

\[
\operatorname{ID}_{S3}(stripe,w)=(stripe-1)K+w.
\]

- Item universe: `1..3K`.
- Ví dụ K=128: `(BOTTOM,w5)→261`.
- Mỗi retained patch đóng góp đúng một `(stripe,word)`; deduplicate trong từng ảnh.
- Transaction length: `0 ≤ |T_i^{S3}| ≤ min(3K,49)`.

### 6.3. Acceptance invariant riêng

\[
\operatorname{sort}(\operatorname{unique}(\operatorname{words}(T_i^{S3})))=T_i^{S0},\quad \forall i.
\]

S3 rỗng **khi và chỉ khi** S0 rỗng.

---

## 7. S6-B — Local Relative Spatial Relations

### 7.1. Ý nghĩa và lựa chọn thiết kế

S6-B biểu diễn **quan hệ có hướng** giữa các visual words xuất hiện tại **hai retained patches khác nhau**, nằm gần nhau trên lưới 7×7.

Chỉ sử dụng **hai loại quan hệ**:

- `ABOVE(w_a,w_b)`: patch mang `w_a` nằm phía **trên** patch mang `w_b`.
- `LEFT_OF(w_a,w_b)`: patch mang `w_a` nằm **bên trái** patch mang `w_b`.

Không thêm `BELOW`, `RIGHT_OF` vì có thể biểu diễn bằng cách đảo thứ tự word. Không thêm quan hệ khác hoặc threshold khoảng cách khác trong v1.

### 7.2. Định nghĩa khoảng cách

Với hai retained patches **khác nhau** `p≠q`, ở `(r_p,c_p)` và `(r_q,c_q)`:

\[
d_1(p,q)=|r_p-r_q|+|c_p-c_q|.
\]

Cặp patch chỉ được xét nếu:

\[
1\le d_1(p,q)\le 2.
\]

Đây là **khoảng cách Manhattan theo đơn vị ô patch**, không phải pixel. Đặc biệt **không** xét các cặp có khoảng cách lớn hơn 2 dù nằm trên cùng một hàng/cột.

### 7.3. Quy tắc phát sinh quan hệ

Với mỗi cặp retained patches không thứ tự `{p,q}` (duyệt cặp đúng một lần):

- Nếu `r_p < r_q`: emit `ABOVE(w_p,w_q)`; nếu `r_q < r_p`: emit `ABOVE(w_q,w_p)`. Nếu cùng hàng: không emit ABOVE.
- Nếu `c_p < c_q`: emit `LEFT_OF(w_p,w_q)`; nếu `c_q < c_p`: emit `LEFT_OF(w_q,w_p)`. Nếu cùng cột: không emit LEFT_OF.
- **Cặp chéo** (khác cả hàng lẫn cột) có thể tạo **hai** relational items: một ABOVE và một LEFT_OF.
- **Cho phép `w_a=w_b`** nếu hai patches **khác nhau** ở vị trí hợp lệ. `ABOVE(w5,w5)` là quan hệ giữa hai vị trí mang cùng một word, không phải quan hệ tự thân của một patch.
- Item `(relation_type,w_a,w_b)` xuất hiện trong ảnh nếu **tồn tại ít nhất một cặp** retained patches thỏa; số cặp tạo quan hệ đó **không được lưu như frequency** trong binary transaction.
- Chỉ quan hệ là items của S6-B; **không** thêm các visual words S0 như những items độc lập.

### 7.4. Mã hóa item ID (deterministic)

Quy ước `relation_index=1` cho `ABOVE` và `relation_index=2` cho `LEFT_OF`.

\[
\operatorname{ID}_{S6}(rel,a,b)=(rel-1)K^2+(a-1)K+b,
\]

trong đó `rel∈{1,2}`, `a,b∈{1,…,K}`.

- Item universe khả dĩ: `1..2K²`. K=128 → tối đa **32.768** loại item ID.
- Tất cả items được sort/unique như các variants khác. Với các cặp đồng nhất word, quy tắc ID vẫn hợp lệ và không nhập nhằng.
- Không tự lọc những relation items hiếm theo support trong TC6; việc đánh giá/điều chỉnh minsup thuộc EDA2/Pilot Eclat.

### 7.5. Giới hạn hình học và tối ưu thuật toán

Trên lưới 7×7 **đầy đủ 49 patches**:

- Có tối đa **226 cặp patches không thứ tự** với Manhattan distance `1..2`.
- Trong số đó, tối đa **72 cặp chéo** sinh hai relations; các cặp còn lại sinh một relation.
- Vì vậy có tối đa **298 relation occurrences** được sinh trên một ảnh trước dedup; sau lọc TC2 và dedup con số không thể tăng.
- Do đó `0 ≤ |T_i^{S6-B}| ≤ min(2K²,298)`. Đây là cận trên kiểm tra **chỉ dành cho quy tắc hiện tại** (không tính các relations khác).

**Hiệu quả:** precompute danh sách 226 neighbor pairs của lưới 7×7 một lần; cho mỗi ảnh chỉ kiểm tra cặp mà cả hai patches còn retained. Không duyệt tất cả các cặp visual words toàn cục `K²`, không nhân K-means, không đọc lại raw pixel để xác định spatial relations.

### 7.6. Trường hợp rỗng và diễn giải

- S6-B **có thể có transaction rỗng ngay cả khi S0 không rỗng** (ví dụ ảnh chỉ giữ một patch hoặc retained patches không có cặp nào cách nhau tối đa hai ô).
- Eclat support denominator vẫn là 70.000.
- Hai quan hệ `ABOVE(a,b)` và `ABOVE(b,a)` có thể cùng xuất hiện trong **một ảnh** nếu có **những lần xuất hiện patches khác nhau** của các words đó; không coi đây mặc định là lỗi.
- Một frequent itemset gồm nhiều relational items không nhất thiết chứng minh tất cả quan hệ được xác nhận bởi **cùng một instance của từng word**. Khi diễn giải phải truy vết witness patch pairs.

### 7.7. Test cases bắt buộc

1. `(r1,c1,w5)` và `(r2,c2,w12)` với positions `(1,1)` và `(2,2)`: `d=2`, sinh **`ABOVE(w5,w12)` và `LEFT_OF(w5,w12)`**.
2. Positions `(1,1)` và `(3,1)`: `d=2`, sinh **chỉ ABOVE**.
3. Positions `(1,1)` và `(3,2)`: `d=3`, **không** sinh relation.
4. Hai observations cùng một patch ID không bao giờ tạo relation; hai patches khác nhau cùng word ID có thể tạo `ABOVE(w5,w5)`.
5. Lặp lại quan hệ qua nhiều cặp patches vẫn chỉ có **một** item trong transaction.
6. Đảo thứ tự đọc các patches không làm thay đổi transaction kết quả.
7. Ảnh không còn retained patch, chỉ còn một patch hoặc không có cặp gần nhau → transaction S6-B rỗng, nhưng record/TID vẫn tồn tại.

---

## 8. TC7 mở rộng — Export, mapping, provenance và read-back

### 8.1. Output isolation

- **Không ghi vào** 15 folders S0 production và không sửa S0 records, checkpoint hoặc metrics.
- Dùng output_root riêng cho các spatial variants, ví dụ `results/fashion/tc/tc6_configs/`.
- Mỗi bộ spatial output có folder riêng với định danh đủ **method + K + seed + variant**, ví dụ:

```text
results/fashion/tc/tc6_configs/
├── S0/
│   ├── B0_config.toml
│   └── FashionMNIST_T2_S0_B0_K128_seed42/
│       └── ... (15 K/seed runs total)
│   ├── tc4_metrics_summary.csv
│   ├── tc4_seed_stability.toml
│   └── tc_v2_run_summary.toml
├── S1/
│   └── FashionMNIST_T2_S1_B0_K128_seed42/
│       ├── transactions.jsonl
│       ├── item_mapping.csv
│       ├── tid_image_mapping.csv
│       ├── config_snapshot.toml
│       ├── source_artifacts.toml
│       ├── encoding_stats.toml
│       ├── integrity_report.toml
│       └── checkpoint.toml
├── S3/
│   └── FashionMNIST_T2_S3_B0_K128_seed42/
├── S6B/
│   └── FashionMNIST_T2_S6B_B0_K128_seed42/
├── spatial_extension_run_summary.toml
└── eda2_database_manifest.toml
```

TC4/K-means B0 và transactions S0 nằm cùng tại `results/fashion/tc/tc6_configs/S0/`; cấu hình chạy K-means được tách riêng tại `configs/tc/kmeans/`. Các spatial variants S1, S3 và S6B nằm cùng cấp dưới `tc6_configs/`, mỗi run có folder riêng theo K/seed. Smoke outputs dùng `tc6_configs/smoke/`.

### 8.2. Artifacts bắt buộc cho mỗi extension database

| File | Nội dung |
|---|---|
| `transactions.jsonl` | 70.000 JSON lines với fields `tid,image_id,items`, kể cả `items:[]` |
| `item_mapping.csv` | Bảng giải mã **tất cả item IDs thực sự xuất hiện** trong bộ transactions (hoặc toàn bộ universe nếu thuận tiện), kèm schema/version |
| `tid_image_mapping.csv` | Bản mapping TID–image_id **giữ nguyên** từ source run (không sinh ID mới) |
| `config_snapshot.toml` | Cấu hình variant và bộ tham số TC nguồn được kế thừa |
| `source_artifacts.toml` | Relative/absolute path tới source B0 run, `codebook.bin`, `patch_assignments.csv`, S0 baseline; checksums/identifiers cho truy vết; **không copy/fit lại codebook** |
| `encoding_stats.toml` | Counts patches/relations, số items observed, empty/nonempty, min/mean/median/max length, thời gian và cảnh báo nếu có |
| `integrity_report.toml` | Pass/fail từng kiểm tra, read-back, denominator, source lineage và variant invariants |
| `checkpoint.toml` | Trạng thái: pending/running/failed/completed; chỉ completed sau read-back PASS |

`item_mapping.csv` có schema chung gồm `item_id`, `variant`, `item_kind`, và các cột phù hợp:

- S1: `region_id`, `region_label`, `word_id`.
- S3: `stripe_id`, `stripe_label`, `word_id`.
- S6-B: `relation_type` (`ABOVE`/`LEFT_OF`), `word_a`, `word_b`.

Các cột không áp dụng có thể để trống trong CSV; bảo đảm mapping **một-một** với item IDs đã dùng. Ghi lại công thức ID và `K` trong config để decode lại mọi ID hợp lệ ngay cả khi chỉ export observed mappings.

### 8.3. Integrity & read-back bắt buộc

Đối với **mọi** bộ `(K,seed,variant)`:

1. Parser đọc lại file từ đĩa, kiểm tra **đúng 70.000** JSON objects; mỗi `tid` duy nhất, `image_id` khớp mapping source và thứ tự nguồn; transactions rỗng không bị bỏ.
2. `items` là integer IDs **unique, strictly increasing**, ở trong range theo variant (`S1:1..4K`, `S3:1..3K`, `S6-B:1..2K²`).
3. Check per-image length: S1≤`min(4K,49)`, S3≤`min(3K,49)`, S6-B≤`min(2K²,298)`; length≥0.
4. `observed_item_ids` trong transactions phải giải mã được và có mặt **đúng một lần** trong mapping; mọi mapping row hợp lệ và tái mã hóa ra `item_id` ban đầu.
5. **S1/S3:** projection sang words bằng mapping phải **bằng S0 cho từng image_id**, và empty status phải khớp S0.
6. **S6-B:** test neighbor-distance/witness cho mẫu và unit tests; không được giả định S6 empties giống S0; không được đánh giá một relational item thiếu witness pair tương ứng.
7. Provenance: variant/K/seed/method, codebook/source hashes và TID mapping trùng source; labels không xuất hiện trong `items`.
8. `record_count = unique_tid_count = transaction_count = support_denominator = 70000`; `empty_count + nonempty_count = 70000`.
9. Mọi checks phải chạy trên **files đã lưu và đọc lại**, không chỉ kiểm tra mảng trong RAM. Không cần fit TC4 hay chạy Eclat để validate TC7.
10. Nếu lỗi: không đánh dấu `COMPLETED`; tuân thủ `fail_fast=true`, báo lỗi có run identifier, variant, K, seed và nguyên nhân; không làm hỏng/ghi đè S0 production.

---

## 9. Notebook/agent scope và thứ tự triển khai

**Extension nên là notebook/module độc lập** (ví dụ `notebooks/TC6_spatial_extension.ipynb` hoặc file notebook Julia theo convention dự án) để tránh xáo trộn pipeline TC1–TC7 đã được nghiệm thu. Notebook chỉ **đọc và tái sử dụng** 15 source runs; tách logic encoding thành functions/modules tái sử dụng.

Thứ tự cell đề xuất:

1. Imports / Project environment / config.
2. Discover đúng 15 S0 source runs theo `(K,seed)`; load config, checkpoint và integrity reports.
3. Read `patch_assignments.csv`, `tid_image_mapping.csv`, S0 JSONL; normalize/verify `(r,c,w)` và preflight 70k.
4. Unit tests cho S1 2×2, S3 stripes, S6-B local relations, ID encode/decode, empty cases.
5. TC6-S1 encoding → TC7 export/read-back cho từng `(K,seed)`.
6. TC6-S3 encoding → TC7 export/read-back cho từng `(K,seed)`.
7. TC6-S6-B encoding → TC7 export/read-back cho từng `(K,seed)`.
8. Tổng hợp completion, per-variant counts, metrics phục vụ EDA2, report file locations.

Để kiểm soát RAM, cho phép streaming theo `image_id` hoặc batching; chỉ yêu cầu output deterministic, hoàn chỉnh và không mất image/TID. Không ép buộc sao chép mọi source artifacts vào RAM cùng lúc. Checkpoint/resume theo từng `(variant,K,seed)`; không ghi đè một completed output nếu `overwrite_production_artifacts=false`.

**Dừng scope tại xuất và integrity/read-back của 45 bộ spatial transactions.** EDA2 và Pilot Eclat thực thi ở notebook/bước nghiên cứu riêng; việc thiết kế artifacts phải hỗ trợ chúng.

---

## 10. Hợp đồng đầu vào cho EDA2 + Pilot Eclat (giai đoạn sau, không tự chạy trong extension)

### 10.1. Thiết kế so sánh

- Tổng **60 databases**: 15 S0 gốc + 15 S1 + 15 S3 + 15 S6-B.
- So sánh **trong cùng một `(K,seed)`** để cô lập tác động encoding; đồng thời phân tích across K/seeds để thấy tương tác với visual vocabulary.
- Không tự chọn K từ S0 trước rồi chỉ chạy spatial variants trên K đó.
- Mọi phương pháp dùng cùng 70k TIDs và denominator; dùng nhiều minsup nhất quán giữa variants, có sensitivity analysis theo sparsity.

### 10.2. Sáu nhóm đánh giá bắt buộc

1. **Transaction length:** mean/median/std, percentiles, min/max, empty rate, utilization (đọc theo universe mỗi variant).
2. **Item support:** histogram/quantiles, số và tỷ lệ observed items/frequent singletons, items quá hiếm/quá phổ biến; với S1/S3 so theo vùng và số patch slots/vùng.
3. **Transaction diversity:** unique/duplicate transaction rate, sampled pairwise Jaccard; lưu ý ID namespaces và cấu trúc không giống nhau giữa variants.
4. **Frequent itemsets:** counts theo độ dài/minsup, support distribution, closed/maximal sets; không tối đa hóa số lượng một cách máy móc.
5. **Mining runtime/peak memory và interpretability:** minh họa itemsets qua visual word centroids, patches gốc, **witness pairs** cho S6-B; nhãn lớp chỉ được dùng sau khi khai thác.
6. **Codebook stability:** dùng TC4 distortion/occupancy/cluster distributions, ARI/seed stability đã có (không tính lại fit); có thể bổ sung transaction/itemset stability giữa seeds theo cách không phụ thuộc vào word-label permutation.

**Phép kiểm tra bổ sung riêng S6-B:** so sánh observed relation support với **null model** hoán đổi vị trí retained words **trong từng ảnh**, cố định vị trí retained patches và giữ nguyên multiset word IDs mỗi ảnh, dùng random seed xác định. Đây là **thí nghiệm đánh giá ở EDA2**, không phải thành phần TC6 và không dùng để sinh primary transactions. Không mặc định S6 tốt hơn chỉ vì quan hệ có vẻ diễn giải được.

**Quy tắc chọn cuối cùng:** cân bằng quality/interpretability/cost và độ ổn định; không lấy số frequent itemsets, raw distortion hoặc support đơn lẻ làm hàm mục tiêu tuyệt đối. Kết quả nghiên cứu có thể chốt `(K*,seed*,variant*)` và giải thích trade-offs.

---

## 11. TOML cấu hình extension tham chiếu

```toml
[run]
mode = "spatial_extension"
run_id = "FashionMNIST_T2_spatial_70k"
source_root = "results/fashion/tc/tc6_configs/S0"
output_root = "results/fashion/tc/tc6_configs"
overwrite_production_artifacts = false
fail_fast = true

[source]
training_method = "raw_full_batch_kmeans"
method_alias = "B0"
k_candidates = [16, 32, 64, 128, 256]
random_seeds = [42, 123, 2026]
expected_codebooks = 15
expected_images = 70000
expected_patch_grid = [7, 7]
patch_order = "row_major"
require_completed_integrity = true
reuse_s0_without_rewrite = true

[tc6_spatial_extension]
variants_to_generate = ["S1", "S3", "S6-B"]
reference_variant = "S0"
one_image_one_transaction = true
preserve_empty = true
deduplicate = true
sort_items = true
include_labels = false
transactions_format = "jsonl"

[tc6_spatial_extension.s1]
region_layout = "grid_2x2"
row_break_after = 3
col_break_after = 3

[tc6_spatial_extension.s3]
stripe_layout = "horizontal_1x3"
rows_per_stripe = [2, 3, 2]

[tc6_spatial_extension.s6b]
relation_types = ["ABOVE", "LEFT_OF"]
distance = "manhattan_patch_grid"
min_distance = 1
max_distance = 2
pair_semantics = "exists_distinct_retained_patch_pair"
allow_same_word_on_distinct_patches = true
emit_both_relations_for_diagonal_pairs = true
include_global_words = false

[tc7_spatial_export_validation]
transactions_filename = "transactions.jsonl"
item_mapping_filename = "item_mapping.csv"
expected_transactions_per_variant = 70000
support_denominator_source = "total_transaction_records"
readback_integrity_validation = true
validate_projection_to_s0_for_s1_s3 = true
record_source_artifact_hashes = true
save_encoding_stats = true

[execution]
backend = "cpu"
```

**Lưu ý config:** Các khóa trên là **hợp đồng cấu hình đề xuất của extension mới**, không phải cam kết rằng notebook hiện tại đã hỗ trợ chúng. Coding agent phải implement parser/validation phù hợp; tuyệt đối không coi block Q20 của baseline TC v2.1 là lý do thay method khi chạy extension.

---

## 12. Acceptance checklist / Definition of Done

- [ ] Đọc đúng **15** completed B0/S0 source runs (5 K × 3 seeds); preflight metadata, assignments, mappings, coordinates PASS.
- [ ] Không fit lại K-means, không chạy lại TC1–TC5; S0 folders và files giữ nguyên.
- [ ] S1 vùng R1–R4 theo **3+4** hàng/cột; encode ID `(region-1)K+w`, dedup/sort.
- [ ] S3 theo **2–3–2** hàng; encode ID `(stripe-1)K+w`, dedup/sort.
- [ ] S6-B đúng Manhattan `1..2`, chỉ ABOVE/LEFT_OF có hướng, cho cặp chéo hai relations, same-word distinct-patch allowed, relation existence + dedup.
- [ ] S6-B precomputed neighbor pairs và các unit tests ở §7.7 PASS.
- [ ] Tạo đúng **45 bộ spatial transactions** mới, **70.000 JSONL records/bộ**, tất cả TIDs được bảo toàn kể cả rỗng.
- [ ] Mỗi bộ có item mapping, config snapshot, source lineage, encoding stats, integrity report, checkpoint; không nhập nhằng variant/K/seed.
- [ ] S1/S3 **projection khớp S0 từng ảnh** trên đủ 15 codebooks; riêng S6-B có thể rỗng dù S0 không rỗng.
- [ ] Mọi item IDs, lengths, mapping decode/encode, source provenance và denominator=70k đạt kiểm tra.
- [ ] Read-back **từ files đã ghi** PASS trước khi mark `COMPLETED`; không overwrite outputs production.
- [ ] Có báo cáo 60 available databases cho EDA2 (15 S0 + 45 spatial) và danh sách đường dẫn, checksums, pass/fail.
- [ ] Chưa chạy EDA2, Pilot Eclat, chọn best K/seed/variant, hay triển khai S2 và các encodings ngoài scope.

**End of specification.**
