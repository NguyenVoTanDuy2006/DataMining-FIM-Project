# Feature Specification: Demo Fashion-MNIST trên Colab CPU

**Feature Branch**: `feature/fashion-mnist`

**Created**: 2026-11-26

**Status**: Draft

**Input**: Viết ba notebook demo Fashion-MNIST bằng Julia, chạy trên Google Colab CPU và mở trực tiếp từ README. Notebook dùng mã nguồn của dự án tải từ GitHub khi khởi tạo.

## User Scenarios & Testing

### User Story 1 - Mở demo từ README và hiểu cách chuẩn bị ảnh (Priority: P1)

Là người xem demo, tôi muốn mở notebook khám phá dữ liệu ảnh từ README và xem bằng chứng cho các quyết định tiền xử lý được dùng ở bước dựng giao dịch.

**Why this priority**: Đây là điểm vào của demo và giải thích vì sao ảnh được biểu diễn theo cách mà những bước sau sử dụng.

**Independent Test**: Mở notebook khám phá dữ liệu ảnh từ README trên một phiên Colab CPU mới, chạy từ đầu và đối chiếu cấu hình hiển thị với các bảng và hình trong notebook.

**Acceptance Scenarios**:

1. **Given** người xem có quyền đọc repo, **When** họ mở notebook khám phá dữ liệu ảnh từ README, chọn runtime Julia CPU và chạy ô khởi tạo, **Then** mã nguồn được tải theo commit đã ghim, môi trường dự án được khởi tạo và các ô Julia tiếp theo chạy trong cùng kernel.
2. **Given** dữ liệu ảnh đã được tải và kiểm định, **When** người xem chạy phần khám phá dữ liệu, **Then** họ thấy ảnh mẫu, so sánh kích thước vùng ảnh và ngưỡng lọc nền, cùng một ví dụ chuyển vùng ảnh thành vectơ đặc trưng 16 chiều. Notebook ghi rõ cấu hình được dùng ở bước tiếp theo.

### User Story 2 - Tạo giao dịch và mang kết quả sang phiên khác (Priority: P1)

Là thành viên chạy thực nghiệm, tôi muốn thấy cách một ảnh trở thành một giao dịch và lưu kết quả đầy đủ để có thể phân tích lại sau.

**Why this priority**: Bộ giao dịch là đầu vào của Eclat. Lưu kết quả theo lượt chạy giúp chạy lại phần phân tích mà không phải fit từ điển lần nữa.

**Independent Test**: Mở notebook dựng giao dịch trên một phiên Colab CPU mới, chạy toàn bộ từ bước khởi tạo và kiểm định dữ liệu đến lúc có gói kết quả để tải xuống.

**Acceptance Scenarios**:

1. **Given** một phiên sạch, **When** người chạy mở notebook dựng giao dịch và chạy từ đầu, **Then** notebook xác minh dữ liệu, hiển thị ví dụ ảnh → vùng ảnh → từ thị giác → giao dịch, và báo số vòng cùng trạng thái dừng thực tế của K-means.
2. **Given** quy trình dựng và kiểm định giao dịch đã hoàn tất, **When** người chạy xuất gói kết quả, **Then** gói có manifest và các tệp cần để notebook sau đọc giao dịch và truy vết mẫu về ảnh.

### User Story 3 - Khai thác và giải thích mẫu từ giao dịch đã lưu (Priority: P1)

Là người xem demo, tôi muốn so sánh kết quả của hai bản cài đặt Eclat trên cùng bộ giao dịch và thấy ít nhất một mẫu gắn với ảnh cụ thể.

**Why this priority**: Đây là phần cho thấy ứng dụng của Eclat và mối liên hệ giữa mẫu tìm được với ảnh nguồn.

**Independent Test**: Mở notebook khám phá giao dịch từ README trong phiên Colab CPU khác, cung cấp gói giao dịch hợp lệ và chạy các ô phân tích.

**Acceptance Scenarios**:

1. **Given** một gói giao dịch hợp lệ, **When** người xem chạy notebook khám phá giao dịch, **Then** họ thấy phân bố độ dài giao dịch, kết quả Set và BitVector ở sáu ngưỡng hỗ trợ, và kết quả đối chiếu tập mục lẫn số ảnh hỗ trợ ở từng ngưỡng.
2. **Given** có tập mục đạt ngưỡng, **When** người xem mở phần diễn giải, **Then** ít nhất một mẫu được nối về vùng ảnh hoặc ảnh hỗ trợ từ chính lượt chạy đó, kèm độ hỗ trợ và phân bố theo lớp.

### Edge Cases

- Nếu không truy cập được repo hoặc tải dữ liệu thất bại, notebook chỉ ra bước bị lỗi và cách thử lại. Các ô phụ thuộc dừng với thông báo rõ ràng.
- Nếu phiên Colab đã hết hoặc mất tệp cục bộ, notebook 03 nhận gói giao dịch đã lưu từ phiên trước.
- Nếu gói giao dịch thiếu tệp, sai mã kiểm tra toàn vẹn hoặc chứa tệp từ nhiều lượt chạy, notebook 03 báo tệp cần kiểm tra và dừng trước khi khai thác.
- Nếu K-means chạm giới hạn lặp, notebook 02 phân biệt trạng thái đó với hội tụ và áp dụng điều kiện hoàn tất của pipeline hiện tại. Người chạy có thể cấu hình lại giới hạn trước khi chạy lại. Manifest của lượt mới phải ghi giá trị đã dùng.
- Nếu một ngưỡng trả về 0 tập mục, notebook 03 hiển thị 0 cho lượt hoàn tất. Lượt lỗi hoặc chưa hoàn tất có trạng thái riêng và không được tính là đối chiếu đạt.

## Requirements

### Functional Requirements

- **FR-001**: README phải có đúng ba link **Open in Colab** trong mục demo Fashion-MNIST, theo thứ tự khám phá dữ liệu ảnh, dựng giao dịch, rồi khám phá giao dịch và khai thác mẫu.
- **FR-002**: Cả ba notebook phải chạy được từ một phiên Google Colab CPU mới với quyền đọc repo. Mỗi notebook phải khai báo Julia kernel; mọi ô code, xử lý và phân tích đều chạy trực tiếp bằng Julia trong kernel này. Ô khởi tạo đầu tiên tải repo theo một commit xác định, kích hoạt môi trường dự án và chạy `Pkg.instantiate()`. Notebook không dùng Python kernel hoặc Python để khởi chạy Julia. Quy trình demo phải chạy được khi môi trường không có `systemd --user`.
- **FR-003**: Notebook khám phá dữ liệu ảnh phải trình bày bằng chứng cho ba lựa chọn dùng ở bước sau gồm vùng ảnh 4×4, quy tắc giữ vùng nếu có điểm ảnh với mức xám lớn hơn 29 và vectơ đặc trưng gồm 16 giá trị mức xám chuẩn hóa.
- **FR-004**: Notebook dựng giao dịch phải xác minh đầu vào và dựng giao dịch dạng túi từ thị giác nhị phân bằng quy trình bảy bước hiện có. Cấu hình tham chiếu dùng toàn bộ 70.000 ảnh, 32 cụm và giá trị khởi tạo ngẫu nhiên 123. Notebook đọc cấu hình phát hành, ghi đè riêng giới hạn K-means lên 400 vòng cho lượt demo Colab, và hiển thị cả giá trị cấu hình, số vòng quan sát được cùng trạng thái dừng. Cấu hình `release.toml` không bị thay đổi.
- **FR-005**: Notebook dựng giao dịch phải xuất gói có thể mở lại trong phiên khác. Tệp kê khai (manifest) phải ghi mã lượt chạy, cấu hình và mã kiểm tra toàn vẹn của các tệp đầu vào cho notebook 03, bao gồm giao dịch, từ điển thị giác và thông tin truy vết ảnh hoặc vùng ảnh. Notebook 03 phải xác minh gói trước khi sử dụng.
- **FR-006**: Notebook 03 phải hiển thị phân bố độ dài giao dịch và chạy Set, BitVector trên cùng đầu vào ở các ngưỡng 80%, 60%, 40%, 20%, 10% và 5%. Với mỗi cặp hoàn tất, notebook phải đối chiếu toàn bộ tập mục và số giao dịch hỗ trợ rồi hiển thị kết quả theo ngưỡng.
- **FR-007**: Notebook 03 phải minh họa ít nhất một mẫu khi có kết quả đủ điều kiện, với bằng chứng ảnh, độ hỗ trợ và phân bố theo lớp hoặc hệ số làm giàu. Các bảng và hình kết quả phải truy về lượt chạy đang phân tích. Kết luận giới hạn ở đồng xuất hiện và phân bố theo lớp trên tập ảnh quan sát.
- **FR-008**: Các notebook phải ghi nguồn dữ liệu, phiên bản mã nguồn, cấu hình liên quan và mã lượt chạy tương ứng. Đường dẫn cần thiết để chạy phải dùng được trong phiên Colab mới mà không cần thư mục cá nhân từ máy người viết.
- **FR-009**: Notebook 03 phải nêu rõ các mốc tham chiếu đã ghi nhận giữa hai nhánh `feature/fashion-mnist` và `complete`, phân biệt cấu hình giới hạn K-means và cách đo thời gian Eclat, đồng thời ghi rõ đầu ra của lượt đang chạy mới là kết quả cần đọc từ artifact.

