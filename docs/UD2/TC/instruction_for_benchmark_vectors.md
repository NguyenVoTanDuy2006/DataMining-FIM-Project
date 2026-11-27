# INSTRUCTION — Execute TC4 K-means Benchmark

## 1. Objective

Nhiệm vụ của bạn là **thực thi notebook benchmark K-means thay cho người dùng**.

Notebook:

```text
/run/media/fernir/Data/Documents/HCMUS/SEMESTER7/DataMining/TeamProject-FrequentItemsetMining/notebooks/fashion-mnist/04_tc4_vector_pre_kmeans_tradeoff_60k.ipynb
```

Chạy lần lượt các giá trị:

```julia
K_VALUES = [16, 32, 64, 128, 256]
```

**Bắt buộc chạy lại từ K=16**, không bỏ qua bất kỳ giá trị nào.

Notebook đã triển khai đầy đủ logic benchmark, metrics và lưu kết quả. Bạn chỉ cần điều khiển việc thực thi các cell.

## 2. Cell Configuration

**Cell chỉnh tham số K:**

```text
1f4509bb
```

**Danh sách cell cần chạy theo đúng thứ tự:**

```text
72dff2cf
96602191
df581b19
caa2d26f
8e02e966
9b45b9bc
d2eeb519
a50f5986
997a6587
65f2326b
9add36c1
```

## 3. Execution Procedure

Với mỗi giá trị K trong `[16, 32, 64, 128, 256]`, thực hiện:

### Step 1 — Set and Execute K Cell

1. Đi đến cell ID `1f4509bb`.
2. Chỉnh tham số K thành giá trị hiện tại.
3. **Thực thi ngay cell `1f4509bb` để bảo đảm giá trị K được cập nhật trong Julia kernel.**
4. Chỉ chuyển sang bước tiếp theo sau khi cell này thực thi thành công.

**Quan trọng:** Không được chỉ sửa nội dung cell mà quên thực thi cell đó.

### Step 2 — Execute Benchmark Cells

Chạy tuần tự các cell:

```text
72dff2cf
→ 96602191
→ df581b19
→ caa2d26f
→ 8e02e966
→ 9b45b9bc
→ d2eeb519
→ a50f5986
→ 997a6587
→ 65f2326b
→ 9add36c1
```

Quy tắc:

- Thực thi đúng thứ tự.
- Chờ cell hiện tại hoàn thành trước khi chạy cell tiếp theo.
- Không bỏ qua cell.
- Không chạy nhiều K song song.
- Không chạy thêm benchmark ngoài danh sách.

### Step 3 — Confirm Execution

Sau khi cell cuối cùng `9add36c1` kết thúc:

1. Xác nhận tất cả các cell đã thực thi thành công.
2. Xác nhận không có exception hoặc lỗi thực thi chưa xử lý.
3. Xác nhận lượt benchmark với K hiện tại đã hoàn thành.

Không cần phân tích metrics hoặc kiểm tra nội dung kết quả.

### Step 4 — Repeat for Next K

Nếu lượt chạy hiện tại thành công:

1. Quay lại cell `1f4509bb`.
2. Chỉnh sang giá trị K tiếp theo.
3. **Chạy lại cell `1f4509bb`.**
4. Chạy lại toàn bộ các cell trong Step 2.
5. Xác nhận kết quả thực thi ở Step 3.

Tiếp tục đến khi hoàn thành K=256.

## 4. Execution Order

```text
K = 16
  → Edit & RUN cell 1f4509bb
  → RUN 11 benchmark cells
  → Confirm SUCCESS

K = 32
  → Edit & RUN cell 1f4509bb
  → RUN 11 benchmark cells
  → Confirm SUCCESS

K = 64
  → Edit & RUN cell 1f4509bb
  → RUN 11 benchmark cells
  → Confirm SUCCESS

K = 128
  → Edit & RUN cell 1f4509bb
  → RUN 11 benchmark cells
  → Confirm SUCCESS

K = 256
  → Edit & RUN cell 1f4509bb
  → RUN 11 benchmark cells
  → Confirm SUCCESS

STOP
```

## 5. Strict Constraints

Bạn **chỉ được phép**:

- Thay đổi giá trị K trong cell `1f4509bb`.
- Thực thi các cell được chỉ định.
- Theo dõi việc thực thi.
- Xác nhận SUCCESS hoặc báo cáo lỗi.

Không được:

- Chỉnh sửa logic notebook.
- Thay đổi tham số khác ngoài K.
- Chỉnh sửa metrics.
- Chỉnh sửa cơ chế lưu kết quả.
- Kiểm tra hoặc tái sử dụng kết quả K trước đó để skip.
- Bỏ qua K=16 hoặc K=32.
- Tự ý chạy thêm thí nghiệm.
- Phân tích hay tổng hợp kết quả.
- Tự sửa code nếu gặp lỗi.

## 6. Error Handling

Nếu một cell thực thi thất bại:

1. **Dừng quá trình benchmark.**
2. Ghi nhận giá trị K đang chạy.
3. Ghi nhận Cell ID gặp lỗi.
4. Báo cáo lỗi/traceback cho người dùng.
5. Không tự sửa lỗi hoặc chuyển sang K tiếp theo.

Không đánh dấu SUCCESS khi còn lỗi thực thi.

## 7. Final Report

Sau khi chạy xong, chỉ cần báo cáo trạng thái:

```text
TC4 K-means Benchmark Execution

K=16   : SUCCESS
K=32   : SUCCESS
K=64   : SUCCESS
K=128  : SUCCESS
K=256  : SUCCESS

Overall Status: COMPLETED
```

Nếu có lỗi, báo cáo giá trị K và cell bị lỗi thay vì đánh dấu COMPLETED.

## 8. Stop Condition

Dừng ngay sau khi **K=256 hoàn thành và tất cả các cell đã thực thi thành công**.

Không thực hiện bất kỳ tác vụ bổ sung nào.

**Core principle: Set K → RUN K cell → RUN benchmark cells sequentially → Confirm → Next K.**

