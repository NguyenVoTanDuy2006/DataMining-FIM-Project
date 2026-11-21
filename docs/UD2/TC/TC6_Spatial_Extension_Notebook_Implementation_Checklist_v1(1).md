# CHECKLIST — Notebook triển khai TC6 Spatial Extension (S0, S1, S3, S6-B)

**Version:** 1.0 — 2026-11-18  
**Dùng để giao:** coding agent triển khai **một notebook Julia** điều phối việc tái sử dụng dữ liệu TC đã có và xuất dữ liệu cho EDA2.  
**Nguồn yêu cầu chính:** `TC6_Spatial_Encoding_Extension_Spec_v1.md` (v1.0).  
**Tài liệu nền:** `TC_Transaction_Construction_Spec_v2.md` và `TC1_TC7_Notebook_Implementation_Checklist.md` (revision 2.1).  
**Nguyên tắc:** Nếu checklist thiếu chi tiết hoặc có xung đột, ưu tiên **TC6 extension spec v1.0**; không thay đổi quy tắc nghiên cứu mà chưa được xác nhận.

## 0. Phạm vi và Definition of Done

- [ ] **SC01 — Một notebook riêng:** triển khai notebook Julia độc lập (ví dụ `notebooks/TC6_spatial_extension.ipynb`; dùng convention thực tế của repository). Notebook điều phối; logic xử lý có thể tái sử dụng dưới dạng hàm/module.
- [ ] **SC02 — Hỗ trợ đủ bốn phương pháp:** `S0`, `S1`, `S3`, `S6-B`. **S0 là baseline đã có, chỉ được đọc và kiểm tra; không tạo lại hoặc ghi đè**. Implement mới **S1, S3, S6-B**.
- [ ] **SC03 — Reuse kết quả TC4/TC5:** chỉ dùng 15 source runs B0 `(K,seed)` đã lưu; **không gọi lại** TC1, TC2, TC3, K-means TC4 hoặc hard assignment TC5.
- [ ] **SC04 — Input 15 cấu hình:** `K=[16,32,64,128,256]`, `seeds=[42,123,2026]`; một source duy nhất cho mỗi tổ hợp; tuyệt đối không tự shortlist K/seed.
- [ ] **SC05 — Kết quả:** 15 bộ S0 gốc + **45 bộ spatial mới** = **60 bộ được tham chiếu cho EDA2**; mỗi bộ 70.000 transactions. 45 bộ mới tương ứng 3.150.000 dòng JSONL.
- [ ] **SC06 — Ngoài scope:** không S2 Spatial Pyramid, Q20, đào tạo codebook, thử minsup, EDA2, Pilot Eclat, class-conditional similarity, chọn cấu hình cuối cùng hay tạo association rules.
- [ ] **SC07 — Bảo toàn production:** `source_root` ở chế độ read-only; `output_root` khác `source_root`; cấm ghi đè S0 và cấm sửa codebooks, assignments, metrics, checkpoints gốc.

## A. Notebook Setup & Config

- [ ] **A01 — Khảo sát mã có sẵn:** kiểm tra cách project đọc TOML/CSV/JSONL, Julia environment, output conventions và hàm mã hóa/validation có thể tái dùng; không tự viết lại nếu hàm đã đúng.
- [ ] **A02 — Cấu hình riêng:** cấu hình TOML theo mục §11 của extension spec (`mode=spatial_extension`, `source_root`, `output_root`, `K`, `seeds`, `variants`, fail_fast, overwrite=false).
- [ ] **A03 — Tham số bắt buộc:** S1 `row_break_after=3`, `col_break_after=3`; S3 `rows_per_stripe=[2,3,2]`; S6-B `ABOVE`, `LEFT_OF`, Manhattan `min=1`, `max=2`, same-word allowed, diagonals emit both.
- [ ] **A04 — Validate config:** chỉ nhận variants được quy định; không tự coi `tc4_methods.q20_weighted_kmeans` là yêu cầu chạy lại TC4; khi sai/thiếu config thì fail có thông báo.
- [ ] **A05 — Reproducibility:** ghi Julia/package versions, config snapshot và phiên bản quy tắc encoding; cùng inputs/config phải cho cùng output.
- [ ] **A06 — Ràng buộc output:** tách hoàn toàn `source_root` và `output_root`; không ghi đè run đã `COMPLETED` khi overwrite=false; hỗ trợ resume an toàn theo từng `(K,seed,variant)`.
- [ ] **A07 — Logging:** báo rõ giai đoạn, K, seed, variant, số ảnh xử lý, timing, source/output path và lỗi; không in hàng triệu rows trong notebook.
- [ ] **A08 — Layout notebook:** có các mục 00–10 theo phần cuối checklist; trước mỗi code cell có Markdown ngắn về mục đích, input, output hoặc phép kiểm tra; không thêm cell phân tích ngoài scope.