### Key Entities

- **Cấu hình tiền xử lý** — kích thước vùng ảnh, quy tắc giữ vùng và cách biểu diễn mức xám.
- **Lượt dựng giao dịch** — phạm vi ảnh, cấu hình K-means, trạng thái dừng, từ điển và giao dịch.
- **Gói bàn giao** — manifest và các tệp cần để xác minh giao dịch và truy vết mẫu trong một phiên khác.
- **Kết quả khai thác** — ngưỡng hỗ trợ, tập mục, số ảnh hỗ trợ, trạng thái đối chiếu và hình minh họa gắn với lượt dựng giao dịch.

### Mục lục ba notebook demo

Mỗi notebook bắt đầu bằng **00 · Khởi tạo runtime Julia CPU**. Colab cung cấp Julia kernel; ô code đầu tải repo theo commit đã chọn và khởi tạo dependency của dự án ngay trong kernel đó. Notebook ghi phiên bản Julia thực tế do Colab cung cấp.

#### Notebook 01 — Khám phá dữ liệu ảnh và lựa chọn tiền xử lý

1. **Kiểm tra dữ liệu Fashion-MNIST** — xác minh nguồn, kích thước, số ảnh ở tập huấn luyện và tập kiểm thử, rồi hiển thị ảnh mẫu.
2. **Chọn kích thước vùng ảnh** — so sánh lưới 4×4 và 7×7 bằng tỷ lệ gradient mất đi khi loại số vùng tương đương.
3. **Chọn ngưỡng lọc nền** — xem các vùng được giữ và bị loại, rồi đối chiếu tỷ lệ vùng bị loại và lượng gradient giữ lại để giải thích ngưỡng 29.
4. **Tạo vectơ đặc trưng và tóm tắt cấu hình** — chuyển một vùng ảnh 4×4 thành vectơ 16 giá trị mức xám chuẩn hóa và ghi cấu hình dùng ở notebook 02.

#### Notebook 02 — Dựng giao dịch bằng túi từ thị giác nhị phân

1. **Xác minh dữ liệu và cấu hình lượt chạy** — hiển thị số ảnh, cấu hình tiền xử lý, số cụm, giá trị khởi tạo ngẫu nhiên và giới hạn lặp.
2. **Chia vùng ảnh, lọc nền và tạo vectơ đặc trưng** — minh họa trên một ảnh và hiển thị tổng số vùng giữ lại.
3. **Học từ điển thị giác bằng K-means** — hiển thị các tâm cụm, số vòng thực tế và trạng thái dừng.
4. **Gán từ thị giác và tạo giao dịch** — gán mỗi vùng ảnh vào tâm gần nhất và tạo tập từ thị giác xuất hiện trong ảnh.
5. **Kiểm định và xuất gói giao dịch** — kiểm tra số giao dịch, xuất tệp kê khai và các tệp cần để khai thác và truy vết ảnh ở notebook 03.

