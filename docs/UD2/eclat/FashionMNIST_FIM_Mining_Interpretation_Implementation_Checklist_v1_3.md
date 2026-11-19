# IMPLEMENTATION CHECKLIST v1.3 — Fashion-MNIST FIM Mining, Interpretation & Downstream Applications

**Tương ứng spec:** `FashionMNIST_FIM_Mining_Interpretation_Spec_v1_3.md` (19/11/2026)  
**Trạng thái:** Checklist giao coding agent; **chưa xác nhận các hạng mục đã triển khai hoặc chạy thành công**.  
**Phạm vi:** Ứng dụng 2 trên Fashion-MNIST; chạy Eclat **đã có của nhóm** và diễn giải frequent visual itemsets.  
**Quy ước:** `[ ]` chưa làm, `[x]` hoàn thành sau khi có bằng chứng; **HARD** = bắt buộc, **CONDITIONAL** = bắt buộc nếu đủ nguồn, **OPTIONAL** = ngoài phạm vi mặc định.  
**Nguyên tắc:** đánh dấu hoàn thành dựa trên **file output + sanity audit + logs**, không chỉ vì code cell chạy không báo lỗi.

## 0. Chốt cấu hình, ranh giới và danh sách bàn giao (spec §§0–1, 12)

- [x] **L001 [HARD] — Khóa cấu hình:** B0 / `raw_full_batch_kmeans`, `K=32`, `seed=123`, `encoding=S0`, tập Fashion-MNIST gồm **70.000** ảnh/giao dịch.
- [x] **L002 [HARD] — Input duy nhất:** sử dụng `results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl` **read-only**, không dùng đường dẫn `v2_full_s0` cũ.
- [x] **L003 [HARD] — N đã kiểm định:** dựa trên xác nhận có 70.000 transactions và **0 empty**; chỉ sanity-check lúc load, **không làm lại TC7**.
- [x] **L004 [HARD] — Không mở lại selection:** không chạy EDA2, không so sánh lại 15 codebooks/60 configurations, không thử S1/S3/S6-B trong FIM chính.
- [x] **L005 [HARD] — Giữ nguyên nguồn:** không sửa/chạy lại TC1–TC7, codebook, assignments, image metadata hoặc transactions sản xuất.
- [x] **L006 [HARD] — Giữ nguyên thuật toán:** không sửa Eclat core, tests, tối ưu, benchmark, CLI hoặc mã của thành viên khác; chỉ tích hợp qua public API.
- [x] **L007 [HARD] — Bốn RQ:** báo cáo cần trả lời Mining behavior, Visual meaning, Image data analysis, Downstream applicability (theo spec §1).
- [x] **L008 [HARD] — Phân tầng phạm vi:** mining/analysis/visual evidence/retrieval/downstream discussion là bắt buộc; classifier mới là optional.
- [x] **L009 [HARD] — Notebook architecture:** thống nhất 2 notebook chính `FIM_Mining_Experiments.ipynb` (FIM-00–02) và `FIM_Visual_Interpretation.ipynb` (FIM-03–04), hoặc ghi rõ nếu repo đã có cấu trúc khác.
- [x] **L010 [HARD] — Không chạy lại mining khi sửa báo cáo:** notebook interpretation đọc **các output đã lưu** thay vì tự gọi `mine` mỗi lần tạo plots/gallery.

## 1. FIM-00 — Environment, input handoff & Eclat adapter (spec §§2–3, 10)

### 1.1. Setup và nguồn dữ liệu

- [x] **I001 [HARD] — Repo-relative paths:** cấu hình source/output paths theo repo; không hardcode đường dẫn tuyệt đối máy cá nhân.
- [x] **I002 [HARD] — Nguồn chuẩn:** xác nhận file JSONL tồn tại, ghi `input_sha256`, source path, configuration ID và thời điểm chạy vào `input_manifest.toml`.
- [x] **I003 [HARD] — Loader JSONL:** đọc từng dòng JSONL và chỉ đưa `items` vào dữ liệu mining, giữ **mỗi dòng là đúng một transaction**.
- [x] **I004 [HARD] — Julia type:** tạo `Vector{Vector{Int}}` (hoặc vector giao dịch tương thích API, được ghi nhận), với **đúng 70.000 phần tử**.
- [x] **I005 [HARD] — S0 item assertions:** mỗi `items` là tập các `Int` thuộc `1:32`, không lặp trong transaction; đọc đủ 70.000 dòng, không tự loại dòng hay âm thầm chữa dữ liệu.
- [x] **I006 [HARD] — Mapping:** bảo toàn index của dòng JSONL ↔ TID/image_id; Julia 1-based index **không mặc nhiên bằng** `tid` hay `image_id`.
- [x] **I007 [HARD] — Không label leakage vào mining:** `tid`, `image_id`, `split`, `label` không được biến thành items.
- [x] **I008 [HARD] — Input notebook tùy chọn:** chỉ reuse nếu tồn tại thật trong worktree; nếu không, implement loader JSONL tối thiểu trong phạm vi FIM, không tạo blocker/đòi chạy lại TC.
- [x] **I009 [HARD] — Supersede minsup cũ:** không dùng lại `[10%,7%,5%,3%,2%,1%,0.5%]` từ notebook chuẩn bị trước; grid chính thức ở §2.
- [x] **I010 [HARD] — Config snapshot:** lưu K, seed, encoding, source, N, engine, minsup counts/fractions, chính sách giới hạn và output dir.

### 1.2. Chỉ tích hợp public Eclat API