## B. Discovery 15 source runs (S0)

- [ ] **B01 — Discover nguồn thực tế:** quét `results/fashion/tc/tc6_configs/S0` (hoặc config path) theo **run_id/metadata**, không dựa hoàn toàn vào thứ tự folder.
- [ ] **B02 — Unique runs:** tạo danh sách canonical 15 cặp `(K,seed)`; **dedup run_ids** khi đọc summary để tránh vấn đề 42 records lặp từng xuất hiện trong báo cáo tổng hợp; không coi records trùng là codebooks độc lập.
- [ ] **B03 — File nguồn bắt buộc:** kiểm tra `patch_assignments.csv`, `transactions.jsonl` S0, `tid_image_mapping.csv`, `config_snapshot.toml`, `integrity_report.toml`, `checkpoint.toml` của từng source.
- [ ] **B04 — Lineage bổ trợ:** ghi đường dẫn/identity của `codebook.bin`, `tc4_metrics.toml` và nếu cần `assignments.bin`; không dùng `.bin` thay CSV cho đến khi đã xác thực schema tương đương.
- [ ] **B05 — Metadata matching:** kiểm tra method B0, K, seed, 70k ảnh, 28×28, patch 4×4, patch grid 7×7, row-major, TC2 threshold 29, S0; không âm thầm sửa metadata.
- [ ] **B06 — Source status:** kiểm tra checkpoint/integrity **độc lập**. Chỉ nhận nguồn hoàn chỉnh và hợp lệ; ghi chú riêng `converged`/`NON_CONVERGED` của TC4, không đánh đồng với tình trạng export/integrity. Nếu không khớp acceptance của spec: báo blocker, không tự chạy lại K-means.
- [ ] **B07 — Phát hiện lỗi sớm:** nếu thiếu source, duplicate conflicting source hoặc file lỗi thì `fail_fast`; ghi `run_id`, đường dẫn và nguyên nhân.
- [ ] **B08 — Manifest 15 nguồn:** chuẩn bị bảng `source_run_id,K,seed,method,s0_path,assignments_path,mapping_path,codebook_path,source_integrity,source_hash_or_identifier` để nội bộ notebook và output tổng hợp.

## C. Loader & Preflight dữ liệu từng source

