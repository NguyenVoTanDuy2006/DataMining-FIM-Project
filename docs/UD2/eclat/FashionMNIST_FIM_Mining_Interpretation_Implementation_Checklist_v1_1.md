# IMPLEMENTATION CHECKLIST v1.1 — Fashion-MNIST FIM Mining, Interpretation & Downstream Applications

**Tương ứng spec:** `FashionMNIST_FIM_Mining_Interpretation_Spec_v1_1.md` (19/11/2026)  
**Trạng thái:** Checklist giao coding agent; **chưa xác nhận các hạng mục đã triển khai hoặc chạy thành công**.  
**Phạm vi:** Ứng dụng 2 trên Fashion-MNIST; chạy Eclat **đã có của nhóm** và diễn giải frequent visual itemsets.  
**Quy ước:** `[ ]` chưa làm, `[x]` hoàn thành sau khi có bằng chứng; **HARD** = bắt buộc, **CONDITIONAL** = bắt buộc nếu đủ nguồn, **OPTIONAL** = ngoài phạm vi mặc định.  
**Nguyên tắc:** đánh dấu hoàn thành dựa trên **file output + sanity audit + logs**, không chỉ vì code cell chạy không báo lỗi.

## 0. Chốt cấu hình, ranh giới và danh sách bàn giao (spec §§0–1, 12)

- [ ] **L001 [HARD] — Khóa cấu hình:** B0 / `raw_full_batch_kmeans`, `K=32`, `seed=123`, `encoding=S0`, tập Fashion-MNIST gồm **70.000** ảnh/giao dịch.
- [ ] **L002 [HARD] — Input duy nhất:** sử dụng `results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl` **read-only**, không dùng đường dẫn `v2_full_s0` cũ.
- [ ] **L003 [HARD] — N đã kiểm định:** dựa trên xác nhận có 70.000 transactions và **0 empty**; chỉ sanity-check lúc load, **không làm lại TC7**.
- [ ] **L004 [HARD] — Không mở lại selection:** không chạy EDA2, không so sánh lại 15 codebooks/60 configurations, không thử S1/S3/S6-B trong FIM chính.
- [ ] **L005 [HARD] — Giữ nguyên nguồn:** không sửa/chạy lại TC1–TC7, codebook, assignments, image metadata hoặc transactions sản xuất.
- [ ] **L006 [HARD] — Giữ nguyên thuật toán:** không sửa Eclat core, tests, tối ưu, benchmark, CLI hoặc mã của thành viên khác; chỉ tích hợp qua public API.
- [ ] **L007 [HARD] — Bốn RQ:** báo cáo cần trả lời Mining behavior, Visual meaning, Image data analysis, Downstream applicability (theo spec §1).
- [ ] **L008 [HARD] — Phân tầng phạm vi:** mining/analysis/visual evidence/retrieval/downstream discussion là bắt buộc; classifier mới là optional.
- [ ] **L009 [HARD] — Notebook architecture:** thống nhất 2 notebook chính `FIM_Mining_Experiments.ipynb` (FIM-00–02) và `FIM_Visual_Interpretation.ipynb` (FIM-03–04), hoặc ghi rõ nếu repo đã có cấu trúc khác.
- [ ] **L010 [HARD] — Không chạy lại mining khi sửa báo cáo:** notebook interpretation đọc **các output đã lưu** thay vì tự gọi `mine` mỗi lần tạo plots/gallery.

## 1. FIM-00 — Environment, input handoff & Eclat adapter (spec §§2–3, 10)

### 1.1. Setup và nguồn dữ liệu

- [ ] **I001 [HARD] — Repo-relative paths:** cấu hình source/output paths theo repo; không hardcode đường dẫn tuyệt đối máy cá nhân.
- [ ] **I002 [HARD] — Nguồn chuẩn:** xác nhận file JSONL tồn tại, ghi `input_sha256`, source path, configuration ID và thời điểm chạy vào `input_manifest.toml`.
- [ ] **I003 [HARD] — Loader JSONL:** đọc từng dòng JSONL và chỉ đưa `items` vào dữ liệu mining, giữ **mỗi dòng là đúng một transaction**.
- [ ] **I004 [HARD] — Julia type:** tạo `Vector{Vector{Int}}` (hoặc vector giao dịch tương thích API, được ghi nhận), với **đúng 70.000 phần tử**.
- [ ] **I005 [HARD] — S0 item assertions:** mỗi `items` là tập các `Int` thuộc `1:32`, không lặp trong transaction; đọc đủ 70.000 dòng, không tự loại dòng hay âm thầm chữa dữ liệu.
- [ ] **I006 [HARD] — Mapping:** bảo toàn index của dòng JSONL ↔ TID/image_id; Julia 1-based index **không mặc nhiên bằng** `tid` hay `image_id`.
- [ ] **I007 [HARD] — Không label leakage vào mining:** `tid`, `image_id`, `split`, `label` không được biến thành items.
- [ ] **I008 [HARD] — Reuse input notebook:** tái sử dụng loader đã có khi phù hợp; không cần xuất SPMF để gọi Eclat.
- [ ] **I009 [HARD] — Supersede minsup cũ:** không dùng lại `[10%,7%,5%,3%,2%,1%,0.5%]` từ notebook chuẩn bị trước; grid chính thức ở §2.
- [ ] **I010 [HARD] — Config snapshot:** lưu K, seed, encoding, source, N, engine, minsup counts/fractions, chính sách giới hạn và output dir.

