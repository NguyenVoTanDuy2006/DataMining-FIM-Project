# EDA-1 — Bằng chứng so sánh patch cho TC

- 70000 ảnh; index SHA-256: 6598319e03fb8568bd80f0983c5437df10c80d24b5ad96c6f575345aeb26fade.
- Q10+=29; Otsu=97; mask I>τ; α=[0.0, 0.0625, 0.125].
- Patch 4×4/7×7 giữ đủ 784 pixel trước lọc; metrics 4550000 dòng.
- Pilot 200 ảnh, 20/lớp, seed 42.

## Dữ kiện filtering

- 4×4, No-filter, α=missing: reduction=0.0, EdgeLoss=0.0, empty_rate=0.0, retained_pixel_slots=54880000.
- 4×4, Q10+, α=0.0: reduction=0.37500116618075807, EdgeLoss=0.044143670816883154, empty_rate=0.0, retained_pixel_slots=34299936.
- 4×4, Q10+, α=0.0625: reduction=0.3930020408163265, EdgeLoss=0.05918495819415912, empty_rate=0.0, retained_pixel_slots=33312048.
- 4×4, Q10+, α=0.125: reduction=0.4105379008746356, EdgeLoss=0.07844203941699344, empty_rate=0.0, retained_pixel_slots=32349680.
- 4×4, Global Otsu, α=0.0: reduction=0.43296851311953355, EdgeLoss=0.08896414828325802, empty_rate=0.0, retained_pixel_slots=31118688.
- 4×4, Global Otsu, α=0.0625: reduction=0.4588008746355685, EdgeLoss=0.11775411012061074, empty_rate=0.0, retained_pixel_slots=29701008.
- 4×4, Global Otsu, α=0.125: reduction=0.48213906705539356, EdgeLoss=0.14987633540500744, empty_rate=1.4285714285714285e-5, retained_pixel_slots=28420208.
- 7×7, No-filter, α=missing: reduction=0.0, EdgeLoss=0.0, empty_rate=0.0, retained_pixel_slots=54880000.
- 7×7, Q10+, α=0.0: reduction=0.23533839285714286, EdgeLoss=0.01434670329969069, empty_rate=0.0, retained_pixel_slots=41964629.
- 7×7, Q10+, α=0.0625: reduction=0.272525, EdgeLoss=0.030173257418260453, empty_rate=0.0, retained_pixel_slots=39923828.
- 7×7, Q10+, α=0.125: reduction=0.3091464285714286, EdgeLoss=0.05548065803150185, empty_rate=0.0, retained_pixel_slots=37914044.
- 7×7, Global Otsu, α=0.0: reduction=0.2766267857142857, EdgeLoss=0.03167652691046135, empty_rate=0.0, retained_pixel_slots=39698722.
- 7×7, Global Otsu, α=0.0625: reduction=0.33056339285714287, EdgeLoss=0.06396687362493764, empty_rate=0.0005, retained_pixel_slots=36738681.
- 7×7, Global Otsu, α=0.125: reduction=0.3813553571428572, EdgeLoss=0.10912249572760356, empty_rate=0.004842857142857143, retained_pixel_slots=33951218.

## Chỗ ghi kết luận của người phân tích

Điền tc_decision_template.csv, đối chiếu Q1.1–Q5.3 và ghi số liệu/ID cụ thể.

## Giới hạn

EdgeLoss là proxy tổng magnitude, không chứng minh chi tiết ngữ nghĩa. Khoảng cách descriptor và extractability chỉ trên pilot. Chưa có codebook/visual words, support hoặc kết quả Eclat; chưa kết luận size/descriptor/spatial tốt nhất.
