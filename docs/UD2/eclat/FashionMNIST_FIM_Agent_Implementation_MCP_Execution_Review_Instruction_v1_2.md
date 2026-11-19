# AGENT INSTRUCTION v1.2 — Implement, Execute via MCP & Evaluate Fashion-MNIST FIM

> **Vai trò:** Bạn là coding/research agent chịu trách nhiệm hoàn thiện **Ứng dụng 2 — Fashion-MNIST Frequent Visual Itemset Mining**. Nhiệm vụ không kết thúc khi viết code: phải **chạy notebook qua MCP, kiểm tra artifacts thực tế, sửa lỗi thuộc phạm vi và đánh giá kết quả bằng số liệu đã chạy**.

## 1. Tài liệu nguồn và thứ tự ưu tiên

Đọc đầy đủ trước khi chỉnh sửa:

1. `FashionMNIST_FIM_Mining_Interpretation_Spec_v1_2.md` — **hợp đồng chức năng, I/O, trạng thái và giới hạn phạm vi**.
2. `FashionMNIST_FIM_Mining_Interpretation_Implementation_Checklist_v1_2.md` — **các công việc và Definition of Done**.
3. `itemset.md` — yêu cầu đồ án, đặc biệt **Chương 3 / Ứng dụng 2**.
4. `FashionMNIST_K32_seed123_S0_FIM_Input_Preparation.ipynb` — **tham khảo tùy chọn nếu có trong worktree**; không có thì tạo loader trực tiếp từ JSONL, không coi là blocker.
5. Source code thực tế của `EclatFIM` trong repository — **chỉ đọc để tìm cách import, xác nhận API và semantics của các giới hạn**, không chỉnh sửa.

Nếu cấu trúc repo thực tế khác đường dẫn notebook/module được đề xuất, **ưu tiên tái sử dụng cấu trúc có sẵn và ghi lại quyết định**, không tự tạo bản song song không cần thiết. Không suy đoán module import, MCP tool name, đường dẫn assets hoặc số liệu thí nghiệm.

## 2. Những quyết định đã khóa — KHÔNG THƯƠNG LƯỢNG

- Cấu hình: **B0 / `raw_full_batch_kmeans` / K=32 / seed=123 / S0 Binary BoVW**.
- Input mining **read-only**:
  `results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl`.
- Nguồn đã được người dùng xác nhận qua kiểm định TC: **70.000 transactions, 0 giao dịch rỗng**. Khi load chỉ sanity-check để phát hiện nhầm file/hỏng parser; **không chạy lại toàn bộ TC validation**.
- Items là các số nguyên `1:32`; chỉ lấy trường `items` cho Eclat. Bảo toàn mỗi dòng JSONL thành một transaction và mapping dòng ↔ `tid` ↔ `image_id`; không mặc định các ID này bằng nhau.
- Engine đã có của thành viên khác, chỉ sử dụng public API:

  ```julia
  patterns = EclatFIM.mine(transactions, min_count)
  # transactions :: Vector{Vector{Int}}
  # min_count :: Int (absolute transaction count)
  # patterns :: Dict{Tuple{Vararg{Int}},Int}  # contract do nhóm cung cấp
  ```

- **Chính xác 6 mức minsup chính thức**, chạy từ cao xuống thấp:

  | Minsup | Absolute support count |
  |---:|---:|
  | 80% | 56000 |
  | 60% | 42000 |
  | 40% | 28000 |
  | 20% | 14000 |
  | 10% | 7000 |
  | 5% | 3500 |

- Support fraction = `support_count / 70000`. **Không** dùng grid minsup cũ trong Input Preparation, không thêm 1% hoặc 0,5% vào bảng chính.
- **KHÔNG sửa, copy lại, tối ưu, benchmark hay bổ sung tests vào Eclat core**; không chạy lại TC1–TC7/K-means; không chạm benchmark/ứng dụng của thành viên khác; không thay đổi codebooks, source transactions hoặc các spatial encodings.
- **Không dùng SPMF làm đầu vào mặc định** vì API Eclat nhận trực tiếp vector transactions.
- Class labels chỉ dùng **sau mining** để diễn giải, không đi vào items hay điều kiện khai thác.
- **Không tự huấn luyện downstream classifier** trong phạm vi mặc định; phần thảo luận ứng dụng của patterns là bắt buộc.

## 3. Quy trình làm việc bắt buộc (thực hiện tuần tự)

### P0 — Inspect repo, MCP prerequisites, engine semantics và budget

