# Insight EDA-1 để chuẩn bị Transaction Construction

## 1. Báo cáo này dựa trên kết quả nào?

Báo cáo đọc **output mới đã có trong `results/fashion/eda1/question_driven/`**, không lấy số liệu từ thư mục EDA cũ và không chạy lại notebook.

- Toàn tập: **70.000 ảnh**, grayscale 28×28, 7.000 ảnh/lớp, giữ train/test nguồn để truy vết.
- Patch 4×4, stride 4: **49 patch/ảnh**, tổng 3.430.000 patch.
- Patch 7×7, stride 7: **16 patch/ảnh**, tổng 1.120.000 patch.
- Q10+ = **29**; Otsu toàn cục = **97**; foreground giả định là pixel `I > τ`.
- Alpha chung: **0; 0,0625; 0,125**. Mỗi size có sáu cấu hình lọc Q10+/Otsu và một baseline không lọc. τ=10 được tính bổ sung để đối chiếu cùng các mức alpha.
- SIFT/ORB, histogram hướng và descriptor diversity: **pilot 200 ảnh, 20 ảnh/lớp, seed 42**.
- Môi trường ghi trong metadata: Julia **1.13.3**, OpenCV.jl **4.11.0**, OpenCV **4.14.0**.

Notebook có kết quả thực thi đã lưu cho **79/79 code cell**, không có output lỗi ở phiên EDA trước khi bổ sung τ=10. τ=10 được tính riêng sau đó từ ảnh gốc và metrics gradient đã lưu. SHA-256 bảng patch metrics khớp metadata; bảng có số dòng khai báo 4.550.000. Điều này cho phép diễn giải kết quả của lần chạy đã lưu; không có nghĩa mọi giả thuyết về descriptor/transaction đã được kiểm chứng.

Nguồn: [metadata phiên chạy](../../results/fashion/eda1/question_driven/run_metadata.toml), [tổng quan dataset](../../results/fashion/eda1/question_driven/01_dataset_overview.csv), [hai ngưỡng gốc](../../results/fashion/eda1/question_driven/02_thresholds.csv), [so sánh τ=10](../../results/fashion/eda1/question_driven/q22_tau10_vs_q10_otsu.csv).

## 2. Những quyết định có thể đề xuất ngay cho TC

| Thành phần | Đề xuất từ bằng chứng EDA | Mức chắc chắn |
|---|---|---|
| TC1 — Kích thước patch | Dùng **4×4 làm ứng viên chính**, giữ **7×7 làm đối chứng**. 4×4 cho phép lọc nền cục bộ hơn; 7×7 có ngữ cảnh rộng hơn trong một vector. | Có bằng chứng về reduction/loss; chưa chứng minh kích thước tốt nhất sau codebook. |
| TC2 — Filtering | Ưu tiên thử **Q10+, α=0**, đối chiếu với no-filter; dùng α=0,0625 như mức mạnh hơn. | Q10+ α=0 giảm đáng kể patch, không mất pixel vượt ngưỡng và không tạo ảnh hết patch trong kết quả hiện tại. |
| TC3 — Descriptor | **Raw pixels/255** làm baseline; gradient/histogram hướng là ứng viên đối chứng. | Thống kê cho thấy có cấu trúc cạnh; chưa đo chất lượng cụm hay visual words. |
| TC3 — Strategy | **Dense patches** làm phương án chính; ORB/SIFT là thử nghiệm bổ sung. | Pilot có zero-feature images và coverage patch mục tiêu thấp ở cả hai extractor. |
| TC6 — Spatial | Standard BoVW làm baseline; ưu tiên thử thêm **top/middle/bottom**, giữ 2×2 như ứng viên khác. | Phân bố vùng khác nhau rõ theo lớp; hiệu quả với support và patterns chưa biết. |

Các đề xuất này là nhận định phân tích, không phải thay đổi đã áp dụng vào pipeline TC.

### Bổ sung theo yêu cầu: τ=10

τ=10 nằm dưới Q10+=29 và Otsu=97 nên xem nhiều pixel hơn là foreground. Kết quả trên toàn bộ 70.000 ảnh:

