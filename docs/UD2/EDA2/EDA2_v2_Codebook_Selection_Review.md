# Đề xuất cấu hình biểu diễn ảnh thành transaction từ EDA2 v2

## Cấu hình đã chốt để sử dụng

**B0 / K=32 / seed=123 / S0** (`B0_K32_seed123_S0`) là cấu hình người dùng chọn để biểu diễn ảnh thành transaction. S0 lưu tập visual word xuất hiện trong mỗi ảnh.

Dùng bộ [transactions.jsonl](../../../results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl) hiện có với **70.000 transaction**, **0 transaction rỗng** và kiểm định **PASS**. SHA-256 khớp manifest EDA2 (`b078e485064bfdacea4b5faa5f027efe7123af32a2db2c27acf415d6b1dd7d70`).

Kết luận theo rubric EDA2 vẫn là `INCONCLUSIVE` vì phần D chưa có đánh giá trực quan và độ dư thừa của mẫu.

## Đề xuất trước khi duyệt shortlist và chạy C3

**Cấu hình tạm để dùng thử** `T2 / B0 / K=32 / seed=42 / S3`.

**Kết luận theo protocol** `INCONCLUSIVE`. EDA2 v2 đủ bằng chứng sàng lọc cho 45 database, nhưng chưa có kết quả khai thác sâu và đánh giá mẫu ảnh để chốt một cấu hình cuối. Phạm vi là 15 codebook × S0, S1, S3. S6-B đã được rút khỏi phạm vi EDA2 v2, nên các yêu cầu riêng về witness quan hệ hoặc null shuffle S6-B nằm ngoài lần đánh giá này.

## 1. Vì sao đề xuất B0/K32/seed42/S3

S3 lưu mỗi item dưới dạng `(dải trên/giữa/dưới, visual word)`. Chọn S3 khi bài toán ưu tiên giữ thông tin vị trí theo chiều dọc với từ vựng gọn. S1 phù hợp hơn nếu mục tiêu cần phân biệt trái/phải. S0 là đối chứng khi chỉ cần biết visual word xuất hiện trong ảnh.

EDA2 kiểm định `PASS` cho cả 45 database, mỗi bộ 70.000 transaction và không có transaction rỗng. SHA-256 của 45 tệp transaction hiện tại khớp manifest và nguồn dùng trong pilot. Cả 30 database S1/S3 đều qua kiểm tra chiếu về tập visual word S0 và trạng thái rỗng trên từng TID. TC4 có 15 codebook duy nhất. Hai cờ `NON_CONVERGED` tại `(128,42)` và `(256,123)` là cảnh báo, hai nguồn vẫn qua kiểm định.

So sánh theo cặp, cùng B0/K32/seed42. Pilot EDA2-C1 ở support 3% ≥ 2.100 ảnh, hoàn tất đến độ dài 2.

| Variant | Item ID có mặt | Dài P5 / P50 / P95 | Transaction phân biệt | Singleton ở 1 / 3 / 5 / 10% | Cặp ở 3% | Dung lượng JSONL |
|---|---:|---:|---:|---:|---:|---:|
| S0 | 32 | 7 / 12 / 17 | 92,01% | 32 / 32 / 32 / 31 | 471 | 5,18 MB |
| S1 | 128 | 11 / 18 / 25 | 99,26% | 120 / 102 / 88 / 74 | 1.933 | 6,94 MB |
| **S3** | **96** | **10 / 17 / 23** | **99,23%** | **93 / 84 / 81 / 72** | **1.696** | **6,21 MB** |

S3 có 72/96 singleton đạt support ít nhất 10%. Support trung vị của 1.696 cặp ở ngưỡng 3% là khoảng 5,69% (3.985,5 ảnh). Khi tăng lên K64 trong cùng S3 và seed42, số singleton ở 10% tăng từ 72 lên 79, không gian item tăng từ 96 lên 192, còn support trung vị của các cặp pilot giảm xuống 4,17%. K32 là lựa chọn tạm phù hợp với mục tiêu giữ các visual word theo dải có khả năng xuất hiện lặp lại, với từ vựng nhỏ hơn K64.

K32 hội tụ ở cả ba seed. Với S3, tỷ lệ transaction phân biệt trong khoảng 99,23–99,38% và số cặp ở 3% trong khoảng 1.658–1.712 qua ba seed. Seed42 có distortion thấp nhất trong nhóm K32 (`0,34447`), 1.696 cặp ở giữa ba seed và đã có gallery centroid. Đây là lựa chọn đại diện để thử trước. Số cặp chỉ mô tả pilot trong từng encoding và dùng để kiểm tra độ ổn định, vì item giữa các encoding có ngữ nghĩa khác nhau. Class Jaccard/AUC giữ vai trò hậu nghiệm và không tham gia đề xuất.

Artifact dùng thử: [S3 K32 seed42 – transactions.jsonl](../../../results/fashion/tc/tc6_configs/S3/FashionMNIST_T2_S3_B0_K32_seed42/transactions.jsonl) và [bảng giải mã item](../../../results/fashion/tc/tc6_configs/S3/FashionMNIST_T2_S3_B0_K32_seed42/item_mapping.csv).

## 2. Đối chứng và shortlist đề xuất

| Encoding | Ứng viên ưu tiên | Đối chứng | Trade-off cần kiểm tra |
|---|---|---|---|
| S0 | K64/seed2026 | K128/seed123 | Cả hai hội tụ. K64 có 1.479 cặp, median support cặp 5,91%; K128 có 1.576 cặp, median support cặp 4,36%. So mẫu dài và mức trùng lặp giữa patterns. |
| S1 | K32/seed42 | K64/seed42 | Qua ba seed, K32 có 1.905–1.933 cặp, K64 có 1.591–1.640 ở 3%. K64 có nhiều singletons hơn trên cả bốn ngưỡng. Kiểm tra mẫu trái/phải có thêm thông tin thị giác hữu ích. |
| S3 | K32/seed42 | K64/seed42 | Qua ba seed, K32 có 1.658–1.712 cặp, K64 có 1.514–1.551 ở 3%. Kiểm tra mẫu trên/giữa/dưới và độ nhạy ở support 1%. |