1. Xác định repo root, `git status`, engine code thực sự, Julia environment, path input trong **runtime MCP**, output dirs; không chỉnh core/TC. Input Preparation notebook **không bắt buộc** tồn tại; nếu thiếu tạo loader JSONL trong phạm vi FIM.
2. Khám phá công cụ MCP notebook/Jupyter **đang thực sự có**, khả năng chọn Julia kernel/restart/execute/save/reopen. **Không bịa tên tool hoặc nói chạy MCP nếu chỉ dùng terminal**.
3. Kiểm tra interface `EclatFIM.mine` và **xác nhận theo source** những semantics người review đã báo: `deadline` so với `time()` là absolute timestamp; `max_itemsets` throw; `max_length` có thể trả Dict đã giới hạn mà không có completion flag. Production full ưu tiên chỉ truyền **hai positional arguments**.
4. Đọc JSONL, hash, kiểm tra N=70k, 0 empty, items 1:32. **Tự đếm support 32 singleton từ nguồn**: người dùng báo `max_count=48_922`, tại 80% phải 0 frequent singleton và tại 60% có 2 frequent singleton; nếu khác thì điều tra source/loader trước production.
5. Chốt **con số thực tế** per-run `wall_time_seconds`, `memory_limit_mb`, `output_limit_bytes`; ghi **cơ chế enforce**. Xác nhận có thể dùng process riêng dưới runtime MCP; supervisor/watchdog phải có khả năng stop worker và lưu bằng chứng ngoài notebook kernel. Nếu không enforce/không bảo đảm worker recovery, báo blocker `BUDGET_NOT_ENFORCEABLE`; không chạy production thiếu giám sát rồi tuyên bố được bảo vệ.
6. Ghi hashes, Julia/package/engine git revision, threads, hardware và output filesystem. Định danh từng ngưỡng bởi `configuration+min_count+input_hash+engine_revision+budget_revision` để resume an toàn.

**Exit gate P0:** xác nhận nguồn, API, singleton sanity, MCP kernel, worker/supervisor feasibility và budget enforcement. Chưa chạy production.

### P1 — Implement + smoke ONLY (không chạy 6 ngưỡng production)

1. Viết loader JSONL → `Vector{Vector{Int}}`, mapping dòng ↔ TID ↔ image_id. Viết adapter `EclatFIM.mine(transactions, min_count)` và serializer `Dict{Tuple{Vararg{Int}},Int}` theo thứ tự canonical; không sửa Eclat core.
2. Viết **supervisor process độc lập với notebook kernel** và **worker Julia mới cho mỗi minsup**. Supervisor quản lý wall-time/RAM/output budgets, worker stdout/stderr, PID, heartbeat, atomic status sidecar, temporary output rồi rename. `runs.csv` dựng atomic từ 6 slots cố định.
3. Implement per-run enum **đúng như spec v1.2 §4.3**: `NOT_RUN, COMPLETED_FULL, COMPLETED_ZERO, TIMEOUT, MEMORY_LIMIT, OUTPUT_LIMIT, ITEMSET_CAPPED, LENGTH_CAPPED, COMPLETION_UNVERIFIED, INVALID_OUTPUT, FAILED, UNKNOWN_INTERRUPTED, BLOCKED`, `reason_code` riêng. `COMPLETED_ZERO` có `total=0, max_length=0` và exact output JSONL 0 dòng; mọi status khác ngoài COMPLETED_* có total/max_length NA.
4. **Chỉ smoke với tiny/toy dataset**: import, JSONL load, Dict serialization, completed-zero, exception mapping, timeout giả lập, supervisor recovery và atomic CSV/JSONL; không dùng toàn bộ 70k cho 6 production runs ở P1. Có thể init `runs.csv` 6 hàng `NOT_RUN`; **không đánh dấu completed**.
5. Khi `max_length` được truyền vào bất kỳ run nào và chưa có chứng nhận full độc lập, phải `LENGTH_CAPPED`; `max_itemsets` ném exception được phân loại `ITEMSET_CAPPED` **chỉ nếu đúng exception/cause**; `deadline` phải là absolute `time()+budget` nếu được sử dụng và đã xác minh. Full production chủ yếu giới hạn qua supervisor.

**Exit gate P1:** code + smoke proof + config valid + supervisor recovery khả dụng; **chưa có yêu cầu production results/6 completed rows**.

### P2 — MCP production, read-back, recovery và six-run acceptance

