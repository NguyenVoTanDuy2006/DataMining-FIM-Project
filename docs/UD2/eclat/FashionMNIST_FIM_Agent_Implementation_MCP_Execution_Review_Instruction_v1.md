# AGENT INSTRUCTION v1.0 — Implement, Execute via MCP & Evaluate Fashion-MNIST FIM

> **Vai trò:** Bạn là coding/research agent chịu trách nhiệm hoàn thiện **Ứng dụng 2 — Fashion-MNIST Frequent Visual Itemset Mining**. Nhiệm vụ không kết thúc khi viết code: phải **chạy notebook qua MCP, kiểm tra artifacts thực tế, sửa lỗi thuộc phạm vi và đánh giá kết quả bằng số liệu đã chạy**.

## 1. Tài liệu nguồn và thứ tự ưu tiên

Đọc đầy đủ trước khi chỉnh sửa:

1. `FashionMNIST_FIM_Mining_Interpretation_Spec_v1_1.md` — **hợp đồng chức năng, I/O, trạng thái và giới hạn phạm vi**.
2. `FashionMNIST_FIM_Mining_Interpretation_Implementation_Checklist_v1_1.md` — **các công việc và Definition of Done**.
3. `itemset.md` — yêu cầu đồ án, đặc biệt **Chương 3 / Ứng dụng 2**.
4. `FashionMNIST_K32_seed123_S0_FIM_Input_Preparation.ipynb` — notebook có sẵn, **chỉ tái sử dụng loader/phần thích hợp**.
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

### P0 — Khảo sát repository và chuẩn bị thực thi

1. Kiểm tra `git status`, xác định repo root, đọc spec/checklist, vị trí module `EclatFIM`, notebooks, các artifacts TC6 và ảnh gốc/metadata. **Không ghi đè thay đổi sẵn có của người khác**.
2. Kiểm tra Julia kernel, Project/Manifest hoặc dependency setup hiện có. Xác định **MCP có khả năng thao tác notebook thật**: liệt kê các notebook/Jupyter MCP tools khả dụng và chọn công cụ mở notebook, restart kernel, chạy cells, lấy outputs, lưu notebook. **Không đoán tên MCP tool; dùng đúng API thực sự được cung cấp trong phiên agent**.
3. Kiểm tra đường dẫn `transactions.jsonl` tồn tại trong **runtime mà MCP sử dụng**, không chỉ trong môi trường terminal cục bộ. Nếu runtime remote, xử lý môi trường/mount theo cơ chế đã được cho phép, không âm thầm copy bản khác.
4. Ghi `input_sha256`, source path, git revision của Eclat, Julia version, môi trường, sampling seed và chính sách time/memory/output. **Không tự nhận giới hạn tài nguyên đã được enforce nếu thực tế chưa có cơ chế enforce.**
5. Tạo/sửa trong phạm vi hợp lệ: notebooks dành cho Fashion-MNIST, helper modules ngoài Eclat core nếu thật sự cần, và `results/fashion/fim/B0_K32_seed123_S0/`. Ưu tiên notebooks: `FIM_Mining_Experiments.ipynb` và `FIM_Visual_Interpretation.ipynb`.

**Exit gate P0:** Đã xác nhận input, engine import, Julia environment, MCP kernel/run capability và các paths output; nếu một điều kiện chặn không giải quyết được, ghi `BLOCKED` + chứng cứ cụ thể.

### P1 — Implement và smoke test notebook Mining

