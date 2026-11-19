# Review EDA2 v1.1 & Protocol lựa chọn Codebook/Encoding — đề xuất bổ sung

**Dự án:** Fashion-MNIST → TC4 B0 → TC6 (S0, S1, S3, S6-B) → EDA2/Pilot Eclat  
**Nguồn đã đối chiếu:** `EDA2_FashionMNIST_Transaction_Evaluation_Spec_v1_1.md`, `EDA2_Implementation_Checklist_v1_1.md`; tham chiếu kết quả `tc4_metrics_summary.csv`, `tc4_seed_stability.toml`, `tc_v2_run_summary.toml`.  
**Trạng thái:** Review và *đề xuất bổ sung*, **chưa thay thế spec v1.1**, chưa có kết quả EDA2 thực tế.

## A. Kết luận review

### Các phần đang tốt, nên giữ

1. Thiết kế phân tầng `EDA2-00 → A → B → C1 → C2 → C3 → D → E` với 15 codebooks, 60 databases, hỗ trợ dữ liệu bị giới hạn tài nguyên.
2. Tách intrinsic TC4 khỏi transaction utility và Eclat; phân biệt số patches/cluster với số images/item support.
3. Shortlist `(K, seed)` chỉ sau khi khảo sát 60 datasets; giữ đủ 4 variants/cặp để so sánh có đối chứng.
4. Không loại chỉ vì distortion/ARI/non-convergence, không coi timeout là 0 itemsets.
5. B5 class-conditional similarity chỉ hậu nghiệm; mặc định không tham gia lựa chọn unsupervised.
6. EDA2-D có gallery, witness S6-B và null shuffle giữ multiset words/vị trí retained.

### Các thiếu sót cần bổ sung để agent ra quyết định nhất quán

| ID | Mức độ | Phần spec | Vấn đề | Bổ sung đề xuất |
|---|---|---|---|---|
| R1 | HIGH | §6.3, §8 | Tiêu chí “mining có ý nghĩa”, “không tầm thường”, “ổn định” còn định tính | Định nghĩa bằng chứng tối thiểu, tính hoàn chỉnh và rubric pattern cụ thể |
| R2 | HIGH | §8 | Chưa có quy trình **chọn codebook vs chọn codebook+variant** đủ tường minh | So variants paired trong cùng codebook, sau đó chọn **final joint triple**; báo riêng kết quả tốt nhất theo từng variant |
| R3 | HIGH | §6.2–6.4 | C1 tại 3% và maxlen=2 có thể bất lợi với S6-B thưa, và C2 dẫn đến selection bias | Khảo sát sensitivity **chung** tại ngưỡng thấp hơn nếu cần, không coi “0 mẫu tại 3%” là invalid; bảo toàn coverage K và reserve challengers |
| R4 | HIGH | §8 | Cần tách **feasibility** khỏi **quality** khi TIMEOUT/censoring | Gate feasibility có ngân sách tài nguyên công bố trước; `UNKNOWN/CENSORED` không được chấm 0 hoặc xếp hạng như completed |
| R5 | MEDIUM | §7, §8 | Rubric visual_coherence/nontriviality chưa có thang/tiêu chí phân định | Rubric 0–2, lấy mẫu pattern theo rule cố định, đánh giá blind labels nếu có thể; giữ evidence ảnh/witness |
| R6 | MEDIUM | §4, §8 | Codebook stability theo K và seed chưa gắn vào quy tắc chọn seed | Báo mean/range 3 seeds theo K+variant; ưu tiên seed converged, mining/transactions ổn định khi tie; không dùng raw word ID |
| R7 | MEDIUM | §8 | Chưa nói rõ trường hợp **không có universal-best codebook** | Cho phép chọn codebook tốt nhất theo mỗi variant và một final triple, hoặc `INCONCLUSIVE` |
| R8 | MEDIUM | §3–4 | File TC4 tổng từng có 42 records trùng dù chỉ 15 run IDs; 2 runs NON_CONVERGED | Luôn lấy 15 run IDs duy nhất từ per-run artifacts, tái tính aggregate; giữ convergence flags |
| R9 | MEDIUM | §5.5, §8 | Chọn bằng class similarity làm mất tính thuần unsupervised; đánh giá trên data đã fit codebook không là generalization | Default `use_for_shortlist=false`, `use_for_final=false`; ghi class analysis chỉ descriptive, không tuyên bố predictive generalization |

## B. Mục tiêu ra quyết định

