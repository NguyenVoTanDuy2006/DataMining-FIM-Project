Với bài toán **Visual Pattern Mining sử dụng Eclat**, mình đề xuất bạn thực hiện EDA theo **2 giai đoạn**:

1. **Image-level EDA:** Khám phá đặc điểm của tập ảnh để quyết định cách trích xuất đặc trưng và xây dựng Visual Vocabulary.
2. **Transaction-level EDA:** Sau khi chuyển ảnh thành transaction, phân tích dữ liệu giao dịch để quyết định tham số Eclat, đặc biệt là `minsup`.

Điểm quan trọng là EDA không chỉ để hiểu tập ảnh, mà còn phải trả lời được: **Dataset này có phù hợp để khai thác Frequent Itemsets hay không?**

Trong `itemset.md`, giảng viên yêu cầu giải thích quyết định chuyển đổi ảnh thành transaction, nhưng không quy định một checklist EDA cụ thể. Vì vậy, dưới đây là quy trình mình đề xuất cho đồ án của bạn.

## **1. Tổng quan quy trình**

**Raw Image Dataset**

Ảnh và metadata (nhãn lớp nếu có)

**EDA 1 — Image-level**

Chất lượng, kích thước, lớp, độ trùng lặp, đặc trưng ảnh

**Feature Extraction + Visual Vocabulary**

SIFT → K-means → Visual Words

**EDA 2 — Transaction-level**

Số item, transaction length, sparsity, item support

**Eclat → Frequent Itemsets**

## **2. Giai đoạn 1: Image-level EDA**

### **A. Dataset overview**

Đầu tiên cần hiểu cấu trúc tập dữ liệu.

| Phân tích                | Mục đích                                    |
| ------------------------ | ------------------------------------------- |
| Tổng số ảnh              | Biết quy mô dataset                         |
| Số lớp và số ảnh mỗi lớp | Phát hiện mất cân bằng lớp                  |
| Kích thước ảnh (W × H)   | Quyết định có cần resize                    |
| Aspect ratio             | Phát hiện ảnh có tỷ lệ quá khác nhau        |
| Định dạng ảnh            | Kiểm tra JPG, PNG, grayscale, RGB           |
| Corrupted images         | Xác định ảnh không đọc được                 |
| Duplicate images         | Tránh ảnh trùng tạo ra pattern phổ biến giả |

Ví dụ: Trực quan phân phối nhãn lớp

Dữ liệu minh họa giả định, không phải kết quả của dataset thực tế.

03507001K1.4KCatDogBirdCar

Số liệu minh họa. Nếu có nhãn, biểu đồ này giúp kiểm tra sự cân bằng dữ liệu trước khi khai thác.

### **B. Image quality analysis**

Phân tích chất lượng ảnh vì chất lượng ảnh ảnh hưởng trực tiếp đến descriptors thu được.

| Đặc trưng          | Phương pháp                      | Mục đích                       |
| ------------------ | -------------------------------- | ------------------------------ |
| Brightness         | Mean pixel intensity             | Kiểm tra ảnh quá tối hoặc sáng |
| Contrast           | Standard deviation của intensity | Phát hiện ảnh ít tương phản    |
| Blur               | Variance of Laplacian            | Phát hiện ảnh bị mờ            |
| Color distribution | RGB/HSV histogram                | Hiểu đặc điểm màu sắc          |
| Texture / Edges    | Edge density                     | Ước lượng mức độ chi tiết ảnh  |

Các biểu đồ nên có: histogram phân phối brightness, contrast, blur score; boxplot theo lớp nếu có nhãn; và một grid ảnh đại diện, ảnh tối, mờ hoặc bất thường.

Không cần xử lý toàn bộ vấn đề phát hiện được. Mục tiêu là xác định những yếu tố ảnh hưởng tới bước feature extraction.

### **C. Feature extractability — Rất quan trọng**

Đây là phần mình nghĩ **nên ưu tiên nhất** đối với bài toán Eclat.

Nếu bạn sử dụng SIFT, hãy chạy thử trên một mẫu ảnh để phân tích:

- Số lượng keypoints/descriptors trên mỗi ảnh.
- Tỷ lệ ảnh không có descriptor.
- Phân phối số keypoints theo từng lớp.
- Những vùng ảnh thường được SIFT phát hiện keypoints.

[Computer Vision Project](https://images.openai.com/static-rsc-4/7oOgO3b3PcOek06cwt8u03xnyKe41TPDvZiTzes7qoo1yzDWF2hLzMeY1y0InKaLmlwIANWvhd0OUk8yuwgTkoaZebAa2ROXNREldSPnUVeoxwxzM0-eDC8JIKfEcjNftgzd4YxU56t4LVhOnfgMKAPx5TsFKGUJPy4waBVajXc?purpose=inline)

[Построение SIFT дескрипторов и задача сопоставления изображений / Хабр](https://images.openai.com/static-rsc-4/wuEmvElDAeqFQXvJLEq6wAg6oNxFCgTAg2vt3ausU2QM_j1T7KonjCRT5oKtxPw2X1SXBSYvrFT5c6SxczRne-SJUvUzGYWSqPHBstVo895xoeVX3d68lKn_5ZRaw5k0QvCHcg6Iij8rNn9s3e18vINWUSRHPbfI1_RdJ7nwudo?purpose=inline)

[Introduction to SIFT (Scale-Invariant Feature Transform)](https://images.openai.com/static-rsc-4/AIBhH4i2kxu2g9rohUumtHtNaLjkdBdDCxSJyApt4G5r12vkbKBD86KuBsqw2QsYVR99NfKLqE_xwILKnNlwp4zgjr5lKpub5ZQAGdZga3hiQbUQjdB5MI_55cRdg1yVD2mQrbqSv6OHZ9LWU3T6aLaKdr4RXikZBnQRv2-mPsg?purpose=inline)

8

Ví dụ một ảnh có 200 descriptors, trong khi ảnh khác chỉ có 3 descriptors. Sau khi xây dựng visual vocabulary, hai ảnh này có thể tạo ra transaction với độ dài rất khác nhau.

Đây là vấn đề cần phát hiện trước khi đưa dữ liệu vào Eclat.

## **3. Giai đoạn 2: Transaction-level EDA**

Sau khi xây dựng Visual Vocabulary, mỗi ảnh được chuyển thành một transaction.

Giả sử bạn sử dụng `K = 100` visual words, dữ liệu thu được có dạng:

| Image ID | Transaction | Length |
| -------- | ----------- | ------ |
| 1        | 312254067   | 5      |
| 2        | 3123867     | 4      |
| 3        | 1225406790  | 5      |
| 4        | 34067       | 3      |

Đây chính là dữ liệu mà Eclat sẽ xử lý.

### **Các thống kê quan trọng**

| Phân tích                       | Mục đích                                             |
| ------------------------------- | ---------------------------------------------------- |
| Số transactions                 | Kiểm tra số ảnh chuyển đổi thành công                |
| Số distinct items               | Biết bao nhiêu visual words thực sự được sử dụng     |
| Transaction length distribution | Phân tích số visual words riêng biệt mỗi ảnh         |
| Dataset density / sparsity      | Đánh giá dữ liệu thưa hay dày                        |
| Item support distribution       | Biết những visual words nào phổ biến                 |
| Co-occurrence analysis          | Phân tích các cặp visual words thường cùng xuất hiện |

Đặc biệt, tính:

\\[ Density = \frac{\sum\_{i=1}^{N}|T_i|}{N\times M} \\]

Trong đó \\(N\\) là số transaction, \\(M\\) là số item phân biệt thực sự có trong dữ liệu và \\(|T_i|\\) là số item trong transaction thứ \\(i\\).

Density càng cao thì các transaction càng chứa nhiều item so với kích thước vocabulary, có thể làm số lượng tổ hợp ứng viên lớn hơn.

### **Phân tích support để chọn minsup**

Với từng visual word \\(v\\):

\\[ sup(v)=\frac{|\\{T_i:v\in T_i\\}|}{N} \\]

Vẽ biểu đồ phân phối support của các visual words và kiểm tra xem có quá nhiều item xuất hiện trong gần như tất cả các ảnh không.

Ví dụ nếu hầu hết visual words đều có support trên 90%, dataset có thể sinh ra rất nhiều itemsets, nhưng một số pattern có thể không đủ đặc trưng để mang ý nghĩa hữu ích.

Ngược lại, nếu đa số visual words chỉ xuất hiện ở dưới 1% số ảnh, chọn `minsup = 10%` có thể khiến Eclat tìm được rất ít hoặc không có itemset.

Vì vậy, **minsup nên được lựa chọn sau khi quan sát phân phối support**, thay vì đặt tùy ý.

## **4. Những quyết định EDA cần giúp bạn đưa ra**

| Câu hỏi                          | Quyết định liên quan                                                |
| -------------------------------- | ------------------------------------------------------------------- |
| Ảnh có kích thước quá khác nhau? | Resize hoặc chuẩn hóa kích thước                                    |
| Nhiều ảnh quá mờ, ít keypoints?  | Lọc ảnh lỗi hoặc điều chỉnh feature extractor                       |
| Visual words quá phổ biến?       | Xem lại codebook và khả năng xuất hiện pattern nền                  |
| Transaction quá dài?             | Điều chỉnh kích thước vocabulary hoặc quy tắc lựa chọn visual words |
| Transaction quá thưa?            | Kiểm tra descriptor extraction và cách mã hóa                       |
| Dataset có nhiều ảnh trùng?      | Loại trùng trước khi khai thác                                      |
| Support phân bố như thế nào?     | Chọn dải `minsup` để thử nghiệm Eclat                               |

Một điểm cần kiểm soát là ảnh chứa nhiều keypoints không nhất thiết tạo transaction dài tương ứng, vì các keypoints có thể cùng ánh xạ đến một visual word. Do đó cần đánh giá cả số descriptors ban đầu lẫn số visual words *phân biệt* sau mã hóa.

## **5. Cấu trúc notebook mình đề xuất**

```
notebooks/
├── 01_image_eda.ipynb
│   ├── Dataset Overview
│   ├── Class Distribution
│   ├── Image Dimensions
│   ├── Image Quality
│   ├── Duplicates & Corruption
│   └── SIFT Keypoint Analysis
│
├── 02_transaction_construction.ipynb
│   ├── Feature Extraction
│   ├── Visual Vocabulary (K-means)
│   └── Image-to-Transaction Encoding
│
├── 03_transaction_eda.ipynb
│   ├── Transaction Statistics
│   ├── Transaction Length Distribution
│   ├── Dataset Density
│   ├── Item Support Distribution
│   └── MinSup Selection
│
└── 04_eclat_application.ipynb
    ├── Frequent Itemset Mining
    ├── Pattern Analysis
    ├── Visualizations
    └── Interpretation
```

Đây là cấu trúc đề xuất, không phải cấu trúc notebook bắt buộc trong đề.

## **6. Thứ tự ưu tiên**

Nếu nhóm muốn tránh làm EDA lan man, mình đề xuất checklist trọng tâm sau:

**Checklist triển khai**

0/7 hoàn thành

Dataset overview, phân phối lớp và kích thước ảnh

Chuẩn bị dữ liệu

Phát hiện ảnh lỗi và ảnh trùng lặp

Chuẩn bị dữ liệu

Phân tích brightness, contrast và blur

EDA ảnh

Phân tích số SIFT keypoints/descriptors

EDA ảnh

Xây dựng Visual Vocabulary và transactions

Chuyển đổi dữ liệu

Phân tích transaction length và density

EDA giao dịch

Phân tích item support và lựa chọn minsup

EDA giao dịch

**Kết luận:** Đối với đồ án này, mình sẽ không dành quá nhiều thời gian cho EDA pixel-level thuần túy. Hãy tập trung vào những phân tích ảnh hưởng trực tiếp đến **Feature Extraction → Transaction Encoding → Eclat**, vì đó mới là chuỗi quyết định kỹ thuật cần bảo vệ trước giảng viên.

Khi bạn đã có dataset cụ thể, mình có thể giúp thiết kế EDA sát với đặc điểm dữ liệu và xác định chính xác những biểu đồ, thống kê nào nên đưa vào báo cáo.