1. Loader đọc JSONL trực tiếp thành `Vector{Vector{Int}}`, giữ index dòng ↔ TID/image ID, sanity assert `N=70000`, `empty=0`, items 1–32 không lặp. Nguồn gốc và hash phải ghi vào manifest.
2. Load **module `EclatFIM` của nhóm**, không viết lại Eclat. Làm một smoke test adapter ngắn trên toy transactions để xác nhận cách gọi/type/serialize; **không thực hiện lại bộ correctness tests của thành viên khác**.
3. Tạo runner cho đúng sáu `min_count`. Production full calls mặc định **không truyền** `max_length`, `max_itemsets`, `deadline`. Chỉ dùng giới hạn khi đã đọc rõ semantics trong code và có cách phân biệt partial; nếu không, dùng cơ chế giới hạn ở tầng chạy được chứng minh và đánh dấu status trung thực.
4. Mỗi run ghi thời gian, resource metrics **nếu đo được thật**, status, input hash, engine revision, giới hạn đã dùng và output path. Sau mỗi ngưỡng phải lưu logs/metadata ngay, để lỗi ở ngưỡng sau không làm mất bằng chứng ngưỡng trước.
5. `EclatFIM.mine` chỉ trả Dict, **không có completion metadata**. Chỉ đánh dấu `COMPLETED_FULL`/`COMPLETED_ZERO` khi call kết thúc bình thường, output được kiểm tra và **không bị các giới hạn mining cắt** (hoặc có tín hiệu chứng minh giới hạn không tác động). Nếu không xác minh được, ghi `COMPLETION_UNVERIFIED`. Ghi `TIMEOUT`, `MEMORY_LIMIT`, `ITEMSET_CAPPED`, `LENGTH_CAPPED`, `FAILED`, `BLOCKED` hoặc `UNKNOWN_INTERRUPTED` theo bằng chứng.
6. Với run completed, sort Dict keys theo `(length(itemset), itemset)` rồi xuất **toàn bộ** entries vào `mining/itemsets/minsup_XX.jsonl` gồm `items,length,support_count,support_fraction`. Output partial phải có metadata/tên khác; **không được mang tên file exact**.
7. `mining/runs.csv` phải có **đúng 6 dòng** theo ngưỡng chính thức, kể cả run trả `Dict()` (được phép `COMPLETED_ZERO`), bị lỗi hoặc không được chạy vì blocker. Với run không completed, `total_frequent_itemsets` và `max_itemset_length` là null/NA; không dùng partial counts để vẽ biểu đồ total exact.

**Exit gate P1:** Có 6 rows status trung thực, file exact chỉ cho completed runs, logs/provenance và các checks của adapter/serialization.

### P2 — Chạy notebook bằng **MCP thật** và kiểm tra outputs

1. **Bắt buộc dùng MCP notebook/Jupyter đã được kết nối** để mở notebook, chọn đúng Julia kernel, **restart kernel**, chạy các cells **theo thứ tự từ đầu**, kiểm tra outputs từng giai đoạn và lưu notebook sau chạy. Không coi `nbformat` parse thành công hay file `.ipynb` được tạo là đã thực thi.
2. Chạy smoke loader + import + one high-minsup test trước. Khi thành công mới chạy sáu ngưỡng theo thứ tự 80 → 60 → 40 → 20 → 10 → 5. Không bắt kernel chịu một job không có cách giám sát/dừng; khai báo budget trước khi chạy và tôn trọng tài nguyên hiện có.
3. Nếu gặp lỗi notebook, dependencies, cwd, JSONL parser, adapter, output I/O hoặc visualization **thuộc phạm vi được giao**, sửa đúng nguyên nhân rồi **restart và chạy lại các cells bị ảnh hưởng qua MCP**. Nếu lỗi nằm ở Eclat core, báo blocker với stack trace, không sửa core.
4. Giữ **bằng chứng thực thi MCP** trong `report/mcp_execution_log.md`: MCP server/tool thực sự sử dụng, notebook path, kernel/runtime, thời điểm và thứ tự cell, các lần restart/retry, lỗi đã xử lý, output quan trọng và kết quả save/reopen. **Không ghi log giả hay viết “MCP executed” nếu không gọi thành công công cụ.**
5. Sau mỗi notebook, kiểm tra trên filesystem **thực sự** rằng outputs có thể read-back. Với JSONL, kiểm tra line count = `length(patterns)` của completed run; với CSV/TOML, parse lại và soát schema; với PNG, mở/kiểm tra nội dung không rỗng. Không chỉ dựa vào `println("saved")`.
6. Nếu MCP tool không hiện hữu/không có Julia kernel/không truy cập được input, **không thay thế lén bằng terminal rồi công bố đã chạy MCP**. Hãy ghi `BLOCKED_MCP_UNAVAILABLE`/`BLOCKED_KERNEL`/`BLOCKED_INPUT_ACCESS`, mô tả việc đã thử và phần implement đã hoàn thành. Chỉ dùng cách chạy khác nếu người dùng cho phép riêng, và ghi rõ đó không phải MCP.