### 1.2. Chỉ tích hợp public Eclat API

- [ ] **I011 [HARD] — Import module thực tế:** xác định cách load/import `EclatFIM` từ code nhóm trong repo; không sao chép hay refactor core.
- [ ] **I012 [HARD] — Cú pháp bắt buộc:** `patterns = EclatFIM.mine(transactions, min_count)`; `min_count::Int` là **absolute support count**.
- [ ] **I013 [HARD] — Output contract:** kiểm tra kết quả là `Dict{Tuple{Vararg{Int}},Int}` hoặc Dict thực tế tương thích contract; key canonical, value support integer.
- [ ] **I014 [HARD] — Adapter ngoài core:** mọi parsing, logging, status, serialization, plotting nằm ngoài các file thuật toán Eclat.
- [ ] **I015 [HARD] — No invented return metadata:** không giả định `mine` trả TID-sets, runtime, output path hoặc trạng thái đầy đủ ngoài Dict.
- [ ] **I016 [HARD] — Optional limits:** trước khi truyền `max_length`, `deadline`, `max_itemsets`, phải kiểm tra semantics thực tế trong code được bàn giao; production full run mặc định chỉ truyền 2 positional arguments.
- [ ] **I017 [HARD] — Integration failure policy:** nếu module không load hoặc API khác contract, ghi `BLOCKED` + bằng chứng; không tự sửa thuật toán.
- [ ] **I018 [HARD] — Provenance runtime:** ghi engine revision/commit, Julia version, OS, CPU/RAM nếu có, effective threads và package versions cần thiết.

**Acceptance FIM-00:** nạp đúng `N=70_000`, chỉ có visual-word IDs 1–32, có input hash và gọi được public `EclatFIM.mine` từ notebook/runner mà không sửa core.

## 2. FIM-01 — Official six-minsup mining (spec §4)

### 2.1. Cấu hình thí nghiệm khóa cứng

| Thứ tự | MinSup | `minsup_fraction` | `min_count` (`N=70_000`) |
|---:|---:|---:|---:|
| 1 | **80%** | 0.80 | **56.000** |
| 2 | **60%** | 0.60 | **42.000** |
| 3 | **40%** | 0.40 | **28.000** |
| 4 | **20%** | 0.20 | **14.000** |
| 5 | **10%** | 0.10 | **7.000** |
| 6 | **5%** | 0.05 | **3.500** |

