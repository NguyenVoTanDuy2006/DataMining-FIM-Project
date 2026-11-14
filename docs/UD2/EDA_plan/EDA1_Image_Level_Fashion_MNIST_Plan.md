# EDA-1 — Bằng chứng theo câu hỏi cho Transaction Construction

## Mục tiêu, phạm vi và cách chạy

Notebook: `notebook/UD2/02_fashion_mnist_image_eda.ipynb`.
Mục tiêu: dùng dữ liệu ảnh để trả lời Q1.1–Q5.3, đề xuất các cấu hình TC cần thử.
Không huấn luyện codebook, chọn K/minsup, tạo transaction chính thức hoặc chạy Eclat.
Nhãn lớp chỉ phục vụ phân tích, không trở thành item.

- Toàn tập gộp 70.000 ảnh grayscale 28×28 UInt8; 7.000 ảnh/lớp. Giữ nguyên bản lặp và split/index nguồn để truy vết.
- Patch 4×4, stride 4: lưới 7×7, 49 patch/ảnh, 3.430.000 patch.
- Patch 7×7, stride 7: lưới 4×4, 16 patch/ảnh, 1.120.000 patch.
- Cả hai giữ đủ 784 pixel trước lọc. “Giữ chi tiết” được đánh giá qua cấu trúc nằm trong patch và gradient/foreground bị mất sau lọc.
- SIFT/ORB, raw descriptor diversity và histogram hướng: pilot 200 ảnh, 20/lớp, seed 42. Không ngoại suy thành kết quả toàn tập.
- Julia ≥1.9; môi trường máy hiện tại Julia 1.13.3. Bản refactor chưa chạy toàn bộ notebook; phiên bản thực thi và package được ghi khi người dùng chạy.
- Chọn kernel Julia của repo, restart rồi chạy từ đầu. Notebook kích hoạt root project; `.venv` chỉ phục vụ Jupyter/nbclient.

## Đầu vào và dữ liệu dùng chung

Đọc PNG trong `data/processed/fashion-mnist/combined/` bằng `image_index.csv` theo `image_id`, không ghép nhãn bằng thứ tự folder. Kiểm tra checksum CSV/PNG, shape, pixel type, nhãn và nguồn train/test. D–A–B giữ vai trò kiểm tra nguồn, intensity và foreground cấp ảnh.

Dùng một Q10+ trên pixel dương (nearest rank, không nội suy) và một Global Otsu gồm cả pixel 0 (chọn ngưỡng thấp nhất khi hòa điểm). Mask `I > tau`. Giá trị 29/97 của output cũ là tham chiếu, không hardcode vào pipeline.

Tính Sobel Gx/Gy trên grayscale gốc với replicate border. Định nghĩa `gradient_energy = sum(hypot(Gx,Gy))`, không phải tổng bình phương. Tính một lần mỗi ảnh để tổng hợp patch cả hai size, mean/variance/occupancy/gradient maps và metrics vùng mỗi ảnh. Pilot có thể tính lại Sobel để phân tích hướng và gallery.

### Bảng patch

Khóa `(image_id, patch_size, patch_id)`, thứ tự hàng trước/cột sau; patch ID bắt đầu từ 1.
Các cột:

```text
image_id, class_label, patch_size, stride, patch_id, patch_row, patch_col
mean_intensity, intensity_variance, gradient_energy, mean_gradient_magnitude
foreground_count_q10, foreground_count_otsu
foreground_ratio_q10, foreground_ratio_otsu
```

Variance chia diện tích patch, dùng thang intensity gốc [0,255]. Mean gradient chia diện tích để so sánh hai size. Lưu 4.550.000 dòng dạng CSV gzip trong `data/processed/fashion-mnist/eda1/patch_metrics.csv.gz`, ngoài Git. Ghi metadata, SHA-256 của nguồn và bảng. Không tạo hàng triệu vector descriptor toàn tập trong RAM.

Bảng/hình/báo cáo mới trong `results/fashion/eda1/question_driven/`. Tách khỏi output cũ vì cấu hình alpha và kích thước có thể khác; không coi output cũ là bằng chứng của lần refactor. Metadata khai báo cả hai size và đầy đủ cấu hình extractor.

## Filtering và alpha

Với diện tích A, F pixel foreground:

```text
FR = F/A
Keep = FR > alpha
Discard = F <= floor(alpha*A)
```