**Exit gate P2:** Notebook Mining đã được thực thi qua MCP từ kernel sạch (hoặc có blocker chứng minh được), sản phẩm được mở lại kiểm chứng, log MCP là thật.

### P3 — Sanity audit & phân tích Frequent Itemsets

1. Kiểm tra từng completed output: itemsets không rỗng, sorted unique, IDs 1–32, support integer trong `[min_count, 70000]`; đối chiếu count Dict với số dòng JSONL.
2. Với hai ngưỡng completed a>b: patterns(a) là tập con patterns(b), support của cùng pattern bằng nhau; chọn **mẫu ~20 patterns cố định** để scan/giao lại trên transactions và kiểm chứng support. Đây là audit output ứng dụng, không thay thế tests Eclat core.
3. Tính itemset counts, count by length, max length, support distribution, tỷ trọng singleton/pair/length≥3 và runtime theo minsup; vẽ đồ thị **chỉ dùng giá trị exact từ completed runs**, thể hiện missing/partial/timeout rõ ràng.
4. Gộp master pattern catalog theo canonical itemset, không đếm trùng khi itemset xuất hiện ở nhiều minsup. Chọn khoảng **12–20 representative patterns nếu dữ liệu đủ**, theo nhiều mức support/độ dài và độ đa dạng; lưu lý do lựa chọn, không chỉ cherry-pick patterns đẹp.
5. Viết **nhận xét có số liệu**, không chỉ kể tên charts. Cần trả lời ít nhất: ngưỡng nào có bao nhiêu patterns; số patterns thay đổi ra sao; lengths xuất hiện thế nào; runtime và output size tăng/giảm ra sao; có patterns chiếm tỷ lệ ảnh cao nhưng ít tính phân biệt không. Khi thiếu completed runs, nêu giới hạn và chỉ nhận xét phần có bằng chứng.

**Exit gate P3:** `analysis/` có catalogs, tables, figures và báo cáo insights trích số liệu có thể truy đến artifacts.

### P4 — Interpretation, phân tích ảnh và downstream discussion

1. Notebook `FIM_Visual_Interpretation.ipynb` **đọc các outputs mining đã lưu**; không tự gọi lại `EclatFIM.mine` khi chỉnh plots, galleries hay báo cáo.
2. Tìm đúng assets gốc (codebook B0/K32/seed123, `patch_assignments.csv`, TID-image mapping, raw Fashion-MNIST images, metadata labels nếu có). Không tạo giả chứng cứ khi asset thiếu; phần phụ thuộc nào thiếu thì ghi `BLOCKED_MISSING_ASSET`/`BLOCKED_MISSING_LABELS` cụ thể.
3. Mỗi pattern được chọn cần có: visual-word centroids 4×4 **reshape column-major đúng**, patches thật nếu có, supporting images thật, witness patch positions hợp lệ, ảnh đối chứng nếu có, support/count và caption thận trọng. **S0 chỉ mã hóa đồng xuất hiện, không chứng minh vị trí hay liên kết hình học cố định.**
4. Khi labels có join 1:1 hợp lệ, tính `P(X)=n(X)/70000`, `P(X|c)=n(X,c)/N_c`, `enrichment=P(X|c)/P(X)`. Phân tích common/class-enriched/cross-class **chỉ khi số liệu thực sự ủng hộ**; frequent không đồng nghĩa discriminative.
5. Triển khai **ít nhất một retrieval case thực** từ một itemset đã mine; xây danh sách ảnh chứa `X`, kiểm tra `retrieved_count == support_count(X)`, lưu gallery ảnh tìm được và ảnh contrast.
6. Bắt buộc thảo luận downstream feature engineering: 32 Binary BoVW bits, `φ_j(I)=1[P_j⊆T(I)]`, feature augmented `32+m`; mô tả ứng dụng và thiết kế đánh giá baseline/pattern-only/augmented. Nêu rõ feature patterns **không làm tăng thông tin** vì là hàm của BoVW bits. Codebook fit trên toàn bộ 70k, do đó PoC hiện tại nếu làm là **transductive/exploratory**. **Không huấn luyện classifier** nếu không có giao việc mới, và không bịa accuracy/F1.
7. Chạy notebook Interpretation **bằng MCP từ kernel sạch**, mở/kiểm tra các gallery, CSV và báo cáo sau khi chạy. Nếu sửa notebook thì chạy lại phần liên quan để kiểm chứng.

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
6. Công bố trạng thái cuối: `COMPLETE`, `PARTIAL_RESOURCE_LIMITED`, `PARTIAL_INTERPRETATION`, hoặc `BLOCKED`, đúng Definition of Done trong spec v1.1. Nếu có vấn đề khác, mô tả chính xác thay vì gán nhãn `COMPLETE`.

