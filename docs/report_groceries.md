# Groceries: phân tích giỏ hàng bằng Eclat

## Dữ liệu và cách chuyển thành giao dịch

Nguồn: [Groceries CSV](https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/groceries.csv).
Một dòng là một giỏ hàng, số sản phẩm giữa các dòng có thể khác nhau. Pipeline
`scripts/groceries_demo.jl` đọc từng dòng, bỏ khoảng trắng và sản phẩm lặp trong
cùng giỏ, giữ nguyên các giỏ trùng nhau. Vocabulary được sắp theo tên trước khi
gán ID dương, nên mapping có thể tái lập. Không dùng tên sản phẩm làm đặc trưng
số hoặc bổ sung nhãn vào giao dịch.

Kết quả: **9.835 giao dịch, 169 sản phẩm**. Input Eclat nằm ở
`data/processed/groceries_spmf.txt`; mapping ngược ở `data/processed/item_mapping.csv`.
Nguồn và SHA-256 của input/tham chiếu được ghi trong
[metadata kiểm chứng](../results/groceries/groceries_spmf_0.01_metadata.md).
Test đối chiếu dữ liệu đầy đủ xác nhận cả Set và BitVector khớp SPMF toàn bộ
333 itemsets/support tại minsup 1%.

## Sinh và chọn luật

Eclat của nhóm sinh frequent itemsets; code Julia của nhóm liệt kê các tập con
khác rỗng và khác toàn bộ itemset để tạo hai vế luật. Với luật X → Y:

- support = count(X ∪ Y) / 9.835;
- confidence = count(X ∪ Y) / count(X);
- lift = confidence / (count(Y) / 9.835).

Chọn cấu hình chính **minsup = 1%, minconf = 50%**: 333 frequent itemsets,
15 luật đạt ngưỡng, giữ 10 luật có lift cao nhất. Minsup áp dụng cho itemset
hợp, nên support của X cũng đạt ngưỡng. Xếp tiếp theo confidence, support và
hai vế để kết quả ổn định khi lift bằng nhau. Không dùng thư viện FIM ngoài
để sinh itemsets hoặc luật.

## Top 10 luật và ý nghĩa kinh doanh

Số liệu dưới đây được làm tròn từ [top10_rules.csv](../results/groceries/top10_rules.csv).
Tên sản phẩm giữ theo nguồn để tra mapping; “other vegetables” là một nhóm
sản phẩm, không phải một mặt hàng cụ thể.

| # | X → Y | Số giỏ chứa X ∪ Y | Support | Confidence | Lift | Gợi ý cần thử nghiệm |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | citrus fruit + root vegetables → other vegetables | 102 | 1,037% | 58,62% | 3,030 | Gợi ý nhóm rau khác khi giỏ đã có trái cây có múi và rau củ. |
| 2 | root vegetables + tropical fruit → other vegetables | 121 | 1,230% | 58,45% | 3,021 | Thử gợi ý rau khác cho giỏ có rau củ và trái cây nhiệt đới. |
| 3 | rolls/buns + root vegetables → other vegetables | 120 | 1,220% | 50,21% | 2,595 | Thử gợi ý bổ sung rau cho giỏ có bánh mì và rau củ. |
| 4 | root vegetables + yogurt → other vegetables | 127 | 1,291% | 50,00% | 2,584 | Thử gợi ý nhóm rau khác cho giỏ có rau củ và sữa chua. |
| 5 | curd + yogurt → whole milk | 99 | 1,007% | 58,24% | 2,279 | Thử gợi ý sữa nguyên kem cho nhóm mua curd và sữa chua. |
| 6 | butter + other vegetables → whole milk | 113 | 1,149% | 57,36% | 2,245 | Thử gợi ý sữa cho giỏ có bơ và rau khác. |
| 7 | root vegetables + tropical fruit → whole milk | 118 | 1,200% | 57,00% | 2,231 | Thử bán chéo sữa cho giỏ rau củ và trái cây nhiệt đới. |
| 8 | root vegetables + yogurt → whole milk | 143 | 1,454% | 56,30% | 2,203 | Thử gợi ý sữa nguyên kem cho giỏ rau củ và sữa chua. |
| 9 | domestic eggs + other vegetables → whole milk | 121 | 1,230% | 55,25% | 2,162 | Thử gợi ý sữa trong nhóm giỏ trứng và rau. |
| 10 | whipped/sour cream + yogurt → whole milk | 107 | 1,088% | 52,45% | 2,053 | Thử gợi ý sữa cho giỏ có kem và sữa chua. |

Ví dụ luật thứ nhất: có 174 giỏ chứa citrus fruit + root vegetables; trong đó
102 giỏ còn chứa other vegetables. Confidence = 102/174 ≈ 58,62%.
Other vegetables xuất hiện trong 1.903/9.835 giỏ ≈ 19,35%, nên lift ≈ 3,03:
tần suất mua nhóm rau này trong nhóm giỏ X gấp khoảng 3,03 lần tần suất chung.
Đây không phải mức tăng doanh thu 203% hoặc xác suất khách sẽ mua nếu được gợi ý.

Các luật là cơ sở để đề xuất gợi ý sản phẩm hoặc vị trí trưng bày. Muốn kết luận
có hiệu quả kinh doanh cần thí nghiệm A/B, đo chuyển đổi, lợi nhuận và tác động
đến sản phẩm khác. Đồng xuất hiện không chứng minh quan hệ nhân quả; dữ liệu
không có danh tính khách, thời gian, giá hay khuyến mãi để giải thích các yếu tố đó.

## Ảnh hưởng của ngưỡng

[parameter_summary.csv](../results/groceries/parameter_summary.csv) ghi đủ 12 cấu hình:

| Minsup | Itemsets | Luật minconf 30% | Luật minconf 50% | Luật minconf 70% |
| ---: | ---: | ---: | ---: | ---: |
| 0,5% | 1.001 | 487 | 120 | 1 |
| 1% | 333 | 125 | 15 | 0 |
| 2% | 122 | 37 | 1 | 0 |
| 3% | 63 | 14 | 0 | 0 |

Minconf không thay đổi itemsets vì được áp dụng sau mining. Minsup cao loại
bớt tổ hợp ít gặp; minconf cao giữ ít luật hơn. Cấu hình 1%/50% có đủ 10 luật
để trình bày và mọi luật có ít nhất 99 giỏ chứa cả hai vế. Đây là lựa chọn mô tả
trên dữ liệu hiện có, chưa được tối ưu theo kết quả kinh doanh trên tập giữ lại.
Lift cao vẫn có thể dựa trên một nhóm nhỏ; luôn đọc kèm số giỏ và support.

## Chạy lại

Tải CSV nguồn vào `data/raw/groceries.csv`, sau đó chạy từ repo root:

```powershell
julia --project=. scripts/groceries_demo.jl
julia --project=. test/runtests.jl
```

Demo tạo dữ liệu chuẩn hóa, mapping và hai bảng luật. Test dùng thêm bốn CSDL
benchmark đầy đủ, chuẩn bị theo [README](../README.md). Các bước chuyển đổi
và demo này cần được ghép vào Colab chung trước khi nộp.
