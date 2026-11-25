# Thông tin phép đo Scalability — Retail

- Thời điểm địa phương: 2026-11-24T19:46:30.274
- Julia: 1.13.3; hệ điều hành: Linux; kiến trúc: x86_64
- CPU: broadwell; số CPU logic: 2
- RAM máy (GiB): 12.67
- Số luồng mỗi tiến trình đo: 1; số lần đo mỗi phiên bản/tập con: 5
- Minsup tương đối cố định: 0.04; min_count = ceil(minsup × số giao dịch tập con).
- Số giao dịch Retail đầy đủ: 88162; độ dịch ID: +1.
- Seed: 20261116; bộ sinh: Random.MersenneTwister; chọn bằng randperm.
- Giới hạn thời gian mỗi tiến trình (giây): 600.0
- SHA-256 Retail gốc: d967431ba522e32f0fbb243f2ee113ecd4cb374cb0234c1b0858dae1d499a055
- SHA-256 Retail chuẩn hóa đầy đủ: 417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36
- SHA-256 JAR SPMF: bb371b99b3bfd58fbce6b92e0ea3ccda5f9d1fd173bfe8e40f177672117159ba
- Phiên bản Java: java_version.txt.

## Cách lấy tập con

Tạo một hoán vị duy nhất của chỉ số các dòng Retail. Mỗi mức lấy floor(N × phần trăm / 100) chỉ số đầu tiên của cùng hoán vị, rồi sắp lại theo thứ tự dòng gốc. Tập nhỏ nằm trong tập lớn.
Giữ nguyên các giao dịch trùng nhau: chọn theo chỉ số dòng, không khử trùng nội dung. Mức 100% giữ đúng toàn bộ dữ liệu chuẩn hóa. File đầu vào và chỉ số dòng nằm trong data/benchmark/processed/scalability/, được Git-ignore.

- 10%: 8816 giao dịch; min_count=353
  - SHA-256 đầu vào: 41ed1fb5e37ef4381e9c4ea9f985651136c22cd2b7e5ea67df5a837e3eb6e5d2
  - SHA-256 chỉ số dòng: 7f67bb90d833eff948af41ce574db3f577cff349ecc65cf7fa2b688031e4b0c0
  - SHA-256 tham chiếu SPMF: 23c95688b9813b4d4c463714c7bbe9d3c7807b3ccba16e759154e5057a5f221b
- 25%: 22040 giao dịch; min_count=882
  - SHA-256 đầu vào: 23c56ef3c9aebd34b4ab80a20a54f10e8ff94aa1ddc0ebf65d499ef6c21dc3b1
  - SHA-256 chỉ số dòng: 49c3d269da0bb558f16507008b16522bef90a0457e0fde1f2f3249644346bc1e
  - SHA-256 tham chiếu SPMF: a81f26de8654c56b30915ec41b1d9a43177cddc45d087397ff69d0f5cb569354
- 50%: 44081 giao dịch; min_count=1764
  - SHA-256 đầu vào: c688c4fc2219643ef6b9cb6d8f1595b40a5655440666a2fea2e2e7a62a2546fc
  - SHA-256 chỉ số dòng: b67a60a93bafd5013a96a260bb262af18ae6cb85b3cff2d6f217e18657bf7a74
  - SHA-256 tham chiếu SPMF: 78b5ca5a720cf20676ce815fdb93ccc02eaf930bd8078583c0a2c8b64cae65cf
- 75%: 66121 giao dịch; min_count=2645
  - SHA-256 đầu vào: 11fa1d4bd64e1b5347d78843386fc6ca04255167e8ebbb20e754baca6438ecc6
  - SHA-256 chỉ số dòng: 85e27f302e6d0bd6f240530022ef0c4dc855d13513fc891ca3068e10e8bf7b72
  - SHA-256 tham chiếu SPMF: a693965cde16d3d5e005c5c098e4cf3f598427df69cb50950d1e7d7397320b85
