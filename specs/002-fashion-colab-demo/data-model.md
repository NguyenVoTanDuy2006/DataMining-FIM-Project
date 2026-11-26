# Mô hình dữ liệu cho ba notebook demo

## Dữ liệu ảnh và bằng chứng tiền xử lý

- **Bộ dữ liệu** gồm bốn tệp gốc có mã SHA-256 xác định. Tệp kê khai dữ liệu hiện có ghi mã lượt, số ảnh mỗi tập, kích thước 28×28, 10 lớp, đường dẫn tương đối và kết quả kiểm định.
- **Ảnh nguồn** có định danh `train:<chỉ số>` hoặc `test:<chỉ số>`, với chỉ số bắt đầu từ 0 trong mỗi tập. Khi đọc bằng Julia, cộng 1 để lấy đúng phần tử trong tập tương ứng. Nhãn đi theo ảnh và dùng cho phần phân tích theo lớp.
- **Bằng chứng tiền xử lý** ghi nguồn, kích thước vùng, quy tắc lọc, tỷ lệ vùng bị loại, tỷ lệ gradient mất đi và số ảnh hết vùng khi có số liệu. Bảng khảo sát có nguồn lịch sử. Ảnh mẫu, mặt nạ giữ vùng và vectơ minh họa gắn với dữ liệu đã kiểm định trong phiên hiện tại.

## Lượt dựng giao dịch

- **Cấu hình** gồm phiên bản nguồn, phiên bản Julia, bộ dữ liệu, kích thước vùng và bước trượt 4×4, điều kiện điểm ảnh lớn hơn 29, vectơ 16 chiều chuẩn hóa, số cụm, giá trị khởi tạo ngẫu nhiên, dung sai và giới hạn lặp.
- **Kết quả học từ điển** gồm số vòng thực tế, cờ hội tụ, trạng thái học, tâm cụm và các số đo hiện có trong `tc4_metrics.toml`. Tệp từ điển nhị phân và bảng tâm cụm mô tả cùng một lần fit.
- **Giao dịch** là một dòng đi kèm định danh giao dịch từ 1 đến 70.000 và định danh ảnh. Từ thị giác nằm trong 1–32, sắp tăng dần và duy nhất trong một giao dịch. Hai ảnh có cùng tập từ vẫn là hai giao dịch. Giao dịch rỗng hợp lệ vẫn nằm trong mẫu số.
- **Ánh xạ ảnh và vùng ảnh** nối mỗi giao dịch với một ảnh nguồn. Bảng gán vùng ảnh ghi tọa độ hàng và cột từ 1 đến 7, định danh vùng từ 1 đến 49 và từ thị giác được gán. Các vùng 4×4 được lấy theo tọa độ từ ảnh đã xác minh.

Trạng thái học từ điển và trạng thái kiểm định đầu ra là hai thuộc tính riêng. Lượt chạm giới hạn lặp vẫn có thể hoàn tất nếu bộ dựng giao dịch xác nhận từ điển và dữ liệu hợp lệ. Lượt lỗi hoặc kiểm định thất bại dừng trước khi xuất gói thành công. Khi đổi giới hạn lặp, dùng mã lượt mới.

## Gói giao dịch

- **Tệp kê khai demo** chứa phiên bản định dạng, mã commit, phiên bản Julia, mã lượt dữ liệu và mã lượt từ điển. Nó trỏ đến tệp kê khai dữ liệu, tệp kê khai kiểm định giao dịch và tệp số đo K-means bằng đường dẫn tương đối và SHA-256.
- **Các tệp được bảo toàn** gồm tám đầu ra mà tệp kê khai kiểm định giao dịch hiện tại tham chiếu. Thư mục gốc để giải đường dẫn là gốc gói đã giải nén.
- **Vòng đời** gồm xuất từ lượt đã qua kiểm định, mở trong thư mục riêng, xác minh tệp và liên kết giữa các bảng, rồi dùng làm đầu vào. Nếu xác minh thất bại, dừng trước bước khai thác.

Xem đường dẫn và quy tắc xác minh trong [hợp đồng notebook](contracts/notebook-artifacts.md).

## Kết quả khai thác và bằng chứng ảnh

- **Kết quả theo ngưỡng** ghi mã lượt dựng giao dịch, mã băm giao dịch, tỷ lệ hỗ trợ, số ảnh tối thiểu, số tập mục và trạng thái theo backend. Đối chiếu đạt khi hai ánh xạ tập mục sang số ảnh hỗ trợ giống nhau. Cặp có lượt chưa hoàn tất chưa có kết quả đối chiếu.
- **Mẫu minh họa** ghi tập từ thị giác, ngưỡng nguồn, số ảnh hỗ trợ, tỷ lệ hỗ trợ, phân bố theo lớp và các ảnh cùng vùng được dùng để minh họa. Đếm trực tiếp trên giao dịch phải khớp số hỗ trợ. Tổng số ảnh hỗ trợ qua các lớp phải bằng số ảnh hỗ trợ của mẫu.
- **Hệ số làm giàu**, nếu hiển thị, là tỷ lệ ảnh chứa mẫu trong lớp chia cho tỷ lệ ảnh chứa mẫu trong toàn bộ bộ giao dịch.
