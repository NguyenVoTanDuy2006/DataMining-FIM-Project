# CHECKLIST — EDA2: Codebook, Transaction Quality & Pilot Eclat

**Version:** 1.1 — 2026-11-18  
**Dùng để giao:** Coding agent triển khai và chạy notebooks Julia cho EDA2.  
**Nguồn yêu cầu chuẩn:** `EDA2_FashionMNIST_Transaction_Evaluation_Spec_v1_1.md` (v1.1).  
**Hợp đồng nguồn:** `TC_Transaction_Construction_Spec_v2.md` (TC baseline rev 2.1), `TC6_Spatial_Encoding_Extension_Spec_v1.md` (v1.0).  
**Nguyên tắc:** Checklist chuyển *spec* thành tác vụ có thể kiểm chứng; khi có mâu thuẫn, **ưu tiên spec EDA2 v1.1**, ghi rõ blocker, không tự đổi phương pháp nghiên cứu.

> **Phạm vi:** Đọc **15 codebooks B0** và **45 transaction databases** (`K ∈ {16,32,64,128,256}`, `seed ∈ {42,123,2026}`, `variant ∈ {S0,S1,S3}`), mỗi database **70.000 TIDs kể cả rỗng**. Chạy EDA2-00 → A → B (bao gồm B5 hậu nghiệm theo lớp) → C1 → C2 → C3 → D → E. **Không chỉnh sửa TC, không fit lại TC4, không xây dựng lại TC6, không chạy FIM production.**

## 0. Scope, kế hoạch thực thi & các điều kiện dừng

- [x] **SC01 — Một notebook điều phối:** triển khai `EDA2_FashionMNIST_Transaction_Evaluation.ipynb` cho EDA2-00/A/B rồi C/D/E; dùng module `src/eda2/…` để tách logic khỏi notebook và giữ các phase dễ theo dõi.
- [x] **SC02 — Chỉ đọc nguồn TC:** mọi source files (codebooks, S0, spatial transactions, assignments, metadata) là read-only; output EDA2 nằm ở root riêng; lưu hash nguồn để chứng minh không bị thay đổi.
- [x] **SC03 — Ma trận đầy đủ:** 15 distinct `(B0,K,seed)` và 45 distinct `(B0,K,seed,variant)`; mọi database chính thức có 70.000 transactions.
- [x] **SC04 — Không được tự rút phạm vi:** EDA2-A cho 15 codebooks và EDA2-B/C1 cho 45 databases; chỉ C3 và D được chạy sâu trên shortlist minh bạch. Nếu thiếu nguồn, ghi `BLOCKED`/partial, **không** báo cáo full scope completed.
- [ ] **SC05 — Không nhập nhằng selection:** chỉ chọn `(K,seed,variant)` sau A/B/C/D; nếu không đủ chứng cứ thì công bố `INCONCLUSIVE` cùng shortlist và limitations.
- [x] **SC06 — Không ngoài scope:** không S2, Q20, đổi patch/filter/threshold, rerun K-means, tạo/rewrite transactions, mined association rules hoặc final production Eclat.
- [x] **SC07 — Tách tính hợp lệ khỏi chất lượng:** `NON_CONVERGED` hoặc ARI thấp là cảnh báo, không tương đương source invalid; timeout Eclat là censored run, không phải 0 itemsets.
- [ ] **SC08 — Traceability:** mỗi task/giai đoạn tạo artifact, status/log và reason codes; thiếu metric phải có `missing_reason`, không tự điền số 0 hoặc giá trị giả.

## 1. Setup — Environment, config, notebooks

