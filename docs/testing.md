# Chuẩn bị kiểm thử trên máy local

Chạy từ repo root bằng PowerShell sau khi cài dependencies Julia.

```powershell
julia --project=. scripts/prepare_data.jl
```

Cần Java tương thích với JAR SPMF. Đặt JAR ở
`data/benchmark/tools/spmf.jar`; notebook Eclat có bước tải Java/JAR kèm checksum.
Để tạo đúng năm file tham chiếu mà bộ test đọc:

```powershell
$referenceCases = @(
    @('data/processed/groceries_spmf.txt', 'results/groceries/groceries_spmf_0.01.txt', '1%'),
    @('data/benchmark/processed/processes/chess_spmf.txt', 'results/benchmarks/peak_ram/spmf/chess_0.875.txt', '87.5%'),
    @('data/benchmark/processed/processes/mushroom_spmf.txt', 'results/benchmarks/peak_ram/spmf/mushroom_0.7.txt', '70%'),
    @('data/benchmark/processed/processes/retail_spmf.txt', 'results/benchmarks/peak_ram/spmf/retail_0.04.txt', '4%'),
    @('data/benchmark/processed/processes/T10I4D100K_spmf.txt', 'results/benchmarks/peak_ram/spmf/T10I4D100K_0.015.txt', '1.5%')
)
foreach ($referenceCase in $referenceCases) {
    if (Test-Path -LiteralPath $referenceCase[1]) {
        throw "File tham chiếu đã tồn tại: $($referenceCase[1])"
    }
    New-Item -ItemType Directory -Force (Split-Path $referenceCase[1]) | Out-Null
    java -jar data/benchmark/tools/spmf.jar run Eclat $referenceCase[0] $referenceCase[1] $referenceCase[2]
    if ($LASTEXITCODE -ne 0) { throw 'SPMF không hoàn tất' }
}
julia --project=. test/runtests.jl
```

Test đối chiếu từng tập mục và số hỗ trợ của cả hai backend với tham chiếu
SPMF. Kết quả lần chạy đã lưu nằm trong README.