- [x] **I011 [HARD] — Import module thực tế:** xác định cách load/import `EclatFIM` từ code nhóm trong repo; không sao chép hay refactor core.
- [x] **I012 [HARD] — Cú pháp bắt buộc:** `patterns = EclatFIM.mine(transactions, min_count)`; `min_count::Int` là **absolute support count**.
- [x] **I013 [HARD] — Output contract:** kiểm tra kết quả là `Dict{Tuple{Vararg{Int}},Int}` hoặc Dict thực tế tương thích contract; key canonical, value support integer.
- [x] **I014 [HARD] — Adapter ngoài core:** mọi parsing, logging, status, serialization, plotting nằm ngoài các file thuật toán Eclat.
- [x] **I015 [HARD] — No invented return metadata:** không giả định `mine` trả TID-sets, runtime, output path hoặc trạng thái đầy đủ ngoài Dict.
- [x] **I016 [HARD] — Optional limits:** trước khi truyền `max_length`, `deadline`, `max_itemsets`, phải kiểm tra semantics thực tế trong code được bàn giao; production full run mặc định chỉ truyền 2 positional arguments.
- [x] **I017 [HARD] — Integration failure policy:** nếu module không load hoặc API khác contract, ghi `BLOCKED` + bằng chứng; không tự sửa thuật toán.
- [x] **I018 [HARD] — Provenance runtime:** ghi engine revision/commit, Julia version, OS, CPU/RAM nếu có, effective threads và package versions cần thiết.

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

- [x] **M001 [HARD] — Grid đúng 6:** khai báo chính xác `minsup_counts = [56000,42000,28000,14000,7000,3500]` và fractions tương ứng.
- [x] **M002 [HARD] — Thứ tự chạy:** từ 80% xuống 5%; mọi mức đều có một hàng status, kể cả không chạy thành công.
- [x] **M003 [HARD] — Ngưỡng nguyên:** không truyền `80`, `0.8` hay fraction làm đối số thứ hai; support condition là `count >= min_count`.
- [x] **M004 [HARD] — Full mining là mục tiêu:** không giới hạn max pattern length hoặc enumeration trong runs được công bố là đầy đủ.
- [x] **M005 [HARD] — Resource policy có enforce thật:** trước P2 điền số cụ thể cho `wall_time_seconds_per_run` (spawn→worker exit), `memory_limit_mb_per_worker` (worker Julia per-minsup) và `output_limit_bytes` (một file JSONL itemsets cho một minsup, không cộng logs/sidecar/CSV); ghi enforcement method/scope thật, budget revision. Không dùng tên alias và không chạy production khi không enforce được.
- [x] **M006 [HARD] — Bảng sáu ngưỡng:** **khởi tạo 6 hàng `NOT_RUN` trong P1**, nhưng chỉ chạy production trong P2 qua MCP; supervisor cập nhật atomic 6 status rows kể cả zero/failure/blocked.
- [x] **M007 [HARD] — Run identity:** lưu run_id duy nhất và provenance path/hash/engine/min_count mỗi run.
- [x] **M008 [HARD] — Timing:** đo `runtime_seconds` của lần chạy; nếu warm-up/repetitions thì ghi riêng `repeats.csv`, không trộn warm-up.
- [x] **M009 [HARD] — Memory honesty:** ghi `peak_rss_mb` nếu đo được đúng process; nếu không, để `NA`, không ước lượng như số thực đo.
- [x] **M010 [HARD] — Output size:** sau khi xuất patterns ghi kích thước file thực tế (`output_size_bytes`) và notes khi output quá lớn.
- [x] **M011 [HARD] — Dùng đúng run enum spec §4.3:** `NOT_RUN`, `COMPLETED_FULL`, `COMPLETED_ZERO`, `TIMEOUT`, `MEMORY_LIMIT`, `OUTPUT_LIMIT`, `ITEMSET_CAPPED`, `LENGTH_CAPPED`, `COMPLETION_UNVERIFIED`, `INVALID_OUTPUT`, `FAILED`, `UNKNOWN_INTERRUPTED`, `BLOCKED` (lưu nguyên nhân riêng ở `reason_code`; không tạo status alias).
- [x] **M012 [HARD] — Complete vs partial:** chỉ đánh dấu `COMPLETED_FULL`/`COMPLETED_ZERO` khi toàn bộ khai thác kết thúc bình thường **và** không có cap tác động (hoặc core xác nhận chắc chắn không truncation).
- [x] **M013 [HARD] — Result Dict không tự bảo đảm completeness:** nếu run có limits mà không có tín hiệu kiểm chứng, ghi `COMPLETION_UNVERIFIED`; không lấy `length(patterns) < max_itemsets` làm bằng chứng duy nhất.
- [x] **M014 [HARD] — Nullable metrics:** ở noncompleted, `total_frequent_itemsets`/`max_itemset_length=NA`; ở `COMPLETED_ZERO` cả hai là **0** và JSONL exact có 0 dòng; partial counts (nếu có) phải ở cột riêng.
- [x] **M015 [HARD] — Source guardrails cần xác minh:** người dùng đã đếm max singleton **48.922** nên 80% (56.000) phải `COMPLETED_ZERO`. Ở 60% (42.000) chỉ **hai singleton `(6,)`, `(26,)`** frequent; support `(6,26) = 32.266 < 42.000`, nên output full **chính xác 2 itemsets**. Agent tự tính lại các supports từ đúng JSONL và ghi hash trước khi audit engine.
- [x] **M016 [HARD] — Preserve partial distinctly:** artifacts do ngắt/cap chỉ lưu theo tên hoặc metadata `partial`; không tạo file tên như exact `minsup_XX.jsonl` cho run chưa hoàn tất.
- [x] **M017 [HARD] — Deterministic serialization:** sort keys Dict theo `(length(tuple), tuple)` rồi xuất mọi entry completed ra `mining/itemsets/minsup_XX.jsonl`.
- [x] **M018 [HARD] — Itemset JSONL schema:** mỗi dòng có `items`, `length`, `support_count`, `support_fraction = support_count/70000`; itemsets sắp tăng, không trùng, IDs trong 1..32.
- [x] **M019 [HARD] — Exact export count:** với run completed, `#lines(serialized JSONL) == length(patterns)`; không sử dụng `max_display_patterns` để cắt output khai thác.
- [x] **M020 [HARD] — Source immutability:** chạy sáu ngưỡng trên **cùng một** transactions vector/hash, không sửa/loại ảnh giữa các run.
- [x] **M021 [HARD] — Supervisor persistence:** sidecar `mining/runs/<run_id>/status.toml` là authoritative; chứa `final_committed`, `audit_status`, run identity, status, SHA256/size/record count, timestamps và cause. Commit theo staging JSONL → audit → atomic rename JSONL → final atomic sidecar → rebuild atomic `runs.csv` từ sáu sidecars. Crash trước sidecar final không được reuse JSONL exact.
- [x] **M022 [HARD] — No hidden threshold tuning:** không tự thêm 1%/0,5% hoặc thay grid vì có nhiều/ít patterns; thử ngoài grid phải là bảng thí nghiệm bổ sung tách biệt.
- [x] **M023 [HARD] — Commit/recovery crash windows:** smoke P1 giả lập crash **sau staging**, **sau rename exact trước final sidecar**, **sau final sidecar trước runs.csv**. Chỉ trường hợp 3 được reuse; cases 1–2 không coi `COMPLETED`, quarantine orphan exact sau khi xác minh no live worker.
- [x] **M024 [HARD] — Recovery consistency:** khi resume phải match `input_sha256`, `engine_revision`, `budget_revision`, `minsup_count`, `audit_status=PASS`, `final_committed=true`, exact `output_sha256`, size và record count; nếu mismatch → `INVALID_OUTPUT/COMMIT_MISMATCH`, không tin `runs.csv` hoặc file name.
- [x] **M025 [HARD] — CSV is derived:** xóa/thao tác `runs.csv` mô phỏng và rebuild lại **đúng 6 rows theo fixed grid** từ authoritative sidecars; không chạy lại ngưỡng completed hợp lệ do mất CSV.

