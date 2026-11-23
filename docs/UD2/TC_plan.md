Mình đã đọc báo cáo `EDA1_Insights_For_Transaction_Construction.md`, gồm kết quả của 5 nhóm insight (I1–I5), 15 câu hỏi EDA và các thử nghiệm bổ sung với ngưỡng \\(\tau=10\\).

Từ những kết quả này, mình đề xuất **chốt một pipeline TC chính và xây dựng các pipeline đối chứng theo từng giai đoạn**, thay vì thử tất cả tổ hợp patch size, filtering, descriptor và spatial encoding ngay từ đầu.

# **1. Phương án TC đề xuất**

**Pipeline chính — Dense Visual Words**

| Dataset            | 70.000 ảnh Fashion-MNIST                                 |
| ------------------ | -------------------------------------------------------- |
| Patch extraction   | **4×4, stride 4**, không overlap                         |
| Patch filtering    | **Q10+ = 29, α = 0**                                     |
| Descriptor         | Raw pixel, `Float32(pixel)/255`                          |
| Feature extraction | Dense patches                                            |
| Codebook           | K-means, thử nghiệm số cụm K                             |
| Encoding           | Binary Bag of Visual Words, không spatial                |
| Output             | 1 ảnh → 1 transaction chứa các Visual Word IDs phân biệt |

Đây là cấu hình chính được đề xuất để bắt đầu TC, chưa phải cấu hình tối ưu đã được chứng minh.

## **2. Tại sao chọn cấu hình này?**

Các số liệu EDA hỗ trợ khá rõ ba quyết định đầu tiên.

### **A. Chọn patch 4×4**

Báo cáo cho thấy 4×4 phân tách vùng nền và vùng có cấu trúc cục bộ tốt hơn ở một số phép đo. Có **30,73% patch 4×4 đồng nhất tối**, trong khi con số của 7×7 là 17,72%.

Đặc biệt, khi so sánh hai cấu hình có mức patch reduction gần bằng nhau (khoảng 39,3%), 4×4 có EdgeLoss 5,92%, thấp hơn mức 14,00% của cấu hình 7×7 được dùng để đối chiếu.

Điều này ủng hộ lựa chọn 4×4 để lọc nền chọn lọc, nhưng chưa khẳng định 4×4 tạo visual words tốt hơn sau K-means.&#x20;

EDA1_Insights_For_Transaction_Construction.md

EDA1_Insights_For_Transaction_Construction.md



### **B. Chọn Q10+ = 29, α = 0**

Kết quả thực nghiệm trên 70.000 ảnh, patch 4×4

| Filtering             | Patch reduction | EdgeLoss  | Ảnh hết patch |
| --------------------- | --------------- | --------- | ------------- |
| Không lọc             | 0%              | 0%        | 0             |
| τ = 10, α = 0         | 36,43%          | 3,78%     | 0             |
| **Q10+ = 29, α = 0**  | **37,50%**      | **4,41%** | **0**         |
| Otsu = 97, α = 0      | 43,30%          | 8,90%     | 0             |
| Q10+ = 29, α = 0,0625 | 39,30%          | 5,92%     | 0             |

2%4%6%8%10%3638404244

Q10+ α=0 là điểm khởi đầu cân bằng: giảm đáng kể số patch, không loại pixel vượt ngưỡng đã chọn và không tạo ảnh không còn patch trong kết quả EDA.

So với \\(\tau=10\\), Q10+ giảm thêm 1,07 điểm phần trăm số patch, nhưng mất thêm 0,63 điểm phần trăm gradient energy. Đây là một đánh đổi nhỏ, đáng kiểm chứng bằng transactions thực tế.&#x20;

EDA1_Insights_For_Transaction_Construction.md

EDA1_Insights_For_Transaction_Construction.md



Lưu ý: EdgeLoss chỉ là chỉ số đại diện cho lượng gradient bị loại, không đo trực tiếp lượng thông tin ngữ nghĩa bị mất.

### **C. Chọn Raw Pixel + Dense Patch**

Báo cáo cho thấy trong pilot 200 ảnh, ORB không tìm được keypoint ở 2,5% ảnh, còn SIFT là 8,5%. Coverage theo lưới patch 4×4 cũng khá hạn chế. Vì thế Dense Patch phù hợp hơn để xây dựng một hệ thống giao dịch có cấu trúc ổn định.