- [ ] **M001 [HARD] — Grid đúng 6:** khai báo chính xác `minsup_counts = [56000,42000,28000,14000,7000,3500]` và fractions tương ứng.
- [ ] **M002 [HARD] — Thứ tự chạy:** từ 80% xuống 5%; mọi mức đều có một hàng status, kể cả không chạy thành công.
- [ ] **M003 [HARD] — Ngưỡng nguyên:** không truyền `80`, `0.8` hay fraction làm đối số thứ hai; support condition là `count >= min_count`.
- [ ] **M004 [HARD] — Full mining là mục tiêu:** không giới hạn max pattern length hoặc enumeration trong runs được công bố là đầy đủ.
- [ ] **M005 [HARD] — Resource policy công khai:** trước khi chạy ghi policy time/memory/output và khả năng enforce thực tế; không tự nhận đã enforce chỉ vì config có con số.
- [ ] **M006 [HARD] — Bảng sáu ngưỡng:** tạo `mining/runs.csv` gồm **đúng 6 status rows** theo chính thức, kể cả zero/failure/blocked.
- [ ] **M007 [HARD] — Run identity:** lưu run_id duy nhất và provenance path/hash/engine/min_count mỗi run.
- [ ] **M008 [HARD] — Timing:** đo `runtime_seconds` của lần chạy; nếu warm-up/repetitions thì ghi riêng `repeats.csv`, không trộn warm-up.
- [ ] **M009 [HARD] — Memory honesty:** ghi `peak_rss_mb` nếu đo được đúng process; nếu không, để `NA`, không ước lượng như số thực đo.
- [ ] **M010 [HARD] — Output size:** sau khi xuất patterns ghi kích thước file thực tế (`output_size_bytes`) và notes khi output quá lớn.
- [ ] **M011 [HARD] — Status enum:** phân loại `COMPLETED_FULL`, `COMPLETED_ZERO`, `TIMEOUT`, `MEMORY_LIMIT`, `ITEMSET_CAPPED`, `LENGTH_CAPPED`, `FAILED`, `BLOCKED`, `COMPLETION_UNVERIFIED`; nếu process bị kill và không có bằng chứng, ghi `UNKNOWN_INTERRUPTED`/failed rõ ràng.
- [ ] **M012 [HARD] — Complete vs partial:** chỉ đánh dấu `COMPLETED_FULL`/`COMPLETED_ZERO` khi toàn bộ khai thác kết thúc bình thường **và** không có cap tác động (hoặc core xác nhận chắc chắn không truncation).
- [ ] **M013 [HARD] — Result Dict không tự bảo đảm completeness:** nếu run có limits mà không có tín hiệu kiểm chứng, ghi `COMPLETION_UNVERIFIED`; không lấy `length(patterns) < max_itemsets` làm bằng chứng duy nhất.
- [ ] **M014 [HARD] — Nullable metrics:** `total_frequent_itemsets` và `max_itemset_length` phải `NA` ở các run không completed; không dùng partial counts để vẽ chart itemset counts chính thức.
- [ ] **M015 [HARD] — Zero là kết quả hợp lệ:** `Dict()` rỗng ở 80%/60% không bị xem như lỗi nếu thuật toán hoàn tất đầy đủ, ghi `COMPLETED_ZERO`.
- [ ] **M016 [HARD] — Preserve partial distinctly:** artifacts do ngắt/cap chỉ lưu theo tên hoặc metadata `partial`; không tạo file tên như exact `minsup_XX.jsonl` cho run chưa hoàn tất.
- [ ] **M017 [HARD] — Deterministic serialization:** sort keys Dict theo `(length(tuple), tuple)` rồi xuất mọi entry completed ra `mining/itemsets/minsup_XX.jsonl`.
- [ ] **M018 [HARD] — Itemset JSONL schema:** mỗi dòng có `items`, `length`, `support_count`, `support_fraction = support_count/70000`; itemsets sắp tăng, không trùng, IDs trong 1..32.
- [ ] **M019 [HARD] — Exact export count:** với run completed, `#lines(serialized JSONL) == length(patterns)`; không sử dụng `max_display_patterns` để cắt output khai thác.
- [ ] **M020 [HARD] — Source immutability:** chạy sáu ngưỡng trên **cùng một** transactions vector/hash, không sửa/loại ảnh giữa các run.
- [ ] **M021 [HARD] — Checkpoint/run logs:** ghi started/ended/status/lỗi/notes/output path sau mỗi ngưỡng, để không mất báo cáo khi một lần chạy sau thất bại.
- [ ] **M022 [HARD] — No hidden threshold tuning:** không tự thêm 1%/0,5% hoặc thay grid vì có nhiều/ít patterns; thử ngoài grid phải là bảng thí nghiệm bổ sung tách biệt.

### 2.2. Sanity audit ở tầng ứng dụng — **không tái làm unit tests của Eclat core**

- [ ] **V001 [HARD] — Validate values:** với run completed, mọi key không rỗng, sorted unique, IDs 1..32, `min_count <= support_count <= 70000`.
- [ ] **V002 [HARD] — Canonical uniqueness:** không có hai records chứa cùng một itemset trong file xuất.
- [ ] **V003 [HARD] — Cross-minsup anti-monotonicity:** nếu ngưỡng cao và thấp đều completed, itemsets ở ngưỡng cao là tập con của ngưỡng thấp.
- [ ] **V004 [HARD] — Stable support:** một itemset xuất hiện ở nhiều ngưỡng phải giữ đúng cùng `support_count`.
- [ ] **V005 [HARD] — Sample support audit:** chọn mẫu deterministic (ví dụ 20 patterns qua bands length/support) và đếm lại từ **transactions nguồn**; so với Dict/JSONL, ghi audit log.
- [ ] **V006 [HARD] — Zero-run audit:** nếu `COMPLETED_ZERO`, đối chiếu singleton support để xác nhận không có item nào vượt ngưỡng.
- [ ] **V007 [HARD] — Inconsistency handling:** nếu audit sai, đánh dấu run invalid/failed và ngừng sử dụng kết quả ấy để tính thống kê chính xác; không sửa im lặng file output.
- [ ] **V008 [HARD] — Read-back:** đọc lại `runs.csv`, một số JSONL/manifest đã lưu; xác nhận schema/paths/hash/row counts.

**Acceptance FIM-01:** có 6 dòng runs/status; mỗi `COMPLETED_*` có output exact và audit hợp lệ; các ngưỡng resource-limited được báo trung thực, không bị quy thành kết quả đầy đủ.

## 3. FIM-02 — Frequent pattern statistics & representative selection (spec §5)

