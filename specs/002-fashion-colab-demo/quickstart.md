# Hướng dẫn nghiệm thu demo Fashion-MNIST

Dùng tài liệu này để kiểm chứng khi ba notebook đã có trong phiên bản GitHub được mở từ README.

## Chuẩn bị

- Quyền đọc repo và commit nguồn đã khóa, kết nối để tải dependency cùng dữ liệu Fashion-MNIST.
- Trên Colab chọn **Runtime → Change runtime type → Runtime type: Julia**, đặt **Hardware accelerator: None**. Bắt đầu từ phiên mới với thư mục làm việc trống.
- Xác minh ba nút **Open in Colab** trong mục demo README mở đúng ba notebook. Metadata mỗi notebook phải khai báo Julia; chạy ô khởi tạo đầu tiên và kiểm tra commit, phiên bản Julia cùng số thread thực tế được in ra.

## 1. Khám phá ảnh

Mở notebook 01 và chạy lần lượt. Kiểm tra có đủ 60.000 ảnh huấn luyện và 10.000 ảnh kiểm thử. Xem bảng so sánh kích thước vùng ở tỷ lệ loại tương đương, bảng so sánh lọc nền và hình hoặc bảng vectơ 16 chiều. Các số liệu từ khảo sát trước phải có ghi nguồn. Ví dụ vùng ảnh và vectơ phải được tạo khi chạy.

## 2. Dựng và tải gói giao dịch

Mở notebook 02 trên một phiên CPU mới và chạy đầy đủ với cấu hình mặc định. Kiểm tra ví dụ ảnh → vùng ảnh → từ thị giác → giao dịch, trạng thái dừng của K-means, giới hạn demo 400 vòng và số vòng quan sát được. Xác minh `release.toml` không đổi (giới hạn 300); notebook demo ghi đè giới hạn này cho lượt Colab. Nếu chạm giới hạn, đối chiếu trạng thái học và trạng thái kiểm định giao dịch riêng biệt theo [mô hình dữ liệu](data-model.md). Với lượt hoàn tất, xác minh tệp kê khai báo kiểm định đạt và có đúng 70.000 giao dịch. Tải gói `.tar.gz` về máy và ghi mã lượt cùng mã băm giao dịch.

## 3. Mở từ một phiên khác

Mở notebook 03 trong một phiên Julia CPU mới. Dùng Files panel của Colab để tải gói lên `/content`, rồi chạy cell nhận gói. Kiểm tra mã lượt và mã băm khớp với notebook 02, phân bố độ dài có tổng 70.000 giao dịch và sáu ngưỡng đều có trạng thái. Nghiệm thu lượt đầy đủ khi cả sáu ngưỡng có kết quả đối chiếu đạt. Mở ít nhất một mẫu để xem ảnh, vùng ảnh và bảng theo lớp. Đối chiếu số ảnh đếm lại, số hỗ trợ và tổng qua các lớp.

## 4. Kiểm tra gói lỗi

Tạo bản sao của gói hợp lệ. Trong bản sao giải nén, sửa một dòng trong tệp giao dịch hoặc bỏ bảng gán từ thị giác, rồi nén lại theo cấu trúc cũ. Mở bản sao trong một phiên phân tích riêng. Kỳ vọng notebook chỉ rõ tệp sai mã băm hoặc còn thiếu và dừng trước bảng khai thác. Gói ban đầu vẫn mở được. Xem [quy tắc nhập](contracts/notebook-artifacts.md#3-quy-tắc-nhập-ở-notebook-03).

## 5. Tái chạy riêng K-means trên Colab

Mở notebook tái chạy K-means từ mục Fashion-MNIST experiments trên README, chọn runtime Julia và CPU. Xác minh notebook dùng trực tiếp `FashionTC` trong Julia kernel, snapshot cấu hình ghi `max_iterations = 400`, BLAS chạy một luồng, mục tiêu `OPENBLAS_CORETYPE=Haswell` được ghi lại, và run summary lưu phiên bản Julia cùng số thread thực tế của kernel. Đọc số vòng thực tế từ summary; 372 là mốc đã quan sát trên một lượt Colab, không phải số vòng được ép hay kết quả đảm bảo trên mọi máy. `JULIA_NUM_THREADS` phải được đặt trước khi kernel khởi động nên cell không thể đổi thread count sau đó. Cấu hình phát hành trong `release.toml` vẫn là 300 vòng.

## Kiểm tra môi trường Julia cục bộ

Chạy từ gốc repo của commit được notebook tải để kiểm tra môi trường và các giao diện mà ba notebook gọi:

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=. -e 'using EclatFIM; using EclatFIM.FashionMNIST: FashionTC, FashionFIMWorkflow'
```

Các bước nghiệm thu ở trên chạy trực tiếp trong notebook trên Colab CPU.
