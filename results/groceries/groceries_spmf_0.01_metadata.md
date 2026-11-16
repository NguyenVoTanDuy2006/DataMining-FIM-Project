# Tham chiếu SPMF Groceries cho auto test

- Ngày tạo: 2026-11-16.
- Đầu vào đầy đủ: `data/processed/groceries_spmf.txt`, 9.835 giao dịch, 169 item.
- Minsup: 1%; min_count: 99.
- Kết quả SPMF: 333 frequent itemsets, kèm support count.
- SHA-256 đầu vào: `4760f4b207d93e173613a7aba04beb13a9152b798e0e50ba425201dca74d0fb0`.
- SHA-256 đáp án `groceries_spmf_0.01.txt`: `908f267d28e121d8e349492ed0ac8001f0041a66e07e1146ae9e7712ec1aa996`.
- SHA-256 JAR SPMF: `2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0`.

Đáp án được tạo bằng SPMF Eclat trên đúng đầu vào ở trên:

```powershell
java -jar data/benchmark/tools/spmf.jar run Eclat data/processed/groceries_spmf.txt results/groceries/groceries_spmf_0.01.txt 1%
```

Set và BitVector đều được đối chiếu toàn bộ itemset/support với đáp án này.
Auto test chỉ đọc file đáp án đã lưu, không gọi Java hoặc sinh đáp án bằng
EclatFIM. Các dòng metadata `@...` của SPMF được bỏ qua khi đọc.
