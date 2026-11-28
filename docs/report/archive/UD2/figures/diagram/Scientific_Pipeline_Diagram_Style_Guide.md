# Scientific Pipeline Diagram — Style Guide

> **Mục đích:** Hệ thống hóa phong cách vẽ sơ đồ phương pháp/kiến trúc khoa học rút ra từ hình tham chiếu **EVTransPipeline** do người dùng cung cấp. Tài liệu dùng để thống nhất phong cách thiết kế sơ đồ pipeline và kiến trúc cho báo cáo học thuật, không gắn với một bài toán cụ thể.
>
> **Phạm vi:** Quy chuẩn thiết kế hình, **không** phải mô tả kết quả thực nghiệm hoặc đặc tả thuật toán. Các giá trị màu, kích thước và quy chuẩn đặt tên ở mục “Đề xuất áp dụng” là gợi ý thiết kế; hình tham chiếu không cung cấp mã màu/font/size chính thức.

## 1. Nhận diện phong cách

- **Tên phong cách:** *Scientific Methodology / Model Architecture Diagram*.
- **Ứng dụng:** Sơ đồ pipeline xử lý dữ liệu, kiến trúc mô hình, kiến trúc đa nhánh, sơ đồ phương pháp trong bài báo IEEE/ACM hoặc luận văn.
- **Cảm nhận thị giác:** nền trắng; các khối pastel nhẹ; nhãn rõ ràng; phân tầng chức năng; đường nối gọn; kết hợp biểu diễn dữ liệu thật, minh họa mạng học sâu và ký hiệu toán học.
- **Nguyên tắc trung tâm:** Người đọc phải nhận ra ngay **đầu vào → xử lý → biểu diễn trung gian → đầu ra**, và phân biệt được **các stage, nhánh thay thế, luồng dữ liệu phụ**.

## 2. Những đặc điểm quan sát trực tiếp từ hình tham chiếu

| Yếu tố | Cách hình tham chiếu thể hiện | Ý nghĩa |
|---|---|---|
| Bố cục chính | Luồng ngang trái → phải, kết hợp các mũi tên rẽ nhánh, đi xuống | Thể hiện quan hệ xử lý và phụ thuộc dữ liệu |
| Nhóm chức năng | Khung bo tròn lớn, viền nét đứt; tên nhóm nằm ở phía trên (*Voice Synthesis*, *Face Synthesis*) | Gom nhiều thành phần cùng chức năng |
| Khối xử lý | Hình chữ nhật bo góc, màu pastel, tên đậm; đôi khi có công thức | Module thực hiện phép biến đổi |
| Dữ liệu trung gian | Khối viền đen nét đứt hoặc khung mảnh, thường nền trắng | Trạng thái/biểu diễn được truyền giữa module |
| Dữ liệu đầu vào/đầu ra | Khối có tên, ảnh hoặc waveform minh họa, ký hiệu toán học bên dưới | Cho thấy **kiểu dữ liệu**, không chỉ tên biến |
| Hệ thống nhiều phương án | Hai khung con đánh số `1`, `2` bên trong vùng *Face Synthesis* | Hai **phương án kiến trúc**, không phải hai bước nối tiếp |
| Stage trong mô hình | Nhãn `Stage 01`, `Stage 02` và dấu ngoặc ngang bên dưới | Chia các tiểu giai đoạn của một nhánh |
| Ký hiệu toán học | Ký hiệu in nghiêng, chỉ số dưới/trên: `A_en`, `T_vi`, `F_ASR`, `M_{1:T}` | Liên kết tên khối với định nghĩa khoa học |
| Minh họa nội bộ | Waveform, ảnh khuôn mặt, landmark frames, các khối neural network | Trực quan hóa dữ liệu và chức năng module |
| Hướng mũi tên | Phần lớn mũi tên đen đặc; một số luồng đi ngược/nhánh màu xanh đậm | Phân biệt phụ thuộc hoặc nhánh tín hiệu |

### Lưu ý quan trọng về cách đọc hình

