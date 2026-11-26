# Nghiên cứu cho demo Fashion-MNIST trên Colab CPU

## 1. Chạy mã Julia trong Colab

**Quyết định** — Dùng runtime Julia gốc của Colab. Cả ba notebook demo và notebook tái chạy K-means khai báo Julia kernel; các ô code đọc dữ liệu, tiền xử lý, dựng giao dịch, khai thác, thống kê và sinh hình chạy trực tiếp trong kernel. Ô đầu clone và checkout commit đã khóa qua thư viện `LibGit2`, kích hoạt dự án và gọi `Pkg.instantiate()`; notebook ghi phiên bản Julia thực tế do Colab cung cấp. Mỗi notebook dùng depot riêng trong `/content`, giới hạn BLAS một luồng, yêu cầu `OPENBLAS_CORETYPE=Haswell` và tắt tự động precompile khi cài package.

**Lý do** — Colab hiện hỗ trợ Julia như một ngôn ngữ runtime; kernel Julia giúp code cell thực thi đúng ngôn ngữ của dự án, không cần Python làm lớp gọi. Manifest trong repo được tạo bằng Julia 1.13.3, còn Julia version của runtime Colab có thể khác nên notebook cần ghi lại phiên bản thực tế và nghiệm thu `Pkg.instantiate()` trên Colab. `JULIA_NUM_THREADS` phải được đặt trước khi tiến trình Julia khởi động, nên gán biến này trong cell không thay đổi số thread đang hoạt động; notebook ghi số thread thực tế. `BLAS.set_num_threads(1)` áp dụng cho BLAS đang chạy, còn kết quả số học vẫn được đọc từ artifact thay vì giả định các CPU khác nhau sẽ cho kết quả giống hệt.

**Phương án đã cân nhắc** — Python kernel gọi Julia sẽ thêm lớp điều phối và che khuất ngôn ngữ notebook. Nhúng toàn bộ mã hoặc tạo bản Python riêng sẽ nhân đôi phần xử lý của repo. Julia runtime gốc của Colab cho phép dùng trực tiếp kernel Julia mà không phải tự cài một kernel Jupyter tùy chỉnh.