- [ ] **A001 [HARD] — Source đã hoàn tất:** FIM-02 chỉ coi itemsets từ `COMPLETED_FULL`/`COMPLETED_ZERO` là tập hoàn chỉnh; các ngưỡng khác chỉ làm phần diagnostics.
- [ ] **A002 [HARD] — Counts theo minsup:** tính total itemsets và group theo itemset length, bảo đảm tổng count-by-length = total completed.
- [ ] **A003 [HARD] — Support distribution:** tính min/Q25/median/Q75/max hoặc histogram support fraction cho từng ngưỡng completed; trường hợp no patterns ghi `NA` và count=0.
- [ ] **A004 [HARD] — Composition:** tỷ lệ singleton, pairs và length >=3; itemset length max theo từng minsup completed.
- [ ] **A005 [HARD] — Chart count:** `figures/minsup_vs_itemset_count.png`; phân biệt run partial/censored và xử lý zero khi dùng log y-axis.
- [ ] **A006 [HARD] — Chart runtime:** `figures/minsup_vs_runtime.png`; ghi chú completed vs stopped; không diễn giải timeout như runtime hoàn thành.
- [ ] **A007 [HARD] — Length chart:** `figures/itemset_lengths_by_minsup.png`, heatmap hoặc stacked-bar, chỉ so complete distributions khi cả runs completed.
- [ ] **A008 [HARD] — Support semantics:** mọi caption/trục nêu support theo **số ảnh**/70k, không theo patches.
- [ ] **A009 [HARD] — Master catalog:** gộp frequent itemsets trùng giữa các minsup thành `analysis/master_patterns.jsonl`; có stable `pattern_id`, canonical `items`, length, support, minsup occurrences và run IDs.
- [ ] **A010 [HARD] — Cross-threshold de-dup:** một pattern chỉ có một record trong master catalog, không cộng support hoặc cộng số patterns của nhiều minsup như unique patterns.
- [ ] **A011 [HARD] — Deterministic sample selection:** mục tiêu **12–20 representative patterns nếu có đủ**, phân tầng theo support và length (1,2,>=3 khi tồn tại), có diversity/chống trùng nội dung.
- [ ] **A012 [HARD] — Chọn thật, không tô hồng:** không invent đủ quota; không chọn toàn top-support; không gán `class-enriched`/`cross-class` trước khi tính labels.
- [ ] **A013 [HARD] — Selection provenance:** ghi `representative_patterns.csv` với `pattern_id`, `items`, length, count/fraction, `selection_rule`, `reference_minsup`, notes.
- [ ] **A014 [HARD] — Qualitative interpretation caution:** số patterns lớn không đồng nghĩa tốt; S0 co-occurrence không chứng minh spatial relation.
- [ ] **A015 [OPTIONAL] — Redundancy/closed/maximal:** phân tích support equality/containment khi có thời gian; chỉ ghi `closed`/`maximal` nếu đúng định nghĩa và mined output đầy đủ; không gán cho top-k/truncated.
- [ ] **A016 [HARD] — Written insights:** `analysis/pattern_statistics.md` có nhận xét gắn với kết quả thật, phân biệt observation vs explanation/hypothesis.

**Acceptance FIM-02:** có bảng/charts và master catalog nhất quán, selection rules tái lập, không đưa số liệu ngưỡng chưa hoàn tất vào kết luận như full results.

## 4. FIM-03 — Visual pattern interpretation (spec §6)

### 4.1. Resolve assets và truy vết dữ liệu

- [ ] **G001 [HARD] — Exact codebook:** resolve đúng `codebook.bin` của B0 / K32 / seed123; không lấy nhầm codebook khác từ thư mục cũ.
- [ ] **G002 [HARD] — Resolve raw image assets:** xác nhận nguồn Fashion-MNIST gốc, image metadata, TID mapping, patch assignments đọc được; assets không nằm cùng folder thì cấu hình đường dẫn rõ.
- [ ] **G003 [HARD] — Provenance:** liên kết source file/checksum/codebook config và mapping vào interpretation manifest.
- [ ] **G004 [HARD] — Correct 4×4 display:** reshape centroid 16D → 4×4 theo column-major; không transpose/reshape row-major sai.
- [ ] **G005 [CONDITIONAL] — Real exemplar patches:** nếu raw patch pixels hoặc source images/coordinates cho phép, lấy actual patches gần centroid; đánh dấu rõ `real patch` khác `synthetic centroid`.
- [ ] **G006 [HARD] — Supporting TIDs:** với mỗi pattern, truy hồi chính xác các TIDs thỏa `X ⊆ transaction.items`, không dựa giả định TID==image_id.
- [ ] **G007 [HARD] — Support recheck:** số supporting TIDs của pattern phải bằng support count đã mine; nếu không khớp, chặn gallery của pattern đó và log.
- [ ] **G008 [HARD] — Image join:** join image_id theo mapping chính thức; kiểm tra uniqueness/coverage, không đánh dấu/hiển thị ảnh không thuộc TIDs truy hồi.
- [ ] **G009 [HARD] — Patch witnesses:** lấy actual patch positions từ `patch_assignments.csv`; highlight patch có word ID phù hợp, không tạo tọa độ suy đoán.
- [ ] **G010 [HARD] — Multiple witness sites:** một word có thể có nhiều patches trong ảnh; quy tắc chọn/highlight cụ thể, không mặc định chỉ một site.
- [ ] **G011 [HARD] — Contrast sampling:** lấy ít nhất một ảnh không có đầy đủ X nếu tồn tại, sample deterministic; khác biệt giữa `not containing all` và `containing none` phải diễn đạt đúng.
- [ ] **G012 [HARD] — S0 semantics:** chỉ mô tả đồng xuất hiện trong ảnh; không suy ra words kề nhau, có graph hình học hay xuất hiện cùng bộ phận trang phục.

