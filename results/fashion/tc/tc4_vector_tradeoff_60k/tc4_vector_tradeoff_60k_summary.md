# TC4 pre-K-means vector tradeoff — kết quả

- Julia: `1.13.3`
- Train descriptors N: `1836369` (D=16)
- Tau Q10+ train: `29.0`
- Duplicate rate raw TC2: `0.005370380353839521`
- PCA fit seconds: `1.788`
- K-means fits: `0` (không chạy trong notebook này)
- Pareto candidates: `10`

## Shortlist sơ bộ

| Cấu hình | Compute proxy | Normalized distortion | P95 RMSE | Spearman | Prep (s) | U/N |
|---|---:|---:|---:|---:|---:|---:|
| Q32 | 0.6406 | 0.007983 | 0.043059 | 0.9971 | 1.87 | 1176320/1836369 |
| PQ12_A25 | 0.6223 | 0.018077 | 0.08809 | 0.9934 | 4.21 | 1523747/1836369 |
| PQ12_A50 | 0.471 | 0.032495 | 0.099479 | 0.9761 | 4.43 | 1153158/1836369 |

`compute_proxy` và nghịch đảo của nó là proxy lý thuyết, không phải speedup đo được. MSE thấp không chứng minh codebook K-means tốt. Chỉ dùng bảng này để chọn tối đa 2–3 ứng viên cho thí nghiệm K=64, seed=42 ở giai đoạn sau; TC5 vẫn dùng descriptor raw 16D.
