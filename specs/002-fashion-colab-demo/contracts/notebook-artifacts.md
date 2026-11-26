# Hợp đồng notebook và gói bàn giao Fashion-MNIST

## 1. Điểm vào từ README

- Ba nút **Open in Colab** trong mục demo lần lượt mở `01_image_exploration.ipynb`, `02_transaction_construction.ipynb` và `03_transaction_exploration_and_mining.ipynb` trong `notebook/UD2/demo/`.
- Cả ba notebook khai báo Julia kernel; ô code đầu tải repo ở commit cố định, kích hoạt môi trường dự án và gọi `Pkg.instantiate()` ngay trong kernel. Notebook ghi commit và phiên bản Julia thực tế. Không dùng Python kernel hoặc Python để khởi chạy Julia. Các thao tác bàn giao và hiển thị cũng chạy trong Julia.
- Notebook 01 và 02 tải hoặc kiểm định lại dữ liệu đầu vào. Notebook 03 nhận một đường dẫn đến gói giao dịch, gồm cả gói được tải lên trong một phiên mới. Các notebook báo lỗi rõ khi thiếu quyền repo, môi trường chưa sẵn sàng hoặc thiếu đầu vào.

## 2. Gói xuất từ notebook 02

Tên tải xuống dự kiến là `fashion-demo-<run_id>.tar.gz`. Tệp `demo_manifest.toml` nằm ở gốc gói. Các mục còn lại dùng đường dẫn tương đối so với gốc repo, giữ nguyên nội dung từ lượt xây dựng.

| Trường trong `demo_manifest.toml` | Hợp đồng |
| --- | --- |
| `schema_version` | Số nguyên, phiên bản đầu là `1`. |
| `run_id`, `tc_run_id` | Khớp định danh tương ứng trong tệp kê khai kiểm định giao dịch. `run_id` cũng khớp tệp kê khai dữ liệu. Các trường này giữ tên nội bộ để tương thích với bộ đọc hiện có. |
| `source_commit`, `julia_version` | Mã commit đầy đủ và phiên bản Julia quan sát được ở notebook 02. |
| `dataset_manifest`, `transaction_manifest`, `fit_metrics` | Ba bảng có `path` và `sha256`, trỏ đến `dataset_manifest.toml`, `tc7_manifest.toml` và `tc4_metrics.toml`. |

Tệp `tc7_manifest.toml` hiện có phải ở trạng thái `PASS` và trỏ đến đủ tám tệp. Gói mang theo `transactions.jsonl`, `codebook.bin`, `centroids.csv`, `patch_assignments.csv`, `tid_image_mapping.csv`, `image_metadata.csv`, `config_snapshot.toml` và `integrity_report.toml`. Tám tệp giữ nguyên quy ước của [hợp đồng phát hành](../../001-fashion-notebook-release/contracts/notebook-artifacts.md). Bốn tệp ảnh và nhãn nén lấy lại từ nguồn chính thức và xác minh theo tệp kê khai dữ liệu khi cần truy vết.

## 3. Quy tắc nhập ở notebook 03

1. Mở gói ở thư mục riêng. Chỉ nhận thư mục và tệp thường. Từ chối đường dẫn tuyệt đối, đường dẫn thoát khỏi gốc, mục trùng và liên kết. Áp dụng kiểm tra đường dẫn cho cả nội dung gói và các tham chiếu trong tệp kê khai.
2. Xác minh phiên bản định dạng và mã SHA-256 của các tệp được trỏ đến. Kiểm tra hai tệp kê khai gốc cùng lượt, cấu hình và tệp giao dịch đúng với báo cáo kiểm định. Xác minh định danh giao dịch theo thứ tự, định danh ảnh theo tập gốc, các từ thị giác hợp lệ và ánh xạ ảnh nhất quán.
3. Khi cần ảnh gốc, xác minh bốn tệp nén bằng mã đã lưu và đọc tập gốc theo định danh ảnh. Dùng `centroids.csv` cho hiển thị, kiểm tra mã băm của `codebook.bin` mà không cần giải tuần tự hóa tệp từ gói nhận vào.
4. Nếu thiếu tệp, sai mã băm hoặc định danh không khớp, thông báo tên tệp hoặc điều kiện sai và dừng trước khi xuất kết quả khai thác. Gói đang kiểm tra được xử lý riêng để tránh dùng nhầm kết quả từ lần mở trước.

## 4. Kết quả hiển thị của notebook 03

- Một hàng mỗi ngưỡng với `minsup_percent`, `min_count`, trạng thái và số tập mục của từng backend, cùng trạng thái đối chiếu. Với 70.000 giao dịch, số đếm lần lượt là 56.000, 42.000, 28.000, 14.000, 7.000 và 3.500 ở 80%, 60%, 40%, 20%, 10% và 5%. Cặp hoàn tất và cùng trả rỗng có số tập mục 0 và có thể đối chiếu đạt. Cặp lỗi có trạng thái lỗi và không ghi số tập mục 0 thay cho dữ liệu thiếu.
- Một minh họa khi có tập mục phù hợp. Ưu tiên một mẫu nhiều từ trong kết quả đã đối chiếu đạt ở ngưỡng 5%, chọn theo số ảnh hỗ trợ giảm dần rồi thứ tự mã từ thị giác. Có thể dùng tập một mục nếu không có tập nhiều mục. Nếu ngưỡng này hoàn tất và không có tập mục, báo không có mẫu để minh họa. Nếu lượt ở ngưỡng này lỗi, báo trạng thái và thiếu đầu vào cho minh họa.
- Bảng kết quả và hình minh họa đi kèm mã lượt dựng giao dịch và mã băm giao dịch. Ghi bằng chứng đối chiếu cả khóa tập mục và số hỗ trợ, số ảnh đếm lại cho mẫu được minh họa và phân bố theo lớp.