### 4.2. Gallery và annotation

- [ ] **G013 [HARD] — Pattern cards:** mỗi representative pattern có items/length/minsup/support, thumbnail centroids, ảnh support, witness highlights, image contrast nếu có và caption.
- [ ] **G014 [HARD] — Gallery sampling:** cố định sampling seed, có đa dạng supporting images/labels (nếu sẵn) và không chỉ cherry-pick một lớp khi pattern phổ biến đa lớp.
- [ ] **G015 [HARD] — No fictitious visuals:** gallery chỉ sử dụng Fashion-MNIST images/patches có provenance; thiếu nguồn phải báo `BLOCKED_MISSING_ASSET` hoặc giới hạn cụ thể.
- [ ] **G016 [HARD] — Annotation fields:** `pattern_annotations.csv` chứa `pattern_id, decodable, witness_valid, visual_coherence, interpretation, limitations, reviewer`.
- [ ] **G017 [HARD] — Coherence rubric:** `0` không nhất quán, `1` một phần/mơ hồ, `2` nhất quán ở nhiều ảnh; reviewer đánh giá theo evidence, không tự động chấm 2 vì support cao.
- [ ] **G018 [HARD] — Evidence captions:** mỗi mô tả dẫn tới ảnh/patch đã hiển thị, nêu rõ mức chắc chắn và giới hạn diễn giải S0.
- [ ] **G019 [HARD] — Report figures:** lưu gallery dưới `interpretation/pattern_gallery/` để báo cáo có thể dùng lại mà không chạy lại Eclat.
- [ ] **G020 [HARD] — Missing-assets policy:** nếu codebook, patch, image hoặc labels thiếu, vẫn giữ các bước khác chạy được; report đúng phần `PARTIAL_INTERPRETATION`/blocker, không bịa charts hay ảnh.

**Acceptance FIM-03:** từ một frequent itemset thực tế có thể kiểm tra chain **pattern → supporting TIDs → image IDs → patch witnesses → figure**, và giới hạn thông tin S0 được ghi trong báo cáo.

## 5. FIM-04 — Image dataset insights & downstream application (spec §7)

### 5.1. Class-conditional insights — bắt buộc nếu labels có nguồn xác minh

- [ ] **D001 [CONDITIONAL] — Label source:** đọc đúng `image_metadata.csv` / mapping label có provenance; verify join 1:1 với các image IDs trước khi tính class metrics.
- [ ] **D002 [CONDITIONAL] — Actual class counts:** tính `N_c` từ metadata thật; không giả định 7.000 ảnh mỗi lớp nếu chưa xác minh.
- [ ] **D003 [CONDITIONAL] — Pattern membership:** từ supporting TIDs, đếm `n(X,c)` cho mỗi pattern/lớp; có chính sách phạm vi catalog vs representatives khi data rất lớn.
- [ ] **D004 [CONDITIONAL] — Correct formulas:** `P(X)=n(X)/70000`, `P(X|c)=n(X,c)/N_c`, `enrichment=P(X|c)/P(X)` (chỉ khi mẫu số >0).
- [ ] **D005 [CONDITIONAL] — Support by class:** ghi `pattern_class_support.csv` với `pattern_id,class_id,N_c,n_X_c,p_X_given_c,p_X,enrichment`.
- [ ] **D006 [CONDITIONAL] — Heatmap:** xuất `figures/pattern_class_heatmap.png` theo `P(X|c)` của representative patterns, có thể kèm heatmap enrichment; nhãn/trục rõ ràng.
- [ ] **D007 [CONDITIONAL] — 3 perspectives khi có evidence:** phân tích `common`, `class-enriched`, `cross-class`; nếu nhóm nào không xuất hiện trong dữ liệu thì ghi không tìm thấy, không ép minh họa.
- [ ] **D008 [HARD] — No supervised mining:** labels chỉ dùng hậu nghiệm; không dùng labels để sửa minsup, codebook hoặc itemset đã mine.
- [ ] **D009 [HARD] — Frequent ≠ discriminative:** nêu rõ pattern phổ biến không nhất thiết có tính phân loại; enrichment là tương đối, không chứng minh causality.
- [ ] **D010 [HARD] — Missing-label behavior:** nếu thiếu/không join được label, ghi `BLOCKED_MISSING_LABELS`, minh bạch lý do và vẫn tiếp tục mining/retrieval/gallery có thể thực hiện.