| Size, alpha | τ=10: reduction / EdgeLoss | Q10+: reduction / EdgeLoss | Otsu: reduction / EdgeLoss |
|---|---:|---:|---:|
| 4×4, α=0 | 36,43% / 3,78% | 37,50% / 4,41% | 43,30% / 8,90% |
| 4×4, α=0,0625 | 38,07% / 5,03% | 39,30% / 5,92% | 45,88% / 11,78% |
| 4×4, α=0,125 | 39,73% / 6,73% | 41,05% / 7,84% | 48,21% / 14,99% |
| 7×7, α=0 | 22,75% / 1,22% | 23,53% / 1,43% | 27,66% / 3,17% |
| 7×7, α=0,0625 | 26,20% / 2,57% | 27,25% / 3,02% | 33,06% / 6,40% |
| 7×7, α=0,125 | 29,70% / 4,85% | 30,91% / 5,55% | 38,14% / 10,91% |

Ở cùng size và α, τ=10 luôn giảm ít patch hơn và mất ít gradient hơn Q10+ hoặc Otsu. So với Q10+ α=0, τ=10 α=0 giảm ít hơn **1,07 điểm phần trăm** ở patch 4×4, nhưng EdgeLoss cũng thấp hơn **0,63 điểm**; với patch 7×7, reduction thấp hơn **0,78 điểm**, EdgeLoss thấp hơn **0,21 điểm**.

**Diễn giải:** τ=10 có thể là lựa chọn giữ lại nhiều vùng tối/gradient hơn, nhưng chỉ một phần nhỏ các patch bổ sung tạo ra khác biệt EdgeLoss so với Q10+. Đây là ứng viên “lọc nhẹ” để đối chứng, không phải bằng chứng rằng τ=10 là ngưỡng tối ưu. Không ảnh nào hết patch ở sáu cấu hình τ=10 trong bảng.

Nguồn: [τ=10, Q10+ và Otsu theo cấu hình](../../results/fashion/eda1/question_driven/q22_tau10_vs_q10_otsu.csv), [tác động theo lớp](../../results/fashion/eda1/question_driven/q22_tau10_class_impact.csv), [đồ thị reduction–loss 4×4](../../results/fashion/eda1/question_driven/q22_tau10_tradeoff_4x4.svg), [đồ thị reduction–loss 7×7](../../results/fashion/eda1/question_driven/q22_tau10_tradeoff_7x7.svg).

## 3. I1 — Patch Suitability

### Q1.1 — Patch biến thiên cường độ như thế nào?

**Trả lời:** Patch 4×4 phân tách được nhiều vùng đồng nhất hơn; patch 7×7 thường trộn nền và vật thể trong cùng cửa sổ nên variance lớn hơn.

| Chỉ số | Patch 4×4 | Patch 7×7 |
|---|---:|---:|
| Mean variance | 2.145,51 | 3.552,86 |
| Median variance | 237,28 | 2.501,30 |
| Patch đồng nhất tối, mean=0 | 30,73% | 17,72% |
| Patch đồng nhất nhưng mean>0 | 0,0183% | 0,00027% |
| Patch gần đồng nhất, 0<variance≤1 | 4,11% | 3,91% |
| Patch variance>1 | 65,14% | 78,37% |

Variance cao hơn của 7×7 không tự chứng minh nó giữ chi tiết tốt hơn: cửa sổ lớn có thể đi qua nhiều mức sáng hơn. Ngược lại, tỷ lệ patch tối cao của 4×4 cho thấy tập descriptor chưa lọc chứa nhiều vector nền lặp lại.

**Ý nghĩa cho TC:** Có cơ sở khảo sát lọc patch 4×4 và cách lấy mẫu descriptors trước K-means. Không loại mọi patch variance thấp: patch sáng đồng nhất vẫn có thể mang thông tin intensity.

Nguồn: [variance summary](../../results/fashion/eda1/question_driven/q11_variance_summary.csv), [nhóm đồng nhất](../../results/fashion/eda1/question_driven/q11_homogeneous_groups.csv), [histogram](../../results/fashion/eda1/question_driven/q11_variance_distribution.svg).

### Q1.2 — Patch có nắm bắt được cấu trúc cạnh không?

**Trả lời:** Cả hai kích thước đều có patch chứa biến thiên cạnh đáng kể; 4×4 tách biệt vùng ít cạnh và nhiều cạnh mạnh hơn, còn 7×7 gộp thông tin trong cửa sổ lớn hơn.

| Mean magnitude Sobel/pixel | Patch 4×4 | Patch 7×7 |
|---|---:|---:|
| Trung bình toàn bộ patch | 183,06 | 183,06 |
| P25 | 2,06 | 53,98 |
| Median | 132,77 | 190,52 |
| P95 | 497,79 | 403,78 |

