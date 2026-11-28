# Báo cáo thành viên 3 — Fashion-MNIST

`Report_TV3.tex` là bản riêng của thành viên 3; `fashion.tex`,
`appendix.tex` và `references.tex` là các nguồn được nạp vào bản này.
Các hình nằm trong `figures/`.

## Kết quả thí nghiệm được dùng

- `results/fashion/eda2/v3_20261127/` lưu kết quả khảo sát năm giá trị
  K-means, ba seed, cùng các thống kê và kiểm tra biểu diễn giao dịch.
- `results/fashion/tc/tc6_configs/` lưu các gói cấu hình S0, vùng, dải
  và quan hệ lân cận. Các artifact TC6 trên nhánh `master` trùng với
  bản đã có trong nhánh Fashion-Mnist.

## Biên dịch bản riêng

Từ thư mục này, chạy XeLaTeX hai lượt để cập nhật tham chiếu:

```sh
xelatex -interaction=nonstopmode -halt-on-error Report_TV3.tex
xelatex -interaction=nonstopmode -halt-on-error Report_TV3.tex
```