- **Đơn vị intrinsic**: một codebook `c=(K,seed)`; 15 codebooks B0.
- **Đơn vị transaction/mining**: `u=(K,seed,variant)`; 60 databases.
- **Đầu ra chính**: `selected=(B0,K*,seed*,variant*)` **hoặc** `INCONCLUSIVE` nếu không có bằng chứng công bằng. Báo **các ứng viên mạnh nhất riêng cho S0/S1/S3/S6-B**, không khẳng định một K luôn tốt cho mọi encoding.
- **Điều kiện so sánh công bằng**: cùng 70.000 TIDs và minsup tuyệt đối, cùng Eclat/runtime limit, cùng quy tắc sampling/annotation. So variants **paired theo `(K,seed)`**; không so item ID thô giữa các codebooks.

## C. Tiêu chí và vai trò (không gộp thành điểm weighted tùy ý)

### C0. Validity & provenance — HARD GATE

Yêu cầu: source integrity PASS, schema/IDs/centroids hợp lệ, 70.000 TIDs, provenance/lineage khớp, tương ứng variant và support denominator=70.000; codebook metrics truy vết được. **Loại** nếu invalid. `NON_CONVERGED` chỉ **WARN** khi centroids và artifacts vẫn hợp lệ.

### C1. Intrinsic codebook — DIAGNOSTIC/SECONDARY

| Metric | Cách dùng | Không được suy diễn |
|---|---|---|
| Distortion, improvement khi tăng K | Đánh giá độ cô đọng và lợi ích giảm dần | K cao distortion thấp là tối ưu FIM |
| Occupancy và size (entropy, top cluster share, min/P5/median/max) | Nhận diện suy biến/chiếm ưu thế | Cụm đều là tốt nhất |
| ARI trên fixed descriptors / pairwise seed ARI | Stability theo K | ARI thấp = codebook không hợp lệ |
| Distortion spread, convergence/iterations | Reliability giữa seeds, cảnh báo `NON_CONVERGED` | Không hội tụ = transactions vô dụng |
| Centroid gallery, nearest real patches | Mức khác biệt và ý nghĩa thị giác | Nhãn lớp suy ra từ centroid nếu chưa kiểm tra ảnh |

**Không loại codebook từ nhóm C1 trừ lỗi validity.** Nếu distortion/ARI metrics thiếu provenance thì đánh `UNVERIFIED`, không chèn 0.

### C2. Transaction usability — PRIMARY SCREENING EVIDENCE (theo variant)

| Metric | Bằng chứng mong muốn | Cảnh báo |
|---|---|---|
| Length distribution, `empty_rate`, `P5/P50/P95`, `length=1` | Không suy biến thành toàn `[]` hoặc gần như một signature chung | S6-B là relation items, không so lengths với S0 theo độ lớn |
| Item support ECDF, share đạt minsup chung | Có repeated items đủ khai thác tại các ngưỡng đáng quan tâm | Ubiquitous gần 100% hoặc phần lớn cực hiếm không tự động invalid |
| Unique transactions, Jaccard distribution | Các ảnh không đồng nhất hoàn toàn, vẫn có patterns chia sẻ | “unique cao nhất” không tự động tốt nhất |
| Spatial: region/stripe support, S6-B relation prevalence/witness | Có tín hiệu không gian gắn đúng mapping, witness | Vùng 9/12/12/16 và 14/21/14 có cơ hội khác nhau |
| Across-seed distribution/range (cùng K, variant) | Bằng chứng ổn định ở các seeds | Không compare IDs thô giữa seeds |

### C3. Mining utility — PRIMARY DECISION EVIDENCE

- **Common bounded pilot C1**: cùng `minsup=0.03` và `maxlen=2` cho đủ 60. Phân biệt `COMPLETED_LENGTH_CAPPED` (đầy đủ đến 2) với `TIMEOUT/ITEMSET_LIMIT` (censored); không quy số itemsets partial thành 0.
- **Deep C3** trên shortlist: thử `minsup ∈ {0.01,0.03,0.05,0.10}` giống nhau cho 4 variants. Báo frequent singletons, pairs, ≥3 khi mine đầy đủ; support distributions; closed/maximal **chỉ khi exact**; sensitivity; median runtime/peak RSS.
- **Nontriviality cần có rubric đo được:**
  - `verified_support`: support count được cross-check bằng TID intersection/scan;
  - `nonredundant`: không là tautology do encoding hay duplicate pattern theo định nghĩa đã công bố; S6-B relational item tự thân biểu diễn một quan hệ, **không yêu cầu ít nhất 2 items** mới gọi là informative;
  - `witness_valid`: có image/patch instances tương ứng (bắt buộc với spatial relations);
  - `visual_coherence`: ví dụ ảnh/patch hỗ trợ mô tả nhất quán, dùng thang 0–2 bên dưới;
  - `coverage_across_minsup`: có bằng chứng mẫu hữu ích trên hơn một ngưỡng được khảo sát, hoặc có lý do cho trường hợp chỉ xuất hiện ở ngưỡng thấp.