Raw pixel được ưu tiên làm baseline vì giữ lại mức sáng và bố cục pixel trong patch, đồng thời tương thích trực tiếp với Euclidean K-means. Gradient và histogram hướng vẫn là những ứng viên đối chứng, chưa có đủ bằng chứng để thay thế raw pixel ngay.&#x20;

EDA1_Insights_For_Transaction_Construction.md

EDA1_Insights_For_Transaction_Construction.md



# **3. Bộ thí nghiệm TC nên xây dựng**

Thay vì chạy mọi cấu hình trong báo cáo, mình đề xuất chia thành ba vòng:

## **Vòng 1 — Chốt patch filtering và patch size**

| ID     | Patch   | Filtering    | Descriptor | Spatial   | Mục đích                    |
| ------ | ------- | ------------ | ---------- | --------- | --------------------------- |
| T1     | 4×4     | No-filter    | Raw        | Không     | Baseline                    |
| **T2** | **4×4** | **Q10+ α=0** | **Raw**    | **Không** | **Ứng viên chính**          |
| T3     | 4×4     | τ=10 α=0     | Raw        | Không     | Kiểm tra lọc nhẹ hơn        |
| T4     | 7×7     | No-filter    | Raw        | Không     | Đối chứng kích thước        |
| T5     | 7×7     | Q10+ α=0     | Raw        | Không     | Đối chứng kích thước có lọc |

Bốn cấu hình T1, T2, T4 và T5 có trong đề xuất của báo cáo. Mình bổ sung T3 vì báo cáo đã có số liệu \\(\tau=10\\), và sự khác biệt nhỏ giữa \\(\tau=10\\) với Q10+ đáng được kiểm tra tiếp sau lượng tử hóa.&#x20;

EDA1_Insights_For_Transaction_Construction.md



## **Vòng 2 — Đánh giá Descriptor**

Chỉ sau khi có kết quả vòng 1, giữ cố định patch size, filtering và so sánh:

- Raw pixel descriptor — baseline.
- Sobel gradient descriptor — phương án đối chứng.
- Histogram hướng gradient 8 bin — phương án đối chứng bổ sung.

Báo cáo xác nhận có cơ sở thử histogram hướng, nhưng chưa xác nhận cấu hình HOG hoàn chỉnh phù hợp với patch 4×4.&#x20;

EDA1_Insights_For_Transaction_Construction.md



## **Vòng 3 — Đánh giá Spatial Encoding**

Với pipeline triển vọng từ hai vòng trước, thử:

| Encoding                 | Item                               | Số item tiềm năng |
| ------------------------ | ---------------------------------- | ----------------- |
| Standard BoVW            | `V5`                               | K                 |
| Three horizontal regions | `V5_top`, `V5_middle`, `V5_bottom` | 3K                |
| 2×2 regions (tùy chọn)   | `V5_TL`, `V5_TR`, …                | 4K                |

Mình ưu tiên **top/middle/bottom** vì phân tích EDA đã cho thấy phân bố foreground và gradient khác nhau rõ rệt giữa các vùng và giữa các loại trang phục.&#x20;

EDA1_Insights_For_Transaction_Construction.md



# **4. Thiết kế triển khai TC1–TC7**

Đây là phần mình đề xuất bổ sung vào kế hoạch TC dựa trên kết quả EDA.

1. **TC1 — Patch Extraction**

   Trích 49 patch 4×4 từ mỗi ảnh. Giữ `image_id`, `patch_id`, tọa độ hàng/cột và `original_split`. Không áp dụng mask trực tiếp lên giá trị pixel.
2. **TC2 — Patch Filtering**

   Với T2, giữ patch khi có ít nhất một pixel có intensity lớn hơn 29. Với T3, dùng ngưỡng 10. T1 giữ tất cả patch. Luôn giữ bảng ánh xạ patch được giữ/loại.
3. **TC3 — Feature Extraction**

   Chuyển mỗi patch 4×4 thành vector `Float32` 16 chiều, chia giá trị intensity cho 255. Không đưa class label hoặc vị trí patch vào raw descriptor.