Trung bình 183,06 bằng nhau là kết quả được kỳ vọng: hai cách chia dùng cùng bản đồ gradient và cùng đủ 784 pixel. Patch 7×7 có median lớn hơn nhưng P95 nhỏ hơn, phù hợp với việc gộp vùng nền và vùng có cạnh làm phân bố bớt cực đoan.

**Ý nghĩa cho TC:** 4×4 có khả năng cô lập chi tiết cục bộ; 7×7 chứa ngữ cảnh rộng hơn. Thống kê magnitude chưa xác nhận chi tiết nào quan trọng về ngữ nghĩa; cần đối chiếu [gallery cùng ảnh, hai cách cắt](../../results/fashion/eda1/question_driven/i1_representative_patch_comparison.svg) và kiểm chứng qua codebook/transactions.

Nguồn: [mean gradient](../../results/fashion/eda1/question_driven/q12_mean_gradient_summary.csv), [ví dụ patch và gradient](../../results/fashion/eda1/question_driven/q12_gradient_examples.svg).

### Q1.3 — Thông tin phân bố như thế nào trên ảnh?

**Trả lời:** Thông tin không phân bố đều; cũng không thể xem toàn bộ viền ảnh là nền cần loại.

Ở lưới patch 4×4, mean gradient/pixel trung bình của **vòng patch ngoài cùng** là **148,93**, còn phần trong là **215,83**. Tuy nhiên vị trí có mean gradient cao nhất toàn tập lại là patch **ID 5, hàng 1, cột 5**, giá trị **258,25**. Ở lưới patch 7×7, vị trí cao nhất là **ID 14, hàng 4, cột 2**, giá trị **241,87**.

Các số vòng ngoài/phần trong được tổng hợp từ bảng vị trí; hai vòng có bề dày pixel khác nhau giữa hai size, vì vậy không dùng chúng để xếp hạng kích thước.

**Ý nghĩa cho TC:** Không lọc bằng quy tắc cố định như “bỏ patch sát mép”. Dùng nội dung từng patch để lọc; giữ tọa độ phục vụ ứng viên spatial encoding.

Nguồn: [metrics vị trí](../../results/fashion/eda1/question_driven/q13_patch_position_metrics.csv), [heatmap gradient theo lớp](../../results/fashion/eda1/question_driven/q13_mean_gradient_maps.svg).

## 4. I2 — Background Filtering

### Q2.1 — Có bao nhiêu patch trống hoặc gần nền?

**Trả lời:** Lượng patch không chứa pixel vượt ngưỡng đủ lớn để đáng thử filtering.

| Tỷ lệ patch có FR=0 | Patch 4×4 | Patch 7×7 |
|---|---:|---:|
| Q10+, τ=29 | 37,50% | 23,53% |
| Otsu, τ=97 | 43,30% | 27,66% |

Otsu chọn τ cao hơn, nên nhiều patch được xem là trống hơn. “Trống” ở đây là **không có pixel I>τ**, không có nghĩa mọi pixel đều bằng 0 hoặc không có gradient.

**Ý nghĩa cho TC:** Có cơ sở lọc FR=0, đặc biệt với 4×4. Mức giảm FR giữa hai ngưỡng thể hiện thay đổi định nghĩa foreground, chưa chứng minh Otsu phân đoạn nền tốt hơn.

Nguồn: [empty/near-empty](../../results/fashion/eda1/question_driven/q21_empty_near_empty.csv), [phân phối FR](../../results/fashion/eda1/question_driven/q21_patch_fr_distribution.svg).

### Q2.2 — Mỗi cấu hình loại được bao nhiêu patch?

Alpha là tỷ lệ foreground tối đa mà patch vẫn bị loại: `F≤floor(alpha×area)`.

| Alpha | Patch 4×4 loại khi | Patch 7×7 loại khi |
|---:|---|---|
| 0 | F=0 | F=0 |
| 0,0625 | F≤1 | F≤3 |
| 0,125 | F≤2 | F≤6 |

Bảng sau kết hợp hiệu quả filtering và loss để đọc cùng nhau. Reduction và loss đều là phần trăm, không phải điểm số phân loại.