- [x] **SET01 — Khảo sát repository:** xác định Julia Project/Manifest, reader `.bin` (Clustering.jl codebooks), CSV/TOML/JSONL, Eclat implementation, plotting, báo cáo, cơ chế checkpoints hiện có.
- [ ] **SET02 — Config EDA2:** tạo config TOML riêng theo §11 của spec (input roots, K/seeds/variants, minsup, sampling, budget, shortlist, B5, paths, flags). Không coi các keys gợi ý là đã được TC hỗ trợ sẵn.
- [x] **SET03 — Validate config:** fail sớm khi khác B0/5 K/3 seeds/3 variants hoặc có root đầu ra chồng root nguồn; không silently fallback sang phương pháp khác.
- [ ] **SET04 — Resource caps:** xác nhận timeout, giới hạn RAM và output capacity **theo máy thật** trước chạy C1/C3; log giới hạn có thực thi được hay chỉ monitoring.
- [ ] **SET05 — Metadata tái lập:** ghi Julia, packages, Eclat engine/version, hardware/threads, warming protocol, execution mode, timestamps, RNG seeds, config snapshot và code version.
- [ ] **SET06/07 — Unified notebook sections:** `00–11` discovery and structural analysis → `12` validation gate → `13` Eclat check → `14` common pilot → `15` human shortlist → `16–18` deep pilot and interpretation → `19–20` comparison and decision report.
- [ ] **SET08 — Mô tả code cells:** mỗi cell nêu ngắn gọn mục đích, inputs, outputs/checks; orchestration có thể chạy từng phase, không chạy mọi combinations trong một cell không resume được.
- [x] **SET09 — I/O an toàn:** stream/iterator JSONL, xử lý một database tại một thời điểm; không tải 45 databases vào RAM cùng lúc.
- [ ] **SET10 — Checkpoints/logs:** checkpoint theo phase/database/minsup/mode/repetition, chứa input/config hashes; resume chỉ khi hashes tương ứng; không tự skip task chưa `COMPLETED`.

## 2. EDA2-00 — Discovery, manifests & independent validation (spec §3)

- [x] **V001 — Discover 15 S0 sources:** đọc danh mục runs và metadata thật, không suy ra run từ thứ tự folder; `K=[16,32,64,128,256]`, seeds `[42,123,2026]`.
- [x] **V002 — Discover 30 spatial sources:** đủ S1/S3 theo từng `(K,seed)`, đúng lineage về S0 tương ứng; không tạo spatial data nếu thiếu.
- [x] **V003 — Deduplicate metadata:** dùng canonical `(method,K,seed,variant)`/unique run ID; tổng hợp CSV/TOML từng từng chứa 42 records trùng → **không** đếm là 42 codebooks; không viết lại file nguồn.
- [x] **V004 — Manifest 45 rows:** `database_id,method,K,seed,variant,source_root,run_path,transactions_path,codebook_ref,item_mapping_ref,tid_mapping_path,integrity_path,config_path,source_digest,record_count,status`.
- [x] **V005 — Check status:** mỗi source phải `COMPLETED` và integrity `PASS` theo contract; `converged` được lưu **riêng**; có lỗi thì nêu đúng `(K,seed,variant)`/path.
- [x] **V006 — Đọc lại dữ liệu thật:** parse 70.000 JSONL records/database, `tid`, `image_id`, `items`; không bỏ `items=[]`, không chỉ dựa vào stored counts.
- [x] **V007 — Kiểm tra TIDs:** unique TIDs, `image_id` hợp lệ, mapping one-to-one, cùng 70.000 image population/mapping qua 45 databases; support denominator **70.000**.
- [x] **V008 — Kiểm tra transactions:** item list integer strictly sorted, deduplicated; valid range S0 `1..K`, S1 `1..4K`, S3 `1..3K`.
- [x] **V009 — Check codebook:** `K×16` centroids hữu hạn; đọc `.bin` theo reader/layout xác minh từ project, không đoán raw file layout; metadata K/seed/method/τ=29 nhất quán.
- [x] **V010 — Source lineage:** spatial `source_artifacts.toml`/snapshot trỏ đến đúng B0 `(K,seed)`; không trộn codebook của seed khác.
- [x] **V011 — S1/S3 projection:** decode item mappings và chứng minh tập word thu được từ S1/S3 **khớp S0 trên từng TID**, không chỉ sample; S1/S3 empty status khớp S0.
- [x] **V013 — Digests/read-only:** lưu hashes hay digest tương đương của source artifacts, config EDA2, source code và môi trường; checksum mismatch → `BLOCKED`, không auto-repair.
- [x] **V014 — Xuất validation:** `input_manifest.csv`, `validation_report.toml`, `input_issues.csv` (được phép rỗng), `environment.toml`; có schema read-back.
- [x] **V015 — Gate trước A/B/C:** chỉ phân tích valid sources; thiếu source thì chạy partial được ghi rõ nhưng không kết luận đủ 45 datasets hoặc full selection.