- [ ] **C01 — Đọc S0 JSONL** với schema `tid` (int), `image_id` (int), `items` (int[]); đủ 70.000 records, bao gồm `[]`; IDs unique/sorted trong `1..K`.
- [ ] **C02 — TID/image map:** đọc `tid_image_mapping.csv` và xác nhận one-to-one; giữ nguyên thứ tự và định danh, không tự giả định tất cả `tid=image_id` nếu file dùng quy ước khác.
- [ ] **C03 — Đọc `patch_assignments.csv`:** khớp schema thật của file; tối thiểu nhận được `image_id`, `patch_id`, `word_id`, patch row/col hoặc tọa độ có thể phục hồi một cách có căn cứ.
- [ ] **C04 — Chuẩn hóa tọa độ:** đưa về `(r,c)` 1-based trên lưới 7×7; nếu có `patch_row/patch_col` dùng trực tiếp; nếu là top-left pixel hoặc patch_id thì chuyển theo quy tắc §2.2 của spec, **chỉ khi biết chắc base/order**.
- [ ] **C05 — Kiểm tra tọa độ:** r,c∈1..7; `patch_id∈1..49`; không duplicate `(image_id,patch_id)`; `word_id∈1..K`; các nguồn tọa độ cùng tồn tại phải nhất quán.
- [ ] **C06 — Không tái đánh số patch_id:** patch_id gốc được tạo trước lọc TC2; không nén/đánh lại sau lọc.
- [ ] **C07 — Dữ liệu đúng retained patches:** **chỉ** dùng assignments của retained patches; không đọc raw pixel, không khôi phục patches đã lọc để tạo spatial items.
- [ ] **C08 — Index theo ảnh:** nhóm observations `(r,c,w)` theo `image_id`, đảm bảo những ảnh không có retained patches vẫn tồn tại khi sinh output.
- [ ] **C09 — Cross-check S0:** `sort(unique(words_from_retained_patches(image)))` phải bằng `S0.items` cho mọi ảnh trước khi encode spatial variants.
- [ ] **C10 — Cross-run consistency:** 15 sources phải có cùng ánh xạ TID→image_id và 70.000 ảnh; khác word IDs giữa codebooks là điều bình thường, **không** so số nguyên word IDs giữa seeds.
- [ ] **C11 — Memory plan:** có thể stream/batch theo image_id; chỉ lưu các structures thật sự cần; không ép tải tất cả 15 CSV và transactions vào RAM cùng lúc.

## D. Encoder S0 — Reuse baseline

- [ ] **D01 — Dùng S0 như oracle:** load đủ 15 `transactions.jsonl` gốc phục vụ projection checks; không xuất đè một file S0 nào.
- [ ] **D02 — Không mutate:** không sort/rewrite S0 trên đĩa; nếu nguồn không hợp lệ thì fail/report thay vì tự sửa.
- [ ] **D03 — Manifest link:** đưa S0 vào final manifest (15 `database_id` S0), lưu source path/hashes để EDA2 đọc bản gốc.
- [ ] **D04 — Schema baseline:** item universe `1..K`, max length `min(K,49)`; S0 empty iff không có retained patches.

## E. Encoder S1 — Spatial Grid 2×2

- [ ] **E01 — Vùng cố định:** R1 rows 1–3 cols 1–3; R2 rows 1–3 cols 4–7; R3 rows 4–7 cols 1–3; R4 rows 4–7 cols 4–7. Không đổi thành 4+3.
- [ ] **E02 — Hàm region:** mỗi retained patch thuộc đúng một trong bốn vùng; kiểm tra 49 vị trí phủ kín, số ô 9/12/12/16.
- [ ] **E03 — Encode ID:** `id=(region_id-1)*K+word_id`, với region 1..4; range `1..4K`; kiểm tra decode→encode ngược.
- [ ] **E04 — Binary transaction:** mỗi patch đóng góp `(region,word)`; dedup và sort, không thêm global word ids.
- [ ] **E05 — Giới hạn và empty:** `length <= min(4K,49)`; S1 rỗng iff S0 rỗng.
- [ ] **E06 — Invariant bắt buộc:** giải mã S1 rồi unique visual words phải **khớp chính xác S0 cho cả 70k ảnh** của mỗi `(K,seed)`.
- [ ] **E07 — Mini test:** với K=64: `(R1,w5)=5`, `(R2,w12)=76`, `(R3,w5)=133`; cùng region/word từ nhiều patches chỉ là một item.

## F. Encoder S3 — Horizontal Stripes 1×3

- [ ] **F01 — Dải cố định:** TOP rows 1–2 (14 ô), MIDDLE rows 3–5 (21 ô), BOTTOM rows 6–7 (14 ô).
- [ ] **F02 — Hàm stripe:** mọi vị trí patch thuộc đúng một dải, không chia 3–2–2 hoặc 2–2–3.
- [ ] **F03 — Encode ID:** `id=(stripe_id-1)*K+word_id`, stripe 1..3, range `1..3K`; kiểm tra decode→encode.
- [ ] **F04 — Binary transaction:** dedup/sort, không thêm global word ids.
- [ ] **F05 — Giới hạn và empty:** `length <= min(3K,49)`; S3 rỗng iff S0 rỗng.
- [ ] **F06 — Invariant bắt buộc:** giải mã S3 về unique words phải **bằng S0 từng ảnh** (15×70k comparisons).
- [ ] **F07 — Mini test:** K=128, `(BOTTOM,w5)=261`; cùng stripe/word từ nhiều patches chỉ là một item.