| Size | Ngưỡng | α | Reduction | EdgeLoss | Foreground loss | Ảnh hết patch |
|---|---|---:|---:|---:|---:|---:|
| 4×4 | No-filter | — | 0,00% | 0,00% | 0,00% | 0 |
| 4×4 | Q10+ | 0,0 | 37,50% | 4,41% | 0,00% | 0 |
| 4×4 | Q10+ | 0,0625 | 39,30% | 5,92% | 0,25% | 0 |
| 4×4 | Q10+ | 0,125 | 41,05% | 7,84% | 0,74% | 0 |
| 4×4 | Global Otsu | 0,0 | 43,30% | 8,90% | 0,00% | 0 |
| 4×4 | Global Otsu | 0,0625 | 45,88% | 11,78% | 0,45% | 0 |
| 4×4 | Global Otsu | 0,125 | 48,21% | 14,99% | 1,26% | 1 |
| 7×7 | No-filter | — | 0,00% | 0,00% | 0,00% | 0 |
| 7×7 | Q10+ | 0,0 | 23,53% | 1,43% | 0,00% | 0 |
| 7×7 | Q10+ | 0,0625 | 27,25% | 3,02% | 0,34% | 0 |
| 7×7 | Q10+ | 0,125 | 30,91% | 5,55% | 1,18% | 0 |
| 7×7 | Global Otsu | 0,0 | 27,66% | 3,17% | 0,00% | 0 |
| 7×7 | Global Otsu | 0,0625 | 33,06% | 6,40% | 0,59% | 35 |
| 7×7 | Global Otsu | 0,125 | 38,14% | 10,91% | 2,05% | 339 |

Ở Q10+, α=0, 4×4 còn trung bình **30,62 descriptor/ảnh**, 7×7 còn **12,23 descriptor/ảnh**. Trước lọc, tổng số scalar raw bằng nhau: **54.880.000**; sau cấu hình này còn lần lượt **34.299.936** và **41.964.629**.

**Ý nghĩa cho TC:** 4×4 tạo nhiều vector hơn nhưng ngắn hơn, đồng thời loại được nhiều pixel slots hơn. 7×7 tạo ít vector hơn nhưng mỗi vector 49 chiều thay vì 16. Không thể suy ra thời gian K-means chỉ từ số descriptor hoặc tổng scalar; cần đo ở TC.

Nguồn: [so sánh filtering](../../results/fashion/eda1/question_driven/q22_filter_comparison.csv), [phân phối số patch giữ](../../results/fashion/eda1/question_driven/q22_retained_distribution.csv).

### Q2.3 — Lọc có làm mất cạnh hoặc chi tiết nhỏ không?

**Trả lời:** Có mất tổng gradient, kể cả khi foreground loss bằng 0. Mức mất tăng khi α tăng, và Otsu tạo loss cao hơn Q10+ tại cùng size/alpha trong các cấu hình đã khảo sát.

Ví dụ Q10+, α=0:

- 4×4 loại **37,50%** patch, mất **4,41%** gradient, foreground loss **0%**.
- 7×7 loại **23,53%** patch, mất **1,43%** gradient, foreground loss **0%**.

Kết luận “7×7 giữ nhiều gradient hơn” đúng ở **cùng alpha** nhưng đi kèm mức giảm dữ liệu thấp hơn. Khi dùng sweep cutoff để so mức reduction gần nhau:

| Cấu hình Q10+ | Reduction | EdgeLoss |
|---|---:|---:|
| 4×4, loại F≤1 | 39,3002% | 5,9185% |
| 7×7, loại F≤13 | 39,3926% | 13,9969% |

Chênh reduction chỉ **0,0924 điểm phần trăm**, trong khi 4×4 mất ít hơn khoảng **8,08 điểm phần trăm** gradient. Cutoff 13 của 7×7 thuộc sweep bổ sung, không phải bộ ba alpha mặc định.

**Insight:** Ở mức reduction khoảng 39,3% trong phép đối chiếu Q10+ này, **4×4 bảo toàn tổng magnitude tốt hơn 7×7**. Điều này ủng hộ giả thuyết rằng ô nhỏ cho phép loại nền chọn lọc hơn. Chưa đủ để nói mọi chi tiết ngữ nghĩa được giữ tốt hơn hoặc 4×4 tối ưu ở mọi mức reduction.

Sobel được tính trên ảnh gốc, có thể phản ứng ở vùng tối và quanh ranh giới patch. Vì vậy EdgeLoss là proxy mất cấu trúc gradient; foreground loss=0 không đồng nghĩa EdgeLoss=0.

Nguồn: [cutoff sweep](../../results/fashion/eda1/question_driven/q23_all_integer_cutoffs.csv), [cặp reduction gần nhau](../../results/fashion/eda1/question_driven/q23_near_reduction_comparisons.csv), [đồ thị reduction–loss](../../results/fashion/eda1/question_driven/q23_cutoff_tradeoff.svg).