4. **TC4 — Codebook Construction**

   Lấy mẫu descriptors từ nhiều ảnh, huấn luyện K-means để tạo \\(K\\) visual words, lưu centroids và cấu hình huấn luyện.
5. **TC5 — Visual Word Assignment**

   Gán mỗi descriptor vào tâm cụm gần nhất bằng Euclidean distance. Lưu ánh xạ từ patch sang visual word.
6. **TC6 — Transaction Encoding**

   Gom các visual word IDs của một ảnh, loại trùng và sắp xếp để tạo transaction. Không thêm class label vào transaction.
7. **TC7 — Export & Validation**

   Xuất 70.000 transaction logic, ánh xạ TID–image_id, codebook, metadata cấu hình và thống kê kiểm tra.

## **5. Một quyết định kỹ thuật quan trọng: K-means Codebook**

EDA-1 chưa xác định được giá trị \\(K\\) tối ưu. Vì vậy, mình đề xuất thử các giá trị ban đầu:

**Số Visual Words (K)**

Ứng viên thực nghiệm

32

64

128

Standard BoVW

# **32 items**

3-region Spatial BoVW

# **96 items**

Đây là kích thước vocabulary tối đa theo cấu hình, chưa phải số item thực tế xuất hiện trong transactions.

Các giá trị 32, 64, 128 là **đề xuất thử nghiệm của mình**, không phải những giá trị được EDA-1 xác nhận.

### **Cách huấn luyện để so sánh công bằng**

Mình khuyên:

- Dùng cùng một tập ảnh, seed và chính sách lấy mẫu descriptor giữa các thí nghiệm có thể so sánh.
- Bắt đầu với khoảng 100.000–200.000 descriptors được lấy mẫu trải đều theo ảnh; sau đó kiểm tra độ ổn định của codebook.
- **Ở T1, T2, T3:** dùng chung một codebook 4×4 cho mỗi giá trị \\(K\\) trong phép so sánh có kiểm soát, để sự khác biệt về transaction chủ yếu đến từ filtering. Tập học codebook nên bao phủ cả patches nền và patches được giữ, tránh thiên lệch quá mức về một loại.
- **Ở T4, T5:** huấn luyện codebook 7×7 riêng vì descriptors có 49 chiều, rồi dùng chung codebook đó để đối chứng filtering.
- Sau phép so sánh có kiểm soát, có thể huấn luyện lại codebook chuyên biệt cho pipeline được chọn để kiểm tra liệu hiệu quả có cải thiện hay không.

Phân biệt hai câu hỏi: *Filtering thay đổi transactions như thế nào nếu codebook giữ nguyên?* và *Pipeline hoàn chỉnh nào tốt hơn khi được huấn luyện riêng?*

Hai câu hỏi này không nên trộn vào cùng một thí nghiệm.

# **6. TC phải lưu những dữ liệu gì?**

Mình đề xuất tối thiểu bốn nhóm output.

| Output              | Nội dung                                              | Mục đích             |
| ------------------- | ----------------------------------------------------- | -------------------- |
| `transactions`      | TID và tập item IDs                                   | Đầu vào Eclat        |
| `patch_assignments` | image_id, patch_id, tọa độ, keep flag, visual_word_id | Truy vết visual word |
| `codebook`          | Centroids và thông số K-means                         | Tái lập biểu diễn    |
| `tc_metadata`       | Patch size, filtering, descriptor, K, seed, encoding  | Quản lý thí nghiệm   |

Ví dụ một ảnh được gán visual words:

```
Image ID: 1024

Patch IDs:      [1, 2, 3, 4, 5]
Visual Word IDs:[8, 8, 12, 25, 12]

Transaction:    {8, 12, 25}
```

Sau khi encode, cần giữ được đúng **70.000 transaction logic**, kể cả transaction rỗng. Không được tự động xóa chúng nếu làm vậy thay đổi mẫu số support.

Đây cũng là lý do mình khuyên giữ một định dạng trung gian có TID rõ ràng, bên cạnh file transaction TXT dành cho Eclat.

# **7. EDA-2 phải trả lời những câu hỏi nào để chọn TC cuối cùng?**

Đây là phần còn thiếu để chuyển những đề xuất từ EDA-1 thành quyết định có căn cứ.