### 2.2. Sanity audit ở tầng ứng dụng — **không tái làm unit tests của Eclat core**

- [x] **V001 [HARD] — Validate values:** với run completed, mọi key không rỗng, sorted unique, IDs 1..32, `min_count <= support_count <= 70000`.
- [x] **V002 [HARD] — Canonical uniqueness:** không có hai records chứa cùng một itemset trong file xuất.
- [x] **V003 [HARD] — Cross-minsup anti-monotonicity:** nếu ngưỡng cao và thấp đều completed, itemsets ở ngưỡng cao là tập con của ngưỡng thấp.
- [x] **V004 [HARD] — Stable support:** một itemset xuất hiện ở nhiều ngưỡng phải giữ đúng cùng `support_count`.
- [x] **V005 [HARD] — Sample support audit:** chọn mẫu deterministic (ví dụ 20 patterns qua bands length/support) và đếm lại từ **transactions nguồn**; so với Dict/JSONL, ghi audit log.
- [x] **V006 [HARD] — Zero-run audit:** nếu `COMPLETED_ZERO`, đối chiếu singleton support để xác nhận không có item nào vượt ngưỡng.
- [x] **V007 [HARD] — Inconsistency handling:** nếu audit sai, đánh dấu run invalid/failed và ngừng sử dụng kết quả ấy để tính thống kê chính xác; không sửa im lặng file output.
- [x] **V008 [HARD] — Read-back:** đọc lại `runs.csv`, một số JSONL/manifest đã lưu; xác nhận schema/paths/hash/row counts.

**Acceptance FIM-01:** có 6 dòng runs/status; mỗi `COMPLETED_*` có output exact và audit hợp lệ; các ngưỡng resource-limited được báo trung thực, không bị quy thành kết quả đầy đủ.

## 3. FIM-02 — Frequent pattern statistics & representative selection (spec §5)