## 3. EDA2-A — Intrinsic Codebook Evaluation: 15 codebooks (spec §4)

- [x] **A01 — Extract per-run TC4:** đọc `tc4_metrics.toml`, checkpoint, `.bin`, `patch_assignments.csv` khi cần; provenance của định nghĩa distortion/tolerance.
- [x] **A02 — Dedup trước aggregate:** lập đúng 15 rows và **3 seeds duy nhất / K**; không aggregate trên 42 duplicated summary records; mean/std phải tính lại từ 3 runs độc lập.
- [x] **A03 — Distortion/inertia:** lưu metric đúng như backend báo; chỉ so khi cùng descriptor population/normalization/definition; không tự cố tính lại từ TC3 raw descriptors không sẵn.
- [x] **A04 — Elbow:** tính relative change giữa các K tăng dần, hình distortion-vs-K theo seed và mean; không tự gắn nhãn K tối ưu.
- [ ] **A05 — Occupancy:** tính `used/K`, số clusters rỗng/cụm nhỏ; tách `cluster_size` theo patches khỏi per-image item support ở B.
- [ ] **A06 — Cluster size statistics:** min/median/max, P5/P95 hoặc quantiles hiện có, top1/top5 share, normalized entropy; bổ sung từ assignments nếu artifact metrics thiếu.
- [x] **A07 — Variability by K:** mean/std/min/max distortion, occupancy và metrics phù hợp trên đúng 3 seeds; không ghép các K.
- [ ] **A08 — ARI:** chỉ dùng giữa seeds của **cùng K** trên fixed 10.000 descriptors với provenance xác thực; đọc 3 pairwise ARIs khi có; nếu chỉ mean mà thiếu evidence cohort thì `UNVERIFIED`.
- [ ] **A09 — No raw ID matching:** không dùng equality của word IDs giữa seeds làm stability; ARI label permutation invariant, test đảo nhãn cho ARI=1.
- [x] **A10 — Convergence flags:** lưu iterations/maxiter, `FITTED`/`NON_CONVERGED`/`DEGENERATE_WARNING`/`FAILED`, stop reason; record cảnh báo hai runs đã từng được báo chưa hội tụ nếu file vẫn xác nhận, không tự loại.
- [ ] **A11 — Centroid gallery:** reshape 16D → 4×4 theo column-major; figure centroid per `(K,seed)` và near-centroid **real patches** chỉ khi đủ provenance/reader pixel.
- [x] **A12 — Intrinsic screening:** chỉ loại mining khi file/artifact invalid, assignment/lineage lỗi; các metric xấu khác là `flags`, **không** shortlist seeds/K trước B.
- [x] **A13 — Xuất A:** `codebook_metrics_15.csv`, `codebook_metrics_by_k.csv`, `seed_stability_by_k.csv`, `codebook_flags.csv`, plots/gallery; kiểm tra đúng 15 rows, 5 nhóm K.

## 4. EDA2-B1 — Transaction Length, Density, Empty (spec §5.1)

- [x] **B101 — Full coverage:** chạy trên **45 databases**, giữ nguyên 70.000 TIDs/database.
- [x] **B102 — Length stats:** mean, std, median, min/max, P5/P25/P75/P95/P99, empty count/rate, nonempty count, proportion length=1.
- [x] **B103 — Vocabulary:** theoretical universe `K/4K/3K/2K²`, observed universe (count of appearing IDs), utilization ratio.
- [x] **B104 — Density:** tính `sum(length)/(70000 * theoretical_universe)`, observed-universe density riêng; không xếp hạng variants chỉ bằng density.
- [x] **B105 — Length capacity checks:** S0 `≤min(K,49)`, S1 `≤min(4K,49)`, S3 `≤min(3K,49)`; nếu vượt, báo validation error.
- [x] **B106 — Paired comparisons:** cùng `(K,seed,tid)` so S0/S1/S3 về length và empties.
- [x] **B107 — Figures:** histogram/ECDF/boxplot lengths, empty-rate comparison, table by K×variant×seed.