## G. Encoder S6-B — Local Relative Spatial Relations

- [ ] **G01 — Chỉ hai relation types:** index 1 = `ABOVE`, index 2 = `LEFT_OF`; không thêm BELOW, RIGHT_OF, adjacency khác, global words hay thresholds mới.
- [ ] **G02 — Chỉ retained-patch pairs:** cặp **hai patches khác nhau**, không thứ tự, mỗi cặp duyệt đúng một lần; Manhattan distance `d=|r1-r2|+|c1-c2|` trong `1..2` (đơn vị ô, không phải pixel).
- [ ] **G03 — Precompute neighbor pairs:** với full grid 7×7 có đúng **226 unordered pairs** ở Manhattan 1..2; **72 cặp chéo** có thể sinh hai relations; kiểm tra upper bound **298 relation occurrences** trước dedup.
- [ ] **G04 — ABOVE:** nếu `r_p<r_q` emit `(ABOVE,w_p,w_q)`; nếu đảo hướng thì emit ngược word order; cùng row không emit ABOVE.
- [ ] **G05 — LEFT_OF:** nếu `c_p<c_q` emit `(LEFT_OF,w_p,w_q)`; đảo hướng thì emit ngược word order; cùng column không emit LEFT_OF.
- [ ] **G06 — Diagonal:** một pair chéo `d=2` có thể emit **cả ABOVE và LEFT_OF**; hai quan hệ có thể có thứ tự word khác nhau tùy hướng hình học.
- [ ] **G07 — Same-word:** cho phép `(ABOVE,w,w)` hoặc `(LEFT_OF,w,w)` nếu witnesses là hai patches **khác nhau**. Không được tạo relation từ một patch so với chính nó.
- [ ] **G08 — Existence semantics:** relation tồn tại nếu **ít nhất một** cặp patches hợp lệ làm witness; lặp nhiều witnesses chỉ tạo **một item** trong transaction.
- [ ] **G09 — Encode ID:** `id=(relation_index-1)*K^2+(word_a-1)*K+word_b`; universe `1..2K^2`; mã hóa/giải mã lossless.
- [ ] **G10 — Không trộn S0:** S6-B chỉ có relational items, không chứa visual-word IDs đơn lẻ.
- [ ] **G11 — Giới hạn:** `0<=length<=min(2K^2,298)`; S6-B **có thể rỗng dù S0 không rỗng**; không dùng điều kiện iff của S1/S3.
- [ ] **G12 — Witness check:** có thể truy ngược một relational item được chọn ra ít nhất một cặp patches `(p,q)` còn retained đúng hướng/khoảng cách.
- [ ] **G13 — Unit test 1:** `(1,1,w5)` và `(2,2,w12)` tạo **ABOVE(5,12)** và **LEFT_OF(5,12)**.
- [ ] **G14 — Unit test 2:** `(1,1,w5)` và `(3,1,w12)` chỉ có **ABOVE(5,12)**.
- [ ] **G15 — Unit test 3:** `(1,1)` và `(3,2)` có `d=3` nên không tạo relation.
- [ ] **G16 — Unit test 4:** hai positions khác nhau nhưng cùng word tạo relation hợp lệ; trùng position/patch ID không tạo relation.
- [ ] **G17 — Unit test 5:** cùng relation sinh bởi nhiều pairs vẫn là một item; thay đổi thứ tự đọc patches không đổi output.
- [ ] **G18 — Unit test 6:** image rỗng, chỉ một retained patch, hoặc có nhiều patches nhưng không có valid neighbor pairs → items `[]` và **vẫn có record**.
- [ ] **G19 — Boundary test:** cặp cách 1, 2 được nhận; cách 3 bị loại; ở các hàng/cột biên không có out-of-bounds.

## H. TC7 spatial — Export artifacts độc lập

