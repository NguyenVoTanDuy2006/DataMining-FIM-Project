# Implementation Plan: Demo Fashion-MNIST trên Colab CPU

**Branch**: `feature/fashion-mnist` | **Date**: 2026-11-26 | **Spec**: [spec.md](spec.md)

**Input**: [Đặc tả và mục lục ba notebook](spec.md#mục-lục-ba-notebook-demo)

## Summary

Đưa ba notebook Julia lên README để người xem có thể mở trực tiếp trong Colab CPU. Mỗi notebook khởi tạo từ cùng một phiên bản mã nguồn. Notebook 01 trình bày lựa chọn tiền xử lý, notebook 02 tạo và đóng gói giao dịch, notebook 03 mở gói trong phiên mới để so sánh hai bản Eclat và truy một mẫu về ảnh nguồn. Tên mục trong notebook dùng đầy đủ tên bước như mục lục đã chốt.

## Technical Context

- **Ngôn ngữ và môi trường** — Dùng Julia kernel gốc của Colab. Mọi ô code và xử lý chạy trực tiếp trong kernel; không có Python kernel hoặc Python gọi Julia. Mỗi notebook dùng `EclatFIM`, `Clustering`, `TOML`, `SHA`, `Tar`, `CodecZlib`, `PNGFiles` và `ColorTypes` từ môi trường của repo.
- **Nền tảng** — Phiên Colab do Google quản lý, CPU, Linux x86_64. Ô đầu xác minh commit nguồn, kích hoạt `Project.toml`/`Manifest.toml` và gọi `Pkg.instantiate()` trong Julia kernel. Phiên bản Julia do runtime Colab cung cấp được in và lưu cùng kết quả. Notebook giới hạn BLAS ở một luồng và yêu cầu `OPENBLAS_CORETYPE=Haswell`. `JULIA_NUM_THREADS` chỉ có hiệu lực trước khi khởi động kernel; notebook ghi số luồng thực tế thay vì giả định ô khởi tạo đổi được cấu hình đã chạy.
- **Dữ liệu** — 60.000 ảnh huấn luyện và 10.000 ảnh kiểm thử. Vùng ảnh 4×4, giữ khi có điểm ảnh lớn hơn 29, vectơ 16 chiều, 32 cụm, giá trị khởi tạo ngẫu nhiên 123 và dung sai 0,0001. `release.toml` giữ giới hạn 300 vòng; notebook 02 ghi đè riêng trần lặp lên 400 vòng cho lượt demo Colab và ghi giá trị thực tế vào artifact.
- **Lưu trữ** — Thư mục cục bộ cho mỗi lượt, gói `.tar.gz` và tệp kê khai có SHA-256. Lượt phân tích đọc gói một cách độc lập với phiên dựng giao dịch. Bộ dữ liệu tải từ nguồn chính thức khi cần.
- **Quy mô và hiệu năng** — Xác minh luồng đầy đủ trên 70.000 ảnh với sáu ngưỡng. Mỗi ngưỡng chỉ giữ kết quả của cặp backend đang đối chiếu, cộng với tập ứng viên cần cho phần minh họa. Duyệt bảng gán từ thị giác từng dòng để tìm vùng minh họa. Thời gian được ghi theo lần chạy, chưa đặt cam kết thời lượng Colab.
- **Kiểm chứng** — Nghiệm thu bằng ba link từ README, một lượt dựng đầy đủ, một phiên mới mở gói và một lần kiểm tra gói thiếu hoặc sai tệp. Xem [quickstart.md](quickstart.md).

## Constitution Check

**Trước nghiên cứu** — `.specify/memory/constitution.md` là mẫu chưa điền. Kế hoạch áp dụng hướng dẫn của [AGENTS.md](../../AGENTS.md) và [kế hoạch dự án](../../docs/plan.md). Dùng lại thuật toán, giữ giao diện giao dịch và số hỗ trợ, lưu thông tin tái lập và dùng bộ dữ liệu thật ở ngoài Git.

**Sau thiết kế** — Ba notebook gọi các giao diện Julia hiện có. Ô bàn giao dùng thư viện nén và kiểm tra mã băm của dự án trên đầu ra đã tạo. Định dạng phát hành và giao diện Eclat được dùng nguyên bản. Kế hoạch yêu cầu chạy Colab sạch trước khi nghiệm thu. Các quyết định đều có phương án trong [research.md](research.md).

## Project Structure

### Documentation (this feature)

```text
specs/002-fashion-colab-demo/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── notebook-artifacts.md
└── checklists/
    └── requirements.md
```

### Tệp triển khai demo

```text
README.md
notebook/
└── UD2/
    ├── demo/
    │   ├── 01_image_exploration.ipynb
    │   ├── 02_transaction_construction.ipynb
    │   └── 03_transaction_exploration_and_mining.ipynb
    └── experiments/
        └── 06_tc4_kmeans_colab_reproduction.ipynb # cập nhật cấu hình tái chạy Colab
```

**Structure Decision** — Phạm vi triển khai gồm ba notebook demo, link trong README và chuyển notebook Colab tái chạy K-means hiện có sang Julia kernel. Tất cả bốn notebook gọi trực tiếp `EclatFIM.FashionMNIST` và các giao diện Julia của commit đã tải. Các ô Julia giữ cấu hình, thứ tự gọi hàm, thao tác tải hoặc mở gói và phần trình bày. Dùng `Tar`, `CodecZlib`, `TOML` và `SHA` cho thao tác bàn giao ngay trong notebook.

## Phase 0 — Research

Chốt cách gọi Julia từ Colab, khóa phiên bản nguồn, nguồn bảng so sánh tiền xử lý, cách giữ trạng thái hội tụ, định dạng bàn giao và giao diện Eclat. Xem [research.md](research.md).

## Phase 1 — Design & Contracts

| Notebook | Phần mã dùng lại | Nội dung và đầu ra |
| --- | --- | --- |
| 01 · Khám phá dữ liệu ảnh và lựa chọn tiền xử lý | `download_fashion_mnist`, `load_fashion_mnist`, `FashionTC.extract_patches`, `FashionTC.make_descriptors` | Bảng khảo sát đã lưu kèm nguồn, ảnh mẫu và vectơ tính trên dữ liệu đã kiểm định, cấu hình tóm tắt cho notebook 02. |
| 02 · Dựng giao dịch bằng túi từ thị giác nhị phân | `create_dataset_manifest`, `FashionTC.prepare_run`, các hàm dựng và kiểm định giao dịch hiện có | Một tiến trình Julia tạo gói giao dịch, tệp kê khai và ví dụ trực quan. Báo trạng thái K-means và trạng thái kiểm định đầu ra riêng. |
| 03 · Khám phá giao dịch và khai thác mẫu | `FashionFIMWorkflow.load_transactions`, `EclatFIM.mine`, ánh xạ ảnh và bảng gán từ thị giác | Xác minh gói, xem độ dài giao dịch và tần suất từ thị giác, đối chiếu sáu ngưỡng và tạo minh họa có nguồn gốc từ lượt đang phân tích. |

Notebook 02 tự chuẩn bị dữ liệu và giữ các lời gọi dựng giao dịch trong cùng một tiến trình Julia. Notebook 03 cần gói của notebook 02, chạy được trong phiên khác và dùng lại từ điển đã lưu. Các ô thống kê và minh họa đọc các tệp đầu ra hiện có để tạo bảng và hình. Thiết kế bàn giao, các trường dữ liệu và trạng thái được mô tả trong [data-model.md](data-model.md) và [hợp đồng notebook](contracts/notebook-artifacts.md).

## Trình tự tích hợp

1. Chọn commit nguồn đã có trên GitHub chứa các giao diện Fashion-MNIST và Eclat cần dùng. Dùng cùng cách khởi tạo và cùng commit nguồn cho các notebook Colab.
2. Viết các ô Julia gọi hàm hiện có, mở hoặc đóng gói kết quả và trình bày theo mục lục. Kiểm tra gói có thể chuyển sang phiên mới.
3. Gắn ba nút **Open in Colab** trong README vào ref chứa bộ notebook trên GitHub, giữ link notebook tái chạy K-means ở mục thí nghiệm và nghiệm thu theo [quickstart.md](quickstart.md).