## 5. EDA2-B2 — Item Support Distribution (spec §5.2)

- [x] **B201 — Image-level support:** `n_j=#TIDs chứa j`; `support_j=n_j/70000` (không dùng patches count hay nonempty count).
- [x] **B202 — Observed vs unseen IDs:** stats min/median/mean/P5/P95/max cho **observed IDs**; theoretical-but-unused IDs báo riêng, không trộn zeros để bóp méo histogram.
- [x] **B203 — Threshold grid:** same minsup fractions `[0.01,0.03,0.05,0.10]`, integer cutoff `ceil(70000×fraction)` và comparison `>=`; tính singleton counts và proportions theo observed/theoretical universe.
- [x] **B204 — Rare/ubiquitous:** dùng thresholds từ config (`rare_support_max`, `ubiquitous_support_min`); log chúng như descriptive flags, không tự loại codebook.
- [x] **B205 — Spatial supports:** S1 theo R1–R4 kèm slot capacities `9/12/12/16`; S3 TOP/MIDDLE/BOTTOM kèm `14/21/14`; không so raw region support mà không nhắc đến khác biệt slot capacities.
- [x] **B207 — Charts:** support histogram/ECDF/log-scale, #singletons by minsup, support-per-region/relation type.
- [x] **B208 — Xuất B2:** `item_support_summary_45.csv`, item-level support files theo database (CSV/Parquet/JLD2 tùy dữ liệu), region/relation tables.

## 6. EDA2-B3/B4 — Diversity & Encoding Invariants (spec §5.3–5.4)

- [ ] **B301 — Uniqueness:** `unique_transaction_count`, unique/duplicate ratio, multiplicity distribution và repeated transactions được decode trước diễn giải.
- [x] **B302 — Jaccard pairs:** tạo deterministic **20.000 unordered distinct TID pairs** (giá trị đề xuất qua config) bằng một seed cố định, dùng y hệt cho 45 databases; lưu pair manifest/hash.
- [x] **B303 — Jaccard convention:** `J(∅,∅)=1`, `J(∅,nonempty)=0`; report both-empty shares riêng, không bỏ empty records khỏi population.
- [x] **B304 — Pair statistics:** mean/median/P5/P95, sampled pair counts, empty-pair rates; không so raw item ID xuyên variants/seeds.
- [ ] **B305 — Paired/seed comparisons:** so distributions cùng `(K,seed)` giữa variants và aggregate theo `(K,variant)` qua 3 seeds; không coi 3,15 triệu TIDs là 3,15 triệu ảnh độc lập.
- [x] **B306 — S1/S3 invariants:** đã PASS 100% TIDs về projection/empty status; tích hợp kết quả sanity vào report B4.
- [x] **B308 — Xuất B3/B4:** `transaction_diversity_45.csv`, B flags, Jaccard plots, validation summaries.

## 7. EDA2-B5 — Class-Conditional Similarity (BẮT BUỘC post-hoc, spec §5.5)