### 5.2. Pattern-based image retrieval — bắt buộc minh họa

- [ ] **D011 [HARD] — Actual query:** chọn **ít nhất một** frequent itemset đã mine và confirmed support làm query.
- [ ] **D012 [HARD] — Retrieval implementation:** lấy tất cả images thỏa `X ⊆ T(image)` từ đúng 70k transactions; không dùng nhãn để quyết định ảnh được trả về.
- [ ] **D013 [HARD] — Exact count:** `retrieved_count == support_count(X)` sau khi join mapping (nếu data/mapping hợp lệ); bất nhất phải điều tra.
- [ ] **D014 [HARD] — Retrieval gallery:** lưu các ảnh truy hồi thật, ảnh đối chứng không chứa X nếu có; nêu cách lấy mẫu và đặc điểm quan sát.
- [ ] **D015 [HARD] — Output registry:** ghi `retrieval_examples.csv` gồm `pattern_id,retrieved_count,example_image_ids,contrast_image_ids,notes`.
- [ ] **D016 [CONDITIONAL] — Retrieved-class distribution:** nếu labels hợp lệ, so mô tả phân bố lớp trong retrieved set với class priors.
- [ ] **D017 [HARD] — Claims boundary:** không gọi đây là semantic/embedding image retrieval và không tuyên bố cải thiện precision/recall nếu không có ground truth relevance.

### 5.3. Technical downstream discussion — bắt buộc; classifier PoC — optional

- [ ] **D018 [HARD] — Baseline representation:** mô tả `x_BoVW(I) ∈ {0,1}^32` từ S0.
- [ ] **D019 [HARD] — Pattern indicator:** định nghĩa `φ_j(I)=1[P_j ⊆ T(I)]` và `x_pattern(I) ∈ {0,1}^m`.
- [ ] **D020 [HARD] — Augmented feature:** mô tả `x_aug(I)=[x_BoVW(I),x_pattern(I)] ∈ {0,1}^{32+m}` với ví dụ dựa trên pattern thật (không bịa performance).
- [ ] **D021 [HARD] — Candidate downstream tasks:** thảo luận Logistic Regression/Linear SVM với tương tác tường minh, image grouping/signature và pattern-based retrieval.
- [ ] **D022 [HARD] — Theory limitation:** pattern activations là hàm xác định của 32 BoVW bits, **không bổ sung thông tin mới** theo nghĩa information theory; chỉ có thể thay đổi khả năng biểu diễn của một số mô hình.
- [ ] **D023 [HARD] — Leakage caveat:** codebook B0 đã fit trên 70k ảnh, do đó classifier với codebook này chỉ nên xem là transductive/exploratory; không mô tả như independent inductive evaluation.
- [ ] **D024 [HARD] — Proposed evaluation design:** nếu đề xuất PoC, nêu E0 BoVW-only, E1 pattern-only, E2 augmented; metrics accuracy, macro-F1, per-class F1; không tự bắt buộc chạy.
- [ ] **D025 [HARD] — Train-only protocol for any PoC:** phải chọn/mine patterns/hyperparameters từ train/validation, không dùng test labels để chọn features; giữ nguyên artifacts TC chính, refit sạch là một thực nghiệm ngoài phạm vi.
- [ ] **D026 [OPTIONAL] — PoC riêng:** chỉ khi nhóm chủ động chọn, chạy classifier E0/E1/E2 với báo cáo trung thực transductive setting, tính toán thật và không làm thay đổi pipeline mining chính.
- [ ] **D027 [HARD] — Report claims:** nếu không chạy PoC, ghi `proposed experiment / future work` và **không** xuất hoặc nhận xét số accuracy/F1 giả định như kết quả.

**Acceptance FIM-04:** có ít nhất 1 retrieval case có support đối chiếu; có class analysis khi labels hợp lệ, hoặc blocker minh bạch; có downstream feature-engineering discussion rõ công thức, giới hạn và cách kiểm chứng.

## 6. FIM-05 — Outputs, notebooks, reporting & reproducibility (spec §§8,10–11)

### 6.1. Directory và output contract

```text
results/fashion/fim/B0_K32_seed123_S0/
├── config_snapshot.toml
├── input_manifest.toml
├── mining/
│   ├── runs.csv
│   ├── runs/                       # Logs, timing, status/provenance
│   └── itemsets/minsup_XX.jsonl   # Chỉ khi run completed/exact
├── analysis/
│   ├── count_by_length.csv
│   ├── pattern_support_summary.csv
│   ├── master_patterns.jsonl
│   ├── representative_patterns.csv
│   └── pattern_statistics.md
├── interpretation/
│   ├── pattern_annotations.csv
│   ├── pattern_class_support.csv   # Khi labels hợp lệ
│   ├── retrieval_examples.csv
│   ├── pattern_gallery/
│   └── visual_interpretation.md
├── figures/
│   ├── minsup_vs_itemset_count.png
│   ├── minsup_vs_runtime.png
│   ├── itemset_lengths_by_minsup.png
│   └── pattern_class_heatmap.png  # Khi labels hợp lệ
└── report/
    ├── fashion_fim_application_report.md
    └── experiment_manifest.toml
```

