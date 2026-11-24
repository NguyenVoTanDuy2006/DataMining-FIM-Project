# Nội dung báo cáo IEEE — benchmark và Groceries

Bản biên tập ngày 21/11/2026: PDF 6 trang (kể cả tài liệu tham khảo và phụ lục),
phần chính A4 hai cột và phụ lục số đo, gồm 5 hình, 8 bảng và 6 tài liệu
tham khảo. Đã kiểm tra trực quan PDF; đối chiếu đủ 56 dòng của sáu bảng số liệu
với CSV. Lượt biên dịch cuối không có lỗi tràn hộp, thiếu ký tự hay dẫn chiếu
chưa xác định. Không chạy lại unit test/benchmark vì chỉ bổ sung tài liệu.

Mở [Report_TV2.pdf](../Report_TV2.pdf). Đây là phần Chương II (benchmark) và
III.A (Groceries), không phải báo cáo nhóm đầy đủ. Yêu cầu 10–15 trang của đề
áp dụng cho bản nhóm, không áp dụng riêng phần này. Nội dung bắt đầu trực tiếp
từ Chương II; không có tiêu đề riêng, tên cá nhân, abstract, từ khóa hay tổng
kết công việc. Abstract và từ khóa chỉ đặt một lần ở đầu báo cáo nhóm.

## Biên dịch

Nếu cần tạo lại hình khổ một cột từ CSV, chạy `python scripts/plot_report.py`
tại repo root trước khi biên dịch. Script chỉ đọc CSV và vẽ năm PNG trong
`docs/report_tv2/figures/`, không chạy mining hoặc tạo nội dung báo cáo.

Cần XeLaTeX, Times New Roman, Arial, Consolas và các package chuẩn trong
preamble. Chạy từ thư mục gốc repo bằng PowerShell:

```powershell
Set-Location docs
New-Item -ItemType Directory -Force ../.build/report_tv2 | Out-Null
1..2 | ForEach-Object {
    xelatex --disable-installer -interaction=nonstopmode -halt-on-error -file-line-error '-jobname=Report_TV2' '-output-directory=../.build/report_tv2' report_tv2.tex
    if ($LASTEXITCODE -ne 0) { throw 'XeLaTeX failed' }
}
Copy-Item -LiteralPath ../.build/report_tv2/Report_TV2.pdf -Destination Report_TV2.pdf
Set-Location ..
```

`--disable-installer` không tự cài package thiếu. Nếu thiếu package, cài qua
trình quản lý TeX rồi biên dịch lại. MiKTeX cần quyền ghi cache/font ngoài repo.
Log và file trung gian nằm trong `.build/`, được Git-ignore. Một số bản MiKTeX
cảnh báo font `TU/ptm` khi nạp IEEEtran trước fontspec và thiếu mẫu ngắt từ
Vietnamese; nội dung dùng Times New Roman do fontspec thiết lập sau đó.

## Ghép vào báo cáo nhóm

- Dùng XeLaTeX và preamble tương thích của `report_tv2.tex`. Giữ các macro
  `\bv`, `\st`, hai môi trường `reportfigure`, `reporttable` và graphicspath
  `report_tv2/figures/` (từ thư mục `docs/`). Hai môi trường giữ hình/bảng nhỏ
  trong luồng nội dung thay vì cho trôi sang phần khác.
- Sau Chương I, thêm `\input{report_tv2/benchmark}` để tạo Chương II.
- `groceries.tex` chứa `\section{Ứng dụng thực tế}` và `\subsection{Groceries...}`.
  Đưa phần Fashion-MNIST vào sau dưới dạng subsection tiếp theo của Chương III;
  tránh tạo thêm một section Chương III trùng.
- Ghép các bibitem trong `report_tv2.tex` vào bibliography chung, giữ citation keys
  hoặc đổi đồng bộ. File chính chỉ là vỏ để xem PDF; khi ghép dùng các input nội
  dung, không sao chép preamble, document hoặc lệnh ngắt trang của vỏ.
- Chỉ có hai file nội dung: `benchmark.tex` và `groceries.tex`; các bảng nằm
  trực tiếp trong file tương ứng, không phụ thuộc file bảng rời.
- `benchmark.tex` định nghĩa `\EclatBenchmarkAppendix`, chứa thông tin tái lập
  và bảng runtime 28 cấu hình. Gọi macro này ở vị trí phụ lục chung sau các
  chương. Vỏ xem riêng dùng `\onecolumn` trước macro để bảng rộng dễ đọc;
  lệnh đổi số cột không nằm trong hai file nội dung.
- Sau khi ghép, biên dịch lại hai lượt để cập nhật số hình/bảng.

## Nguồn số liệu và kiểm chứng

Các bảng LaTeX là bản chụp tĩnh trực tiếp từ CSV kết quả ngày 16/11/2026 trong
`results/benchmarks/` và `results/groceries/`. Chúng không tự đổi khi biên dịch;
nếu đo lại, cập nhật bảng, hình, nhận xét và kiểm chứng đồng bộ. Không thêm
chức năng tạo báo cáo vào script Python vẽ hình.

Sáu bảng số liệu được nhúng trong hai file nội dung, bao phủ 28 cấu hình runtime,
4 dòng RAM, 5 mức scalability, 5 độ dài, 12 cấu hình luật và 10 luật top.
Hai bảng thống kê/correctness nằm trong phần benchmark. Hình được vẽ lại theo
khổ cột từ cùng CSV, không thay đổi CSV hoặc chạy lại benchmark. Kết quả 439 assertions và
560 mẫu là chứng cứ của lần chạy đã lưu, không tuyên bố chạy lại ở lần viết PDF.

Lớp `../IEEEtran.cls` là bản V1.8b (2015/08/26) chính thức, tải nguyên vẹn từ
<https://mirrors.ctan.org/macros/latex/contrib/IEEEtran/IEEEtran.cls>.
Giữ nguyên thông báo bản quyền và giấy phép LPPL 1.3 trong header;
xem <https://www.latex-project.org/lppl/lppl-1-3/>. Đây là mã định dạng của bên
thứ ba, không phải cài đặt thuật toán của nhóm.
