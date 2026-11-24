# Phần TV1 — Chương I: Thuật toán Eclat và tối ưu hóa

Bản biên tập ngày 25/11/2026 dùng lại chương TV1 từ commit `24b49eb` trên
nhánh `docs/benchmark_groceries`, cập nhật theo API hiện tại và log test
24/11/2026. Định dạng thống nhất với TV2: IEEE conference A4 hai cột,
bắt đầu trực tiếp từ chương, không có tiêu đề, tên cá nhân hoặc abstract
riêng. PDF gồm 2 trang kể cả tài liệu tham khảo; yêu cầu 10–15 trang áp
dụng cho báo cáo nhóm.

- `../report_tv1.tex`: vỏ biên dịch; `../Report_TV1.pdf`: bản đọc.
- `algorithm.tex`: nội dung Chương I để ghép vào báo cáo chung.
- Trọng tâm: biểu diễn dọc, DFS, tính đúng đắn, baseline Set, hai kỹ thuật
  tối ưu đã cài đặt (BitVector và lọc singleton trước cấp phát), độ phức
  tạp, bằng chứng cải thiện và giới hạn. API/I/O/CLI chỉ là phần tích hợp.
- Dùng cùng ký hiệu `s`, `c(X)`, `c_min` với TV2; dùng `E` cho tổng số lần
  xuất hiện item để không trùng `L` chỉ độ dài giỏ trong thí nghiệm TV2.
- Các citation keys `zaki`, `spmf`, `agrawal` trùng TV2. Khi ghép, giữ một
  bibitem cho mỗi key, thêm `julia` từ vỏ TV1 vào bibliography chung.
- API phân biệt rõ tỷ lệ và số đếm: `mine(T, 1.0)` là 100%, còn
  `mine(T, 1)` là count 1. Giới hạn độ dài, deadline và số itemset chỉ
  có trên API số đếm; CLI hiện chỉ nhận tỷ lệ.

## Biên dịch

Cần XeLaTeX, IEEEtran, fontspec, babel Vietnamese, amsmath, amssymb,
booktabs, algorithmic, hyperref; font Times New Roman, Arial, Noto Sans Mono
và TeX Gyre Termes. Font mono dùng Noto Sans Mono vì máy hiện tại không có
Consolas của vỏ TV2; có thể đổi về Consolas khi ghép nếu đã cài font đó.

Chạy từ repo root, hai lượt để cập nhật dẫn chiếu:

```sh
mkdir -p /tmp/eclat-tv1
cd docs
xelatex -interaction=nonstopmode -halt-on-error -jobname=Report_TV1 -output-directory=/tmp/eclat-tv1 report_tv1.tex
xelatex -interaction=nonstopmode -halt-on-error -jobname=Report_TV1 -output-directory=/tmp/eclat-tv1 report_tv1.tex
cp /tmp/eclat-tv1/Report_TV1.pdf Report_TV1.pdf
```

## Ghép với TV2

Trong vỏ báo cáo nhóm, thêm package `algorithmic` và các lệnh đổi nhãn
Đầu vào/Đầu ra từ vỏ TV1. Sau phần mở đầu, dùng lần lượt:

```tex
\input{report_tv1/algorithm}
\input{report_tv2/benchmark}
\input{report_tv2/groceries}
```

Không mang lệnh `\setcounter{section}{1}` từ vỏ xem riêng TV2 sang báo cáo
chung. Nội dung TV1 tránh lặp bảng correctness, đồ thị và số liệu hiệu năng
đã có ở Chương II. Các tham chiếu “Chương II” trong bản riêng hướng đến
phần TV2 khi ghép. PDF riêng chưa phải `docs/Report.pdf` nộp cuối cùng.

## Kiểm chứng bản thảo

Đã đối chiếu nội dung với mã core, test và tài liệu TV2; biên dịch hai lượt,
kiểm tra trực quan cả hai trang, không có tràn hộp, thiếu ký tự hoặc dẫn
chiếu chưa xác định. IEEEtran có cảnh báo font `TU/ptm` lúc nạp class;
font nội dung được fontspec thiết lập sau đó.

Kết quả 569/569 assertions là log toàn bộ package trên Julia 1.13.3/Linux
ngày 24/11/2026 đã lưu trong README, bao gồm core và ứng dụng. Cả hai
backend khớp toàn bộ itemset/support của năm CSDL đầy đủ. Không đồng nhất
số assertions này với số cấu hình SPMF hoặc với 560 mẫu hiệu năng ngày
16/11/2026 của TV2. Biên tập tài liệu không chạy lại benchmark.

Để chuẩn bị input kiểm thử trên máy mới, chạy
`julia --project=. scripts/prepare_data.jl` trước bộ test. Báo cáo này
không phụ thuộc kết quả Fashion 70.000 ảnh đang được chạy lại trên Colab.