- [ ] **R001 [HARD] — Output path:** dùng thư mục `results/fashion/fim/B0_K32_seed123_S0/`; không ghi đè source TC hoặc output thành viên khác.
- [ ] **R002 [HARD] — Run schema:** `runs.csv` có `run_id,configuration,minsup_fraction,minsup_count,status,total_frequent_itemsets,max_itemset_length,runtime_seconds,peak_rss_mb,output_size_bytes,engine_revision,input_sha256,notes`.
- [ ] **R003 [HARD] — Itemset schema:** mỗi completed JSONL có `items,length,support_count,support_fraction`; file `minsup_XX.jsonl` phải đọc lại được.
- [ ] **R004 [HARD] — Master pattern schema:** `pattern_id,items,length,support_count,support_fraction,observed_at_minsup,source_run_ids` hoặc JSONL tương đương.
- [ ] **R005 [HARD] — Interpretation outputs:** `pattern_annotations.csv`, gallery và `visual_interpretation.md` phải có links/paths dẫn đến bằng chứng thật.
- [ ] **R006 [HARD] — Manifest:** `experiment_manifest.toml` ghi source/engine hash, paths, hardware/runtime/software, limits, sampling seed, six grid, statuses và output filenames.
- [ ] **R007 [HARD] — Determinism:** pin sampling seeds, sort itemsets/keys, canonical pattern IDs, stable row order để rerun không đảo file vô cớ.
- [ ] **R008 [HARD] — Resume without recomputation:** nếu output được checkpoint và checksum/status đầy đủ, có thể skip/reuse completed minsup theo chính sách rõ ràng; không nhận file partial là exact.
- [ ] **R009 [HARD] — Modular code:** nếu cần module helper, đặt ngoài Eclat core (ví dụ `src/fashion_fim/`), notebook điều phối và mô tả chức năng code cell ngắn gọn.
- [ ] **R010 [HARD] — Separation of notebooks:** Notebook B đọc mining artifacts; không chạy Eclat lại khi refresh phần gallery/report.
- [ ] **R011 [HARD] — Report structure:** `fashion_fim_application_report.md` gồm: dữ liệu/cấu hình → setup Eclat/sáu minsup → kết quả FIM → image/patch interpretation → class/retrieval/downstream → limitations/conclusion.
- [ ] **R012 [HARD] — No unsupported results:** không bịa counts/figures/class enrichment/accuracy; kết quả chưa chạy để placeholder `NOT_RUN`/`BLOCKED` thay vì tự điền.
- [ ] **R013 [HARD] — Scope of overall report:** đầu ra này chỉ là **Ứng dụng 2** đóng góp cho báo cáo đồ án chung; không tự tạo đầy đủ chương benchmark hoặc báo cáo IEEE khác nếu không được giao.
- [ ] **R014 [HARD] — README/handoff:** chỉ dẫn môi trường Julia, đường dẫn nguồn, cách chạy theo thứ tự, cách đọc output, lưu ý ảnh/label assets và giới hạn tài nguyên.
- [ ] **R015 [HARD] — Version/commit summary:** tóm tắt rõ file nào tạo/sửa, file nào cố ý không đụng, trạng thái hoàn thành và blockers còn lại.

### 6.2. Review và smoke test theo thứ tự

- [ ] **T001 [HARD] — Static audit:** không có code cell đụng TC/K-means/Eclat core, SPMF default hay dải minsup cũ.
- [ ] **T002 [HARD] — Loader smoke:** chạy đọc JSONL, xác nhận N=70k, no-empty, items 1–32, SHA256, mapping đủ cho diễn giải.
- [ ] **T003 [HARD] — Adapter smoke:** gọi `EclatFIM.mine` trên dữ liệu nhỏ bằng API nhóm để xác nhận import/type/serialization **chỉ nhằm kiểm tra adapter**, không chạy lại bộ correctness tests của nhóm.
- [ ] **T004 [HARD] — MinSup mapping:** test 80/60/40/20/10/5 → 56000/42000/28000/14000/7000/3500, không lệch integer.
- [ ] **T005 [HARD] — Completed-zero path:** Dict trống phải serialize/ghi run correctly và không làm hỏng plotting/reporting.
- [ ] **T006 [HARD] — Partial path:** simulated missing/limited run phải để nullable exact counts và không tạo file exact giả.
- [ ] **T007 [HARD] — JSONL read-back:** verify canonical sorting, unique keys, line counts, exact support fraction formula.
- [ ] **T008 [HARD] — Cross-threshold sanity:** check containment và support consistency giữa completed outputs.
- [ ] **T009 [HARD] — Witness smoke:** query 1 pattern thật → supporting TIDs → mapping → patch positions → image grid; mismatch phải surfaced, không bỏ qua.
- [ ] **T010 [HARD] — Retrieval smoke:** `retrieved_count == support_count` cho query đã chọn; nếu không thì `FAIL` tới khi giải quyết.
- [ ] **T011 [CONDITIONAL] — Label join smoke:** `image_id→label` 1:1, N_c counts và `n(X,c)` khớp tổng over classes khi labels complete.
- [ ] **T012 [HARD] — Notebook restart:** chạy sạch từ kernel mới, thứ tự execution rõ, không phụ thuộc biến ẩn hoặc cell cũ.
- [ ] **T013 [HARD] — No forced expensive reruns:** notebook interpretation/report có thể chạy lại độc lập khi mining completed outputs đã tồn tại.
- [ ] **T014 [HARD] — Scope review:** kiểm tra `git diff` không có thay đổi bất kỳ TC artifacts/Eclat core hay ngoài thư mục phân công.
- [ ] **T015 [HARD] — Independent file audit:** mở lại một số CSV/JSONL/PNG/TOML trong runtime; kiểm tra nội dung thật, không chỉ existence.

