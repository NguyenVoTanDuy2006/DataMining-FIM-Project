# Cấu hình lần đo

- Thời điểm địa phương: 2026-11-16T08:03:25.714
- Julia: 1.13.3
- CPU: tigerlake
- Số CPU logic: 8
- Số luồng Julia: 1
- Hệ điều hành: NT / x86_64
- RAM máy (GiB): 15.73
- Số lần ghi nhận mỗi backend / cấu hình: 5
- Java: `C:\Program Files\Eclipse Adoptium\jdk-25.0.1.8-hotspot\bin\java.exe`; phiên bản trong java_version.txt
- SHA-256 spmf.jar: `2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0`
- SHA-256 chương trình điều khiển tại thời điểm đo: `5a21705fc1c8f296e8ca3bfb757cdbd07e3c72097d0ef74ef6a66c6235eca391`
- SHA-256 mine_once.jl tại thời điểm đo: `b1842cf0c35b0d9a10bac06bee871a5c285daea7eecdf03e576fec07b6fc72bf`

Mã chạy lại nằm trong `scripts/`. Chỉ lưu checksum, không sao chép mã nguồn;
checksum có thể khác nếu sửa script sau lần đo.

## Phương pháp

Mỗi lần tạo tiến trình mới. Tính khởi động runtime, nạp package/lớp, JIT, đọc dữ liệu, dựng TID-set, khai thác và ghi file kết quả/log.
Chuẩn hóa dữ liệu, tạo lệnh, mở log và đối chiếu kết quả không tính vào thời gian.
Mỗi cấu hình chạy chuẩn bị một lần cho mỗi backend; các lần đo sau vẫn tạo tiến trình mới và vẫn tính JIT. Không phải đo cold disk cache.
Chạy tuần tự, luân phiên thứ tự Julia/SPMF giữa các lần; lấy median, giữ min/max và mọi số đo gốc. Đối chiếu toàn bộ Dict sau mỗi cặp chạy.
Giữ cùng số giao dịch, ID và minsup; Julia Set baseline và SPMF Eclat. Không so trực tiếp với các CSV đo mine sau warm-up trước đó.
Không đo peak RSS, không dùng Maximum memory usage của Java thay cho peak RSS.

## Dữ liệu

- retail: 88162 giao dịch; ID +1; minsup = [0.1, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005]; SHA-256 đầu vào: `417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36`
- chess: 3196 giao dịch; ID +0; minsup = [0.95, 0.925, 0.9, 0.875, 0.85, 0.825, 0.8]; SHA-256 đầu vào: `341d0ff8676e053dd3b417d61f84c732736154f987ce56975a099b07460957f5`
- mushroom: 8124 giao dịch; ID +0; minsup = [0.95, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4]; SHA-256 đầu vào: `06206c73983251a9488414c4379a030e836bbeb6fe9eff1b5624a0193a811640`
- T10I4D100K: 100000 giao dịch; ID +1; minsup = [0.03, 0.025, 0.02, 0.015, 0.01, 0.0075, 0.005]; SHA-256 đầu vào: `fb2dd118ff822ff88d724e47d5a4cea6531c0bd6294397db4d36890c1450f1a7`

Nguồn SPMF: https://www.philippe-fournier-viger.com/spmf/download.php
Nguồn dữ liệu: https://fimi.uantwerpen.be/data/

## Kiểm chứng sau khi đo

- Bộ test dự án: 95/95 pass. Kiểm tra tập trung cho CLI, parser và worker: 21/21 pass.
  Không tạo test_results.txt và không chèn output test cuối vào README.