Cùng alpha `{0, 1/16, 2/16}` cho hai size:

| Alpha | Patch 4×4: loại khi | Patch 7×7: loại khi |
|---|---|---|
| 0 | F=0 | F=0 |
| 0.0625 | F≤1 | F≤3 |
| 0.125 | F≤2 | F≤6 |

Hai tau × ba alpha + no-filter = 7 phương án/size, 14 phương án tổng cộng. No-filter khác alpha=0. Công bố cutoff thực tế và số keep masks khác biệt, kể cả khi tau trùng hoặc cấu hình trùng hiệu lực.

Bổ sung sweep mọi cutoff nguyên từ -1 (no-filter) đến A (loại mọi patch), tổng hợp từ histogram count và gradient. So sánh reduction–EdgeLoss ở những điểm đạt được; báo các cặp reduction gần nhau và độ lệch, không ngụ ý có cấu hình trung gian. Cờ Pareto tính trên tập điểm hai size/hai tau: reduction lớn hơn và loss nhỏ hơn là hướng ưu tiên.

## 15 câu hỏi, phép phân tích và output

| Câu hỏi | Dữ liệu/phép tính | Output chính |
|---|---|---|
| Q1.1 Biến thiên cường độ? | Mean/variance toàn tập từng size; variance=0 tách mean=0 và mean>0; gần 0 là 0<variance≤1; đối chiếu FR | `q11_*`: summary, histogram chung biên, nhóm đồng nhất |
| Q1.2 Có cấu trúc cạnh? | Mean gradient/pixel và tổng magnitude/patch; ví dụ gần p05/p95 | `q12_*`: hai summary, histogram và gallery gốc/gradient |
| Q1.3 Tập trung ở đâu? | Variance, mean gradient từng vị trí, toàn tập và 10 lớp | `q13_*`: bảng vị trí, heatmap lưới 7×7/4×4 cùng thang màu |
| Q2.1 Bao nhiêu patch gần nền? | Histogram FR rời rạc, count≤cutoff; phân phối số patch gần trống mỗi ảnh | `q21_*`: tỷ lệ và phân phối |
| Q2.2 Giảm được bao nhiêu? | 14 phương án; retained/reduction, mean retained, empty rate, pixel slots và raw descriptor dimensions | `q22_*`: comparison, distribution, số masks khác biệt |
| Q2.3 Mất cạnh không? | EdgeLoss=sum magnitude bỏ/sum magnitude gốc, foreground loss; sweep cutoff, điểm gần reduction và gallery giữ/loại | `q23_*`: tradeoff, frontier/cutoff table, gallery |
| Q2.4 Tác động theo lớp? | Cùng metric trên 7.000 ảnh/lớp; độ chênh giữa lớp | `q24_*`: class impact, spread và heatmap lớp×cấu hình |
| Q3.1 Intensity hay gradient? | Scatter tối đa 2.000 patch/size từ pilot; nhóm theo p25/p75 toàn tập từng size | `q31_*`: scatter, tiêu chí/số lượng nhóm và gallery |
| Q3.2 Có cơ sở thử HOG? | Unsigned [0,pi), 8 bin cứng, magnitude-weighted; entropy, bin trội; patch mean gradient≥80; cosine khi dịch cửa sổ 1 pixel ngang/dọc, replicate | `q32_*`: histogram hướng, patch statistics, stability, gallery |
| Q3.3 Descriptor dư thừa? | Raw Float32(pixel)/255; exact duplicates; RMS chia số chiều tới 1.024 tham chiếu/size seed 42, bỏ self; trước/sau lọc | `q33_*`: diversity, cặp gần nhau, gallery và redundancy |
| Q4.1 SIFT/ORB đủ features? | Pilot 200 ảnh, giữ cấu hình extractor cũ; giữ cả ảnh 0 descriptor trong mẫu số | `q41_*`: counts/coordinates, summary, histogram, theo lớp |
| Q4.2 Coverage vùng quan trọng? | Tâm keypoint→pixel→ô đánh giá cố định 4×4 (lưới 7×7); foreground target F>0; edge target mean gradient≥80 | `q42_*`: coverage cấp ảnh/theo lớp, gallery mask/gradient/keypoint |
| Q5.1 Phụ thuộc vị trí? | Regional mean intensity, FR, mean gradient/pixel và gradient share; summary và phân phối cấp ảnh | `q51_*`, bảng cấp ảnh lớn ngoài Git |
| Q5.2 Khác nhau theo lớp? | Mean, variance, gradient và occupancy maps trên pixel gốc, cùng thang màu từng metric | `q52_*`: maps toàn tập và 10 lớp |
| Q5.3 Chia spatial thế nào? | No-spatial; ba dải; quadrants; patch gán nguyên theo tâm; số patch/diện tích vùng | `q53_*`: mapping, region counts, candidates, sơ đồ |