### Q2.4 — Filtering có ảnh hưởng không đồng đều giữa lớp?

**Trả lời:** Có; số patch loại và loss thay đổi theo lớp, một số cấu hình còn tạo ảnh không còn patch.

- Với **4×4, Q10+, α=0**, reduction của Pullover là **22,10%**, Sneaker là **54,83%**. EdgeLoss theo lớp nằm khoảng **3,29–5,31%**.
- Với **4×4, Otsu, α=0,125**, EdgeLoss của Trouser khoảng **8,00%**, Sandal khoảng **20,06%**.
- Với **7×7, Otsu, α=0,125**, có **339/70.000 ảnh** hết patch, tương đương **0,4843%**. Riêng Shirt là **141/7.000 ảnh**, khoảng **2,0143%**.
- **7×7, Otsu, α=0,0625** có **35 ảnh** hết patch; **4×4, Otsu, α=0,125** có **1 ảnh**. Các cấu hình Q10+ đang khảo sát không tạo ảnh hết patch.

**Ý nghĩa cho TC:** Không ưu tiên cấu hình chỉ vì reduction toàn tập cao. Otsu với α lớn cần đối chứng thận trọng. TC phải giữ truy vết image_id và quy định cách xử lý ảnh không còn descriptor, không âm thầm xóa ảnh khỏi mẫu số support.

Nguồn: [class impact](../../results/fashion/eda1/question_driven/q24_class_filter_impact.csv), [độ chênh giữa lớp](../../results/fashion/eda1/question_driven/q24_class_spreads.csv).

## 5. I3 — Feature Informativeness

### Q3.1 — Intensity hay gradient đang thể hiện thông tin gì?

**Trả lời:** Variance intensity cao thường đi kèm gradient cao theo các nhóm quartile đã khảo sát; hai đại lượng có liên hệ nhưng chưa chứng minh descriptor tương đương.

- 4×4: nhóm variance thấp/gradient thấp chiếm **23,93%**; cao/cao chiếm **21,99%**.
- 7×7: các nhóm tương ứng chiếm **22,94%** và **17,04%**.
- Nhóm **variance>p75 và mean gradient≤p25 có 0 patch** ở cả hai size. Kết quả này phụ thuộc đúng tiêu chí quartile của từng size, không phải phát biểu cho mọi cách chia nhóm.

Raw intensity giữ mức sáng tuyệt đối; gradient mô tả thay đổi cường độ và hướng cạnh. Patch đồng nhất sáng có thể khác patch đồng nhất tối trong raw descriptor, trong khi gradient đều thấp; vì vậy không coi gradient là thay thế hoàn toàn raw chỉ từ tương quan.

**Ý nghĩa cho TC:** Dùng raw/255 làm baseline dễ giải thích; thử gradient như đối chứng. Chất lượng visual words phải đánh giá sau khi huấn luyện codebook.

Nguồn: [tiêu chí và số lượng nhóm](../../results/fashion/eda1/question_driven/q31_patch_group_criteria.csv), [scatter](../../results/fashion/eda1/question_driven/q31_variance_gradient.svg).

### Q3.2 — Có cơ sở thử HOG không?

**Trả lời:** Có cơ sở thử histogram hướng, đặc biệt với 7×7; chưa thể kết luận HOG sẽ tốt hơn raw.

| Chỉ số trên pilot | Patch 4×4 | Patch 7×7 |
|---|---:|---:|
| Số patch | 9.800 | 3.200 |
| Mean gradient≥80 | 59,03% | 70,72% |
| Gradient bằng 0 | 20,91% | 14,28% |
| Mean entropy của hướng trên nhóm có cạnh, bit | 1,4381 | 1,8245 |
| Mean cosine khi dịch cửa sổ 1 pixel | 0,9315 | 0,9751 |

Histogram của 7×7 có hướng đa dạng hơn theo entropy và ít thay đổi hơn khi dịch một pixel trong pilot. Tuy nhiên, cửa sổ lớn chứa nhiều pixel hơn và có tỷ lệ overlap sau dịch lớn hơn: **6/7 so với 3/4** theo chiều dịch. Đây là yếu tố hình học cần tính đến khi diễn giải độ ổn định.