Shortlist trình duyệt gồm 9 codebook, giữ cả ba encoding cho mỗi cặp `(K,seed)` để so sánh ghép cặp.

| K | Seed | Lý do giữ |
|---:|---|---|
| 16 | 123 | Đối chứng codebook nhỏ. S0 có đủ 120 tổ hợp cặp ở 3% qua cả ba seed, cần kiểm tra pattern có phân biệt được cấu trúc ảnh. |
| 32 | 42, 123, 2026 | Ưu tiên S1/S3 và kiểm tra biến động qua ba seed. |
| 64 | 42, 123, 2026 | Đối chứng cho S1/S3 và ứng viên S0, có đủ ba seed. |
| 128 | 123 | Ứng viên S0 có số cặp cao và đã hội tụ. |
| 256 | 42 | Đối chứng K lớn đã hội tụ. S1 có 584 singleton ở 1% nhưng còn 284 ở 3%, nên đáng giữ để kiểm tra độ nhạy ở ngưỡng thấp. |

Shortlist tương ứng 27 database và 108 điều kiện `(K,seed,variant,minsup)` nếu chạy toàn bộ grid. File quyết định C2 hiện ghi 0/15 codebook được chọn. Bảng trên là đề xuất để duyệt.

## 3. Phần EDA còn thiếu để xác nhận trước khi chỉnh

| Mức | Phần | Bằng chứng hiện có và việc cần bổ sung |
|---|---|---|
| Cần để chốt | EDA2-C2 và C3 | C2 đang chờ duyệt. Chạy C3 trên shortlist ở support `1%, 3%, 5%, 10%` (`700, 2.100, 3.500, 7.000` ảnh), độ dài tối đa 4. Báo số lượng và phân bố support theo độ dài. Khi so qua các mức support, theo dõi mẫu bằng ID cố định trong từng database. Chỉ dùng kết quả có output đầy đủ đã kiểm tra. Các lượt đụng giới hạn ghi censored và lý do. Closed/maximal toàn cục cần bằng chứng exact ngoài giới hạn độ dài. |
| Cần để chốt | EDA2-D và rubric | Chưa có artifact đánh giá pattern. Hàm D hiện chỉ lấy mẫu ở 3%, lấy tối đa 5 TID đầu tiên tìm thấy và để trống tọa độ patch. Cần duyệt trước cách chọn mẫu theo variant, ngưỡng, độ dài và dải support, đếm lại support bằng scan hoặc giao TID, đối chiếu patch/tọa độ, xuất ảnh overlay, định nghĩa redundancy và chấm visual coherence 0–2. Ghi người review và mức bất đồng nếu có nhiều người review. |
| Cần để kết luận về chi phí | Benchmark C5 | Pilot C1 có một runtime mỗi database. C3 đã có cấu hình một warmup và ba lượt đo, nhưng chưa chạy. Chốt ngân sách trước khi chạy, dùng cùng engine, threads và máy. Báo median runtime, peak RSS và dung lượng. `8 GiB` hiện chỉ có trong cấu hình, chưa được thực thi và cột peak RSS đang trống. Dựa trên output chính xác và trạng thái lượt đo khi so chi phí. |
| Cần để chốt | EDA2-E | Báo cáo hiện sinh mặc định `INCONCLUSIVE`. Bổ sung bảng ứng viên theo từng variant, so sánh ghép cặp và ghi quyết định dựa trên mẫu đã kiểm chứng, độ nhạy support và ngân sách. Giữ `INCONCLUSIVE` nếu chưa đủ bằng chứng. |
| Bổ sung chẩn đoán | EDA2-A/B và provenance | A đã có metrics, ARI lưu từ TC4 và gallery centroid. B đã có length, diversity/Jaccard, spatial coverage và support count theo từng item. Có thể bổ sung gallery real patches gần centroid và biểu đồ ECDF từ các support đã lưu. Báo cáo mean/range ba seed theo từng K/variant có thể lấy từ các CSV hiện có. Coverage theo dải phụ thuộc vào số ô patch `14/21/14`, chỉ cho biết dải có patch được giữ. |

## Nguồn đối chiếu

- Criteria của người dùng, `EDA2_Codebook_Selection_Review_and_Criteria.md`, mục C0–C6, D1–D7 và E.
- EDA2 v2, [kiểm định](../../../results/fashion/eda2/v2/validation_report.csv), [manifest nguồn](../../../results/fashion/eda2/v2/input_manifest.csv), [codebook metrics](../../../results/fashion/eda2/v2/codebook/codebook_metrics_15.csv) và [spatial invariants](../../../results/fashion/eda2/v2/transactions/spatial_invariants_45.csv).
- EDA2 v2, [transaction metrics](../../../results/fashion/eda2/v2/transactions/transaction_metrics_45.csv), [item support](../../../results/fashion/eda2/v2/transactions/item_support_summary_45.csv), [pilot C1](../../../results/fashion/eda2/v2/pilot_eclat/pilot_common_45.csv), [cấu hình benchmark C1](../../../results/fashion/eda2/v2/pilot_eclat/pilot_validation_report.toml), [shortlist C2](../../../results/fashion/eda2/v2/pilot_eclat/shortlist_decision.csv) và [trạng thái quyết định cuối](../../../results/fashion/eda2/v2/final/final_selection.md).