- 100%: 88162 giao dịch; min_count=3527
  - SHA-256 đầu vào: 417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36
  - SHA-256 chỉ số dòng: 8233451f80b123a0c6676ead7eac10be951162d051742a9891e89feb4cf9089d
  - SHA-256 tham chiếu SPMF: 97d2df9bdbd935afc49c76e370497cbb73f6989ac0016135c1e2c888273e9135

## Phạm vi đo

Mỗi mẫu dùng tiến trình Julia mới và chỉ chạy một backend. Đọc input trước; warm-up một lần trên đúng toàn bộ tập con và cùng minsup; GC; sau đó @elapsed đo một lần mine. Không tính khởi động, đọc dữ liệu, warm-up/JIT, GC trước phép đo, ghi output hoặc correctness. GC phát sinh bên trong mine vẫn nằm trong thời gian đo.
Đảo thứ tự Set/BitVector giữa các lần đo. Báo cáo trung vị, min/max và từng mẫu gốc. Phép đo là wall-clock của mine sau warm-up, không ghép với runtime toàn tiến trình ở processes/.
Tạo SPMF reference cho từng tập con ngoài phần đo. Mỗi output Julia phải khớp toàn bộ itemset/support. SPMF chỉ kiểm chứng correctness, không có đường thời gian SPMF trong thí nghiệm này.
Giữ minsup tương đối cố định; số frequent itemset có thể thay đổi do phân bố tập con và làm tròn ngưỡng. Không yêu cầu runtime hoặc số itemset tăng đơn điệu. Không dùng kết quả năm điểm để chứng minh độ phức tạp tổng quát.

## Mã SHA-256 của mã nguồn tại thời điểm đo