Nguồn: [Thông báo runtime Julia trên Colab](https://github.com/googlecolab/colabtools/issues/5151), [quy tắc JULIA_NUM_THREADS phải đặt trước khi Julia khởi động](https://docs.julialang.org/en/v1/manual/environment-variables/), [Julia Pkg environments](https://pkgdocs.julialang.org/v1/environments/), [OpenBLAS runtime variables](https://github.com/OpenMathLib/OpenBLAS/blob/develop/docs/runtime_variables.md), [notebook tái chạy K-means](../../notebook/UD2/experiments/06_tc4_kmeans_colab_reproduction.ipynb), [Manifest.toml](../../Manifest.toml).

## 2. Mở notebook từ README và khóa phiên bản nguồn

**Quyết định** — Dùng ba nút **Open in Colab** trong mục demo, trỏ đến ba tệp notebook ở một ref đã xuất hiện trên GitHub. Cả ba ô khởi tạo khóa cùng một commit mã nguồn đã có trên GitHub, chứa các mô-đun Fashion-MNIST và Eclat, môi trường và cấu hình. Tách ref mở notebook khỏi commit nguồn để tránh việc tệp phải chứa mã băm của chính commit tạo ra nó.

**Lý do** — Khi người đọc mở notebook, phiên Colab chỉ có các ô và nội dung đã lưu. Ô đầu phải đưa mã nguồn và môi trường vào máy chạy. Nếu repo yêu cầu quyền đọc, xác nhận riêng quyền mở notebook và quyền tải mã trong phiên chạy, dùng cơ chế bí mật của Colab cho thông tin xác thực nếu cần.

**Phương án đã cân nhắc** — Tải HEAD của nhánh mỗi lần có thể làm kết quả đổi theo thời điểm. Nhúng đường dẫn máy cá nhân khiến người khác không thể tái lập.

Nguồn: [Open in Colab URL](https://github.com/googlecolab/open_in_colab), [Colab FAQ về tệp trong phiên chạy](https://research.google.com/colaboratory/faq.html).

## 3. Bằng chứng lựa chọn tiền xử lý

**Quyết định** — Notebook đầu xác minh dữ liệu thật và tạo ví dụ vùng ảnh, mặt nạ giữ vùng và vectơ đặc trưng bằng Julia. Dùng bảng khảo sát đã lưu trong tài liệu dự án để giải thích đánh đổi theo kích thước và ngưỡng lọc. Ghi nguồn và phân biệt bảng khảo sát trước đây với các kết quả tính trong phiên. Với so sánh 4×4 và 7×7, đối chiếu ở tỷ lệ vùng bị loại khoảng 39,3%. Với cấu hình sẽ dùng ở notebook 02, dùng hàng giữ vùng có ít nhất một điểm ảnh với mức xám lớn hơn 29.

**Lý do** — Notebook khám phá ảnh cũ đọc các tệp CSV trong thư mục kết quả cục bộ. Một bản clone sạch thiếu các tệp này. Tài liệu đã lưu bảng bằng chứng, gồm 5,92% so với 14,00% mất gradient cho phép so sánh hai kích thước và 37,50% vùng bị loại cùng 4,41% gradient bị mất cho cấu hình ngưỡng đem đi dựng giao dịch. Các ví dụ trực tiếp dùng `extract_patches` và `make_descriptors` trên ảnh đã kiểm định.

**Phương án đã cân nhắc** — Chạy lại toàn bộ khảo sát tiền xử lý sẽ tăng chi phí demo và cần phục hồi định nghĩa gốc của phép đo gradient. Có thể khảo sát riêng khi cần cập nhật các bảng.

Nguồn: [bằng chứng tiền xử lý](../../docs/UD2/TC_plan.md), [notebook khám phá ảnh hiện có](../../notebook/UD2/experiments/01_image_preprocessing_decisions.ipynb), [mã tạo vectơ](../../src/applications/Fashion-Mnist/transaction_construction/descriptors/RawDescriptors.jl).

## 4. Cấu hình dựng giao dịch và trạng thái hội tụ

**Quyết định** — Tạo mã lượt mới, tải và xác minh bốn tệp Fashion-MNIST, tạo tệp kê khai dữ liệu trong notebook 02, rồi dùng cấu hình `release.toml` và chạy bảy bước hiện có. Giữ 70.000 ảnh, 32 cụm, giá trị khởi tạo ngẫu nhiên 123 và dung sai 0,0001. `release.toml` giữ trần 300 vòng; lượt demo Colab ghi đè riêng trần lên 400 để có thể đạt mốc dừng 372 đã quan sát. Lưu giới hạn, số vòng thực tế, trạng thái dừng và trạng thái kiểm định trong các artifact của lượt.

**Lý do** — Bộ dựng giao dịch lưu kết quả chưa hội tụ nếu các tâm cụm hợp lệ và có thể hoàn thành giao dịch khi bước kiểm định cuối đạt. Người dùng cung cấp các mốc Colab khác nhau giữa hai nhánh: `feature/fashion-mnist` dùng trần 300 và dừng ở 139; `complete` dùng trần 3.000 và dừng ở 372. Notebook demo dùng trần 400 để cho phép lượt Colab đi qua vòng 372 nhưng vẫn ghi nhận kết quả thực tế. Các số tập mục ở 5% lần lượt là 7.228 và 7.051; ở 40%, 20%, 10% là 15/174/1.275 và 14/167/1.221. Thời gian ở 5% cũng được đo khác cách: lượt feature ghi Set 13,17 giây, BitVector 8,20 giây; lượt complete là trung vị năm lượt sau warm-up, lần lượt 9,945 và 0,167 giây. Không xem đây là một benchmark cùng điều kiện.

**Phương án đã cân nhắc** — Các cấu hình khảo sát nhiều số cụm và nhiều giá trị khởi tạo sẽ chạy nhiều phép fit. Tự nâng giới hạn vòng lặp làm thay đổi cấu hình thí nghiệm.

Nguồn: [cấu hình phát hành](../../src/applications/Fashion-Mnist/configs/transactions/release.toml), [huấn luyện từ điển](../../src/applications/Fashion-Mnist/transaction_construction/codebook/CodebookTraining.jl), [kiểm định xuất giao dịch](../../src/applications/Fashion-Mnist/transaction_construction/artifacts/CombinedExportValidation.jl). Đối chiếu lịch sử bằng `git show complete:results/fashion/colab_report_20261125/runtime_observations.toml`.

## 5. Bàn giao giữa hai phiên Colab

**Quyết định** — Đóng một gói nén với tệp kê khai demo chứa phiên bản định dạng, mã commit, phiên bản Julia, hai mã định danh lượt chạy và đường dẫn cùng mã băm của hai tệp kê khai gốc và bảng số đo K-means. Giữ nguyên đường dẫn tương đối tính từ thư mục gốc và nội dung các tệp của lượt chạy. Notebook 03 mở gói vào thư mục riêng, xác minh trước khi đọc giao dịch và tải lại bốn tệp ảnh gốc chính thức theo các mã băm đã lưu khi cần truy vết.

**Lý do** — Tệp kê khai kiểm định giao dịch hiện có đã liên kết tám tệp và tệp kê khai dữ liệu bằng SHA-256. Mỗi phiên Colab có hệ thống tệp riêng. Bảng tâm cụm CSV đủ để hiển thị tâm cụm, tệp từ điển nhị phân vẫn được đóng gói để kiểm tra tính toàn vẹn. Đọc bảng gán từ thị giác từng dòng khi tìm vùng ảnh minh họa.

**Phương án đã cân nhắc** — Bắt buộc dùng Drive sẽ thêm quyền truy cập ngoài repo. Sửa đường dẫn trong tệp kê khai sau giải nén làm thay đổi nội dung đã băm. Nạp lại toàn bộ trạng thái Julia từ tệp tuần tự hóa tăng phụ thuộc vào phiên bản và dữ liệu nội bộ.

Nguồn: [định dạng đầu ra hiện tại](../001-fashion-notebook-release/contracts/notebook-artifacts.md), [Julia Tar](https://docs.julialang.org/en/v1/stdlib/Tar/), [Julia Serialization](https://docs.julialang.org/en/v1/stdlib/Serialization/).

## 6. Khai thác và diễn giải trong Julia

**Quyết định** — Dùng `FashionFIMWorkflow.load_transactions` và `EclatFIM.mine` với hai backend ở sáu ngưỡng. Chuyển tỷ lệ sang số đếm bằng `cld(percent * N, 100)`. So sánh trực tiếp hai ánh xạ tập mục sang số ảnh hỗ trợ. Chọn một mẫu theo quy tắc xác định, đếm lại số ảnh bằng phép kiểm tra chứa tập mục, rồi ghép nhãn và vùng ảnh từ gói đã xác minh. Dùng bảng Markdown hoặc SVG do Julia tạo và các thư viện ảnh đã khóa trong dự án để vẽ minh họa.

**Lý do** — Bộ khai thác Julia hiện tại đã giữ cùng giao diện cho hai backend. Bộ bao benchmark phát hành yêu cầu `systemd --user`. Lượt chạy trên nhánh `complete` là bằng chứng tham khảo cho việc gọi Julia trực tiếp. Các ô demo gọi API hiện có của nhánh đang làm. Hai backend có thể trả về 0 tập mục hợp lệ. Lỗi hoặc giới hạn phải hiện thành trạng thái riêng.

**Phương án đã cân nhắc** — Dùng nguyên bộ bao benchmark và diễn giải Python sẽ đưa vào phụ thuộc hệ thống và quy trình đánh giá ngoài phạm vi demo. Chỉ so số lượng tập mục sẽ bỏ sót khác biệt về tập mục hoặc số ảnh hỗ trợ.

Nguồn: [bộ đọc giao dịch](../../src/applications/Fashion-Mnist/mining/TransactionInput.jl), [giao diện Eclat](../../src/algorithm/EclatBaseline.jl), [quy trình benchmark phát hành](../001-fashion-notebook-release/quickstart.md). Đối chiếu điểm chạy lịch sử bằng `git show complete:scripts/fashion_colab_demo.jl`.