| Câu hỏi EDA-2                                   | Metric cần tính                                     | Vì sao quan trọng?                           |
| ----------------------------------------------- | --------------------------------------------------- | -------------------------------------------- |
| Transaction có quá dài hoặc quá ngắn không?     | Mean, median, P95 transaction length                | Ảnh hưởng độ phức tạp Eclat                  |
| Có nhiều transaction rỗng không?                | Empty transaction rate                              | Kiểm tra mất biểu diễn ảnh                   |
| Codebook có được sử dụng tốt không?             | Vocabulary utilization, word frequency distribution | Phát hiện nhiều visual words không xuất hiện |
| Có item xuất hiện trong gần như mọi ảnh không?  | Singleton support                                   | Tránh patterns quá phổ biến, ít đặc trưng    |
| Có sự đồng xuất hiện đủ đa dạng không?          | Pair co-occurrence, frequent pairs                  | Đánh giá tiềm năng khai thác tập phổ biến    |
| Filtering thay đổi transactions thế nào?        | Các metrics trên khi giữ chung codebook             | Đo tác động thực tế của filtering            |
| Eclat khai thác được patterns có ý nghĩa không? | Itemset count, runtime, pattern visualization       | Đánh giá giá trị thực tế của encoding        |

Sau EDA-2, có thể thực hiện pilot Eclat với một dải `minsup` chung, chẳng hạn 1%, 2% và 5%, tương ứng 700, 1.400 và 3.500 ảnh trên toàn tập 70.000. Đây là các mức thử nghiệm đề xuất, chưa phải `minsup` cuối cùng.

Không nên lựa chọn TC chỉ vì nó tạo ra nhiều frequent itemsets nhất. Chúng ta cần xem xét cả khả năng diễn giải visual words, mức trùng lặp pattern và chi phí khai thác.

# **8. Thứ tự thực hiện mình khuyên dùng**

**TC Execution Plan**

Thực hiện theo thứ tự

Bước 1

**Xây dựng T1 và T2**

Hoàn thiện pipeline end-to-end trên patch 4×4 với raw descriptor

Bước 2

**Thử K = 32, 64, 128**

Đánh giá codebook, word assignment và transactions

Bước 3

**Bổ sung T3**

So sánh τ=10 với Q10+ trên cùng codebook

Bước 4

**Chạy EDA-2**

Đánh giá transaction length, support, density và vocabulary utilization

Bước 5

**Bổ sung T4, T5 nếu cần**

Kiểm chứng tác động của patch size 7×7

Bước 6

**Thử gradient và spatial encoding**

Chỉ mở rộng khi kết quả các bước trước tạo lý do rõ ràng

Bước 7

**Pilot Eclat và chốt pipeline**

So sánh khả năng khai thác, chi phí và tính dễ diễn giải

## **9. Kết luận: Những quyết định mình đề xuất chốt**

| Thành phần           | Quyết định                                    |
| -------------------- | --------------------------------------------- |
| Patch size           | **4×4, stride 4** làm chính; 7×7 là đối chứng |
| Patch filtering      | **Q10+ = 29, α=0** làm ứng viên chính         |
| Filtering đối chứng  | No-filter và τ=10, α=0                        |
| Feature extraction   | **Dense patches**, chưa ưu tiên SIFT/ORB      |
| Descriptor           | **Raw pixel/255** làm baseline                |
| K-means              | Thử K = 32, 64, 128                           |
| Transaction encoding | **Binary Standard BoVW** làm baseline         |
| Spatial              | Thử top/middle/bottom sau vòng đầu            |
| Dữ liệu              | Toàn bộ 70.000 ảnh, giữ metadata để truy vết  |

**Đề xuất thực hiện ngay:** Bắt đầu với **T1 (4×4, no-filter)** và **T2 (4×4, Q10+ α=0)**, dùng raw pixel descriptors và chung codebook cho các phép so sánh filtering.

Hai cấu hình này đủ để xây dựng và kiểm thử toàn bộ TC1–TC7, đồng thời trả lời câu hỏi quan trọng đầu tiên mà EDA-1 chưa thể giải quyết: **Việc loại 37,5% patches có thực sự giúp tạo ra một cơ sở dữ liệu giao dịch tốt hơn để khai thác bằng Eclat hay không?**