# Thông tin phép đo Scalability — Retail

- Thời điểm địa phương: 2026-11-16T10:31:56.647
- Julia: 1.13.3; hệ điều hành: NT; kiến trúc: x86_64
- CPU: tigerlake; số CPU logic: 8
- RAM máy (GiB): 15.73
- Số luồng mỗi tiến trình đo: 1; số lần đo mỗi phiên bản/tập con: 5
- Minsup tương đối cố định: 0.04; min_count = ceil(minsup × số giao dịch tập con).
- Số giao dịch Retail đầy đủ: 88162; độ dịch ID: +1.
- Seed: 20261116; bộ sinh: Random.MersenneTwister; chọn bằng randperm.
- Giới hạn thời gian mỗi tiến trình (giây): 600.0
- SHA-256 Retail gốc: d967431ba522e32f0fbb243f2ee113ecd4cb374cb0234c1b0858dae1d499a055
- SHA-256 Retail chuẩn hóa đầy đủ: 417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36
- SHA-256 JAR SPMF: 2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0
- Phiên bản Java: java_version.txt.

## Cách lấy tập con

Tạo một hoán vị duy nhất của chỉ số các dòng Retail. Mỗi mức lấy floor(N × phần trăm / 100) chỉ số đầu tiên của cùng hoán vị, rồi sắp lại theo thứ tự dòng gốc. Tập nhỏ nằm trong tập lớn.
Giữ nguyên các giao dịch trùng nhau: chọn theo chỉ số dòng, không khử trùng nội dung. Mức 100% giữ đúng toàn bộ dữ liệu chuẩn hóa. File đầu vào và chỉ số dòng nằm trong data/benchmark/processed/scalability/, được Git-ignore.

- 10%: 8816 giao dịch; min_count=353
  - SHA-256 đầu vào: 41ed1fb5e37ef4381e9c4ea9f985651136c22cd2b7e5ea67df5a837e3eb6e5d2
  - SHA-256 chỉ số dòng: 7f67bb90d833eff948af41ce574db3f577cff349ecc65cf7fa2b688031e4b0c0
  - SHA-256 tham chiếu SPMF: b313822e900c558e46af80504edf388d51679c0843583cef0ade23c0c2ef7966
- 25%: 22040 giao dịch; min_count=882
  - SHA-256 đầu vào: 23c56ef3c9aebd34b4ab80a20a54f10e8ff94aa1ddc0ebf65d499ef6c21dc3b1
  - SHA-256 chỉ số dòng: 49c3d269da0bb558f16507008b16522bef90a0457e0fde1f2f3249644346bc1e
  - SHA-256 tham chiếu SPMF: 4fe303c6596470474270e01ed0880e56db2f5692ebda2f1577d2534db1f0bf33
- 50%: 44081 giao dịch; min_count=1764
  - SHA-256 đầu vào: c688c4fc2219643ef6b9cb6d8f1595b40a5655440666a2fea2e2e7a62a2546fc
  - SHA-256 chỉ số dòng: b67a60a93bafd5013a96a260bb262af18ae6cb85b3cff2d6f217e18657bf7a74
  - SHA-256 tham chiếu SPMF: a18734e8d9e96095e4bb61342943e260924fab04492baf4eb9a34e113c527e8f
- 75%: 66121 giao dịch; min_count=2645
  - SHA-256 đầu vào: 11fa1d4bd64e1b5347d78843386fc6ca04255167e8ebbb20e754baca6438ecc6
  - SHA-256 chỉ số dòng: 85e27f302e6d0bd6f240530022ef0c4dc855d13513fc891ca3068e10e8bf7b72
  - SHA-256 tham chiếu SPMF: fb439cbcb1e3b5dc1beb67cee766473c4e1ca7e884140863f2608249dc293842
- 100%: 88162 giao dịch; min_count=3527
  - SHA-256 đầu vào: 417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36
  - SHA-256 chỉ số dòng: 8233451f80b123a0c6676ead7eac10be951162d051742a9891e89feb4cf9089d
  - SHA-256 tham chiếu SPMF: 563c3a53dbf453a8e7d6e50e803285e7c126d23b2bede51bfff64e79a40528d8

## Phạm vi đo

Mỗi mẫu dùng tiến trình Julia mới và chỉ chạy một backend. Đọc input trước; warm-up một lần trên đúng toàn bộ tập con và cùng minsup; GC; sau đó @elapsed đo một lần mine. Không tính khởi động, đọc dữ liệu, warm-up/JIT, GC trước phép đo, ghi output hoặc correctness. GC phát sinh bên trong mine vẫn nằm trong thời gian đo.
Đảo thứ tự Set/BitVector giữa các lần đo. Báo cáo trung vị, min/max và từng mẫu gốc. Phép đo là wall-clock của mine sau warm-up, không ghép với runtime toàn tiến trình ở processes/.
Tạo SPMF reference cho từng tập con ngoài phần đo. Mỗi output Julia phải khớp toàn bộ itemset/support. SPMF chỉ kiểm chứng correctness, không có đường thời gian SPMF trong thí nghiệm này.
Giữ minsup tương đối cố định; số frequent itemset có thể thay đổi do phân bố tập con và làm tròn ngưỡng. Không yêu cầu runtime hoặc số itemset tăng đơn điệu. Không dùng kết quả năm điểm để chứng minh độ phức tạp tổng quát.

## Mã SHA-256 của mã nguồn tại thời điểm đo

- Project.toml: fa1f9d95778b509cc39740a54768d32dcd25a6889b2b4192ad14d25d88ee6b09
- scripts\benchmark_peak_ram.jl: 693e58c2eb1b0c9c16b35c42c7b682f66748c77a871ca0d49cfe6925151e2f18
- scripts\benchmark_processes.jl: c29ad666f5c841b2357aa5e4ff35b3f8f9d563d16fa182df016c3480f01efa13
- scripts\benchmark_scalability.jl: f68c22582c8a355bc622f18db8889b5053db7fab3eafd46a2f3426f658bde489
- scripts\scalability_worker.jl: 117f30917aa7ef9613f5b6bc6560d3e40f860bead3c6caa2695af1bf03767ad6
- src\EclatFIM.jl: 93bdc2375e1eb58a8f988f84dd321ec3adf693be4552f87ee915339d1d1be5ac
- src\algorithm\EclatBaseline.jl: a08dd0f0dca0c4c69cd50699a126023a0e80c25a4a419b792cc64fbc0bade4e2
- src\algorithm\EclatOptimized.jl: 12ef3ba62cc642cd882199f8a2e0a1bce3e77e31fb5bf707d7f3fb6d10270295
- src\applications\AssociationRules.jl: d57ecf18e08451a53dc3fe8133d53cea5e56e62c750cb2f8353235d85d3f6e76
- src\applications\FashionMNIST.jl: 30efc8ba1fad024828e404129816bc80ef7c7b68ea7fddc40d3308da372055e0
- src\applications\Groceries.jl: fe5d47f75524d8569b919eca67cbd78c8d850a52389d4e1f1df26e96544aa8d6
- src\applications\VisualCodebook.jl: 0d156398c89bd919d21212f7d3db84044d275ec0517f0c756dd552eb6e39e786
- src\applications\VisualMining.jl: a32aebb2c578556a1b0b1ebbdf7da5766efe6d69d8aff8e9ddc0ae1fa3843476
- src\utils\SPMFIO.jl: f5b90bbb444a08feb0cc2c68e9a52afd197e00511b785c097323995d3e07505f

Không cần package Julia bên ngoài; dùng thư viện chuẩn và EclatFIM cục bộ.
Đề bài: https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/