1. Dùng MCP **thật** mở notebook Mining, chọn đúng Julia kernel, **restart sạch**, chạy cells P2 theo thứ tự, lưu và reopen notebook; ghi MCP provider/tool, kernel ID/version, time, cell execution status vào `report/mcp_execution_log.md`.
2. Notebook khởi chạy **supervisor ngoài kernel**, supervisor spawn **worker Julia riêng từng ngưỡng** lần lượt 80%,60%,40%,20%,10%,5%. **Production chỉ thực hiện tại đây**; không chạy lại full job do P1 đã smoke. Notebook MCP poll bounded và đọc persisted logs/trạng thái, không khóa kernel vô hạn.
3. Mỗi worker phải có `started_at`, `heartbeat`, `pid`, `deadline_at`, `exit code/signal`, stdout/stderr và `reason_code`. Supervisor enforce numeric budgets từ P0, kill theo đúng nguyên nhân và ghi atomic metadata, sau đó cập nhật `mining/runs.csv` **đúng sáu hàng**. Worker chỉ gọi engine nhóm, không sửa core.
4. Sau Dict return, **chưa vội coi COMPLETED**: validate canonical keys/support, JSONL line-count, checksum/read-back, cross-minsup audit, so singleton guardrails 80/60. Audit PASS mới atomic rename file exact `minsup_XX.jsonl` và chốt status. Output incomplete đặt tên/metadata `partial`, không dùng exact output path.
5. Nếu kernel ngắt, MCP reconnect và **reconcile supervisor journal**, check PID/heartbeat/exit marker, không spawn hai worker cho một threshold. Supervisor còn sống thì tiếp tục monitor; mất supervisor/worker mà không rõ nguyên nhân → `UNKNOWN_INTERRUPTED`, tuyệt đối không gán TIMEOUT/OOM theo cảm tính. Mọi lần retry phải có run revision/notes và chỉ retry khi xác minh worker cũ không còn chạy.
6. `COMPLETED_ZERO` ở 80% sau independent singleton check: `total=0`, `max_length=0`, `minsup_80.jsonl` rỗng hợp lệ. 60% phải có **2 singleton frequent**, không được suy luận tổng itemsets chính xác là 2 nếu có frequent pair.
7. Nếu MCP tool/kernel/input không có, ghi `BLOCKED` với `reason_code=MCP_UNAVAILABLE`/`KERNEL_UNAVAILABLE`/`INPUT_INACCESSIBLE`; **không giả log MCP**. Nếu notebook không chạy nhưng artifacts từ terminal/cache tồn tại, trạng thái **MCP vẫn UNVERIFIED**; toàn dự án không được công bố COMPLETE.

**Exit gate P2:** MCP notebook evidence thật + supervisor/worker persistence + `runs.csv` đúng 6 rows và artifact read-back (hoặc blocker được ghi rõ). *Không* tự động yêu cầu cả sáu ngưỡng hoàn tất bằng mọi giá; trung thực về resource-limited outputs.

### P3 — Sanity audit & phân tích Frequent Itemsets

1. Kiểm tra từng completed output: itemsets không rỗng, sorted unique, IDs 1–32, support integer trong `[min_count, 70000]`; đối chiếu count Dict với số dòng JSONL.
2. Với hai ngưỡng completed a>b: patterns(a) là tập con patterns(b), support của cùng pattern bằng nhau; chọn **mẫu ~20 patterns cố định** để scan/giao lại trên transactions và kiểm chứng support. Đây là audit output ứng dụng, không thay thế tests Eclat core.
3. Tính itemset counts, count by length, max length, support distribution, tỷ trọng singleton/pair/length≥3 và runtime theo minsup; vẽ đồ thị **chỉ dùng giá trị exact từ completed runs**, thể hiện missing/partial/timeout rõ ràng.
4. Gộp master pattern catalog theo canonical itemset, không đếm trùng giữa các ngưỡng. Chọn **target 16** theo protocol spec v1.2 §5.4: length 1/2/≥3 × support tertiles, deterministic round-robin, Jaccard items ≤0.80 (nới 0.90 một lần nếu cần), tie theo canonical IDs; lưu selection seed/rule và lý do, không cherry-pick.
5. Viết **nhận xét có số liệu**, không chỉ kể tên charts. Cần trả lời ít nhất: ngưỡng nào có bao nhiêu patterns; số patterns thay đổi ra sao; lengths xuất hiện thế nào; runtime và output size tăng/giảm ra sao; có patterns chiếm tỷ lệ ảnh cao nhưng ít tính phân biệt không. Khi thiếu completed runs, nêu giới hạn và chỉ nhận xét phần có bằng chứng.

**Exit gate P3:** `analysis/` có catalogs, tables, figures và báo cáo insights trích số liệu có thể truy đến artifacts.

### P4 — Interpretation, phân tích ảnh và downstream discussion

