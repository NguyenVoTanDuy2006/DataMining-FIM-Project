# Thông tin phép đo ảnh hưởng độ dài giao dịch

- Thời điểm địa phương: 2026-11-16T11:04:58.616
- Julia: 1.13.3; hệ điều hành: NT; kiến trúc: x86_64
- CPU: tigerlake; số CPU logic: 8
- RAM máy (GiB): 15.73
- Số luồng tiến trình đo: 1; số lần đo mỗi phiên bản/CSDL: 5
- N cố định: 5000; M cố định: 64
- Các độ dài: [4, 8, 12, 16, 20]; mỗi giao dịch có đúng L item, nên độ dài trung bình bằng L.
- Minsup cố định: 0.05; min_count cố định: 250
- Seed: 20261116; bộ sinh: Random.MersenneTwister; phép chọn: randperm.
- Giới hạn thời gian mỗi tiến trình (giây): 600.0
- SHA-256 JAR SPMF: 2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0
- Phiên bản Java: java_version.txt.

## Thiết kế CSDL tổng hợp

Với mỗi TID, tạo một hoán vị ngẫu nhiên riêng của các item 1:M. Mỗi mức L lấy L item đầu của cùng hoán vị cho TID đó, rồi sắp tăng dần. Các TID khác nhau dùng các hoán vị khác nhau.
Khi tăng L, chỉ thêm item vào cùng giao dịch, giữ N và tập item quan sát được là M. Không nhân bản CSDL hoặc chèn item trùng trong một giao dịch; giữ nguyên các giao dịch có nội dung trùng nhau.
Mật độ bằng L/M, tổng số lần xuất hiện item bằng N×L. Các itemset/support của mức ngắn không giảm ở mức dài khi min_count cố định. Đã kiểm tra quan hệ này trên các tham chiếu SPMF.
Dữ liệu sinh nằm trong data/benchmark/processed/transaction_length/, được Git-ignore. Đây là một họ CSDL có cùng seed, không phải các lần sinh dữ liệu độc lập.

- L=4: độ dài trung bình=4.0; số item quan sát=64; tổng số lần xuất hiện=20000; mật độ=0.0625
  - SHA-256 đầu vào: 84c870c7eb650b2312cb35383086d2b0922db38895a1bc01e3d28ad86ce55051
  - SHA-256 tham chiếu SPMF: aa1db4fc219aac0bef4f3e4ae9e36301390d5903594bbe1b4f4030d5a041bc18
- L=8: độ dài trung bình=8.0; số item quan sát=64; tổng số lần xuất hiện=40000; mật độ=0.125
  - SHA-256 đầu vào: 708b50f1919280478a45d38870950be2f235951c73e4bfc6d60d84db0e687dd2
  - SHA-256 tham chiếu SPMF: 247473a9479b8d5b5edf524c834e2441347941550fa54271638496ddc92601bf
- L=12: độ dài trung bình=12.0; số item quan sát=64; tổng số lần xuất hiện=60000; mật độ=0.1875
  - SHA-256 đầu vào: fb4e9f54b22474072f75ed0851f2d92fda5c8ba440ccd6c40b3d9a60fdedae55
  - SHA-256 tham chiếu SPMF: 08613f3b36e4566bcff4b43e075821c25f754cde52e74935b9a35cbaa743bc8b
- L=16: độ dài trung bình=16.0; số item quan sát=64; tổng số lần xuất hiện=80000; mật độ=0.25
  - SHA-256 đầu vào: be405d3da755587faafd1b05ed0a859a5a8b82de3d32fac1b4849eb06693cb29
  - SHA-256 tham chiếu SPMF: ea2c85224270e27d6178d96605fde922730ce2994503470832a75b78f7657d3c
- L=20: độ dài trung bình=20.0; số item quan sát=64; tổng số lần xuất hiện=100000; mật độ=0.3125
  - SHA-256 đầu vào: e60a2fd458d8b4053d4758be5711298b1631a54e5c7663da011a37187e4bcea0
  - SHA-256 tham chiếu SPMF: 830c6bdadf70e04a3eea704996d06e00270cd93fee8213edce8ebc94f55093e4

## Phạm vi đo

Dùng cùng worker với scalability. Mỗi mẫu tạo tiến trình Julia mới, một backend, một luồng. Đọc input; warm-up một lần mine trên đúng toàn bộ CSDL/cùng minsup; GC; @elapsed đo một lần mine.
Không tính khởi động, đọc input, warm-up/JIT, GC trước đo, ghi output và correctness. GC bên trong mine vẫn được tính. Đảo thứ tự Set/BitVector giữa các lần; lưu trung vị, min/max và từng mẫu.
SPMF chỉ tạo tham chiếu correctness ngoài phép đo. Mỗi output Julia phải khớp toàn bộ itemset/support. Thí nghiệm này đo runtime và số itemset, không đo lại Peak RAM hoặc runtime SPMF.
Tăng L đồng thời tăng mật độ và có thể làm tăng số ứng viên/output: đây là các cơ chế ảnh hưởng của độ dài giao dịch, không phải phép đo tách riêng từng nguyên nhân. Một seed và dải tham số không đại diện mọi CSDL.

## Mã SHA-256 của mã nguồn tại thời điểm đo

- Project.toml: fa1f9d95778b509cc39740a54768d32dcd25a6889b2b4192ad14d25d88ee6b09
- scripts\benchmark_peak_ram.jl: 693e58c2eb1b0c9c16b35c42c7b682f66748c77a871ca0d49cfe6925151e2f18
- scripts\benchmark_processes.jl: c29ad666f5c841b2357aa5e4ff35b3f8f9d563d16fa182df016c3480f01efa13
- scripts\benchmark_scalability.jl: f68c22582c8a355bc622f18db8889b5053db7fab3eafd46a2f3426f658bde489
- scripts\benchmark_transaction_length.jl: 9854dad84dcf25efab3ec3e2217a7e950c394b3ee87d8b44bb3dfb7899bf538f
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
