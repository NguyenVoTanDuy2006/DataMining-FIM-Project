# Báo cáo nhóm

Nguồn và tài nguyên báo cáo được gom tại thư mục này. Bản PDF để đọc vẫn ở
[`docs/Report.pdf`](../Report.pdf).

```text
report/
├── Report.tex              # Nguồn báo cáo chính
├── references.tex
├── sections/               # Các phần dùng trong báo cáo chính
├── figures/                # Hình benchmark và Fashion-MNIST
├── members/tv1/            # Nguồn riêng thành viên 1
├── members/tv2/            # Nguồn riêng thành viên 2
├── members/tv3/            # Nguồn riêng thành viên 3
├── archive/UD2/            # Bản UD2 cũ, không được nạp vào báo cáo chính
└── IEEEtran.cls
```

## Biên dịch báo cáo chính

Từ thư mục gốc:

```sh
mkdir -p /tmp/eclat-full-report
cd docs/report
xelatex -interaction=nonstopmode -halt-on-error -jobname=Report -output-directory=/tmp/eclat-full-report Report.tex
xelatex -interaction=nonstopmode -halt-on-error -jobname=Report -output-directory=/tmp/eclat-full-report Report.tex
cp /tmp/eclat-full-report/Report.pdf ../Report.pdf
```

Các PDF riêng của TV1–TV3 và hướng dẫn biên dịch nằm trong từng thư mục
`members/tvN/`. Hình kết quả benchmark có thể dựng lại bằng
`python scripts/plot_report.py`; bộ dữ liệu và số đo gốc nằm trong `results/`.
