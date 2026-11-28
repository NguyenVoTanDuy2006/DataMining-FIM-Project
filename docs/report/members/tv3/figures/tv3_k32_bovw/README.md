# Hình cho bản thảo lựa chọn K=32 và BoVW nhị phân

Các SVG nguồn được trích từ gói `fashion-full-experiment-20261127T181640Z.tar.gz`:

- `kmeans_distortion_source.svg` ← `analysis/figures/notebook/a_do_meo.svg`
- `frequent_pairs_source.svg` ← `analysis/figures/notebook/c1_cap_item.svg`
- `codebook_centroids_source.svg` ← `analysis/codebook/figures/centroids_K32_seed123.svg`
- `spatial_encoding_schematic.svg` là sơ đồ vector minh họa được dựng theo quy tắc trong `src/applications/Fashion-Mnist/spatial/FashionTCSpatial.jl`, `configs/spatial/full.toml` và đặc tả TC6; không phải ảnh Fashion-MNIST hay kết quả thực nghiệm.

Các PDF cùng tên được chuyển từ SVG bằng `rsvg-convert` để XeLaTeX có thể nhúng hình trực tiếp. Trong hình so sánh định lượng, chú giải dùng tên mô tả cho BoVW nhị phân, biểu diễn theo vùng 2×2 và biểu diễn theo ba dải ngang; sơ đồ riêng minh họa thêm quan hệ lân cận cục bộ. Tiêu đề biểu đồ số cặp cũng được viết đầy đủ thay cho mã kỹ thuật. Hình codebook được cắt lề trắng phía dưới và Việt hóa nhãn trong `codebook_centroids_cropped.svg`; các SVG gốc vẫn được giữ nguyên để đối chiếu. Bảng trong bản thảo tổng hợp `analysis/codebook/codebook_metrics_by_k.csv`, `analysis/transactions/transaction_metrics_60.csv` và các giá trị cặp hiển thị trong hình số cặp.