## 4. Điều kiện nghiệm thu nhanh (agent tự kiểm tra trước khi báo hoàn tất)

- [ ] Hai notebook chính có logic rõ, mỗi code cell có mô tả ngắn gọn về **mục đích**; không chèn giải thích dài dòng hoặc section thừa.
- [ ] Không sửa Eclat/TC/source của nhóm; `git diff` chứng minh ranh giới.
- [ ] Đọc đúng JSONL đã khóa, 70.000 transactions; chỉ items 1–32; SHA256/provenance được ghi.
- [ ] Chỉ gọi `EclatFIM.mine(transactions, min_count)` (không sửa core); sáu counts = 56000,42000,28000,14000,7000,3500.
- [ ] Notebook chạy qua **MCP** từ kernel sạch, có log bằng chứng; failures/blockers được báo thật.
- [ ] `mining/runs.csv` đúng 6 dòng, trạng thái và nullable metrics hợp lệ.
- [ ] Mọi completed JSONL có exact counts/support, sorted canonical, read-back pass; audit cross-minsup pass.
- [ ] Có phân tích counts/support/length/runtime, representative patterns và figures từ dữ liệu thật.
- [ ] Có galleries ảnh/patchs/witness thật, retrieval itemset thật; labels/enrichment khi đủ metadata.
- [ ] Có thảo luận rõ cách dùng patterns làm input ML và giới hạn leakage/transductive; classifier PoC vẫn optional.
- [ ] Có report, manifests, README, agent evaluation và trạng thái tổng thể chứng minh được.

## 5. Định dạng báo cáo cuối của agent — phải trả lời theo mục này

1. **Status chung** và lý do (COMPLETE / PARTIAL_RESOURCE_LIMITED / PARTIAL_INTERPRETATION / BLOCKED).
2. **Files tạo/sửa**: notebook, modules, results và báo cáo; file nào được giữ nguyên.
3. **MCP execution evidence**: notebook nào đã chạy, MCP/kernel thực sự dùng, trạng thái restart/run/save, errors/retries và đường dẫn log.
4. **Bảng 6 minsup**: threshold, absolute count, status, số itemsets exact (nếu completed), max length, runtime, memory nếu đo được.
5. **3–5 insights có số liệu**: xu hướng, pattern classes, runtime, giá trị/hạn chế.
6. **Visual/application evidence**: representative examples, retrieval count/support, class enrichment (nếu hợp lệ), downstream discussion.
7. **DoD checklist**: các mục PASS/PARTIAL/BLOCKED, việc còn thiếu hoặc cần người khác cung cấp; **không che blockers**.
8. **Scope check**: `git diff` xác nhận không sửa Eclat core/TC và đề xuất bước tiếp theo có căn cứ.

**Quy tắc cuối:** Không dừng ở “đã code xong”. Công việc chỉ hoàn thành khi **đã chạy được bằng MCP, có artifacts thực tế, đọc lại được, đánh giá có bằng chứng và bàn giao minh bạch**. Nếu môi trường không cho phép làm đủ, hoàn tất phần có thể làm và báo đúng blocker, tuyệt đối không tự dựng kết quả.
