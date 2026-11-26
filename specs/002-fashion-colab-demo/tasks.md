---
description: "Danh sách công việc triển khai ba notebook Julia trên Colab CPU"
---

# Tasks: Demo Fashion-MNIST trên Colab CPU

**Đầu vào** — [Đặc tả](spec.md), [mục lục notebook](spec.md#mục-lục-ba-notebook-demo), [kế hoạch](plan.md), [nghiên cứu](research.md), [mô hình dữ liệu](data-model.md), [hợp đồng notebook](contracts/notebook-artifacts.md) và [hướng dẫn nghiệm thu](quickstart.md).

**Nghiệm thu** — Chạy từng notebook trong Colab CPU và thử một gói bàn giao lỗi theo đặc tả. Các bước này dùng notebook và hiện vật của lượt chạy.

**Trạng thái triển khai** — Ba notebook demo và notebook K-means riêng khai báo Julia kernel, các bước xử lý gọi trực tiếp mã Julia và link README đã được viết. T009, T015, T022 và T024 vẫn để mở vì cần chạy nghiệm thu trên Colab CPU sạch; T026 chờ các kết quả này để rà soát cuối. Các notebook mới hiện ở working tree, chưa có trên ref GitHub mà README trỏ tới; cần đưa thay đổi lên ref đó trước khi mở link và nghiệm thu hosted.

## Quy ước đường dẫn và nhãn

Mọi đường dẫn trong checklist tính từ gốc repo. Ba tệp notebook demo nằm ở `notebook/UD2/demo/`. Cả ba notebook demo và notebook K-means riêng dùng Julia kernel và gọi trực tiếp mã Fashion-MNIST/Eclat hiện có; không có Python kernel hoặc Python gọi Julia. Phần triển khai gồm ba notebook demo, notebook Colab tái chạy K-means và `README.md`.

- `[P]` đánh dấu công việc có thể chạy song song sau khi các điều kiện đã nêu hoàn thành.
- `[US1]`, `[US2]` và `[US3]` chỉ luồng người dùng tương ứng trong đặc tả.

## Phase 1 — Chuẩn bị

- [X] T001 Tạo khung theo mục lục đã chốt cho `notebook/UD2/demo/01_image_exploration.ipynb`, `notebook/UD2/demo/02_transaction_construction.ipynb` và `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`. Dùng tên đầy đủ cho các bước xử lý và đặt ô **00 · Khởi tạo Colab CPU** là ô code đầu tiên.

## Phase 2 — Khởi tạo Colab và xác minh phiên bản nguồn

- [X] T002 Kiểm tra commit nguồn đã có trên GitHub từ ref `origin/feature/fashion-mnist-consolidated`. Đối chiếu `Project.toml`, `Manifest.toml`, `src/EclatFIM.jl` và `src/applications/Fashion-Mnist/configs/transactions/release.toml` để khóa một SHA đầy đủ có đủ giao diện và cấu hình.
- [X] T003 Viết ô khởi tạo Julia đầu tiên trong `notebook/UD2/demo/01_image_exploration.ipynb`. Metadata dùng Julia kernel; cell clone và checkout repo theo commit ghim qua `LibGit2`, xác minh SHA thực tế, kích hoạt dự án và gọi `Pkg.instantiate()`. In commit, phiên bản Julia Colab và số thread thực tế. Không cài Julia riêng, gọi Python hoặc gọi Git qua shell.
- [X] T004 [P] Dùng cùng kernel Julia, cách khởi tạo và SHA nguồn của T003 trong `notebook/UD2/demo/02_transaction_construction.ipynb`. Giữ các bước dựng giao dịch trong cùng kernel Julia.
- [X] T005 [P] Dùng cùng kernel Julia, cách khởi tạo và SHA nguồn của T003 trong `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`. Nhận gói giao dịch từ Files panel Colab rồi xác minh và phân tích trực tiếp trong Julia.

**Điểm kiểm tra** — T003–T005 hoàn thành khi ba notebook có cùng SHA nguồn và Julia có thể nạp `EclatFIM` từ dự án vừa tải.

## Phase 3 — US1 · Khám phá dữ liệu ảnh và lựa chọn tiền xử lý (P1, MVP)

**Mục tiêu** — Người xem mở notebook đầu và thấy bằng chứng cho ba lựa chọn tiền xử lý.

**Nghiệm thu độc lập** — Chạy notebook 01 trong phiên Colab CPU mới. Kiểm tra số ảnh của hai tập, hình vùng ảnh trước và sau lọc, phép so sánh kích thước vùng và vectơ đặc trưng 16 chiều.

- [X] T006 [P] [US1] Trong `notebook/UD2/demo/01_image_exploration.ipynb`, tải và xác minh bốn tệp Fashion-MNIST bằng các hàm hiện có của `EclatFIM.FashionMNIST`. Hiển thị nguồn dữ liệu, mã lượt, 60.000 ảnh huấn luyện, 10.000 ảnh kiểm thử, ảnh 28×28, 10 lớp và ảnh mẫu.
- [X] T007 [US1] Trong `notebook/UD2/demo/01_image_exploration.ipynb`, trình bày bằng chứng có nguồn từ `docs/UD2/TC_plan.md` cho hai phép so sánh. So sánh vùng 4×4 với 7×7 ở tỷ lệ loại tương đương, rồi đối chiếu các cấu hình lọc nền để giải thích điều kiện “giữ vùng nếu có điểm ảnh với mức xám lớn hơn 29”. Ghi rõ các bảng dùng số liệu khảo sát đã lưu.
- [X] T008 [US1] Trong `notebook/UD2/demo/01_image_exploration.ipynb`, gọi `FashionTC.extract_patches` và `FashionTC.make_descriptors` trên ảnh đã kiểm định để hiển thị vùng giữ lại, vùng bị loại và vectơ 16 giá trị mức xám chuẩn hóa. Chốt cấu hình chuyển sang notebook 02.
- [ ] T009 [US1] Nghiệm thu `notebook/UD2/demo/01_image_exploration.ipynb` trong Colab CPU sạch theo mục 1 của `specs/002-fashion-colab-demo/quickstart.md`. Xác minh ba lựa chọn đều có bằng chứng và ảnh cùng vectơ minh họa được tạo lại khi chạy.

## Phase 4 — US2 · Dựng giao dịch bằng túi từ thị giác nhị phân (P1)

**Mục tiêu** — Người chạy tạo một bộ giao dịch có thể mang sang phiên Colab khác.

**Nghiệm thu độc lập** — Chạy notebook 02 trên phiên CPU mới, xác minh tệp kê khai báo kiểm định đạt, đếm đúng 70.000 giao dịch và tải được gói cùng mã băm giao dịch.

- [X] T010 [P] [US2] Trong `notebook/UD2/demo/02_transaction_construction.ipynb`, tạo mã lượt mới bằng `new_release_run_id` và tệp kê khai dữ liệu bằng `create_dataset_manifest`. Đọc cấu hình phát hành để xử lý 70.000 ảnh, 32 cụm, giá trị khởi tạo ngẫu nhiên 123 và dung sai 0,0001; giữ `release.toml` ở 300 vòng nhưng ghi đè giới hạn notebook demo lên 400. Ghi cấu hình thực tế và tạo mã lượt khác khi chạy lại với cấu hình đã đổi.
- [X] T011 [US2] Trong `notebook/UD2/demo/02_transaction_construction.ipynb`, gọi `FashionTC.prepare_run` và bảy bước có sẵn từ `run_tc1!` đến `run_tc7!` trong cùng tiến trình Julia. Hiển thị đường đi của một ảnh từ vùng ảnh, lọc nền và vectơ đặc trưng đến từ thị giác và giao dịch nhị phân. Dùng đúng bước trượt 4×4, điều kiện điểm ảnh lớn hơn 29 và vectơ 16 chiều chuẩn hóa.
- [X] T012 [US2] Trong `notebook/UD2/demo/02_transaction_construction.ipynb`, đọc bảng tâm cụm, `tc4_metrics.toml` và kết quả kiểm định để hiển thị giới hạn lặp, số vòng thực tế, cờ hội tụ, trạng thái học và trạng thái kiểm định đầu ra riêng. Chỉ tiếp tục xuất khi đầu ra đạt kiểm định. Giữ trạng thái chưa hội tụ nếu lượt chạm giới hạn và đầu ra hợp lệ.
- [X] T013 [US2] Trong `notebook/UD2/demo/02_transaction_construction.ipynb`, tạo `demo_manifest.toml` ở gốc gói `fashion-demo-<run_id>.tar.gz` bằng `TOML`, `SHA`, `Tar` và `CodecZlib`. Ghi `schema_version = 1`, `run_id`, `tc_run_id`, `source_commit`, `julia_version` và ba bảng `dataset_manifest`, `transaction_manifest`, `fit_metrics` với `path` và `sha256` đúng [hợp đồng](contracts/notebook-artifacts.md#2-gói-xuất-từ-notebook-02).
- [X] T014 [US2] Trong `notebook/UD2/demo/02_transaction_construction.ipynb`, đưa nguyên vẹn hai tệp kê khai, bảng số đo K-means và đủ tám tệp tham chiếu vào gói theo đường dẫn tương đối từ gốc repo. Hiển thị đường dẫn tải gói, mã lượt, số giao dịch và mã băm giao dịch sau khi xuất thành công.
- [ ] T015 [US2] Nghiệm thu `notebook/UD2/demo/02_transaction_construction.ipynb` trong Colab CPU sạch theo mục 2 của `specs/002-fashion-colab-demo/quickstart.md`. Xác minh một dòng cho mỗi ảnh, 70.000 dòng, trạng thái kiểm định đạt và gói tải được. Lưu gói để nghiệm thu US3.

## Phase 5 — US3 · Khám phá giao dịch và khai thác mẫu (P1)

**Mục tiêu** — Người xem phân tích giao dịch của một lượt đã lưu, đối chiếu hai bản Eclat và giải thích ít nhất một mẫu bằng ảnh nguồn khi có kết quả.

**Nghiệm thu độc lập** — Mở gói hợp lệ trong phiên Colab CPU mới, chạy sáu ngưỡng và đối chiếu kết quả. Thử bản sao thiếu hoặc sai tệp để xác minh notebook dừng trước bước khai thác.

- [X] T016 [P] [US3] Trong `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`, nhận đường dẫn gói do người dùng tải lên, kiểm tra danh sách mục rồi giải nén vào thư mục riêng. Chỉ nhận tệp thường và thư mục. Từ chối đường dẫn tuyệt đối, đường dẫn thoát khỏi gốc, đường dẫn trùng và liên kết khi đọc gói hoặc giải các tham chiếu trong tệp kê khai.
- [X] T017 [US3] Trong `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`, xác minh phiên bản định dạng, hai mã lượt, SHA-256, cấu hình, báo cáo kiểm định và ánh xạ ảnh trước khi khai thác bằng đầu vào từ `FashionFIMWorkflow.load_transactions`. Kiểm tra “định danh giao dịch từ 1 đến 70.000” và “Từ thị giác nằm trong 1–32, sắp tăng dần và duy nhất trong một giao dịch”. Giữ nguyên các dòng có nội dung giống nhau và giữ giao dịch rỗng trong mẫu số. Kiểm tra định danh ảnh dạng `train:<chỉ số>` hoặc `test:<chỉ số>`, với chỉ số bắt đầu từ 0 trong mỗi tập. Báo đúng tên tệp hoặc điều kiện lỗi rồi dừng trước khi khai thác.
- [X] T018 [US3] Trong `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`, hiển thị mã lượt, mã băm giao dịch, phân bố độ dài và tần suất từng từ thị giác. Kiểm tra tổng số giao dịch qua các nhóm độ dài và hiển thị cả nhóm giao dịch rỗng nếu có.
- [X] T019 [US3] Trong `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`, gọi `EclatFIM.mine` với `:set` và `:bitvector` trên cùng dữ liệu ở 80%, 60%, 40%, 20%, 10% và 5%. Tính số hỗ trợ tối thiểu bằng `cld(percent * N, 100)`. So sánh toàn bộ ánh xạ tập mục sang số hỗ trợ và trình bày một hàng mỗi ngưỡng. Hiển thị số 0 cho lượt hoàn tất rỗng và trạng thái riêng cho lượt lỗi hoặc chưa hoàn tất.
- [X] T020 [US3] Trong `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`, lấy một mẫu theo quy tắc chọn ở ngưỡng 5% trong [hợp đồng](contracts/notebook-artifacts.md#4-kết-quả-hiển-thị-của-notebook-03). Đếm lại số ảnh hỗ trợ, ghép nhãn và kiểm tra tổng số ảnh hỗ trợ qua 10 lớp. Đọc bảng gán từ thị giác từng dòng cho ảnh đã chọn. Bảng ghi “tọa độ hàng và cột từ 1 đến 7, định danh vùng từ 1 đến 49”. Tải hoặc kiểm định lại ảnh nguồn theo bốn SHA-256 đã ghi, đọc tâm cụm từ `centroids.csv` và dùng Julia để hiển thị vùng ảnh, ảnh hỗ trợ và bảng theo lớp hoặc hệ số làm giàu.
- [X] T021 [US3] Trong `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`, gắn kết quả và hình minh họa với mã lượt cùng mã băm giao dịch. Hiển thị rõ tình huống thiếu mẫu hoặc chưa có đầu ra hợp lệ ở 5%. Kết luận ở mức đồng xuất hiện và phân bố theo lớp trên tập ảnh quan sát.
- [ ] T022 [US3] Nghiệm thu `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb` trong một phiên Colab CPU mới bằng gói hợp lệ và bản sao có tệp thiếu hoặc sai mã băm theo mục 3–4 của `specs/002-fashion-colab-demo/quickstart.md`. Xác minh sáu cặp đối chiếu đều đạt với lượt đầy đủ, một mẫu truy được về ảnh nguồn, và bản lỗi bị chặn trước khi khai thác.

## Phase 6 — README và nghiệm thu chung

- [X] T025 Chuyển `notebook/UD2/experiments/06_tc4_kmeans_colab_reproduction.ipynb` sang Julia kernel, dùng trực tiếp pipeline FashionTC hiện có để tạo descriptor và chạy một fit TC4. Giữ `max_iterations = 400`, yêu cầu BLAS một luồng và `OPENBLAS_CORETYPE=Haswell`, lưu phiên bản Julia cùng số thread thực tế trong run summary, và ghi rõ đây là cấu hình tái chạy khác với profile phát hành 300 vòng. Trỏ link thí nghiệm trong README đến ref chứa phiên bản cập nhật.

- [X] T023 Trong `README.md`, gắn đúng ba nút **Open in Colab** theo thứ tự cho `notebook/UD2/demo/01_image_exploration.ipynb`, `notebook/UD2/demo/02_transaction_construction.ipynb` và `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`. Dùng ref GitHub chứa notebook. Đặt link notebook tái chạy K-means riêng ở mục thí nghiệm nếu README đang đặt nó trong mục demo.
- [ ] T024 Mở ba notebook demo và notebook tái chạy K-means từ `README.md` trên Colab Julia CPU. Nghiệm thu luồng giao dịch theo `specs/002-fashion-colab-demo/quickstart.md`; xác minh mọi code cell chạy trong Julia kernel, snapshot K-means dùng giới hạn 400, ghi môi trường BLAS Haswell/một luồng cùng số thread Julia thực tế, và lưu số vòng thực tế trong run summary. Đối chiếu commit, phiên bản Julia, gói 70.000 giao dịch, mã băm xuyên suốt giữa notebook 02 và 03, sáu ngưỡng và hình mẫu.
- [ ] T026 Rà phạm vi thực hiện theo `specs/002-fashion-colab-demo/plan.md` trước khi bàn giao. Kiểm tra Julia kernel metadata, không có code cell Python, tên đầy đủ các mục, điểm vào từ `README.md`, kết quả nghiệm thu và phạm vi tệp triển khai gồm ba notebook demo, notebook K-means đã cập nhật và README.

## Phụ thuộc và thứ tự thực hiện

- T001 → T002 → T003 → T004 và T005. Hoàn tất khởi tạo trước khi nối phần xử lý của từng notebook.
- US1 và US2 độc lập khi chạy. Notebook 02 chuẩn bị và xác minh dữ liệu của mình. Notebook 01 cung cấp cách giải thích cấu hình đã chốt.
- US3 có thể viết phần nhập và phân tích dựa trên hợp đồng đã chốt. T022 cần gói hợp lệ theo hợp đồng. Dùng gói của T015 khi nghiệm thu toàn bộ.
- T023 cần đủ ba notebook demo có thể mở từ GitHub. T024 cần T025, các link từ T023 và bàn giao thực từ notebook 02 sang notebook 03. T026 hoàn tất sau nghiệm thu.

## Ví dụ chạy song song

| Luồng | Việc có thể thực hiện cùng luồng khác sau khi khởi tạo |
| --- | --- |
| US1 | T006–T008 trên `notebook/UD2/demo/01_image_exploration.ipynb`. |
| US2 | T010–T014 trên `notebook/UD2/demo/02_transaction_construction.ipynb`. T010 có thể bắt đầu cùng T006. |
| US3 | T016–T021 trên `notebook/UD2/demo/03_transaction_exploration_and_mining.ipynb`. T016 có thể bắt đầu cùng T006 và T010. Chạy dữ liệu thật sau khi có gói hợp lệ. |

Trong từng notebook, làm các việc theo thứ tự mã công việc. T004 và T005 có thể thực hiện song song sau khi T003 hoàn thành.

## Chiến lược triển khai

1. **MVP** — Hoàn thành US1 để xem cách Colab mở repo và minh họa ba quyết định tiền xử lý. Có thể nghiệm thu từ link của riêng notebook 01 trước khi hoàn thành mục demo đầy đủ.
2. **Bàn giao dữ liệu** — Hoàn thành US2 và xác minh có gói dùng được từ phiên mới.
3. **Demo đầy đủ** — Hoàn thành US3, mở đủ ba notebook từ README và dùng cùng gói để trình bày kết quả trong notebook cuối.