**Ý nghĩa cho TC:** Histogram hướng 8 bin đáng thử, nhưng patch 4×4 chỉ có 16 pixel nên cần thiết kế bin/cell/normalization phù hợp. Kết quả hiện tại dùng histogram unsigned magnitude-weighted, chưa phải một cấu hình HOG hoàn chỉnh có block normalization.

Nguồn: [orientation summary](../../results/fashion/eda1/question_driven/q32_orientation_summary.csv), [shift stability](../../results/fashion/eda1/question_driven/q32_shift_stability.csv), [ví dụ hướng](../../results/fashion/eda1/question_driven/q32_orientation_examples.svg).

### Q3.3 — Descriptor có dư thừa không?

**Trả lời:** Có nhiều vector raw trùng trước lọc; trên pilot, sự trùng chính xác gần như biến mất sau khi loại patch FR=0.

| Chỉ số | Patch 4×4 | Patch 7×7 |
|---|---:|---:|
| Descriptor trước lọc | 9.800 | 3.200 |
| Vector raw khác nhau chính xác | 6.610 | 2.602 |
| Tỷ lệ bản lặp ngoài vector đầu tiên | 32,55% | 18,69% |
| Descriptor sau Q10+, α=0 | 6.127 | 2.419 |
| Vector khác nhau sau Q10+, α=0 | 6.125 | 2.419 |
| Median RMS đến tham chiếu gần nhất trước lọc | 0,0410 | 0,1022 |

Đây là dấu hiệu rằng patch nền/đồng nhất đóng góp lớn vào sự trùng raw descriptor trên pilot. Không trùng chính xác không đồng nghĩa descriptor hữu ích hoặc không gần nhau.

Cả hai size dùng 1.024 tham chiếu, nhưng tổng số vector và số chiều khác nhau; phép tìm nearest chỉ trong tập tham chiếu. Không dùng median RMS để khẳng định 7×7 có khả năng phân biệt lớp tốt hơn.

**Ý nghĩa cho TC:** Cân nhắc lọc nền trước khi lấy mẫu codebook; công bố chính sách lấy mẫu theo ảnh và size. Chưa chọn K từ tỷ lệ vector unique.

Nguồn: [raw diversity](../../results/fashion/eda1/question_driven/q33_raw_descriptor_diversity.csv), [trước/sau lọc](../../results/fashion/eda1/question_driven/q33_before_after_filter_redundancy.csv), [phân phối RMS](../../results/fashion/eda1/question_driven/q33_nearest_rms_distribution.svg).

## 6. I4 — Feature Extractability

### Q4.1 — SIFT/ORB có tạo đủ keypoints không?

**Trả lời:** Cả hai tạo được descriptor trên phần lớn ảnh pilot, nhưng ORB có tính khả dụng tốt hơn trong cấu hình đang thử; không phương pháp nào bảo đảm mọi ảnh đều có feature.

| Chỉ số, 200 ảnh pilot | ORB | SIFT |
|---|---:|---:|
| Mean keypoints/ảnh | 6,885 | 4,24 |
| Median | 7 | 4 |
| Không keypoint/descriptor | 5 ảnh, 2,5% | 17 ảnh, 8,5% |
| Có ≤2 descriptor | 20 ảnh, 10% | 60 ảnh, 30% |

Theo lớp, SIFT có **30% ảnh Trouser không keypoint**, **75% có ≤2 descriptor**; ORB có **15% ảnh T-shirt/top không keypoint**. Mỗi lớp chỉ có 20 ảnh pilot, nên những tỷ lệ theo lớp này là tín hiệu cần kiểm chứng thêm.

**Ý nghĩa cho TC:** Dense patches là lựa chọn chính có cơ sở, vì mọi ảnh có sẵn 49 hoặc 16 vị trí trước filtering. ORB/SIFT có thể giữ làm đối chứng; kết quả này gắn với cấu hình đã ghi, không đại diện mọi cách chỉnh extractor.

Nguồn: [extractor summary](../../results/fashion/eda1/question_driven/q41_extractor_summary.csv), [theo lớp](../../results/fashion/eda1/question_driven/q41_keypoints_by_class.csv), [tham số](../../results/fashion/eda1/question_driven/run_metadata.toml).

### Q4.2 — Keypoints có bao phủ vùng chứa thông tin không?

**Trả lời:** Keypoints thường nằm trên foreground nhưng chỉ hit một phần nhỏ các ô foreground/cạnh của lưới đánh giá.

| Chỉ số mean theo ảnh pilot | ORB | SIFT |
|---|---:|---:|
| Tỷ lệ keypoint nằm trên foreground Q10+ | 86,46% | 73,26% |
| Coverage ô foreground Q10+ | 18,84% | 9,88% |
| Coverage ô có mean gradient≥80 | 17,08% | 9,49% |