- [x] **A001 [HARD] — Source đã hoàn tất:** FIM-02 chỉ coi itemsets từ `COMPLETED_FULL`/`COMPLETED_ZERO` là tập hoàn chỉnh; các ngưỡng khác chỉ làm phần diagnostics.
- [x] **A002 [HARD] — Counts theo minsup:** tính total itemsets và group theo itemset length, bảo đảm tổng count-by-length = total completed.
- [x] **A003 [HARD] — Support distribution:** tính min/Q25/median/Q75/max hoặc histogram support fraction cho từng ngưỡng completed; trường hợp no patterns ghi `NA` và count=0.
- [x] **A004 [HARD] — Composition:** tỷ lệ singleton, pairs và length >=3; itemset length max theo từng minsup completed.
- [x] **A005 [HARD] — Chart count:** `figures/minsup_vs_itemset_count.png`; phân biệt run partial/censored và xử lý zero khi dùng log y-axis.
- [x] **A006 [HARD] — Chart runtime:** `figures/minsup_vs_runtime.png`; ghi chú completed vs stopped; không diễn giải timeout như runtime hoàn thành.
- [x] **A007 [HARD] — Length chart:** `figures/itemset_lengths_by_minsup.png`, heatmap hoặc stacked-bar, chỉ so complete distributions khi cả runs completed.
- [x] **A008 [HARD] — Support semantics:** mọi caption/trục nêu support theo **số ảnh**/70k, không theo patches.
- [x] **A009 [HARD] — Master catalog:** gộp frequent itemsets trùng giữa các minsup thành `analysis/master_patterns.jsonl`; có stable `pattern_id`, canonical `items`, length, support, minsup occurrences và run IDs.
- [x] **A010 [HARD] — Cross-threshold de-dup:** một pattern chỉ có một record trong master catalog, không cộng support hoặc cộng số patterns của nhiều minsup như unique patterns.
- [x] **A011 [HARD] — Deterministic sample selection:** target mặc định **16**, override trong **12–20**; support tertiles theo **distinct support counts** (ties không chia bucket), fixed 9-cell length-major order `(1,low)…(>=3,high)`, inner sort `(-support_count,length,items lex)`, one-per-cell round robin, Jaccard ≤0.80; nếu thiếu target thì reset chạy lại đúng một lần với ≤0.90. `selection_seed=42` chỉ áp dụng gallery sampling.
- [x] **A012 [HARD] — Chọn thật, không tô hồng:** không invent đủ quota; không chọn toàn top-support; không gán `class-enriched`/`cross-class` trước khi tính labels.
- [x] **A013 [HARD] — Selection provenance:** `representative_patterns.csv` lưu `selection_order,support_bucket,length_bucket,diversity_max_jaccard,rule_version,selection_seed,selection_notes` và columns hiện có; cùng input phải tái tạo cùng pattern IDs.
- [x] **A014 [HARD] — Qualitative interpretation caution:** số patterns lớn không đồng nghĩa tốt; S0 co-occurrence không chứng minh spatial relation.
- [ ] **A015 [OPTIONAL] — Redundancy/closed/maximal:** phân tích support equality/containment khi có thời gian; chỉ ghi `closed`/`maximal` nếu đúng định nghĩa và mined output đầy đủ; không gán cho top-k/truncated.
- [x] **A016 [HARD] — Written insights:** `analysis/pattern_statistics.md` có nhận xét gắn với kết quả thật, phân biệt observation vs explanation/hypothesis.
- [x] **A017 [HARD] — Ties and deterministic selection tests:** synthetic catalog test mọi same-support patterns vào cùng bucket, thứ tự duyệt 9 ô cố định, deterministic item lexical ties, relax reset một lần khi thiếu target, không ép quota nếu catalog thiếu; cùng input → cùng ordered pattern IDs.

**Acceptance FIM-02:** có bảng/charts và master catalog nhất quán, selection rules tái lập, không đưa số liệu ngưỡng chưa hoàn tất vào kết luận như full results.

## 4. FIM-03 — Visual pattern interpretation (spec §6)

### 4.1. Resolve assets và truy vết dữ liệu

- [x] **G001 [HARD] — Exact codebook:** resolve đúng `codebook.bin` của B0 / K32 / seed123; không lấy nhầm codebook khác từ thư mục cũ.
- [x] **G002 [HARD] — Resolve raw image assets:** xác nhận nguồn Fashion-MNIST gốc, image metadata, TID mapping, patch assignments đọc được; assets không nằm cùng folder thì cấu hình đường dẫn rõ.
- [x] **G003 [HARD] — Provenance:** liên kết source file/checksum/codebook config và mapping vào interpretation manifest.
- [x] **G004 [HARD] — Correct 4×4 display:** reshape centroid 16D → 4×4 theo column-major; không transpose/reshape row-major sai.
- [x] **G005 [CONDITIONAL] — Real exemplar patches:** nếu raw patch pixels hoặc source images/coordinates cho phép, lấy actual patches gần centroid; đánh dấu rõ `real patch` khác `synthetic centroid`.
- [x] **G006 [HARD] — Supporting TIDs:** với mỗi pattern, truy hồi chính xác các TIDs thỏa `X ⊆ transaction.items`, không dựa giả định TID==image_id.
- [x] **G007 [HARD] — Support recheck:** số supporting TIDs của pattern phải bằng support count đã mine; nếu không khớp, chặn gallery của pattern đó và log.
- [x] **G008 [HARD] — Image join:** join image_id theo mapping chính thức; kiểm tra uniqueness/coverage, không đánh dấu/hiển thị ảnh không thuộc TIDs truy hồi.
- [x] **G009 [HARD] — Patch witnesses:** lấy actual patch positions từ `patch_assignments.csv`; highlight patch có word ID phù hợp, không tạo tọa độ suy đoán.
- [x] **G010 [HARD] — Multiple witness sites:** một word có thể có nhiều patches trong ảnh; quy tắc chọn/highlight cụ thể, không mặc định chỉ một site.
- [x] **G011 [HARD] — Contrast sampling:** lấy ít nhất một ảnh không có đầy đủ X nếu tồn tại, sample deterministic; khác biệt giữa `not containing all` và `containing none` phải diễn đạt đúng.
- [x] **G012 [HARD] — S0 semantics:** chỉ mô tả đồng xuất hiện trong ảnh; không suy ra words kề nhau, có graph hình học hay xuất hiện cùng bộ phận trang phục.

### 4.2. Gallery và annotation

- [x] **G013 [HARD] — Pattern cards:** mỗi representative pattern có items/length/minsup/support, thumbnail centroids, ảnh support, witness highlights, image contrast nếu có và caption.
- [x] **G014 [HARD] — Gallery sampling:** cố định sampling seed, có đa dạng supporting images/labels (nếu sẵn) và không chỉ cherry-pick một lớp khi pattern phổ biến đa lớp.
- [x] **G015 [HARD] — No fictitious visuals:** gallery chỉ sử dụng Fashion-MNIST images/patches có provenance; thiếu nguồn phải báo `BLOCKED_MISSING_ASSET` hoặc giới hạn cụ thể.
- [x] **G016 [HARD] — Annotation fields (spec §8.2 authoritative):** `pattern_annotations.csv` dùng **đúng schema spec v1.3 §8.2**: `pattern_id,decodable,witness_valid,review_status,visual_coherence,interpretation,limitations,reviewer,reviewed_at,evidence_paths`; không giữ schema cũ hoặc lược các trường review/evidence.
- [x] **G017 [HARD] — Coherence rubric và review outcomes:** `0` không nhất quán, `1` một phần/mơ hồ, `2` nhất quán ở nhiều ảnh; chỉ người thật chấm. `PENDING_REVIEW` → chưa duyệt; `NEEDS_REVISION` → `interpretation=NEEDS_REVISION`, cần sửa và review lại; có `REJECTED` thì không dùng làm positive visual evidence.
- [x] **G018 [HARD] — Evidence captions:** mỗi mô tả dẫn tới ảnh/patch đã hiển thị, nêu rõ mức chắc chắn và giới hạn diễn giải S0.
- [x] **G019 [HARD] — Report figures:** lưu gallery dưới `interpretation/pattern_gallery/` để báo cáo có thể dùng lại mà không chạy lại Eclat.
- [x] **G020 [HARD] — Missing-assets policy:** nếu codebook, patch, image hoặc labels thiếu, vẫn giữ các bước khác chạy được; report đúng phần `PARTIAL_INTERPRETATION`/blocker, không bịa charts hay ảnh.