1. Notebook `FIM_Visual_Interpretation.ipynb` **đọc các outputs mining đã lưu**; không tự gọi lại `EclatFIM.mine` khi chỉnh plots, galleries hay báo cáo.
2. Tìm đúng assets gốc (codebook B0/K32/seed123, `patch_assignments.csv`, TID-image mapping, raw Fashion-MNIST images, metadata labels nếu có). Không tạo giả chứng cứ khi asset thiếu; phần phụ thuộc nào thiếu thì ghi `BLOCKED_MISSING_ASSET`/`BLOCKED_MISSING_LABELS` cụ thể.
3. Mỗi pattern được chọn cần có: visual-word centroids 4×4 **reshape column-major đúng**, patches thật nếu có, supporting images thật, witness patch positions hợp lệ, ảnh đối chứng nếu có, support/count và caption thận trọng. **S0 chỉ mã hóa đồng xuất hiện, không chứng minh vị trí hay liên kết hình học cố định.**
4. Khi labels có join 1:1 hợp lệ, tính `P(X)=n(X)/70000`, `P(X|c)=n(X,c)/N_c`, `enrichment=P(X|c)/P(X)`. Phân tích common/class-enriched/cross-class **chỉ khi số liệu thực sự ủng hộ**; frequent không đồng nghĩa discriminative.
5. Triển khai **ít nhất một retrieval case thực** từ một itemset đã mine; xây danh sách ảnh chứa `X`, kiểm tra `retrieved_count == support_count(X)`, lưu gallery ảnh tìm được và ảnh contrast.
6. Bắt buộc thảo luận downstream feature engineering: 32 Binary BoVW bits, `φ_j(I)=1[P_j⊆T(I)]`, feature augmented `32+m`; mô tả ứng dụng và thiết kế đánh giá baseline/pattern-only/augmented. Nêu rõ feature patterns **không làm tăng thông tin** vì là hàm của BoVW bits. Codebook fit trên toàn bộ 70k, do đó PoC hiện tại nếu làm là **transductive/exploratory**. **Không huấn luyện classifier** nếu không có giao việc mới, và không bịa accuracy/F1.
7. Chạy notebook Interpretation **bằng MCP từ kernel sạch**, mở/kiểm tra gallery, CSV và báo cáo. `pattern_annotations.csv` mặc định `review_status=PENDING_REVIEW`, `visual_coherence=NA`; **người thật** chấm 0/1/2 và duyệt. Agent không tự chấm `APPROVED`/2. Gallery auto hoàn thành **chưa đủ** để công bố interpretability verified và overall COMPLETE.

**Exit gate P4:** Có evidence thực tế cho ít nhất một frequent pattern → supporting images/patches → image retrieval → nhận xét ứng dụng có giới hạn; labels chỉ dùng khi join hợp lệ.

### P5 — Báo cáo đánh giá thực nghiệm, audit và bàn giao

1. Tạo `report/fashion_fim_application_report.md` gồm: cấu hình/dữ liệu → setup thực nghiệm → bảng 6 minsup/status → phân tích pattern length/support/runtime → visual evidence → class analysis/retrieval → downstream application → limitations/conclusion.
2. Tạo `report/experiment_manifest.toml`, README chạy lại (thứ tự notebook và MCP prerequisites), bảng output và cách phân biệt completed/partial. Chốt checklist **chỉ đánh dấu `[x]` hạng mục có bằng chứng**; không tô xong theo dự định.
3. **Tự review như người chấm đồ án**, tập trung vào:
   - **Correctness of integration:** input/`min_count` đúng, support/count đúng, no core edits.
   - **Completeness of mining:** sáu thresholds, statuses trung thực, không có partial ngụy trang exact.
   - **Research value:** so sánh minsup có số liệu và bình luận nguyên nhân hợp lý, không dùng “nhiều patterns = tốt”.
   - **Visual evidence:** centroid/patch/image mapping có căn cứ, không suy diễn spatial S0.
   - **Application value:** class enrichment & retrieval có dữ liệu, downstream protocol rõ, không overclaim.
   - **Reproducibility:** MCP execution thật, file hashes, version, log, read-back và notebooks restart sạch.