- Không xếp hạng bằng `#itemsets` trực tiếp giữa variants; số items và semantics khác nhau; có thể thêm **lift/excess cooccurrence** để phân biệt cặp phổ biến chỉ do singleton phổ biến, nhưng cần kiểm soát rare-item bias và phụ thuộc logic.

### C4. Interpretability & spatial meaningfulness — PRIMARY QUALITATIVE EVIDENCE

Với pattern selection predeclared theo variant/minsup/length/support band, lưu `pattern_id, source, witnesses, support, image examples, visual_coherence, nonredundancy, reviewer, notes`.

**Visual coherence 0–2 (đề xuất rubric mới):**
- `0` — không giải mã/witness sai hoặc ví dụ minh họa không hỗ trợ diễn giải;
- `1` — một phần ví dụ ủng hộ họa tiết/quan hệ nhưng có tính mơ hồ hoặc không nhất quán;
- `2` — nhiều ảnh/patch đại diện xác nhận đặc trưng hoặc quan hệ một cách nhất quán, đủ bằng chứng hiển thị.

Tách `decodable` và `witness_valid` (boolean) khỏi `visual_coherence` (0–2). Không tuyên bố một điểm chủ quan là ground truth; nên có ≥2 người review hoặc lưu mức bất đồng. S6-B bổ sung **null shuffle** 20 repetitions như spec, báo observed-minus-null và limitations, không tự tuyên bố significance.

### C5. Cost & robustness — FEASIBILITY + TIE-BREAK

- Mọi completed pilots so performance phải chung engine/threads/hardware, tối thiểu 3 measured runs sau warmup; theo dõi median runtime, peak RSS, storage size khi đo được.
- **Feasibility**: người chạy chốt trước tài nguyên thực (ví dụ timeout/memory theo config), không tự chuyển đổi caps giữa các variants. `TIMEOUT`/`MEMORY_LIMIT` là trạng thái **chưa đánh giá đầy đủ**, không phải điểm chất lượng 0. Nếu cần lựa chọn phù hợp máy thật, ghi rõ lựa chọn chịu ràng buộc ngân sách tính toán.
- Nếu các ứng viên gần tương đương về mining usefulness và visual evidence, **ưu tiên** cấu hình ít tốn chi phí và ổn định hơn; K nhỏ/converged là tie-break có căn cứ, **không** phải điều kiện thắng cứng.

### C6. Post-hoc class similarity — DIAGNOSTIC ONLY (default)

Within-/between-class Jaccard, gap, pairwise AUC trên cùng 100.000 sampled pairs (nếu labels đầy đủ). Báo như kiểm tra cấu trúc lớp; mặc định không dùng shortlist/final selection. Nếu dùng, ghi **label-aware selection** và không báo kết luận lựa chọn hoàn toàn unsupervised. Không tuyên bố predictive generalization từ codebook đã fit trên tất cả ảnh.

## D. Quy trình ra quyết định cụ thể (khuyến nghị thay §6.3 + §8)

**D1 — Verify all.** Truy xuất unique 15 codebooks/60 databases, chặn các nguồn lỗi hoặc bị thiếu, tạo `eligibility.csv` có cờ/pass/fail và reason. Nếu không đủ nguồn, báo partial/inconclusive.

**D2 — Analyze without premature rejection.** Tính nhóm intrinsic C1 cho 15 codebooks, nhóm transaction C2 cho đủ 60 databases, và bounded Pilot Eclat (giai đoạn EDA2-C1) cho cả 60; ghi trạng thái từng trial. Các K có distortion cao hoặc ARI thấp vẫn phải thấy trong bảng so sánh nếu data hợp lệ.

**D3 — Select codebook shortlist.** Sau D2, chọn mục tiêu 6–9 codebooks `(K,seed)` có evidence tốt hoặc trade-off đáng nghiên cứu; mỗi codebook giữ cả 4 variants. **Bảo toàn mỗi K ít nhất một seed nếu hợp lệ**, có ≥2 seeds cho một số K trọng điểm để kiểm tra robustness. Đối với một variant không có frequent patterns tại C1=3%, đánh `NO_PATTERN_AT_SCREENING_THRESHOLD`, không mặc nhiên loại: quy tắc sensitivity chung có thể được predeclare nếu cần.

**D4 — Deep evidence.** EDA2-C3 đánh giá shortlist × 4 encodings × fixed minsup grid. Khi tài nguyên cho phép, giữ 1–2 *challenger codebooks* bị loại ở ranh giới shortlist (chọn trước khi xem deep results) để kiểm tra rủi ro shortlist bỏ sót ứng viên tốt. Chạy pattern sampling/gallery, S6-B null control. Bảo lưu uncertainty/censoring; để các configs chưa mine hết là `INCONCLUSIVE_FOR_MINING_RANK`.