- [x] **B501 — Nhãn có provenance:** load `image_id → class_label` từ metadata hợp lệ; join bằng TID/image mapping, **không** dựa file order. Check 70.000 mappings, 10 class IDs, consistency across 45 databases.
- [ ] **B502 — B5 missing label policy:** nếu missing/inconsistent: `CLASS_LABELS_BLOCKED`, log nguồn và coverage; các B1–B4/C không dùng nhãn vẫn tiếp tục nếu valid; không tự suy đoán labels.
- [x] **B503 — Cặp within:** target 50.000 unique unordered pairs, cân bằng 5.000 cặp/lớp cho 10 lớp, no self-pairs, sample không hoàn lại.
- [x] **B504 — Cặp between:** target 50.000 unique unordered pairs, phân tầng đều trên **45 cặp lớp**, mỗi nhóm ~1.111–1.112; no duplicates, lưu actual counts nếu quota không thể đạt.
- [x] **B505 — Reuse pair manifest:** fixed `class_pair_sampling_seed=2026`; duy nhất **một manifest within/between** cho toàn bộ 45 datasets; không thay cặp theo variant/K/seed.
- [x] **B506 — Empty-pair handling:** tính J theo B3; **both-empty pairs** vẫn được log `J=1` nhưng loại khỏi aggregate chính B5, báo tỷ lệ both-empty/one-empty từng nhóm.
- [x] **B507 — Within distribution:** mean, median, P5/P25/P75/P95 và valid-pair count; làm tương tự giữa lớp (between).
- [x] **B508 — Separation gap:** `within_mean − between_mean` theo tập pairs hợp lệ, report status khi không thể tính.
- [x] **B509 — Pairwise AUC:** tính `P(J_within>J_between)+0.5*P(tie)`; khi thiếu một nhóm thì `UNDEFINED`, không gán 0.
- [x] **B510 — Classwise breakdown:** 10 within-class rows/database và 45 unordered between-class rows/database, mean/median/quantiles, valid pairs, empty counts; heatmap 10×10 được gắn nhãn *similarity*, không gọi confusion matrix.
- [ ] **B511 — Pooled vs macro:** báo pooled estimates song song macro-by-class và macro-by-class-pair; so 45 databases bằng paired design, không dùng raw word IDs xuyên codebooks.
- [ ] **B512 — Statistical caution:** 100k pairs dùng lại image IDs → không xem là 100k quan sát độc lập; nếu CI dùng bootstrap image-level phù hợp; nếu không thì chỉ mô tả.
- [x] **B513 — Unsupervised boundary:** labels chỉ dùng đánh giá hậu nghiệm; `use_for_shortlist=false` mặc định; nếu dùng B5 để shortlist/tie-break phải ghi `label-aware selection`, không tự gọi là strict-unsupervised.
- [ ] **B514 — Xuất B5:** `class_similarity_summary_45.csv`, `classwise_similarity.csv`, `class_pair_similarity.csv`, `class_similarity_pair_manifest.csv`, distribution plots, heatmaps, K×variant comparisons.
- [x] **B515 — Acceptance B5:** summary đúng 45 distinct databases **nếu labels valid**; pair manifest cố định, AUC tie handling, empty-pair policy, counts/quota đều có bằng chứng.

## 8. EDA2-C0/C1 — Eclat adapter & common bounded pilot (spec §6.1–6.2)

- [x] **C001 — Reuse Eclat:** xác định Eclat engine/adapter hiện có trong repo, xác minh đúng semantics support và output; không tự thay Apriori/FP-Growth.
- [x] **C002 — Toy tests:** chạy toy datasets 5–10 transactions gồm empty, đối chiếu singleton/pair support và frequent itemsets với kết quả thủ công; support denominator đúng tổng TIDs.
- [x] **C003 — Min support conversion:** `minsup_count=ceil(minsup_fraction * 70000)`, frequent iff support_count `>=` cutoff; engine xử lý từng database độc lập, không dùng labels.
- [x] **C004 — Fixed C1 protocol:** common `minsup=0.03` (`count=2100`), `max_itemset_length=2`, **cùng** limits/engine/conditions cho 45 runs; config cố định *trước* khi xem kết quả.
- [x] **C005 — Resource enforcement:** timeout/RAM/output caps có cơ chế giám sát/dừng an toàn; log nếu giới hạn không enforce được. `max_reported_itemsets` không đồng nghĩa giới hạn search.
- [ ] **C006 — Ghi metrics C1:** frequent 1-/2-itemset counts **khi hoàn chỉnh**, support distribution cho completed family, runtime, peak RSS nếu đo được, active singleton count, completed length, throughput, status.
- [ ] **C007 — Status enum:** `COMPLETED`, `COMPLETED_LENGTH_CAPPED`, `TIMEOUT`, `MEMORY_LIMIT`, `ITEMSET_LIMIT`, `FAILED`, `SKIPPED_BLOCKED`; count censored không bị xử lý như exact hoặc zero.
- [x] **C009 — C1 coverage:** đủ 45 result/status rows (hoặc blockers minh bạch), không chặn các runs khác chỉ vì một cấu hình vượt tài nguyên theo policy.
- [x] **C010 — Xuất C1:** `pilot_common_45.csv`, validation/logs, reason codes và per-run checkpoint; read-back metrics.