## 7. Final Definition of Done (spec §9)

- [ ] **DoD-01 — Locked source:** đúng B0/K32/seed123/S0, đọc `transactions.jsonl` đã có, `N=70000`, không chỉnh nguồn.
- [ ] **DoD-02 — Engine ownership:** chỉ gọi `EclatFIM.mine(transactions, min_count)`; không sửa Eclat core/benchmark/tests.
- [ ] **DoD-03 — Six-run report:** đủ 6 rows đúng ngưỡng và trạng thái, đầy đủ provenance/limits; no fake completion.
- [ ] **DoD-04 — Exact mining outputs:** mọi run `COMPLETED_*` đều có file patterns/support chính xác, canonical JSONL, audit pass.
- [ ] **DoD-05 — Analysis:** có counts/support/length/runtime charts, master catalog, representatives có selection rules.
- [ ] **DoD-06 — Visual evidence:** galleries thật theo chain itemset → TIDs → image IDs → patch witnesses → nhận xét giới hạn S0.
- [ ] **DoD-07 — Image applications:** retrieval case thực tế; class support/enrichment nếu labels xác thực hoặc `BLOCKED_MISSING_LABELS` minh bạch.
- [ ] **DoD-08 — Downstream:** thảo luận pattern activation features, ứng dụng ML và leakage; không tuyên bố performance khi chưa có PoC.
- [ ] **DoD-09 — Reporting & reuse:** report Ứng dụng 2, config/manifests, hướng dẫn chạy lại, figures và notebooks tách biệt.
- [ ] **DoD-10 — Honest handoff:** công bố trạng thái tổng thể theo bằng chứng: `COMPLETE`, `PARTIAL_RESOURCE_LIMITED`, `PARTIAL_INTERPRETATION` hoặc `BLOCKED`.

### Quy tắc công bố trạng thái cuối cùng

| Trạng thái | Khi nào sử dụng |
|---|---|
| **`COMPLETE`** | 6 mức minsup đều hoàn tất chính xác (`COMPLETED_FULL` hoặc `COMPLETED_ZERO`); các output bắt buộc của interpretation, retrieval, report hợp lệ. |
| **`PARTIAL_RESOURCE_LIMITED`** | Có mức chưa khai thác đầy đủ do tài nguyên, nhưng completed runs được báo đúng và interpretation có dữ liệu thật. |
| **`PARTIAL_INTERPRETATION`** | Mining có thể chạy nhưng thiếu codebook/patch/ảnh/label artifacts cần để thực hiện đầy đủ phần diễn giải có điều kiện. |
| **`BLOCKED`** | Không đọc được input cần thiết hoặc không tích hợp được `EclatFIM.mine`, và không thể triển khai công việc chính. |

**Bàn giao tối thiểu cho người review:** đường dẫn 2 notebooks; `runs.csv`; manifest; các file itemsets completed; 3 plots FIM; master/representatives; gallery có witness thật; retrieval example; phần thảo luận downstream; status cuối cùng, blockers và phạm vi `git diff`.

---

## Thứ tự giao coding agent (để tránh mở rộng phạm vi)

1. **P0:** Hoàn thành nhóm **L, I**; smoke adapter và data loader. Không sửa Eclat core.
2. **P1:** Hoàn thành **M, V**; chạy 6 ngưỡng và lưu exact/partial status minh bạch.
3. **P2:** Hoàn thành **A**; tính stats/charts, chọn representative patterns.
4. **P3:** Hoàn thành **G, D**; pattern galleries, class analysis (khi labels hợp lệ), retrieval, downstream discussion.
5. **P4:** Hoàn thành **R, T, DoD**; report, reproducibility và bàn giao.

**Không tạo công việc ẩn:** Không bắt buộc classifier PoC, không chạy SPMF, không triển khai lại Eclat, không mở EDA2, không thử codebook khác và không đổi dải minsup chính thức.