- *Voice Synthesis* là một chuỗi xử lý qua các module ASR → MT → TTS, xen giữa là transcript/intermediate data.
- *Face Synthesis* chứa **hai cách tiếp cận** đặt trên hai hàng: một nhánh landmark/renderer và một nhánh conditional encoder/diffusion. Không được vẽ mũi tên từ hàng 1 xuống hàng 2 như thể đây là chuỗi các bước thực hiện liên tiếp.
- Các khối như `English Transcript`, `Vietnamese Transcript` là **dữ liệu**, không phải module tính toán.

## 3. Hệ thống phân cấp bố cục

### 3.1. Ba mức thông tin

1. **Functional Group / Subsystem:** Vùng chức năng lớn, có đường bao đứt nét và tiêu đề trung tâm ở cạnh trên.
2. **Processing Stage / Module:** Các hộp xử lý bên trong vùng chức năng; có tên module và, nếu phù hợp, ký hiệu phép biến đổi.
3. **Data Representation:** Ảnh, tensor, bảng, vector, waveform, chuỗi khung hình và kết quả trung gian nằm giữa các bước.

### 3.2. Hướng bố trí

- Ưu tiên trục **trái → phải** cho dòng xử lý chính.
- Dùng hướng **trên → dưới** cho việc cung cấp đầu vào phụ, tách nhánh hoặc chuyển từ phân hệ này sang phân hệ khác.
- Dùng **hai hàng song song** khi mô tả các phương án thay thế; ghi rõ nhãn `Approach 1/2`, không gộp thành một pipeline nối tiếp.
- Căn chỉnh tâm module trên cùng một hàng; dùng khoảng cách đều và các đường gấp khúc 90° khi cần đi vòng.
- Tránh đường cắt nhau và tránh để mũi tên đi xuyên qua nhãn hoặc ảnh minh họa.

## 4. Quy tắc hình khối và đường viền

| Loại đối tượng | Hình dạng ưu tiên | Nền | Đường viền | Nội dung |
|---|---|---|---|---|
| Input | Rounded rectangle | Trắng hoặc pastel rất nhẹ | Liền, mảnh | Tên, dữ liệu trực quan, ký hiệu |
| Processing module | Rounded rectangle | Pastel theo nhóm chức năng | Liền, cùng tông nhưng đậm hơn | Tiêu đề đậm, tùy chọn công thức |
| Intermediate data | Rectangle/rounded rectangle | Trắng | Nét đứt | Tên biểu diễn và ký hiệu |
| Final output | Rectangle hoặc rounded rectangle | Trắng | Liền hoặc nét đứt theo vai trò | Hình/giá trị minh họa và tên |
| Functional group | Rounded rectangle kích thước lớn | Trong suốt hoặc trắng | **Nét đứt có màu** | Tên nhóm phía trên |
| Model internals | Các khối đứng, encoder/decoder, hình học đơn giản | Pastel nhạt | Mảnh, liền | Tượng trưng cho module con |
| Stage span | Dấu ngoặc ngang/đường chỉ phạm vi | Không có | Nét mảnh | `Stage 01`, `Stage 02` |

**Không đánh đồng** các hộp dữ liệu trung gian với hộp xử lý. Đặc biệt, một *codebook* hoặc *transaction* là dữ liệu, dù nó nằm giữa các khối xử lý.

## 5. Bảng màu

### 5.1. Vai trò màu quan sát được

- **Xanh lam nhạt:** ASR/TTS và một số khối xử lý.
- **Xanh lá nhạt:** Machine Translation và minh họa dạng vector/feature.
- **Tím lavender:** Time Alignment hoặc mô-đun liên quan.
- **Xanh cyan nhạt:** Vision Feature và phân biệt luồng thông tin hình ảnh.
- **Cam/peach nhạt:** Conditional Encoder/feature blocks.
- **Xám/kem rất nhạt:** Nền của các phương án model lớn.
- **Đen/xám sẫm:** Chữ, khung nội dung và mũi tên chính.

### 5.2. Palette đề xuất để tái tạo (xấp xỉ, không phải mã màu gốc)