### Các quy ước tránh suy luận sai

- Giá trị gradient mỗi patch lớn có thể do diện tích lớn; phép so sánh chính dùng mean/pixel hoặc loss trên tổng gradient cùng ảnh.
- Histogram log dùng `log10(1+số đếm)`, không ghi nhầm xác suất. Hướng gradient dùng tỷ trọng magnitude.
- Nhóm variance cao/gradient thấp có thể rỗng; ghi số nhóm và tiêu chí thay vì ép chọn ví dụ.
- Histogram hướng là bằng chứng cho HOG ứng viên, chưa là HOG chuẩn có block normalization.
- Diversity: pilot 4×4 có 9.800 vector 16 chiều, 7×7 có 3.200 vector 49 chiều; sample size khác nhau cần ghi rõ. Nearest reference không phải exact nearest toàn bộ tập.
- Coverage: tọa độ OpenCV 0-based đổi về pixel Julia 1-based. Không keypoint nhưng có target -> coverage=0; mẫu số 0 -> missing/N/A. Patch hit không phải segmentation coverage.
- Gallery dùng cùng 10 sample IDs đã chọn seed 42; gallery keypoint dùng 1 ảnh/lớp thuộc pilot. Gallery filtering có thêm ID loss cao của cả hai size; tiêu chí ghi trong code.
- Foreground mask và EdgeLoss là proxy, không chứng minh chi tiết ngữ nghĩa đã được bảo toàn.

## Spatial encoding ứng viên

- Ba dải theo pixel: rows1:9, rows10:19, rows20:28. Patch gán theo tâm với ranh giới tương ứng.
- Quadrants: pixel rows/cols1:14 và15:28; tâm <14.5 thuộc trên/trái, bằng ranh giới thuộc dưới/phải.
- Báo diện tích pixel thật khi phân tích vùng và số pixel slots đại diện bởi patch khi encoding; không coi hai đại lượng đồng nhất.
- Item universe tối đa K, 3K, 4K; chưa có support/transaction density để chọn spatial scheme.

## Notebook, báo cáo và bàn giao

- Toàn bộ code hỗ trợ nội bộ nằm trong notebook; không đổi public API package.
- Nhóm setup/hỗ trợ được gộp; code mới thụt lề bốn dấu cách, docstring/comment tiếng Việt, các nhóm cách nhau dòng trống.
- Câu hỏi có mục đích TC/cách tính trước cell; cách đọc, câu hỏi gợi ý, insight và giới hạn sau hình/bảng.
- Report tự ghi dữ kiện/số liệu; `tc_decision_template.csv` dành cho người dùng điền observation/interpretation/candidate. Không ghi đè template đã tồn tại khi rerun.
- Bàn giao TC1(size), TC2(filter), TC3(descriptor/strategy), TC6(spatial). Nếu chưa phân biệt rõ hai size thì giữ cả hai làm đối chứng ở TC.
- Metadata lưu Julia/OpenCV, pilot, normalization, alpha, thresholds, checksum và đường dẫn tương đối. Output manifest có SHA-256 và kích thước file.

## Kiểm tra và trạng thái nghiệm thu

Kiểm tra JSON/nbformat và parse mọi cell Julia; kiểm tra logic bằng ảnh tổng hợp 28×28 có ảnh đen/trắng, trường hợp cutoff 0/1/2/3 pixel, partition/reconstruction, count/gradient conservation, no-filter, monotonicity, descriptor dimensions, coverage 0/missing và layout SVG. Đây không thay cho thực thi toàn tập.

Người dùng chạy notebook từ kernel mới; sau đó đối chiếu đầy đủ output, thời gian/RAM, ảnh đúng hướng, chữ/legend không cắt, tất cả assertion, và viết insight. Checklist phân biệt code đã viết với đã chạy/có bằng chứng và đã viết insight. Không tự tick bằng chứng toàn tập dựa trên output trước refactor.