**Acceptance FIM-03:** từ một frequent itemset thực tế có thể kiểm tra chain **pattern → supporting TIDs → image IDs → patch witnesses → figure**, và giới hạn thông tin S0 được ghi trong báo cáo.

## 5. FIM-04 — Image dataset insights & downstream application (spec §7)

### 5.1. Class-conditional insights — bắt buộc nếu labels có nguồn xác minh

- [x] **D001 [CONDITIONAL] — Label source:** đọc đúng `image_metadata.csv` / mapping label có provenance; verify join 1:1 với các image IDs trước khi tính class metrics.
- [x] **D002 [CONDITIONAL] — Actual class counts:** tính `N_c` từ metadata thật; không giả định 7.000 ảnh mỗi lớp nếu chưa xác minh.
- [x] **D003 [CONDITIONAL] — Pattern membership:** từ supporting TIDs, đếm `n(X,c)` cho mỗi pattern/lớp; có chính sách phạm vi catalog vs representatives khi data rất lớn.
- [x] **D004 [CONDITIONAL] — Correct formulas:** `P(X)=n(X)/70000`, `P(X|c)=n(X,c)/N_c`, `enrichment=P(X|c)/P(X)` (chỉ khi mẫu số >0).
- [x] **D005 [CONDITIONAL] — Support by class:** ghi `pattern_class_support.csv` với `pattern_id,class_id,N_c,n_X_c,p_X_given_c,p_X,enrichment`.
- [x] **D006 [CONDITIONAL] — Heatmap:** xuất `figures/pattern_class_heatmap.png` theo `P(X|c)` của representative patterns, có thể kèm heatmap enrichment; nhãn/trục rõ ràng.
- [x] **D007 [CONDITIONAL] — 3 perspectives khi có evidence:** phân tích `common`, `class-enriched`, `cross-class`; nếu nhóm nào không xuất hiện trong dữ liệu thì ghi không tìm thấy, không ép minh họa.
- [x] **D008 [HARD] — No supervised mining:** labels chỉ dùng hậu nghiệm; không dùng labels để sửa minsup, codebook hoặc itemset đã mine.
- [x] **D009 [HARD] — Frequent ≠ discriminative:** nêu rõ pattern phổ biến không nhất thiết có tính phân loại; enrichment là tương đối, không chứng minh causality.
- [x] **D010 [HARD] — Missing-label behavior:** nếu thiếu/không join được label, ghi `BLOCKED_MISSING_LABELS`, minh bạch lý do và vẫn tiếp tục mining/retrieval/gallery có thể thực hiện.

### 5.2. Pattern-based image retrieval — bắt buộc minh họa

- [x] **D011 [HARD] — Actual query:** chọn **ít nhất một** frequent itemset đã mine và confirmed support làm query.
- [x] **D012 [HARD] — Retrieval implementation:** lấy tất cả images thỏa `X ⊆ T(image)` từ đúng 70k transactions; không dùng nhãn để quyết định ảnh được trả về.
- [x] **D013 [HARD] — Exact count:** `retrieved_count == support_count(X)` sau khi join mapping (nếu data/mapping hợp lệ); bất nhất phải điều tra.
- [x] **D014 [HARD] — Retrieval gallery:** lưu các ảnh truy hồi thật, ảnh đối chứng không chứa X nếu có; nêu cách lấy mẫu và đặc điểm quan sát.
- [x] **D015 [HARD] — Output registry:** ghi `retrieval_examples.csv` gồm `pattern_id,retrieved_count,example_image_ids,contrast_image_ids,notes`.
- [x] **D016 [CONDITIONAL] — Retrieved-class distribution:** nếu labels hợp lệ, so mô tả phân bố lớp trong retrieved set với class priors.
- [x] **D017 [HARD] — Claims boundary:** không gọi đây là semantic/embedding image retrieval và không tuyên bố cải thiện precision/recall nếu không có ground truth relevance.

### 5.3. Technical downstream discussion — bắt buộc; classifier PoC — optional