Tỷ lệ keypoint nằm trên foreground lấy trung bình trên **195 ảnh ORB và 183 ảnh SIFT có keypoint**. Coverage lấy cả **200 ảnh**, kể cả ảnh không keypoint.

Coverage dùng cùng lưới 7×7 ô 4×4; một ô được hit khi có tâm keypoint trong ô. Metric này không đo diện tích support của descriptor, nên không được diễn giải rằng ORB/SIFT chỉ giữ đúng 17,08%/9,49% thông tin ảnh.

**Ý nghĩa cho TC:** Dense extraction cung cấp vị trí đều và khả dụng hơn cho mục tiêu tạo transaction từ từng ảnh. Keypoint extraction tập trung vào ít vị trí hơn, cần kiểm tra tác động đến transaction rỗng và nội dung visual words.

Nguồn: [coverage summary](../../results/fashion/eda1/question_driven/q42_coverage_summary.csv), [gallery mask/gradient/keypoint](../../results/fashion/eda1/question_driven/q42_keypoint_mask_gradient_gallery.svg).

## 7. I5 — Spatial Relevance

### Q5.1 — Các vùng ảnh có đặc tính khác nhau không?

**Trả lời:** Có. Vùng giữa sáng hơn và có occupancy lớn hơn; mean gradient vẫn khác nhau sau khi chia cho diện tích.

| Vùng | Số pixel | Mean intensity | Occupancy Q10+ | Mean gradient/pixel | Tỷ trọng tổng gradient |
|---|---:|---:|---:|---:|---:|
| Top, hàng 1–9 | 252 | 54,04 | 33,60% | 146,51 | 25,72% |
| Middle, hàng 10–19 | 280 | 93,55 | 56,83% | 202,31 | 39,47% |
| Bottom, hàng 20–28 | 252 | 69,03 | 42,59% | 198,23 | 34,81% |

Middle rộng hơn top/bottom, nhưng khác biệt không chỉ do diện tích: intensity, occupancy và mean gradient đều đã chia theo số pixel.

**Ý nghĩa cho TC:** Có bằng chứng để thử giữ vị trí. Chưa có lý do bỏ toàn bộ top hoặc bottom chỉ từ trung bình toàn tập.

Nguồn: [regional statistics](../../results/fashion/eda1/question_driven/q51_regional_statistics.csv), [phân phối theo vùng](../../results/fashion/eda1/question_driven/q51_region_distribution_summary.csv).

### Q5.2 — Spatial patterns có khác nhau theo lớp không?

**Trả lời:** Có; trung bình toàn tập che khuất các cấu trúc khác nhau theo loại trang phục.

| Lớp | Occupancy Q10+ top | Middle | Bottom |
|---|---:|---:|---:|
| T-shirt/top | 56,05% | 53,48% | 48,70% |
| Sneaker | 2,54% | 64,03% | 13,96% |
| Bag | 24,43% | 76,22% | 56,51% |

Về tổng gradient, middle của Sneaker chiếm **71,67%**, trong khi T-shirt/top chỉ **34,18%**. Bottom của Ankle boot chiếm **44,05%** tổng gradient. Các đối chiếu này cho thấy vị trí có quan hệ với dạng hình ảnh, không chỉ với mức sáng chung.

**Ý nghĩa cho TC:** Một visual word xuất hiện ở top và bottom có thể mang ngữ cảnh khác nhau. Đây là cơ sở thử spatial encoding; chưa chứng minh spatial words sẽ tăng chất lượng patterns hoặc support.

Nguồn: [bảng vùng theo lớp](../../results/fashion/eda1/question_driven/q51_regional_statistics.csv), [mean maps](../../results/fashion/eda1/question_driven/q52_mean_maps.svg), [gradient maps](../../results/fashion/eda1/question_driven/q52_gradient_maps.svg), [occupancy](../../results/fashion/eda1/question_driven/q52_occupancy_m1.svg).

### Q5.3 — Nên thử chia spatial thành vùng nào?

**Trả lời:** Nên đối chứng standard BoVW với ba dải ngang trước; 2×2 cũng có thể thử nhưng cần chú ý việc gán patch bằng tâm.