## 9. EDA2-C2 — Shortlist selection (spec §6.3)

- [x] **C201 — Timing:** shortlist chỉ sau khi A/B/C1 có đủ bằng chứng hợp lệ; không shortlist chỉ từ raw distortion.
- [x] **C202 — Unit chọn:** chọn **`(K,seed)`** chứ không chọn độc lập `(K,seed,variant)`; giữ đủ 3 variants khi đưa cặp vào C3.
- [x] **C203 — Criteria predeclared:** validity, degeneration flags, support/length/diversity, mining evidence + censored flags, seed stability, cost, K coverage; công khai criteria/reason codes.
- [x] **C204 — Quy mô đề xuất:** target 6–9 codebooks (→ 18–27 databases), trừ khi dữ liệu/khả thi chứng minh cần khác; không hardcode shortlist size như DoD.
- [ ] **C205 — K coverage:** cố giữ ít nhất một `(K,seed)` hợp lệ cho mỗi K, nếu không được thì ghi exception; giữ ≥2 seeds ở một số K nếu khả thi để so stability.
- [x] **C206 — Không dùng B5 mặc định:** class similarity chỉ diagnostic, không xếp hạng shortlist trừ khi được khai báo công khai là label-aware.
- [x] **C207 — Xuất C2:** `shortlist_decision.csv` (selected/reason codes/metrics/invalid flags/protocol version), đủ 15 decision rows, không silently drop.

## 10. EDA2-C3 — Deep pilot, sensitivity, performance (spec §6.4)

- [ ] **C301 — Deep grid:** dùng `minsup=[0.01,0.03,0.05,0.10]` (700/2100/3500/7000), cùng settings trên mọi shortlisted variant; tùy chọn `0.005` chỉ khi đã khai báo sensitivity công bằng và resource-aware.
- [ ] **C302 — Mining completeness:** lưu per-run/minsup/mode status, output reference; itemset counts by length, max mined length, supports và top itemsets **chỉ khi status đủ điều kiện**.
- [ ] **C303 — Closed/maximal exactness:** chỉ tuyên bố exact khi full family đã được khai thác hoặc backend có exact closed/maximal mining; nếu capped/timeout thì `closed_maximal_status=NOT_EXACT`.
- [ ] **C304 — Performance protocol:** ít nhất 1 warm-up + 3 measured repetitions cho cấu hình dùng so performance, cùng engine/environment/threads; report median, dispersion và P95 khi phù hợp.
- [ ] **C305 — Runtime/memory:** runtime, measured peak RSS/allocations nếu có, limits/enforcement state, status và censored reasons; không xem timeout là chất lượng mining thấp.
- [ ] **C306 — Nontriviality:** chọn itemsets ở nhiều support bands/lengths, chú thích novelty, redundancy, interpretability, witness availability theo rubric định sẵn.
- [ ] **C307 — Sensitivity:** vẽ itemset counts/length, support shapes, runtime/memory và rank changes theo minsup; không coi nhiều itemsets hơn là thắng tự động.
- [ ] **C308 — Seed stability:** so summary distributions qua seeds cùng K; chỉ so matching semantic patterns nếu thực sự ghép cluster labels có chứng cứ.
- [ ] **C309 — Correctness checks:** toy Eclat, anti-monotonicity với cùng mining mode hoàn chỉnh, scan/intersection TID support đối chứng; skip inconclusive claims nếu censored.
- [ ] **C310 — Xuất C3:** `pilot_deep_runs.csv`, `pilot_itemset_counts.csv`, `pilot_eclat/itemsets/…`, `performance_summary.csv`, `pilot_validation_report.toml`, plots/logs/checkpoints.

## 11. EDA2-D — Interpretability (spec §7)