| Vai trò | Fill HEX | Stroke HEX |
|---|---|---|
| Blue processing | `#DCE9FB` | `#7B9FD1` |
| Green processing | `#DAE9D4` | `#80B473` |
| Lavender processing | `#E6D9EA` | `#AA87B5` |
| Cyan/vision | `#BEE5F3` | `#369DC3` |
| Peach/model blocks | `#FFE0B9` | `#DE973E` |
| Neutral subpanel | `#F4F4F4` | `#666666` |
| Warm subpanel | `#F9F6ED` | `#777777` |
| Cyan group boundary | `#FFFFFF` | `#26B3BE` |
| Blue group boundary | `#FFFFFF` | `#3C42F5` |

**Quy tắc sử dụng:** Một màu nên có **một ý nghĩa xuyên suốt trong cùng sơ đồ**; không dùng màu tùy ý cho từng module. Không dùng gradient mạnh, đổ bóng dày hoặc nền tối nếu muốn giữ phong cách gốc.

## 6. Typography và hệ thống đặt tên

### 6.1. Typography

- Tiêu đề nhóm: **Bold**, chữ lớn hơn nhãn module, đặt giữa theo cạnh trên của khung nhóm.
- Tên module: **Bold**, ưu tiên 1–3 dòng, căn giữa.
- Dữ liệu trung gian: regular hoặc medium; không dùng cùng trọng lượng với tiêu đề module nếu không cần.
- Ký hiệu toán: math italic với subscript/superscript chuẩn; căn giữa bên dưới tên hoặc ảnh.
- Các nhãn `Stage 01`, `Stage 02` được viết ngắn, đủ để nêu chức năng.
- Ưu tiên font sans-serif (Arial, Helvetica, hoặc tương đương); dùng font toán tương thích LaTeX cho biểu thức.

### 6.2. Quy tắc đặt tên

| Thành phần | Mẫu tên | Ví dụ tham chiếu |
|---|---|---|
| Functional group | Danh từ chỉ tác vụ/đích xử lý | `Voice Synthesis` |
| Processing module | Tên phương pháp hoặc tác vụ | `Automatic Speech Recognition` |
| Data object | Tên kiểu dữ liệu đầu ra | `Vietnamese Transcript` |
| Alternative method | Số thứ tự + tên nhánh | `1`, `2` ở hai subpanel |
| Substage | `Stage 0N: <Function>` | `Stage 02: Appearance Rendering` |
| Mathematical operation | `F_{METHOD}(input)` khi cần | `F_{ASR}(A_{en})` |
| Data variable | Ký hiệu chữ + chỉ số mô tả | `T_{en}`, `A_{vi}`, `V_{ref}` |

**Khuyến nghị:** Đừng cố thêm công thức vào mọi hộp. Chỉ dùng ký hiệu tại các điểm giúp người đọc phân biệt **hàm xử lý** với **đối tượng dữ liệu**.

## 7. Quy tắc ký hiệu toán học

### 7.1. Phân biệt biến và phép xử lý

- **Dữ liệu:** ký hiệu danh từ, ví dụ `I_i`, `P_i`, `X_i`, `T_i`.
- **Phép xử lý:** ký hiệu hàm, ví dụ `F_{patch}`, `F_{desc}`, `F_{assign}`.
- **Mô hình/thuộc tính học được:** một tập/codebook riêng, ví dụ `C={c_1,...,c_K}`.
- **Chuỗi:** chỉ số khoảng `1:T`; dùng dấu `^`/hat cho đầu ra dự đoán nếu đúng ngữ cảnh.

### 7.2. Các quy tắc an toàn về ý nghĩa

- Một biến phải giữ **cùng nghĩa** ở mọi nơi xuất hiện trong hình và chú thích.
- Không gắn `F` vào dữ liệu chỉ để có vẻ học thuật.
- Mũi tên từ `A` sang `B` phải thể hiện đúng phép biến đổi hoặc sự phụ thuộc, không được ngụ ý rằng hai phương án thay thế cùng chạy nối tiếp.
- Trong caption hoặc phần phương pháp, giải thích các ký hiệu không hiển nhiên.

## 8. Mũi tên, luồng dữ liệu và nhánh