- **No-spatial:** item dạng `V5`, tối đa K items.
- **Ba dải:** item dạng `V5_top`, `V5_middle`, `V5_bottom`, tối đa 3K items. Vùng pixel: hàng 1–9, 10–19, 20–28.
- **2×2:** word kết hợp quadrant, tối đa 4K items. Patch được gán nguyên theo tâm; tâm đúng ranh giới 14,5 thuộc phía dưới/phải.

| Size | Số patch top/middle/bottom | Số patch TL/TR/BL/BR |
|---|---|---|
| 4×4 | 14 / 21 / 14 | 9 / 12 / 12 / 16 |
| 7×7 | 4 / 8 / 4 | 4 / 4 / 4 / 4 |

Ở 4×4, quadrant không nhận số patch bằng nhau do hàng/cột giữa có tâm đúng ranh giới. Đây là đặc tính của quy tắc mapping hiện tại; vùng pixel gốc vẫn chia thành bốn phần bằng nhau. Nếu so spatial giữa hai size, phải công bố khác biệt này.

**Ý nghĩa cho TC:** Ba dải có căn cứ trực tiếp từ Q5.1–Q5.2 và quy tắc đơn giản. Sau lượng tử hóa mới kiểm tra item universe thực tế, transaction length, support và ý nghĩa patterns; chưa chọn encoding cuối cùng từ heatmap.

Nguồn: [mapping patch→region](../../results/fashion/eda1/question_driven/q53_patch_region_mapping.csv), [số patch từng vùng](../../results/fashion/eda1/question_driven/q53_region_patch_counts.csv), [các ứng viên](../../results/fashion/eda1/question_driven/q53_spatial_candidates.csv).

## 8. Bộ thí nghiệm TC đề xuất từ các insight

Bắt đầu bằng bốn cấu hình, cùng raw descriptor `Float32(pixel)/255`, dense extraction và no-spatial:

| Thí nghiệm | Size | Filtering | Vai trò |
|---|---|---|---|
| T1 | 4×4 | No-filter | Baseline cho size nhỏ |
| T2 | 4×4 | Q10+, α=0 | Ứng viên chính giảm nền; reduction 37,50%, EdgeLoss 4,41% |
| T3 | 7×7 | No-filter | Đối chứng kích thước/ngữ cảnh |
| T4 | 7×7 | Q10+, α=0 | Đối chứng hiệu quả lọc ở size lớn |

Mỗi size có số chiều descriptor khác nhau, nên huấn luyện codebook riêng; không đưa vector 16 chiều và 49 chiều vào chung một K-means. Chính sách lấy mẫu codebook phải được công bố để tập có nhiều patch hơn không tự chi phối phép so sánh.

Sau bốn cấu hình này, mở rộng có kiểm soát: α=0,0625, descriptor gradient/histogram hướng, rồi spatial ba dải. Thay từng yếu tố để đọc được nguyên nhân khác biệt; K, chất lượng cụm, transaction length/density/support và Eclat thuộc TC/EDA-2.

**Kết luận phục vụ bước tiếp theo:** Đã có số liệu để trả lời 15 câu hỏi ở mức EDA và thêm đối chứng τ=10. Chưa có kết quả codebook/transaction để xác nhận patch 4×4, descriptor raw hoặc spatial encoding là phương án tốt nhất. Dùng **4×4 + Q10+ α=0** làm ứng viên so với **4×4 + τ=10 α=0** và giữ **7×7** làm đối chứng kích thước. τ=10 giảm patch/loss thấp hơn một chút; Q10+ tiết kiệm thêm descriptors. Chọn trade-off cuối cùng sau khi đo codebook và transaction.

## 9. Ghi chú truy vết và giới hạn báo cáo

- Chỉ dùng CSV/TOML mới trong `question_driven/` cho số liệu. Các phần trăm được làm tròn; điểm phần trăm dùng để biểu thị chênh lệch hai tỷ lệ.
- Manifest hiện tại liệt kê các output trong `question_driven/`; SHA-256 các file khớp manifest. Bảng tau=10 được tính trong cell bổ sung từ ảnh theo image_id và gradient của patch.
- Checksum bảng metrics gzip khớp metadata; số dòng 4.550.000 lấy từ metadata phiên chạy, không đếm lại toàn bộ gzip trong tác vụ viết báo cáo.
- Các kết luận về raw/HOG/keypoint chỉ giới hạn ở pilot khi chỉ số được tính trên pilot; khác biệt lớp chưa được kiểm định suy luận thống kê.
- Report không tự sửa insight người dùng trong notebook hoặc quyết định trong `tc_decision_template.csv`.