- [x] **D018 [HARD] — Baseline representation:** mô tả `x_BoVW(I) ∈ {0,1}^32` từ S0.
- [x] **D019 [HARD] — Pattern indicator:** định nghĩa `φ_j(I)=1[P_j ⊆ T(I)]` và `x_pattern(I) ∈ {0,1}^m`.
- [x] **D020 [HARD] — Augmented feature:** mô tả `x_aug(I)=[x_BoVW(I),x_pattern(I)] ∈ {0,1}^{32+m}` với ví dụ dựa trên pattern thật (không bịa performance).
- [x] **D021 [HARD] — Candidate downstream tasks:** thảo luận Logistic Regression/Linear SVM với tương tác tường minh, image grouping/signature và pattern-based retrieval.
- [x] **D022 [HARD] — Theory limitation:** pattern activations là hàm xác định của 32 BoVW bits, **không bổ sung thông tin mới** theo nghĩa information theory; chỉ có thể thay đổi khả năng biểu diễn của một số mô hình.
- [x] **D023 [HARD] — Leakage caveat:** codebook B0 đã fit trên 70k ảnh, do đó classifier với codebook này chỉ nên xem là transductive/exploratory; không mô tả như independent inductive evaluation.
- [x] **D024 [HARD] — Proposed evaluation design:** nếu đề xuất PoC, nêu E0 BoVW-only, E1 pattern-only, E2 augmented; metrics accuracy, macro-F1, per-class F1; không tự bắt buộc chạy.
- [x] **D025 [HARD] — Train-only protocol for any PoC:** phải chọn/mine patterns/hyperparameters từ train/validation, không dùng test labels để chọn features; giữ nguyên artifacts TC chính, refit sạch là một thực nghiệm ngoài phạm vi.
- [ ] **D026 [OPTIONAL] — PoC riêng:** chỉ khi nhóm chủ động chọn, chạy classifier E0/E1/E2 với báo cáo trung thực transductive setting, tính toán thật và không làm thay đổi pipeline mining chính.
- [x] **D027 [HARD] — Report claims:** nếu không chạy PoC, ghi `proposed experiment / future work` và **không** xuất hoặc nhận xét số accuracy/F1 giả định như kết quả.

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

- [x] **R001 [HARD] — Output path:** dùng thư mục `results/fashion/fim/B0_K32_seed123_S0/`; không ghi đè source TC hoặc output thành viên khác.
- [x] **R002 [HARD] — Run schema:** `runs.csv` có `run_id,configuration,minsup_fraction,minsup_count,status,reason_code,total_frequent_itemsets,max_itemset_length,observed_partial_itemsets,runtime_seconds,peak_rss_mb,output_size_bytes,engine_revision,input_sha256,used_optional_limits,worker_log_path,notes`; **đúng 6 dòng** theo grid, rebuild atomic từ authoritative final/current `status.toml` sidecars, không dùng CSV để xác định completed/resume.
- [x] **R003 [HARD] — Itemset schema:** mỗi completed JSONL có `items,length,support_count,support_fraction`; file `minsup_XX.jsonl` phải đọc lại được.
- [x] **R004 [HARD] — Master pattern schema:** `pattern_id,items,length,support_count,support_fraction,observed_at_minsup,source_run_ids` hoặc JSONL tương đương.
- [x] **R005 [HARD] — Interpretation outputs:** `pattern_annotations.csv` có `review_status` mặc định `PENDING_REVIEW`, `visual_coherence=NA` trước khi có reviewer; gallery máy sinh và review thủ công là hai gate khác nhau.
- [x] **R006 [HARD] — Manifest:** `experiment_manifest.toml` ghi source/engine hash, paths, hardware/runtime/software, limits, sampling seed, six grid, statuses và output filenames.
- [x] **R007 [HARD] — Determinism:** pin sampling seeds, sort itemsets/keys, canonical pattern IDs, stable row order để rerun không đảo file vô cớ.
- [x] **R008 [HARD] — Resume without recomputation:** skip/reuse completed minsup **chỉ khi final sidecar + checksum/size/record_count/provenance/audit đều khớp**; không nhận exact-looking JSONL thiếu sidecar là completed; CSV có thể dựng lại mà không rerun.
- [x] **R009 [HARD] — Modular code:** nếu cần module helper, đặt ngoài Eclat core (ví dụ `src/fashion_fim/`), notebook điều phối và mô tả chức năng code cell ngắn gọn.
- [x] **R010 [HARD] — Separation of notebooks:** Notebook B đọc mining artifacts; không chạy Eclat lại khi refresh phần gallery/report.
- [x] **R011 [HARD] — Report structure:** `fashion_fim_application_report.md` gồm: dữ liệu/cấu hình → setup Eclat/sáu minsup → kết quả FIM → image/patch interpretation → class/retrieval/downstream → limitations/conclusion.
- [x] **R012 [HARD] — No unsupported results:** không bịa counts/figures/class enrichment/accuracy; kết quả chưa chạy để placeholder `NOT_RUN`/`BLOCKED` thay vì tự điền.
- [x] **R013 [HARD] — Scope of overall report:** đầu ra này chỉ là **Ứng dụng 2** đóng góp cho báo cáo đồ án chung; không tự tạo đầy đủ chương benchmark hoặc báo cáo IEEE khác nếu không được giao.
- [x] **R014 [HARD] — README/handoff:** chỉ dẫn môi trường Julia, đường dẫn nguồn, cách chạy theo thứ tự, cách đọc output, lưu ý ảnh/label assets và giới hạn tài nguyên.
- [x] **R015 [HARD] — Version/commit summary:** tóm tắt rõ file nào tạo/sửa, file nào cố ý không đụng, trạng thái hoàn thành và blockers còn lại.

### 6.2. Review và smoke test theo thứ tự

