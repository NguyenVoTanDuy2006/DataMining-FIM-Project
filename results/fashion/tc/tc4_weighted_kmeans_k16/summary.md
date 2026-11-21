# Weighted K-means K=16 — benchmark 60k train

- N descriptors: `1836369`; K: `16`; seed: `42`.
- Repeats/config: `3`; max_iter: `1000`; relative objective tolerance: `0.0001`.
- Nhanh nhất theo median fit: **PQ08_A50** (0.57 s).
- Thấp nhất theo median total: **Q20** (3.383 s).
- Thấp nhất theo median Raw-space Validation Distortion: **P12** (0.02760418).
- Gần centroid B0 nhất theo median Centroid MSE Raw 16D: **B0** (0.0).
- Độ lệch lặp lại thấp nhất (median-to-repeat MSE tối đa): **Q20** (0.0).
- Speedup fit và total so B0 được ghi trong CSV; B0 đã chạy cùng môi trường.
- Không hội tụ ở repeat đại diện: không có.
- Spearman giữa compute proxy TC4 và median fit runtime trên lựa chọn này: 0.6088.

Raw-space Validation Distortion = tổng khoảng cách bình phương tới centroid gần nhất trên validation Raw 16D, chia cho 16 × số descriptor validation. Chỉ dùng validation để chấm điểm; không fit ngưỡng, PCA hay K-means trên split này.
Centroid MSE so B0 đo độ khác biệt giữa codebook sau ghép cụm tối ưu; nó không thay cho Validation Distortion.
`compute_proxy` không phải runtime. Inertia giữa các không gian vector khác chiều/thang đo không dùng làm so sánh chất lượng. Validation chỉ dùng để đánh giá distortion; không dùng để fit hay chọn ngưỡng/PCA/K-means. Benchmark không đánh giá visual vocabulary hoặc transactions.