#### Notebook 03 — Khám phá giao dịch và khai thác mẫu

1. **Mở và xác minh gói giao dịch** — đọc tệp kê khai, kiểm tra các tệp đầu vào và hiển thị mã lượt dựng giao dịch.
2. **Khám phá bộ giao dịch** — xem phân bố độ dài giao dịch và tần suất xuất hiện của các từ thị giác.
3. **Khai thác và đối chiếu Eclat** — chạy Set và BitVector ở sáu ngưỡng, xem số tập mục và kiểm tra tập mục cùng số ảnh hỗ trợ.
4. **Diễn giải mẫu bằng ảnh** — chọn ít nhất một mẫu từ lượt chạy, truy về vùng ảnh và ảnh hỗ trợ, rồi xem độ hỗ trợ và phân bố theo lớp hoặc hệ số làm giàu.
5. **Kết luận về mẫu đồng xuất hiện** — tóm tắt quan sát và giới hạn của túi từ thị giác nhị phân khi diễn giải cấu trúc ảnh.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Một người có quyền đọc repo mở đủ 3 notebook từ README và hoàn tất luồng demo bằng CPU trong một buổi chạy kiểm chứng. Phiên ban đầu không có sẵn dự án hoặc dữ liệu của người phát triển.
- **SC-002**: Notebook khám phá dữ liệu ảnh cung cấp ít nhất một bảng, hình hoặc ví dụ cho mỗi lựa chọn trong ba lựa chọn tiền xử lý đã chốt.
- **SC-003**: Với lượt đầy đủ hoàn tất, notebook 02 xuất đúng 70.000 giao dịch, một dòng cho mỗi ảnh. Notebook 03 dùng gói đó trong một phiên mới mà không phải fit lại từ điển.
- **SC-004**: Trên lượt kiểm chứng đầy đủ, cả 6 ngưỡng đều có kết quả đối chiếu và toàn bộ cặp tập mục cùng số ảnh hỗ trợ khớp. Người xem có thể truy vết ít nhất một mẫu đã báo cáo về ảnh nguồn.
- **SC-005**: Trong lần kiểm tra với một gói có tệp bị sửa hoặc bị thiếu, notebook 03 chỉ rõ lỗi xác minh trước khi tạo bảng kết quả.

## Assumptions

- Người chạy có kết nối mạng, quyền đọc phiên bản GitHub được tham chiếu và một phiên Colab CPU có đủ tài nguyên cho lượt kiểm chứng.
- Phạm vi triển khai gồm ba notebook demo, các link trong README và điều chỉnh notebook Colab tái chạy K-means hiện có theo giới hạn 400 vòng cùng môi trường BLAS đã ghim. Notebook demo gọi trực tiếp các hàm Fashion-MNIST và Eclat hiện có. Các ô dùng để chọn cấu hình, gọi hàm, chuyển gói giữa phiên và trình bày kết quả.
- Notebook khám phá dữ liệu ảnh tập trung vào quyết định tiền xử lý. Notebook khám phá giao dịch phân tích bộ giao dịch đã dựng. Notebook tái chạy K-means riêng cũng dùng Julia kernel và gọi pipeline FashionTC hiện có. Khảo sát nhiều số cụm, mã hóa không gian, lượng tử hóa, đo bộ nhớ ở cấp hệ điều hành và phân loại ảnh nằm ngoài phạm vi demo này.
- Cấu hình hiện tại của nhánh `feature/fashion-mnist` là điểm xuất phát; `release.toml` giữ giới hạn K-means 300 vòng. Notebook demo ghi đè riêng giới hạn này lên 400 vòng để có thể chạy đến mốc 372 vòng đã quan sát trên Colab. Số vòng và trạng thái thực tế luôn lấy từ artifact, vì các CPU và nhánh mã khác nhau có thể tạo sai khác số học.