- **Solid black arrows:** luồng dữ liệu/xử lý chính.
- **Orthogonal arrows (gấp khúc vuông góc):** luồng phụ cần tránh giao với module.
- **Mũi tên có màu:** chỉ sử dụng cho một luồng đặc biệt, có ý nghĩa nhất quán (chẳng hạn audio/vision branch).
- **Multiple inputs:** dẫn các mũi tên riêng đến cạnh vào của module; không hợp nhất tùy tiện nếu module thực sự yêu cầu cả hai.
- **Dạng nét đứt:** dùng nhất quán cho đường bao nhóm hoặc các data boxes; nếu dùng cho mũi tên thì phải định nghĩa riêng (ví dụ bước downstream ngoài phạm vi).
- **Không thêm số bước lên mũi tên** khi module đã được đánh số đủ rõ.

## 9. Hình ảnh, icon và minh họa dữ liệu

### 9.1. Nguyên tắc từ hình mẫu

Hình tham chiếu kết hợp **tên khối + nội dung minh họa trực quan + ký hiệu**:

- Waveform màu xanh dương → âm thanh.
- Ảnh khung video thực → video đầu vào/đầu ra.
- Dải ảnh mặt → chuỗi frame.
- Landmark mặt → biểu diễn hình học.
- Các thanh màu/khối mô hình → mạng encoder, renderer hoặc dữ liệu đặc trưng.

### 9.2. Quy tắc chọn icon

1. Ưu tiên **minh họa đúng dạng dữ liệu** thay vì biểu tượng trang trí chung chung.
2. Dùng **ảnh thật hoặc output thật** khi diễn giải một kết quả thực nghiệm cụ thể.
3. Dùng **hình sơ đồ đơn giản** (patch grid, vector cells, centroid mosaic) khi chỉ minh họa nguyên lý.
4. Kích thước icon/hình mẫu nhất quán; không để hình lấn sang tên module.
5. Hình chỉ mang tính minh họa phải có nhãn `Illustrative` hoặc chú thích rõ nếu có nguy cơ bị hiểu là output thực.
6. Khi in đen trắng, đảm bảo hình vẫn đọc được qua nhãn, đường viền và hình dạng.

## 10. Quy chuẩn xuất hình cho báo cáo (đề xuất áp dụng)

- **Tỷ lệ:** landscape rộng, ưu tiên 16:9; nếu nhiều stage có thể dùng khung toàn chiều rộng hai cột (*figure\** trong IEEEtran).
- **File gốc:** lưu dạng vector có thể sửa (SVG, PDF vector, PPTX, draw.io hoặc Figma).
- **Xuất bản:** PDF/SVG vector là lựa chọn ưu tiên; PNG chỉ khi cần, xuất đủ sắc nét.
- **Caption:** đặt dưới hình, mô tả **mục tiêu** và **quá trình** của pipeline, không chỉ lặp tên sơ đồ.
- **Font cuối cùng:** đọc được ở kích thước hình đặt trong trang IEEE hai cột.
- **Tránh:** icon stock không liên quan, chữ quá nhỏ, quá nhiều màu, quá nhiều đường chéo/cắt nhau, biến toán học không được định nghĩa.

## 11. Checklist khi duyệt diagram

- [ ] Có tiêu đề/nhóm chức năng rõ ràng.
- [ ] Luồng chính đọc thuận chiều trái → phải hoặc trên → dưới.
- [ ] Khối xử lý và khối dữ liệu trung gian có kiểu viền/nền khác nhau.
- [ ] Các nhánh độc lập hoặc phương án thay thế không bị nối nhầm thành một chuỗi.
- [ ] Mũi tên biểu thị đúng phụ thuộc đầu vào của từng module.
- [ ] Màu pastel có chức năng nhất quán, độ tương phản đủ cao.
- [ ] Tên khối ngắn gọn, công thức/biến không quá dày đặc.
- [ ] Icon và hình minh họa phản ánh đúng kiểu dữ liệu.
- [ ] Ký hiệu được định nghĩa hoặc giải thích trong caption/phần phương pháp.
- [ ] Hình không bị vỡ bố cục ở kích thước trang báo cáo thực tế.
- [ ] File nguồn còn khả năng chỉnh sửa và file xuất đủ sắc nét.

---

**Tóm tắt phong cách:** *Function-group dashed containers + pastel processing blocks + distinct intermediate-data boxes + mathematical labels + representative data thumbnails + directional arrows + explicit stages.*