- [ ] **H01 — Thư mục theo run:** tạo 45 folders riêng có `variant, B0, K, seed` (vd `FashionMNIST_T2_S6B_B0_K128_seed42`); không trộn item IDs hoặc metadata giữa runs.
- [ ] **H02 — `transactions.jsonl`:** UTF-8, **70.000 JSON objects**, đúng `tid,image_id,items` (integer array); preserve empty `[]`, sort/unique ascending.
- [ ] **H03 — `item_mapping.csv`:** mapping đầy đủ **observed item IDs** (hoặc cả universe), mỗi ID một dòng, có `item_id,variant,item_kind`, và S1 `region_id,region_label,word_id`; S3 `stripe_id,stripe_label,word_id`; S6-B `relation_type,word_a,word_b`.
- [ ] **H04 — `tid_image_mapping.csv`:** xuất mapping **giống source** trong mỗi output; kiểm tra bytewise/semantic equality tùy format CSV; không reassign IDs.
- [ ] **H05 — `config_snapshot.toml`:** lưu variant, K, seed, B0, grid/rules/ID formulas, input TC config kế thừa và encoding version; không ghi nhãn lớp vào items.
- [ ] **H06 — `source_artifacts.toml`:** đường dẫn source run/S0/patch CSV/codebook (ref, **không copy codebook**), checksum/identity cho lineage; không phụ thuộc vào summary CSV có duplicate.
- [ ] **H07 — `encoding_stats.toml`:** record/empty/nonempty counts; retained patches/relations processed; observed items; min/mean/median/max transaction length; timing và warnings.
- [ ] **H08 — `integrity_report.toml`:** kết quả cụ thể của từng validation, source lineage và read-back.
- [ ] **H09 — `checkpoint.toml`:** status rõ ràng `PENDING/RUNNING/FAILED/COMPLETED`; đánh dấu `COMPLETED` **chỉ sau** khi read-back PASS.
- [ ] **H10 — Output isolation:** ghi các variants vào `results/fashion/tc/tc6_configs/{S1,S3,S6B}/` hoặc config path riêng; không sửa S0 production hay source B0 files; no overwrites.
- [ ] **H11 — Atomicity/resume:** tránh public partial outputs như hoàn tất; nếu interrupted thì giữ checkpoint để resume, khi resume không chạy lại TC4/TC5 và không nhân bản 70k records.

## I. Read-back & Integrity Acceptance

- [ ] **I01 — Đọc lại từ đĩa** mọi `transactions.jsonl`, mappings, configs, stats; không chỉ kiểm tra dữ liệu còn trong RAM.
- [ ] **I02 — Cardinality mỗi run:** `transaction_count=unique_tid_count=image_count=support_denominator=70000`, `empty_count+nonempty_count=70000`.
- [ ] **I03 — TID mapping:** không thiếu, trùng, đảo hoặc phát sinh image/TID mới; khớp source S0 của đúng K/seed.
- [ ] **I04 — Item validity:** ID dương, in-range theo variant, strictly increasing và unique; không có labels hay object strings trong `items`.
- [ ] **I05 — Length bounds:** S1≤min(4K,49), S3≤min(3K,49), S6-B≤min(2K²,298).
- [ ] **I06 — Item mapping:** mọi observed item có đúng một mapping row; decode/encode round-trip khớp; không tồn tại conflicts hoặc mapping sai variant/K.
- [ ] **I07 — S1 projection:** toàn bộ 70k ảnh của mỗi source: projection words(S1) == S0; empty iff khớp.
- [ ] **I08 — S3 projection:** tương tự với S3; không chấp nhận chỉ lấy mẫu để nghiệm thu điều kiện này.
- [ ] **I09 — S6-B witness:** unit tests + sampled observed relations phải có witness pairs; không áp empty iff S0.
- [ ] **I10 — Provenance:** source hashes/method/K/seed/variant/path/checkpoints nhất quán; không sửa source artifacts.
- [ ] **I11 — Errors:** nếu validation/read-back fail, run = `FAILED` hoặc `BLOCKED`, tuyệt đối không `COMPLETED`; có log và nguyên nhân cụ thể.

## J. Execution & Bàn giao