- [ ] **D001 — Pattern sampling:** chốt trước rule lấy representative itemsets theo variant, K, lengths, support bands; không chỉ chọn top support; ghi `pattern_selection_manifest.csv`.
- [ ] **D002 — Decode/trace:** với mỗi pattern lưu database/minsup, item IDs → semantic mapping, support_count/fraction, TID examples, image/patch coordinates, source references.
- [ ] **D003 — Centroids & real patches:** visualize 4×4 centroids reshape đúng, near-centroid **real** patches và representative images khi có source dữ liệu xác thực.
- [ ] **D004 — Spatial overlays:** S1 R1–R4 (9/12/12/16), S3 TOP/MIDDLE/BOTTOM (14/21/14); show matched patch positions và controls.
- [ ] **D006 — Rubric:** `decodable,visual_coherence,nontriviality,redundancy,annotator_notes`; ghi ai đánh giá và cách giải quyết khác biệt khi có subjective labels.
- [ ] **D007 — Labels post-hoc:** chỉ sau mining mới xem class distribution/enrichment mô tả cho pattern; không lọc candidates bằng labels trước mining; không tính support theo số ảnh từng lớp để thay support gốc.
- [ ] **D013 — Xuất D:** `pattern_gallery/`, `pattern_interpretability.csv`, plots và source links.

## 12. EDA2-E — Final comparison & decision (spec §8)

- [ ] **E001 — Gate dữ liệu:** tách invalid source khỏi normal candidates; incomplete/censored pilot được ghi hạn chế **không** tự coi là 0 quality.
- [ ] **E002 — Evidence tổng hợp:** intrinsic codebook, length/support/diversity, mining utility, performance, interpretability, seed robustness và **B5 post-hoc riêng**.
- [ ] **E003 — Fair paired comparison:** so variants trong cùng `(K,seed)` trước, sau đó xem K×variant qua ba seeds; không so raw IDs hay coi 45 databases là independent populations.
- [ ] **E004 — Trade-off/Pareto:** không đặt weighted score tùy ý; dùng bảng trade-off trên metrics cùng nghĩa, minh họa limitations/censoring.
- [ ] **E005 — B5 transparency:** ghi rõ class similarity có/không ảnh hưởng shortlist/final; nếu có thì công bố label-aware selection.
- [ ] **E006 — Chọn final khi đủ chứng cứ:** `(B0,K*,seed*,variant*)` và reference tới artifacts gốc, không sinh codebook/transaction mới; nếu thiếu chứng cứ, công bố `INCONCLUSIVE` + shortlist + next measurements.
- [ ] **E007 — Competitors:** nêu alternative configurations, vì sao không chọn, độ nhạy minsup, caveats về runtime/memory, stability và data constraints.
- [ ] **E008 — Xuất E:** `final/comparative_summary.csv`, `tradeoff_candidates.csv`, `final_selection.md`, `EDA2_summary_report.md`, paths/checksums/protocols.

## 13. Unit tests, smoke tests & full execution (spec §12)

- [ ] **T001 — Parser:** JSONL có `[]`, duplicate TID detection, invalid sort/range, full denominator 70k.
- [ ] **T002 — Spatial:** S1/S3 projection về S0 và tính nhất quán của transaction rỗng.
- [x] **T003 — Support toy:** 5–10 transactions, empty, multiple-item exact support, ceil(minsup×N), anti-monotonicity trên completed mining.
- [ ] **T004 — Jaccard toy:** identical, disjoint, empty–empty, empty–nonempty, deterministic pairs.
- [ ] **T005 — B5 sampling:** verify 10 within class groups, 45 between groups, no self/duplicate pairs, balanced quotas, same manifest across 45 datasets.
- [ ] **T006 — B5 metrics toy:** gap, AUC ties 0.5, both-empty excluded from primary aggregates, UNDEFINED when a pair group missing, TID→label join correctness.
- [ ] **T007 — Stability toy:** cluster label permutation yields ARI=1; 3 valid seeds/K, no contaminated duplicated summary records.
- [ ] **T009 — Resource test:** mock timeout/memory/itemset cap and verify censored counts never interpreted as completed results.
- [ ] **T010 — Smoke:** 1 codebook × S0/S1/S3 trên subset TIDs, **smoke output riêng**; smoke support không đại diện 70k và không được dùng để select.
- [x] **T011 — Full A/B:** validate đầy đủ 15 codebooks/45 databases, B5 cho 45 (hoặc `CLASS_LABELS_BLOCKED` rõ ràng), read-back artifacts.
- [x] **T012 — Full C1:** 45 bounded pilot statuses, lưu từng completed/censored reason; không bỏ sót runs.
- [ ] **T013 — Full C2/C3/D/E:** shortlist documented, deep/bench trên selected subset, pattern gallery, summary/decision hoàn tất hoặc `INCONCLUSIVE`.
- [ ] **T014 — Idempotency:** resume/re-run không nhân đôi CSV rows, không đổi RNG pair manifest hoặc source artifacts; kiểm tra hashes trước/sau nếu khả thi.

