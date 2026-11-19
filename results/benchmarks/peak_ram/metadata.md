# Thông tin phép đo Peak RAM

- Thời điểm địa phương: 2026-11-16T09:53:58.093
- Julia: 1.13.3; hệ điều hành: NT; kiến trúc: x86_64
- CPU: tigerlake; số CPU logic: 8
- RAM máy (GiB): 15.73
- Số luồng của tiến trình đo: 1; số lần đo mỗi phiên bản/tập dữ liệu: 5
- Giới hạn thời gian mỗi tiến trình đo (giây): 600.0
- Đại lượng đo: Sys.maxrss(), đơn vị byte; MiB = byte / 1024^2.
- Trên Windows, bộ đếm đỉnh là PeakWorkingSetSize qua GetProcessMemoryInfo.
- Phạm vi: từ lúc khởi động tiến trình đến khi mine hoàn tất, trước khi ghi kết quả.
- Bao gồm môi trường thực thi, nạp package/JIT, chạy khởi động trên dữ liệu nhỏ, đọc đầu vào và cấp phát khi khai thác.
- Mỗi mẫu tạo tiến trình mới, chạy khởi động phiên bản được chọn trên cùng bộ dữ liệu nhỏ, rồi thu gom rác (GC) trước khi đọc toàn bộ đầu vào và một lần nữa trước khi gọi mine.
- Bộ đếm đỉnh của tiến trình không thể đặt lại. pre_mine_peak_rss_bytes chỉ phục vụ chẩn đoán; không lấy hiệu hai mức đỉnh để coi là Peak RAM riêng của thuật toán.
- Thứ tự chạy hai phiên bản được đảo giữa các lần đo. Không lấy mẫu theo chu kỳ; đọc bộ đếm mức cao nhất của hệ điều hành.
- Báo cáo trung vị và mức nhỏ nhất/lớn nhất quan sát được của các đỉnh tiến trình độc lập; không phải khoảng tin cậy.
- Khi thất bại, giữ trạng thái/lỗi và nhật ký tiến trình; không báo mẫu thất bại là đạt.

## Lựa chọn tập dữ liệu và minsup

Chọn điểm thứ tư (điểm giữa) trong mỗi dải bảy ngưỡng minsup thử nghiệm, không lấy trung bình cộng hai đầu dải. Giữ nguyên các giỏ hàng trùng nhau.

- retail: N=88162; độ dịch ID=1; dải minsup=[0.1, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005]; mức được chọn=0.04
  - SHA-256 dữ liệu gốc: d967431ba522e32f0fbb243f2ee113ecd4cb374cb0234c1b0858dae1d499a055
  - SHA-256 dữ liệu đã chuẩn hóa: 417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36
  - SHA-256 tham chiếu SPMF được tạo mới: 563c3a53dbf453a8e7d6e50e803285e7c126d23b2bede51bfff64e79a40528d8
- chess: N=3196; độ dịch ID=0; dải minsup=[0.95, 0.925, 0.9, 0.875, 0.85, 0.825, 0.8]; mức được chọn=0.875
  - SHA-256 dữ liệu gốc: a12ea887df58a396709430af5bf0a9a32d1f6eba8e7c13dd41f28b98572c5db2
  - SHA-256 dữ liệu đã chuẩn hóa: 341d0ff8676e053dd3b417d61f84c732736154f987ce56975a099b07460957f5
  - SHA-256 tham chiếu SPMF được tạo mới: f4e090575cd8c2ba13bb9023c6fc86a3a6a240bc67f2e3831128cf1b5e39f1f1
- mushroom: N=8124; độ dịch ID=0; dải minsup=[0.95, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4]; mức được chọn=0.7
  - SHA-256 dữ liệu gốc: 6cf94bc482712c3936f0b40c921381ab2b776c3d9941880fecac4d83ca5cbeb5
  - SHA-256 dữ liệu đã chuẩn hóa: 06206c73983251a9488414c4379a030e836bbeb6fe9eff1b5624a0193a811640
  - SHA-256 tham chiếu SPMF được tạo mới: 961ebf0183e09f98ef68f32234097685a88068eca36c4354391306cf2844c74d
- T10I4D100K: N=100000; độ dịch ID=1; dải minsup=[0.03, 0.025, 0.02, 0.015, 0.01, 0.0075, 0.005]; mức được chọn=0.015
  - SHA-256 dữ liệu gốc: 464d7b87aa7fdc0dc432ddad0493515569b2968b0f229ce39399c454a8c62e0c
  - SHA-256 dữ liệu đã chuẩn hóa: fb2dd118ff822ff88d724e47d5a4cea6531c0bd6294397db4d36890c1450f1a7
  - SHA-256 tham chiếu SPMF được tạo mới: e411b322df0fa9ba208b09911479eb10d4efa083ba71589db3146001a7d914de

Tham chiếu SPMF được tạo mới từ đúng đầu vào đã chuẩn hóa trước khi đo RAM; Java chạy riêng, không thuộc tiến trình được đo RAM.
SHA-256 tệp JAR SPMF: 2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0
Phiên bản Java: xem java_version.txt

## Mã SHA-256 của mã nguồn tại thời điểm đo

- Project.toml: fa1f9d95778b509cc39740a54768d32dcd25a6889b2b4192ad14d25d88ee6b09
- scripts\benchmark_peak_ram.jl: 17a99707cdd34435f8d7cbd959f760b7bc9b6034e6eca03eabb3b5aab1832b97
- scripts\benchmark_processes.jl: c29ad666f5c841b2357aa5e4ff35b3f8f9d563d16fa182df016c3480f01efa13
- scripts\peak_ram_worker.jl: 8831012b9f63a7247f80b46c992d60809616566fa0349b331896342ffaf1443b
- src\EclatFIM.jl: 93bdc2375e1eb58a8f988f84dd321ec3adf693be4552f87ee915339d1d1be5ac
- src\algorithm\EclatBaseline.jl: a08dd0f0dca0c4c69cd50699a126023a0e80c25a4a419b792cc64fbc0bade4e2
- src\algorithm\EclatOptimized.jl: dda834eecccd2d6346510225404117d9a49eba868c226210a1220a0644b493f9
- src\applications\AssociationRules.jl: d57ecf18e08451a53dc3fe8133d53cea5e56e62c750cb2f8353235d85d3f6e76
- src\applications\FashionMNIST.jl: 30efc8ba1fad024828e404129816bc80ef7c7b68ea7fddc40d3308da372055e0
- src\applications\Groceries.jl: fe5d47f75524d8569b919eca67cbd78c8d850a52389d4e1f1df26e96544aa8d6
- src\applications\VisualCodebook.jl: 0d156398c89bd919d21212f7d3db84044d275ec0517f0c756dd552eb6e39e786
- src\applications\VisualMining.jl: a32aebb2c578556a1b0b1ebbdf7da5766efe6d69d8aff8e9ddc0ae1fa3843476
- src\utils\SPMFIO.jl: f5b90bbb444a08feb0cc2c68e9a52afd197e00511b785c097323995d3e07505f

Thư viện phụ thuộc: chỉ dùng thư viện chuẩn Julia và package EclatFIM cục bộ.
Không lấy mẫu ngẫu nhiên; sử dụng toàn bộ giao dịch của từng cơ sở dữ liệu.

Tài liệu tham khảo: [Julia Sys.maxrss](https://docs.julialang.org/en/v1/base/base/#Base.Sys.maxrss), [bộ đếm Windows](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters), [đề bài](https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/).