- Manifest.toml: f92c956c2d97f780309872ea2c4aff1f1ccf2d71a0972b838e50d0146c369b48
- Project.toml: b004265c5a45e4ec69a2ed97119df677e9b75491fba6701a9c7ef2a7f052bcaa
- scripts/benchmark_peak_ram.jl: 693e58c2eb1b0c9c16b35c42c7b682f66748c77a871ca0d49cfe6925151e2f18
- scripts/benchmark_processes.jl: 942601f12a2e5a8e3ea4d943b107bc0e325ef8c887fe17398230546fa68410a9
- scripts/benchmark_scalability.jl: f68c22582c8a355bc622f18db8889b5053db7fab3eafd46a2f3426f658bde489
- scripts/scalability_worker.jl: 117f30917aa7ef9613f5b6bc6560d3e40f860bead3c6caa2695af1bf03767ad6
- src/EclatFIM.jl: eb8c64162470d5d91fd2a71ac4c9631b9298825f3f9f7801370da724d6d0ff2c
- src/algorithm/EclatBaseline.jl: 362409ffdf6edd15c95ee9c8e1e04271a1143a52570923bfb60b4cce2d0266e7
- src/algorithm/EclatCompatibility.jl: 68458116947d98386dc25b20ef50c6ea66cfd78925c7814b7c676316b30ec4ff
- src/algorithm/EclatOptimized.jl: 5ba61cc418b9f62b81f4e41c2df86f1f66e02464d0c1a3e4436433da00642460
- src/applications/AssociationRules.jl: 57167f88594fd79595237675daa2e30872dac7f8a8e9cbd5e51cb60030f26809
- src/applications/Fashion-Mnist/FashionMNIST.jl: 37102fe7bdf36f0df363814c4b4a927f1d2f729fd42f9203360c7f84297dcfab
- src/applications/Fashion-Mnist/FashionTC.jl: 3fc61f6e8ca455d04f3479bdcf8b968995df579e903a95af1ba2adc610774d68
- src/applications/Fashion-Mnist/dataset/FashionMNIST.jl: ff72a14a5e17a08f4254588b265b05af05ecfb2e5122d60bdd083e24b587c43e
- src/applications/Fashion-Mnist/mining/FashionFIMWorkflow.jl: 8c770ebede883ea8577b13c5a50246bc794645c29c154eb64c63c3230b0d0a17
- src/applications/Fashion-Mnist/mining/TransactionInput.jl: e51617d82a99ede2d6041c086f114b41241cceff2d0801abe231a74817fc8f1e
- src/applications/Fashion-Mnist/mining/scripts/run_mining_worker.jl: 038f6666129f866d0f9f071910678f84c4ba07c390a9358d18544e2e0e7d6863
- src/applications/Fashion-Mnist/notebook_tools/install_fashion_tc_kernel.jl: e8e9c7a2721ee81d4a71d073d13e8ab36e6a8034f9b1fc07a864ae27217a43c3
- src/applications/Fashion-Mnist/spatial/FashionTCSpatial.jl: d824e298bd7189fb74d07f8a5eca78512965995ba518c959358f576b2a5ae5d1
- src/applications/Fashion-Mnist/transaction_construction/artifacts/ArchiveExport.jl: 32ee539fc1f2454ffeed2397d064dbf9f42e5829386b05f0bbc0b8b973274b47
- src/applications/Fashion-Mnist/transaction_construction/artifacts/ArtifactIO.jl: fd671610b414761856ee1702a216202c28ace618768c646bc9700a986c64c8df
- src/applications/Fashion-Mnist/transaction_construction/artifacts/Checkpoints.jl: 498a250e1cebc5ef3b77941f70665e2d8abc0df57152c7e3e6ac04174ec28bf1
- src/applications/Fashion-Mnist/transaction_construction/artifacts/CombinedExportValidation.jl: fa5dbab6505aa6a638aa32a0a9db46fee4be5ec21b001aad3c538c470f2b5bdf
- src/applications/Fashion-Mnist/transaction_construction/artifacts/SplitExportValidation.jl: a62def2ec41fdf37cf5dfef32a30bf3df145e1a980a5f1da4028f326a9f3a4cb
- src/applications/Fashion-Mnist/transaction_construction/benchmark/BenchmarkExport.jl: 1daf98f804be15da542a5b99ef3083370800017cd30cc0dea2b6a55a0b568210
- src/applications/Fashion-Mnist/transaction_construction/benchmark/BenchmarkMetrics.jl: dde55e65a2cae9f37168385984fb64eb743035defd071b1aee7124a6fcbd3cbb
- src/applications/Fashion-Mnist/transaction_construction/benchmark/BenchmarkPlots.jl: 9427274545316fab8e9c20f652a7f24af05c6c30346be0126c152395ec522d53
- src/applications/Fashion-Mnist/transaction_construction/benchmark/VectorTradeoff.jl: ce910dbcca16908165da797e2f8221d6148b7ba42d538d6a80e5339459f9c87c
- src/applications/Fashion-Mnist/transaction_construction/benchmark/WeightedBenchmark.jl: 0f849954442e0773ff6fa4d645c3e6f421358f8f91da859eb3084c84f027cdb1
- src/applications/Fashion-Mnist/transaction_construction/codebook/CodebookMetrics.jl: 388ed5380022a1c46dc753ff5e51435a987f26b6f09c53d015727370aee08a5b
- src/applications/Fashion-Mnist/transaction_construction/codebook/CodebookTraining.jl: 2e14ef93f99a5aaa66d38e2ce360f23100b2925d4bc8c273a5e8d623adea39d6
- src/applications/Fashion-Mnist/transaction_construction/codebook/KMeans.jl: 1dc8b7cd5d3c387889016ccad4782c15278eed91e50b021d816368fc7806a58e
- src/applications/Fashion-Mnist/transaction_construction/codebook/WeightedKMeans.jl: f625e9189b0f859caf910613989975276cfedf293a1c8bddfd438a23289c68f8
- src/applications/Fashion-Mnist/transaction_construction/codebook/WordAssignment.jl: 379ecd9b17c2e392780ef7359c7c880631624ac013b8f6eb4f8c88010f5548ca
- src/applications/Fashion-Mnist/transaction_construction/dataset/DatasetPreparation.jl: c7ccf1dbd7a84fb5d2b73c8bae4cd30c80fd6e06f4c6df2298c3487ff67ab2dd
- src/applications/Fashion-Mnist/transaction_construction/dataset/Sampling.jl: fee13ce5eb0a8d3eec8675638db57c5e17d954edd890e1703db96b60052ca105
- src/applications/Fashion-Mnist/transaction_construction/descriptors/PCA.jl: 6dcacd17bc516bc999db7e6678aa2a6894e3c52d2420cf0ad6004fe52c782d91
- src/applications/Fashion-Mnist/transaction_construction/descriptors/PCAQuantization.jl: 859962b79876dffb1be3c04c2409eb5cee4de093cf5dea88bab5db53a36573a7
- src/applications/Fashion-Mnist/transaction_construction/descriptors/PixelQuantization.jl: 336f4dad773caa68bcb6af26312ce2ef2249a49f972af414a065dfdd88be3c8a
- src/applications/Fashion-Mnist/transaction_construction/descriptors/RawDescriptors.jl: bb1bb325bec00d35ec300b48a463fd52812f229e53ed98c91682b90d366057bb
- src/applications/Fashion-Mnist/transaction_construction/patches/ForegroundFilter.jl: c9398d4f58f74f43d5dd75a6c1723036433ad457690c0f853003179ba42f07ad
- src/applications/Fashion-Mnist/transaction_construction/patches/Patches.jl: 810c424c17e4059b9e33884999921d15dab1b3a7dc4d90c2983230af9dd9868d
- src/applications/Fashion-Mnist/transaction_construction/pipeline/Pipeline.jl: 3dfa9732efa6b8e0710768ad278168263219c60e4324cea4d2bff5c306869b8e
- src/applications/Fashion-Mnist/transaction_construction/pipeline/RunConfig.jl: 8756f6cd6405a5d1b7634231db8b3b36c735b41884c2986d067cc94335de7456
- src/applications/Fashion-Mnist/transaction_construction/pipeline/RunState.jl: eeee97df72467947a119e7d8d90932a2396ff3d39e1e0cccd90be589f8c7d5a8
- src/applications/Fashion-Mnist/transaction_construction/pipeline/SmokeChecks.jl: a57c4e1d3c4280df8d6d01b328dcab10709e7921500c7c294339528b9cc50c1f
- src/applications/Fashion-Mnist/transaction_construction/scripts/run_tc.jl: 022c7ddd88514f413e3e2ae6feab6b8f3bae7cb17a5dc927d0ae4272c10684e4
- src/applications/Fashion-Mnist/transaction_construction/scripts/verify_fashion_tc_artifacts.jl: 185695b03c8fe86f9e169d8e99bbf6642412f4cecf263802018d6941e709cc06
- src/applications/Fashion-Mnist/transaction_construction/transactions/BinaryBoVW.jl: cd8913a626f2e24b03d14edf6147e5dfbff128304e4630c18f5637fc6ad33e8b
- src/applications/Fashion-Mnist/transaction_construction/transactions/ImageMapping.jl: bf440b3e5d7b9022d9154ec7217d59d30a1aeb8916aa6f0d14126a0c010f1a16
- src/applications/Fashion-Mnist/transaction_construction/transactions/TransactionText.jl: 9c006ac557547e781f6cf7e255a664aebad3473cf638bf6798db706c0be42cb2
- src/applications/Fashion-Mnist/transaction_eda/FashionMNISTEDA2.jl: 9ce41a114c414af367d7bb49c09c1fe449ed922bee4082a33c4104b28170b405
- src/applications/Fashion-Mnist/transaction_eda/analysis/CodebookAnalysis.jl: 8b98e724868a70923443ad04dc792d0fa81a76fac00500931a877ce4f6bb4626
- src/applications/Fashion-Mnist/transaction_eda/analysis/PairSampling.jl: fc42c539addd78e3a428c9845b4b5821e3675a3d3bb7745610cd11e9b4c602a2
- src/applications/Fashion-Mnist/transaction_eda/analysis/RunAnalysis.jl: f4a69bfc8391c0a117e607e95ba45d081d3b35086de4bd65f251161aa19ddbe7
- src/applications/Fashion-Mnist/transaction_eda/analysis/TransactionMetrics.jl: 114de2891b850b96e4456af19a014529a7e16eabec186cc0ea721e754ed6a667
- src/applications/Fashion-Mnist/transaction_eda/analysis/TransactionSimilarity.jl: b9296234161c9f8471ce2c81ed68bb192fdfcd2174ccc6ca8d0060b15cf533d7
- src/applications/Fashion-Mnist/transaction_eda/artifacts/AnalysisArtifacts.jl: 1b98485267bd36767068aabb95eb25b8da06322daf9b97b42bcf0e96de100108
- src/applications/Fashion-Mnist/transaction_eda/inputs/ArtifactReaders.jl: 90490d7ce81ad26c8958a67b308beffbf2dc210ed643d40c8cbfcb7e5f592fea
- src/applications/Fashion-Mnist/transaction_eda/inputs/Context.jl: fccc470f59488b1e799c60d687215493f3bf3b06e36fac2cf0869b0569b90b65
- src/applications/Fashion-Mnist/transaction_eda/inputs/Lineage.jl: c1c47f2090a4490f17ca1e3e535ebc11048e4ddd476f1ac73445065621b3f8ea
- src/applications/Fashion-Mnist/transaction_eda/pilot_mining/BoundedMining.jl: 7ef76c3e8378aa40995672b937b990a3b33327de2e30b54b8c662f9fcb82cd09
- src/applications/Fashion-Mnist/transaction_eda/pilot_mining/CommonPilot.jl: b45703f5eb47c97dfbc08d2d7a7ff2f22c346b1deaf67a036ae0bc27ee41f8ee
- src/applications/Fashion-Mnist/transaction_eda/pilot_mining/DeepPilot.jl: 03d5eb8c878f0db0fad7c928efd6a4fb3fb0ef278861172e8a2abb7a5af2d0ec
- src/applications/Fashion-Mnist/transaction_eda/pilot_mining/Shortlist.jl: 5e1ab72d097bd0eb4e818d3af452bdec54e154dc3b7cf4cec30c55415ee09963
- src/applications/Fashion-Mnist/transaction_eda/review/PatternReview.jl: 41f2327609d889ba4bbf57edd2c4f1f4762d280ffbc899faebc0a496c3fe77f1
- src/applications/Fashion-Mnist/transaction_eda/review/SummaryReport.jl: ebfbe8534df16f33628c3ca0f44555c6988548a4c408630d7d06767bfbe0a749
- src/applications/Fashion-Mnist/transaction_io/CSVFields.jl: 9f239422fce3eb1c6a993132ab5609790c526fccf21c1d34cd21dfdd44378088
- src/applications/Fashion-Mnist/transaction_io/CompactJSONL.jl: bec9bb8fa1b44fdbb32798b05f2bed29180aa5805d315a2c055681092383b211
- src/applications/Fashion-Mnist/transaction_io/FashionTransactionIO.jl: f72305d910afdcf9665a39aa25113174e4178ebc113100ff392013a909a5db4c
- src/applications/Fashion-Mnist/transaction_io/MiningJSONL.jl: 295aea49946e54ae660dd952e1b0caaa4f514b200d75500cdea43f561e34e23c
- src/applications/Groceries.jl: 41d2f0f8d79c74a9834927fd98a89124a539e98038a28febe8e7c62add9685b3
- src/utils/SPMFIO.jl: a97b0e9eb36ead1d5d0dcd66f52f6c7ae23821682731dc1db1844cfbf89c2791

Không cần package Julia bên ngoài; dùng thư viện chuẩn và EclatFIM cục bộ.
Đề bài: https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/