- [x] **T001 [HARD] — Static audit:** không có code cell đụng TC/K-means/Eclat core, SPMF default hay dải minsup cũ.
- [x] **T002 [HARD] — Loader smoke:** chạy đọc JSONL, xác nhận N=70k, no-empty, items 1–32, SHA256, mapping đủ cho diễn giải.
- [x] **T003 [HARD] — Adapter smoke:** gọi `EclatFIM.mine` trên dữ liệu nhỏ bằng API nhóm để xác nhận import/type/serialization **chỉ nhằm kiểm tra adapter**, không chạy lại bộ correctness tests của nhóm.
- [x] **T004 [HARD] — MinSup mapping:** test 80/60/40/20/10/5 → 56000/42000/28000/14000/7000/3500, không lệch integer.
- [x] **T005 [HARD] — Completed-zero path:** smoke Dict trống → exact JSONL 0 dòng, `total=0,max_length=0`; production 80% phải khớp độc lập với singleton supports; không vẽ log(0) sai.
- [x] **T006 [HARD] — Partial path:** simulated missing/limited run phải để nullable exact counts và không tạo file exact giả.
- [x] **T007 [HARD] — JSONL read-back:** verify canonical sorting, unique keys, line counts, exact support fraction formula.
- [x] **T008 [HARD] — Cross-threshold sanity:** check containment và support consistency giữa completed outputs.
- [x] **T009 [HARD] — Witness smoke:** query 1 pattern thật → supporting TIDs → mapping → patch positions → image grid; mismatch phải surfaced, không bỏ qua.
- [x] **T010 [HARD] — Retrieval smoke:** `retrieved_count == support_count` cho query đã chọn; nếu không thì `FAIL` tới khi giải quyết.
- [x] **T011 [CONDITIONAL] — Label join smoke:** `image_id→label` 1:1, N_c counts và `n(X,c)` khớp tổng over classes khi labels complete.
- [x] **T012 [HARD] — Notebook restart:** chạy sạch từ kernel mới, thứ tự execution rõ, không phụ thuộc biến ẩn hoặc cell cũ.
- [x] **T013 [HARD] — No forced expensive reruns:** notebook interpretation/report có thể chạy lại độc lập khi mining completed outputs đã tồn tại.
- [x] **T014 [HARD] — Scope review:** kiểm tra `git diff` không có thay đổi bất kỳ TC artifacts/Eclat core hay ngoài thư mục phân công.
- [x] **T015 [HARD] — Independent file audit:** mở lại một số CSV/JSONL/PNG/TOML trong runtime; kiểm tra nội dung thật, không chỉ existence.
- [x] **T016 [HARD] — Status combination examples:** `INVALID_OUTPUT` là lỗi duy nhất → `mining=FAIL`, `overall=FAILED_VALIDATION`; `NEEDS_REVISION` là việc duy nhất → `interpretation=NEEDS_REVISION`, `overall=REVISION_REQUIRED`; nhiều vấn đề → `PARTIAL_MIXED` và liệt kê từng lỗi.
- [x] **T017 [HARD] — 60% exact baseline:** từ source JSONL đếm trực tiếp supports của item 6, item 26, và pair (6,26)=32.266; sau mining full 60% verify chính xác keys `(6,)`, `(26,)`, không có pair.

## 7. Final Definition of Done (spec §9)

- [x] **DoD-01 — Locked source:** đúng B0/K32/seed123/S0, đọc `transactions.jsonl` đã có, `N=70000`, không chỉnh nguồn.
- [x] **DoD-02 — Engine ownership:** chỉ gọi `EclatFIM.mine(transactions, min_count)`; không sửa Eclat core/benchmark/tests.
- [x] **DoD-03 — Six-run report:** 6 rows do **P2 MCP production**, không nhầm P1 smoke với production; `runs.csv` dựng từ authoritative sidecars, completed chỉ khi commit/hash verify, không fake completion.
- [x] **DoD-04 — Exact mining outputs:** mọi run `COMPLETED_*` đều có file patterns/support chính xác, canonical JSONL, audit pass.
- [x] **DoD-05 — Analysis:** có counts/support/length/runtime charts, master catalog, representatives có selection rules.
- [x] **DoD-06 — Visual evidence:** galleries thật theo chain itemset → TIDs → image IDs → patch witnesses; phần human rating mặc định `PENDING_REVIEW`, chưa duyệt thì **không COMPLETE**; reviewer trả `NEEDS_REVISION` thì phải sửa, overall `REVISION_REQUIRED` nếu đó là vấn đề duy nhất. Người dùng `fernir` đã xác nhận 16 đánh giá AI-assisted; annotation `APPROVED`, điểm 0:1, 1:11, 2:4; report và manifest ghi nhận review PASS.
- [x] **DoD-07 — Image applications:** retrieval case thực tế; class support/enrichment nếu labels xác thực hoặc `BLOCKED_MISSING_LABELS` minh bạch.
- [x] **DoD-08 — Downstream:** thảo luận pattern activation features, ứng dụng ML và leakage; không tuyên bố performance khi chưa có PoC.
- [x] **DoD-09 — Reporting & reuse:** report Ứng dụng 2, config/manifests, hướng dẫn chạy lại, figures và notebooks tách biệt.
- [x] **DoD-10 — Honest handoff:** báo riêng ba trục `mining`/`execution_mcp`/`interpretation`, dùng **chính xác enum spec v1.3 §9.2** (bổ sung `FAILED_VALIDATION`, `REVISION_REQUIRED`, `PARTIAL_INTERRUPTED`); không tự thêm nhãn.

### Quy tắc công bố trạng thái cuối cùng (spec v1.3 §9.2)

**Luôn công bố ba trục** `mining=PASS/PARTIAL_RESOURCE/PARTIAL_OTHER/BLOCKED/FAIL`, `execution_mcp=PASS/BLOCKED/UNVERIFIED`, `interpretation=PASS/PENDING_REVIEW/NEEDS_REVISION/PARTIAL_MISSING_ASSET/BLOCKED`, kèm tất cả `reason_code`. `report_audit` là gate riêng PASS/FAIL.

**Overall enum khóa tại spec §9.2:** `COMPLETE`, `FAILED_VALIDATION`, `REVISION_REQUIRED`, `BLOCKED`, `PARTIAL_EXECUTION_UNVERIFIED`, `PARTIAL_MIXED`, `PARTIAL_RESOURCE_LIMITED`, `PARTIAL_INTERRUPTED`, `PARTIAL_INTERPRETATION`, `PENDING_HUMAN_REVIEW`.