- [ ] **J01 — Unit tests trước:** chạy tests cho region/stripe functions, S6-B geometry, encode/decode, duplicated inputs và empty cases.
- [ ] **J02 — Smoke test:** chạy trên subset ảnh nhỏ và **một** K/seed để kiểm tra end-to-end exporter, không ghi vào production root; smoke run có tên/path riêng.
- [ ] **J03 — Full execution:** với 15 source runs, xuất lần lượt S1/S3/S6-B; checkpoint sau từng bộ; thứ tự chạy deterministic.
- [ ] **J04 — Tổng hợp 45 outputs mới:** `spatial_extension_run_summary.toml` ghi 45 statuses, counts/timing, warnings, locations, checksum hoặc path identifiers.
- [ ] **J05 — EDA2 manifest:** xuất hoặc cung cấp manifest có đúng **60 database references** (`15 S0 existing + 45 spatial newly created`), duy nhất theo `(K,seed,variant)` và có đường dẫn `transactions`, `item_mapping/ref`, source codebook và lineage.
- [ ] **J06 — Chạy nghiệm thu:** xác nhận **45/45** new runs `COMPLETED/PASS`, 45×70k records và 15 S0 untouched; khi có nguồn lỗi thì báo số thực tế, không tuyên bố hoàn tất 45/45.
- [ ] **J07 — Báo cáo:** cung cấp notebook path, files/modules thay đổi, command/cách chạy, output_root, số run thành công/thất bại, memory/runtime đáng chú ý và các limitations.
- [ ] **J08 — Dừng scope:** không chạy EDA2, class similarity, Pilot Eclat, S6-B permutation null model, lựa chọn K/seed/variant hoặc tinh chỉnh minsup.

## K. Notebook cell order (một notebook)

| Thứ tự | Section / Cell group | Output / Acceptance |
|---|---|---|
| 00 | Environment & Config | Validated Julia environment, TOML, paths |
| 01 | Source Discovery | Canonical manifest 15 `(K,seed)` |
| 02 | Source Preflight | S0 70k, source checkpoint/integrity, metadata and hashes |
| 03 | Load & Normalize Patch Assignments | Per-image `(r,c,w)`, TID mapping, checked vs S0 |
| 04 | Encoder Functions & Unit Tests | S0 oracle, S1/S3/S6-B ID/geometry/empty tests |
| 05 | S1 Encode → Export → Read-back | 15 S1 outputs |
| 06 | S3 Encode → Export → Read-back | 15 S3 outputs |
| 07 | S6-B Encode → Export → Read-back | 15 S6-B outputs |
| 08 | Cross-variant & Source Integrity | S1/S3 projection vs S0, witnesses, 70k denominators |
| 09 | Global Summaries & EDA2 Manifest | 45 statuses, 60 source references |
| 10 | Execution Summary / Handover | What ran, files saved, failures and how to rerun |

**Nguyên tắc tổ chức:** Notebook gọi các functions/modules đã kiểm thử, tránh lặp ba block xử lý export/read-back gần giống nhau; **không** thêm phần phân tích EDA2 vào notebook extension.

## L. Definition of Done (ký nghiệm thu)

- [ ] Có đúng **15 source B0/S0 runs hợp lệ** và đọc được patch assignments có tọa độ.
- [ ] S0 chỉ đọc, 15 source folders/file contents không bị thay đổi.
- [ ] S1, S3, S6-B chạy đúng theo spec, tất cả unit tests PASS.
- [ ] Sinh đúng **45 thư mục output** và **45 `transactions.jsonl`**, mỗi file 70.000 records, bao gồm transactions rỗng.
- [ ] Có đúng 45 bộ mappings/config/lineage/stats/checkpoint/integrity reports; read-back PASS cho tất cả.
- [ ] S1 và S3 projection khớp S0 theo từng ảnh trong đủ 15 sources; S6-B witnesses/geometry/empty cases được xác nhận.
- [ ] Có summary và manifest đại diện **60 datasets** phục vụ EDA2, không nhân bản S0.
- [ ] Không chạy lại K-means/TC5 và không phát sinh EDA2/Pilot Eclat trong quá trình này.

**Kết thúc checklist.**