**D5 — Pick per-variant candidates first.** Đối với mỗi variant, so codebooks trong cùng variant bằng: (i) mining có valid/witnessed nonredundant patterns và support đủ lặp; (ii) sensitivity minsup; (iii) seed/K robustness; (iv) runtime/memory. Báo 1–3 ứng viên và rejected/runner-up theo từng variant. Không cần cùng K thắng cho 4 variants.

**D6 — Paired cross-variant comparison.** So S0/S1/S3/S6-B tại các `(K,seed)` giống nhau, rồi mới so các per-variant winners đã qua deep pilot. Dùng bảng Pareto trên metrics có cùng ý nghĩa, và thuyết minh riêng về novel spatial information mà S0 không có; không dùng raw number of itemsets như mục tiêu chung.

**D7 — Final rule.** Ưu tiên một `final=(K,seed,variant)` nếu:
1. `VALID` và lineage chính xác;
2. Có **đầy đủ chứng cứ pilot ở các ngưỡng quyết định**, không bị censored ở metrics đem dùng để xếp hạng;
3. Tạo các patterns **có support được kiểm chứng, không tầm thường và minh họa/witness hợp lệ**, xét cả redundancy/null khi áp dụng;
4. Khả năng khai thác khả thi với ngân sách đã ghi, hoặc lý giải rõ ràng về ràng buộc tài nguyên;
5. Được ưu tiên hơn các ứng viên còn lại qua trade-off nêu tường minh; nếu gần tương đương, dùng stability/chi phí/parsimony làm tie-break.

Nếu mâu thuẫn chứng cứ, không có finalist hợp lệ, hoặc không thể so sánh công bằng: **`INCONCLUSIVE` + shortlist và next experiments**, không tự phát minh một winner. Ngay cả khi có winner, diễn giải chính xác là **tốt nhất trong các cấu hình và protocol đã đánh giá đủ**, không phải tối ưu toàn cục hay bảo đảm tổng quát hóa ra dữ liệu ngoài Fashion-MNIST 70k.

## E. Minimal acceptance outputs cho selection

- `codebook_metrics_15.csv`: đúng 15 distinct `(K,seed)`, convergence flags, provenance; metrics theo K/seed.
- `transaction_metrics_60.csv`: 60 rows/datasets, 70k records mỗi bộ.
- `pilot_common_60.csv`: 60 statuses; counts không bị đánh đồng với censored.
- `shortlist_decision.csv`: per `(K,seed)`, reason codes, flags, metrics, bốn variants kept; count và K coverage.
- `pilot_deep_runs.csv`: support, minsup grid, status, runtime/memory, exactness.
- `pattern_interpretability.csv`: bài kiểm tra định nghĩa, witness, rubric 0–2, source references.
- `per_variant_finalists.csv` (đề xuất thêm): top candidates trong mỗi S0/S1/S3/S6-B, lựa chọn/alternatives, lý do.
- `final/comparative_summary.csv` + `final_selection.md`: final triple hoặc inconclusive, source paths/checksums, tradeoffs và label policy.

## F. Chỉnh spec/checklist khi chấp nhận protocol

- **Spec §6.3:** thêm mục tiêu quan sát 60 và shortlist 6–9 với bảng reason codes, quy tắc censoring, sensitivity của variant thưa, bảo toàn K/seed.
- **Spec §7.2:** thêm anchored rubric `visual_coherence=0,1,2` + sampling/reviewer rules.
- **Spec §8:** chèn D5–D7; tạo `per_variant_finalists.csv` và ngưỡng ra quyết định dựa trên evidence, không score tùy ý.
- **Spec §10:** bổ sung schema của `per_variant_finalists.csv` và trạng thái `INCONCLUSIVE_FOR_MINING_RANK` khi pilot bị censored.
- **Checklist:** cập nhật nhiệm vụ C2, D, E, acceptance và các unit tests cho rubric/censoring/paired-comparison.

## G. Ghi chú từ TC4 artifacts đang có (chỉ là intrinsic evidence)

`tc4_metrics_summary.csv` có 42 rows nhưng chỉ 15 distinct run IDs. Hai runs được ghi `NON_CONVERGED`: K=128 seed=42; K=256 seed=123; phải flag, không tự loại. Sau dedup, mean distortion theo K lần lượt ≈ 0.4451, 0.3457, 0.2715, 0.2183, 0.1771; mean ARI theo K ≈ 0.8914, 0.8125, 0.7417, 0.6996, 0.6380. **Không có dữ liệu EDA2 transactions/mining tại đây để quyết định K/seed cuối cùng.**