## 14. Output & nghiệm thu cuối cùng (DoD)

- [x] **DONE01 — Data audit:** có đúng 15 codebooks + 45 databases hợp lệ, mỗi bộ đủ 70k records; nếu thiếu phải báo `BLOCKED`/partial, không nói full done.
- [ ] **DONE02 — Intrinsic:** đủ các chỉ số TC4 theo spec cho 15, seed stability có provenance, centroid gallery, warnings convergence.
- [ ] **DONE03 — Structural EDA:** 45 bảng metrics về length, density, empty, item support, diversity và phân bố region/stripe; plots và digest.
- [ ] **DONE04 — Class-conditional B5:** toàn bộ 45 có within/between, gap, AUC, 10 classwise + 45 class-pair rows/database, one shared sampling manifest, empty policy; nếu labels blocked thì công khai incomplete.
- [ ] **DONE05 — Pilot:** C1 cho 45 databases; shortlist có căn cứ, deep minsup sensitivity, exact/NOT_EXACT closed/maximal flags, runtime/memory và status phù hợp.
- [ ] **DONE06 — Interpretation:** pattern galleries và overlays trên shortlist có thống kê, provenance và limitations.
- [ ] **DONE07 — Decision:** report trade-offs, finalists + alternatives; chosen `(K,seed,variant)` **hoặc** `INCONCLUSIVE`; báo rõ ảnh hưởng của B5 nếu có.
- [ ] **DONE08 — Reproducible outputs:** đủ manifests, configs, summaries, figures, logs/checkpoints, read-back, version/hashes; không mutate TC production.
- [ ] **DONE09 — Agent handoff:** cung cấp notebooks/modules mới hoặc sửa, lệnh chạy, thứ tự chạy, paths output, pass/fail tests, completed/blocked/censored counts và known limitations; không claim thực nghiệm đã chạy nếu chỉ mới viết code.

## 15. Bản đồ giữa checklist và spec

| Checklist | Nguồn spec | Đầu ra tiêu biểu |
|---|---|---|
| 0–1 | §0–2, §9, §11 | Config, environment, notebooks |
| 2 (V) | §3 | `input_manifest.csv`, validation report |
| 3 (A) | §4 | `codebook_metrics_15.csv`, `seed_stability_by_k.csv` |
| 4–6 (B1–B4) | §5.1–5.4 | `transaction_metrics_45.csv`, item support/diversity |
| 7 (B5) | §5.5 | `class_similarity_summary_45.csv` + pair/classwise |
| 8 (C1) | §6.1–6.2 | `pilot_common_45.csv` |
| 9 (C2) | §6.3 | `shortlist_decision.csv` |
| 10 (C3) | §6.4 | Deep pilot, itemsets, performance |
| 11 (D) | §7 | Gallery và overlays |
| 12 (E) | §8 | `final_selection.md`, `EDA2_summary_report.md` |
| 13–14 | §10, §12–13 | Tests, full run, DoD |

### Hướng dẫn ngắn để giao agent

> Đọc `EDA2_FashionMNIST_Transaction_Evaluation_Spec_v1_1.md` trước, triển khai theo checklist này. Làm đúng 00 → A → B (bao gồm B5) → C1 → C2 → C3 → D → E, có tests/checkpoints. Chỉ đọc nguồn TC, không tái huấn luyện hay viết lại transactions. Phân biệt VALIDITY / CONVERGENCE / CENSORED / MISSING. Báo rõ các task hoàn thành, blockers và paths của artifacts. Khi thiếu dữ liệu hoặc vượt resource limits, xuất kết quả partial có status minh bạch, **không tự thay luật nghiên cứu hoặc tuyên bố hoàn tất**.