| Tình huống bắt buộc nghiệm thu | Trạng thái đúng |
|---|---|
| Sáu run exact+audited, MCP PASS, interpretation review PASS, report PASS | `COMPLETE` |
| Chỉ `INVALID_OUTPUT`/report audit fail | `mining=FAIL` khi output invalid; `overall=FAILED_VALIDATION` |
| Chỉ reviewer yêu cầu sửa | `interpretation=NEEDS_REVISION`, `overall=REVISION_REQUIRED` |
| Chỉ gallery auto chưa người duyệt | `interpretation=PENDING_REVIEW`, `overall=PENDING_HUMAN_REVIEW` |
| Lỗi mining và thiếu assets/review đồng thời | `PARTIAL_MIXED`, không giấu mining FAIL |
| MCP chưa verify nhưng có artifacts | `PARTIAL_EXECUTION_UNVERIFIED` khi các trục còn lại PASS |
| 80% full sau input check | `COMPLETED_ZERO`, total=0, max_length=0, output checksum rỗng |
| 60% full sau input check | **Đúng 2 itemsets** `(6,)`, `(26,)` vì support pair `(6,26)=32.266` |

**Bàn giao tối thiểu:** 2 notebooks; `runs.csv`/sidecars/hash manifest; file itemsets final có commit hợp lệ; 3 plots FIM; master catalog/representatives; gallery+witness; retrieval; downstream discussion; three-axis status, review details, blockers và phạm vi `git diff`.

## Thứ tự thực thi duy nhất (đồng bộ MCP Instruction)

1. **P0 — Inspect / prerequisite:** nhóm **L, I**; kiểm tra MCP, engine import, paths; chọn numeric budgets và kiểm tra enforcement trước production.
2. **P1 — Implement + smoke ONLY:** loader, adapter, supervisor/worker + error/zero/recovery smoke với toy input; **không chạy sáu minsup production**, không nghiệm thu `runs.csv` 6 hàng completed (có thể init 6 hàng `NOT_RUN`).
3. **P2 — MCP production ONLY:** restart Julia kernel qua MCP, launch supervisor worker cho sáu ngưỡng 80→5, persist `runs.csv` 6 hàng sau mỗi run, read-back, reconcile crash; log MCP có bằng chứng thật.
4. **P3 — Pattern statistics:** nhóm **V, A**, audits exact, biểu đồ, chọn patterns deterministic có provenance.
5. **P4 — Interpretation & applications:** nhóm **G, D**; notebook riêng chạy MCP từ kernel sạch, gallery thật và `PENDING_REVIEW` khi chưa có human reviewer.
6. **P5 — Report/handoff:** nhóm **R, T, DoD**, audit paths, report ba trục + overall, git diff và blockers.

### MCP/Supervisor acceptance bổ sung

- [x] **X001 [HARD]** P1 chỉ smoke, P2 là lần production duy nhất; không chạy full hai lần do tài liệu khác nhau.
- [x] **X002 [HARD]** MCP tools được discover thực tế; không bịa server/tool name; Julia kernel restart/run/save/reopen có evidence. MCP reopen ngày 2026-11-19 xác nhận Mining v438 và Visual v250 đều `dirty=false`, kernel Julia idle, không có cell lỗi; persisted P5 output trả `COMPLETE`.
- [x] **X003 [HARD]** Có external supervisor ngoài notebook kernel, worker Julia per-minsup, atomic status/checkpoint, watchdog có khả năng ngắt theo policy và log cause cụ thể.
- [x] **X004 [HARD]** Đã test simulated supervisor/worker death và recovery trong smoke; khi không thể test an toàn, đánh dấu blocker cho cơ chế đó.
- [x] **X005 [HARD]** `deadline` absolute theo `time()`, `max_itemsets` throws, `max_length` trả capped Dict là semantics cần xác nhận với source; không đánh dấu capped Dict full.
- [x] **X006 [HARD]** Khi kernel/MCP chết, reconcile sidecars và worker PID trước khi resume, không spawn duplicate đang chạy hoặc ghi `COMPLETED` thiếu checkpoint.
- [x] **X007 [HARD]** Kiểm tra 80%=zero; 60%=**đúng 2 itemsets** `(6,)`, `(26,)`, pair count 32.266 < 42.000 trên source thực; bất nhất nêu `INVALID_OUTPUT` hoặc input mismatch tùy chứng cứ.
- [x] **X008 [HARD]** Reviewer là người thật; gallery auto không được tự đánh dấu `APPROVED` hay coherence 2; status ảnh hưởng đúng DoD. Xác nhận của người dùng `fernir` được lưu riêng với nguồn gốc rõ ràng rằng điểm/nhận xét do AI chuẩn bị rồi được người dùng xác nhận.

**Không tạo công việc ẩn:** Không bắt buộc classifier PoC, không chạy SPMF, không triển khai lại Eclat, không mở EDA2, không thử codebook khác và không đổi dải minsup chính thức.


## Changelog v1.2

- Đồng bộ thứ tự P1 smoke / P2 MCP production; thêm supervisor/worker, recovery, guardrails 80/60 và atomic outputs.
- Thống nhất per-run enum, reason_code, completed-zero 0/0, schema và ba trục nghiệm thu.
- Khóa deterministic representatives selection, review status mặc định PENDING_REVIEW và không nhầm gallery auto với human evidence.

## Changelog v1.3

- Sidecar checksum/final commit là nguồn chuẩn; CSV tái dựng, thêm smoke 3 crash windows và chính sách orphan.
- Đồng nhất resource budget names/scope với spec; 60% exact two patterns.
- Chốt deterministic selection tertile ties + cell order/relax; G016 reference spec schema đầy đủ.
- Định nghĩa `FAILED_VALIDATION`, `REVISION_REQUIRED`, `PARTIAL_INTERRUPTED` và nghiệm thu reviewer `NEEDS_REVISION`.
