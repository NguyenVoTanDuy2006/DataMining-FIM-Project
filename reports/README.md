# Báo cáo nhóm — Eclat bằng Julia

Điểm biên dịch chung là `main.tex`; bản đọc đặt tại
[`../docs/Report.pdf`](../docs/Report.pdf). Đây là bản thảo đủ ba chương,
chưa phải bản nộp đã khóa số liệu. PDF hiện có 10 trang chính, một trang
tài liệu tham khảo và một trang phụ lục.

## Nội dung và nguồn

- Chương I dùng `../docs/report_tv1/algorithm.tex`: thuật toán Eclat,
  tính đúng đắn, Set/BitVector, tối ưu và độ phức tạp.
- Chương II dùng `sections/benchmarks.tex`: thiết kế bốn nhóm thí nghiệm,
  bảng/khung hình chờ số liệu, cùng correctness đã kiểm chứng.
- Chương III.A dùng `../docs/report_tv2/groceries.tex`: kết quả Groceries
  từ CSV đã lưu, top-10 luật và diễn giải.
- Chương III.B dùng `sections/fashion_mnist.tex`: pipeline 70k, hợp đồng
  release, audit, selection, enrichment và giới hạn. Hình pipeline lấy từ
  `figures/fashion/TC_pipeline.pdf`; đây là sơ đồ phương pháp, có nguồn
  chỉnh sửa tại `figures/fashion/source/TC_pipeline.drawio`.
- `references.tex` là bibliography chung. Tên tác giả trên trang đầu hiện
  dùng tên đã có trong Project/README; bổ sung họ tên/MSSV khi chốt metadata.

Nguồn các phần riêng được dùng trực tiếp để tránh nhân đôi nội dung. Các
wrapper/PDF TV1 và TV2 là bản xem riêng/lịch sử; không dùng chúng thay
điểm biên dịch chung. Báo cáo không phụ thuộc thư mục `reports/UD2` cũ.

## Số liệu còn chờ

Dấu `—` trong bảng là chưa điền số liệu, không phải 0 hoặc trạng thái lỗi.
Các khung hình chờ không chứa đường dữ liệu giả. Khi đo xong, cập nhật
đồng thời bảng, hình, nhận xét, cấu hình máy, số lượt và nguồn CSV/hash.

- Runtime/RAM/scalability/độ dài ở Chương II chưa nhập số đo hiệu năng cũ
  hoặc mới. Cấu hình, số giao dịch, dải minsup và công thức đã điền.
- Correctness trên năm CSDL và log 569 assertions là bằng chứng kiểm thử
  đã lưu; không phải số mẫu hiệu năng.
- Groceries giữ số liệu đã có, không phải ô chờ benchmark.
- Kết quả Fashion 70k, parity, RSS và mẫu đại diện để trống. Lần chạy mới
  trên Colab chưa hoàn tất; demo 1.000 ảnh không thay full run.
- Số 7.228 và các hình kết quả Fashion cũ không được nhập như kết quả
  mặc định. Nếu dùng lại, phải nêu rõ run và xác nhận transaction hash.
- Nếu dùng full demo thay bộ bốn notebook release, ghi đúng phạm vi:
  demo không đo Peak RSS Fashion và không dùng selector release.

Chưa gộp số đo từ các máy hoặc từ những phạm vi đồng hồ khác nhau.

## Biên dịch

Cần XeLaTeX, các package trong preamble, font Times New Roman, Arial,
Noto Sans Mono và TeX Gyre Termes. Dùng bản IEEEtran có sẵn tại
`../docs/IEEEtran.cls`, giữ nguyên giấy phép LPPL trong file.

Từ repo root:

```sh
mkdir -p /tmp/eclat-full-report
cd reports
TEXINPUTS=../docs: xelatex -interaction=nonstopmode -halt-on-error -jobname=Report -output-directory=/tmp/eclat-full-report main.tex
TEXINPUTS=../docs: xelatex -interaction=nonstopmode -halt-on-error -jobname=Report -output-directory=/tmp/eclat-full-report main.tex
cp /tmp/eclat-full-report/Report.pdf ../docs/Report.pdf
```

Chạy từ `reports/` vì các input và đường dẫn hình phân giải từ đây. Log,
aux và hình kiểm tra PDF nằm ngoài repo. Sau khi đổi bố cục hoặc điền số
liệu, kiểm tra lại số trang chính theo giới hạn 10–15 trang của đề bài.
