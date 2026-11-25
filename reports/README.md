# Báo cáo nhóm — Eclat bằng Julia

Điểm biên dịch chung là `main.tex`; bản đọc đặt tại
[`../docs/Report.pdf`](../docs/Report.pdf). Báo cáo gồm đủ ba chương, đã
được biên tập theo văn phong học thuật. Tài liệu tham khảo và phụ lục nối tiếp
nội dung chính, không ép mỗi phần sang trang riêng.

## Nội dung và nguồn

- Chương I dùng `../docs/report_tv1/algorithm.tex`: thuật toán Eclat,
  tính đúng đắn, Set/BitVector, tối ưu và độ phức tạp.
- Chương II dùng `sections/benchmarks.tex`: thiết kế, bảng và biểu đồ bốn
  nhóm thí nghiệm Colab, cùng correctness đã kiểm chứng.
- Chương III.A dùng `../docs/report_tv2/groceries.tex`: kết quả Groceries
  từ CSV đã lưu, top-10 luật và diễn giải.
- Chương III.B dùng `sections/fashion_mnist.tex`: pipeline 70k, số liệu
  Colab, audit, selection, enrichment và giới hạn. Hình pipeline lấy từ
  `figures/fashion/TC_pipeline.pdf`; đây là sơ đồ phương pháp, có nguồn
  chỉnh sửa tại `figures/fashion/source/TC_pipeline.drawio`.
- `references.tex` là bibliography chung. Tác giả trên trang đầu là
  Nguyễn Thành Trung, Lê Phúc Khang và Nguyễn Võ Tấn Duy.

Nguồn các phần riêng được dùng trực tiếp để tránh nhân đôi nội dung. Các
wrapper/PDF TV1 và TV2 là bản xem riêng/lịch sử; không dùng chúng thay
điểm biên dịch chung. Báo cáo không phụ thuộc nguồn lịch sử ở `sections/UD2/`.

## Số liệu đã nhập và giới hạn

Toàn bộ bảng và hình kết quả đã được điền từ các lần Colab xác minh được;
không còn ô hoặc khung chờ số liệu. CSV giữ các lượt đo và metadata gốc.

- Chương II dùng 560 mẫu Colab ở commit `54049e1`: 420 runtime, 40 Peak
  RSS, 50 scalability và 50 độ dài giao dịch; mỗi cấu hình có năm lượt.
  Dữ liệu, metadata và môi trường ở `../results/benchmarks/colab_20261125/`.
- Correctness trên năm CSDL và log 569 assertions là bằng chứng kiểm thử
  đã lưu; không phải số mẫu hiệu năng.
- Groceries giữ bảng cấu hình/top-10 đã được Colab xác nhận trùng kết quả
  cũ; bổ sung bảng mining/sinh luật/toàn pipeline tại 1%/50% từ 140 lượt đo.
  CSV/metadata ở `../results/groceries/colab_20261125/`.
- Fashion đã nhập run Colab `fashion_655719818688`: đủ 70.000 ảnh,
  2.143.746 descriptor, K-means hội tụ theo tiêu chí thư viện ở vòng
  372/3.000, giữ tolerance `1e-4`. Có cảnh báo cost tăng ở vòng 370.
  Đã nhập sáu ngưỡng mining, 60 mẫu thời gian, parity/audit, bốn mẫu
  minh họa và gallery cùng run. Review ngữ nghĩa vẫn `PENDING_REVIEW`.
- Số 7.228 và các hình kết quả Fashion cũ không được nhập như kết quả
  mặc định. Nếu dùng lại, phải nêu rõ run và xác nhận transaction hash.
- Lần Fashion dùng demo mở rộng, không nghiệm thu đủ bốn notebook release
  hoặc selector release. RSS quan sát mỗi 5 giây của cả tiến trình được
  ghi riêng; không có Peak RSS chính xác cho từng backend.

Chưa gộp số đo từ các máy hoặc từ những phạm vi đồng hồ khác nhau.
Đánh giá ngữ nghĩa độc lập cho gallery Fashion chưa được thực hiện;
báo cáo chỉ kết luận về đồng xuất hiện và mức tập trung theo lớp.
Phạm vi này không bao gồm nghiệm thu workflow bốn notebook hoặc đánh
giá classifier.

Để kiểm tra 560 lượt benchmark và dựng lại bốn hình Chương II:

```sh
python scripts/plot_colab_report.py
```

## Bằng chứng Fashion đã nhập

CSV và metadata chọn lọc: `../results/fashion/colab_report_20261125/`.
Hash đầy đủ, máy đo, cấu hình và phạm vi đồng hồ nằm trong
`runtime_observations.toml`. Artifact đầy đủ giữ cục bộ tại
`../results/colab/fashion_full_20261125/`, không đưa dữ liệu ảnh/transaction
lớn vào Git. Biểu đồ xuất từ CSV; gallery lấy đúng `pattern_3.png` của run.
Để kiểm tra 60 lượt đo, median/min/max, tổng theo độ dài/lớp và dựng lại hình:

```sh
python scripts/plot_fashion_report.py
```

Script cần Matplotlib sẵn có và font Times New Roman; không cần chạy lại mining.

## Biên dịch

Cần XeLaTeX, các package trong preamble, font Times New Roman, Arial
và TeX Gyre Termes. Dùng bản IEEEtran có sẵn tại
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