4. Viết `report/agent_evaluation.md` gồm: bảng tiêu chí **PASS / PARTIAL / FAIL / BLOCKED**, link/đường dẫn evidence cho mỗi tiêu chí; **3–5 insights quan trọng nhất từ kết quả thật**, hạn chế, lỗi đã phát hiện/sửa, việc cần tiếp tục; không dùng số giả định trong kết luận.
5. Kiểm tra `git diff --stat` + `git diff --name-only`: ghi những file mới/sửa; **xác minh không chạm Eclat core, TC artifacts, benchmark hay phần việc của thành viên khác**. Không tự commit/push nếu chưa được yêu cầu.
6. Công bố ba trục `mining`, `execution_mcp`, `interpretation` theo spec v1.2 §9.2; overall chỉ dùng `COMPLETE`, `BLOCKED`, `PARTIAL_EXECUTION_UNVERIFIED`, `PARTIAL_MIXED`, `PARTIAL_RESOURCE_LIMITED`, `PARTIAL_INTERPRETATION`, `PENDING_HUMAN_REVIEW`. Báo đồng thời nhiều blockers, không che lỗi/thiếu review bằng một trạng thái chung.

## 4. Điều kiện nghiệm thu nhanh (agent tự kiểm tra trước khi báo hoàn tất)

- [ ] Hai notebook chính có logic rõ, mỗi code cell có mô tả ngắn gọn về **mục đích**; không chèn giải thích dài dòng hoặc section thừa.
- [ ] Không sửa Eclat/TC/source của nhóm; `git diff` chứng minh ranh giới.
- [ ] Đọc đúng JSONL đã khóa, 70.000 transactions; chỉ items 1–32; SHA256/provenance được ghi.
- [ ] Chỉ gọi `EclatFIM.mine(transactions, min_count)` (không sửa core); sáu counts = 56000,42000,28000,14000,7000,3500.
- [ ] Notebook chạy qua **MCP** từ kernel sạch, có log bằng chứng; failures/blockers được báo thật.
- [ ] P1 chỉ smoke, P2 **mới** chạy sáu ngưỡng production qua MCP; `mining/runs.csv` đúng 6 dòng, status/reason_code và nullable metrics theo enum duy nhất.
- [ ] Mọi completed JSONL có exact counts/support, sorted canonical, read-back pass; audit cross-minsup pass.
- [ ] Có phân tích counts/support/length/runtime, representative patterns và figures từ dữ liệu thật.
- [ ] Có galleries ảnh/patchs/witness thật, retrieval itemset thật; `PENDING_REVIEW` cho manual ratings khi chưa có người duyệt; labels/enrichment khi đủ metadata.
- [ ] Có thảo luận rõ cách dùng patterns làm input ML và giới hạn leakage/transductive; classifier PoC vẫn optional.
- [ ] Có `report/mcp_execution_log.md`, persisted worker sidecars, report/manifest/README/agent evaluation; overall theo 3 trục và chứng minh được.

## 5. Định dạng báo cáo cuối của agent — phải trả lời theo mục này

1. **Status chung** theo enum spec v1.2 **và status ba trục riêng**, reason codes cho mọi blocker, reviewer pending nếu chưa duyệt.
2. **Files tạo/sửa**: notebook, modules, results và báo cáo; file nào được giữ nguyên.
3. **MCP execution evidence**: notebook nào đã chạy, MCP/kernel thực sự dùng, trạng thái restart/run/save/reopen, supervisor/worker PID/heartbeat, errors/retries, recovery và log (không gộp terminal với MCP).
4. **Bảng 6 minsup**: threshold, absolute count, status/reason_code, số itemsets exact (nếu completed), max length (0 ở completed-zero), runtime, memory nếu đo được; kiểm tra baseline 80%/60%.
5. **3–5 insights có số liệu**: xu hướng, pattern classes, runtime, giá trị/hạn chế.
6. **Visual/application evidence**: representative examples, retrieval count/support, class enrichment (nếu hợp lệ), downstream discussion.
7. **DoD checklist**: các mục PASS/PARTIAL/BLOCKED, review status `PENDING_REVIEW` nếu chưa được đánh giá thủ công; việc còn thiếu hoặc cần người khác cung cấp; **không che blockers**.
8. **Scope check**: `git diff` xác nhận không sửa Eclat core/TC và đề xuất bước tiếp theo có căn cứ.

**Quy tắc cuối:** Không dừng ở “đã code xong”. Công việc chỉ hoàn thành khi **đã chạy được bằng MCP, có artifacts thực tế, đọc lại được, đánh giá có bằng chứng và bàn giao minh bạch**. Nếu môi trường không cho phép làm đủ, hoàn tất phần có thể làm và báo đúng blocker, tuyệt đối không tự dựng kết quả.


## Changelog v1.2

- P1 chỉ implement/smoke, P2 chạy MCP production một lần; không chạy sản xuất hai lần.
- Supervisor/worker process độc lập, budget enforcement thật, atomic persistence/recovery, enum status + reason code, 80/60 singleton sanity.
- Input Preparation optional; deterministic representative selection; human review PENDING_REVIEW và tổng hợp DoD trên 3 trục.
