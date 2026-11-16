module ScalabilityBenchmark

using Dates
using Random
using Statistics: median
using EclatFIM: read_spmf_transactions

include("benchmark_peak_ram.jl")
using .PeakRAMBenchmark: run_command
using .PeakRAMBenchmark.ProcessBenchmark: PROJECT_DIR, DATASETS, prepare_input,
    read_itemsets, write_row, file_sha256

const PERCENTAGES = [10, 25, 50, 75, 100]
const BACKENDS = (:set, :bitvector)
const MEASUREMENT = "mine_after_full_subset_warmup"
const METRICS_HEADER = "n_transactions,n_itemsets,mining_seconds,julia_threads"

function parse_options(args)
    options = Dict("--runs" => "5", "--minsup" => "0.04", "--seed" => "20261116",
        "--timeout-seconds" => "600",
        "--output-dir" => joinpath(PROJECT_DIR, "results", "benchmarks", "scalability"))
    iseven(length(args)) || throw(ArgumentError("Mỗi tùy chọn cần một giá trị"))
    for i in 1:2:length(args)
        haskey(options, args[i]) || throw(ArgumentError("Tùy chọn lạ: $(args[i])"))
        options[args[i]] = args[i + 1]
    end
    n_runs = parse(Int, options["--runs"])
    n_runs > 0 || throw(ArgumentError("Số lần đo phải dương"))
    minsup = parse(Float64, options["--minsup"])
    isfinite(minsup) && 0 < minsup <= 1 || throw(ArgumentError("minsup phải thuộc (0, 1]"))
    seed = parse(Int, options["--seed"])
    seed >= 0 || throw(ArgumentError("Seed phải không âm"))
    timeout = parse(Float64, options["--timeout-seconds"])
    isfinite(timeout) && timeout > 0 || throw(ArgumentError("Timeout phải dương và hữu hạn"))
    return n_runs, minsup, seed, timeout, abspath(options["--output-dir"])
end

function nested_indices(n_transactions; seed = 20261116, percentages = PERCENTAGES)
    n_transactions > 0 || throw(ArgumentError("Số giao dịch phải dương"))
    !isempty(percentages) && issorted(percentages) && allunique(percentages) &&
        all(p -> 0 < p <= 100, percentages) || throw(ArgumentError("Dải phần trăm không hợp lệ"))
    permutation = randperm(MersenneTwister(seed), n_transactions)
    selections = Dict{Int, Vector{Int}}()
    for percent in percentages
        n = div(n_transactions * percent, 100)
        n > 0 || throw(ArgumentError("Tập con có kích thước bằng 0"))
        # Nested selections, but restore original row order inside each subset.
        selections[percent] = sort(permutation[1:n])
    end
    return selections
end

function prepare_subsets(full_input, subset_dir; seed = 20261116, percentages = PERCENTAGES)
    transactions = read_spmf_transactions(full_input)
    selections = nested_indices(length(transactions); seed, percentages)
    mkpath(subset_dir)
    subsets = NamedTuple[]
    for percent in percentages
        indices = selections[percent]
        input_path = joinpath(subset_dir, "retail_$(percent)pct_spmf.txt")
        indices_path = joinpath(subset_dir, "retail_$(percent)pct_indices.txt")
        open(input_path, "w") do io
            for index in indices
                println(io, join(transactions[index], " "))
            end
        end
        open(indices_path, "w") do io
            for index in indices
                println(io, index)
            end
        end
        push!(subsets, (percent = percent, n_transactions = length(indices),
            input_path = input_path, indices_path = indices_path))
    end
    return subsets, length(transactions)
end

function worker_command(input_path, output_path, metrics_path, minsup, backend)
    worker = joinpath(@__DIR__, "scalability_worker.jl")
    return `$(Base.julia_cmd()) --startup-file=no --history-file=no --threads=1 --project=$PROJECT_DIR $worker $input_path $output_path $metrics_path $minsup $backend`
end

function read_metrics(path)
    lines = readlines(path)
    length(lines) == 2 && lines[1] == METRICS_HEADER || error("Sai định dạng metrics")
    fields = split(lines[2], ",")
    length(fields) == 4 || error("Sai số cột metrics")
    n, count, elapsed, threads = parse(Int, fields[1]), parse(Int, fields[2]),
        parse(Float64, fields[3]), parse(Int, fields[4])
    n > 0 && count >= 0 && isfinite(elapsed) && elapsed > 0 && threads == 1 ||
        error("Giá trị metrics không hợp lệ")
    return (n_transactions = n, n_itemsets = count, mining_seconds = elapsed, julia_threads = threads)
end

function generate_references(subsets, minsup, output_dir, scratch, timeout)
    java = Sys.which("java")
    isnothing(java) && error("Không tìm thấy Java")
    jar = joinpath(PROJECT_DIR, "data", "benchmark", "tools", "spmf.jar")
    isfile(jar) || error("Thiếu spmf.jar")
    mkpath(joinpath(output_dir, "spmf"))
    references = Dict{Int, Dict{Tuple{Vararg{Int}}, Int}}()
    for subset in subsets
        path = joinpath(output_dir, "spmf", "retail_$(subset.percent)pct.txt")
        command = `$java -jar $jar run Eclat $(subset.input_path) $path $(string(100 * minsup, "%"))`
        run_command(command, joinpath(scratch, "retail_$(subset.percent)pct_spmf.log"), timeout)
        references[subset.percent] = read_itemsets(path)
    end
    open(joinpath(output_dir, "java_version.txt"), "w") do io
        run(pipeline(`$java -version`; stdout = io, stderr = io))
    end
    return references
end

function write_metadata(output_dir, subsets, n_total, n_runs, minsup, seed, timeout, full_input)
    open(joinpath(output_dir, "metadata.md"), "w") do io
        println(io, "# Thông tin phép đo Scalability — Retail\n")
        println(io, "- Thời điểm địa phương: ", now())
        println(io, "- Julia: ", VERSION, "; hệ điều hành: ", Sys.KERNEL, "; kiến trúc: ", Sys.ARCH)
        println(io, "- CPU: ", Sys.CPU_NAME, "; số CPU logic: ", Sys.CPU_THREADS)
        println(io, "- RAM máy (GiB): ", round(Sys.total_memory() / 2.0^30; digits = 2))
        println(io, "- Số luồng mỗi tiến trình đo: 1; số lần đo mỗi phiên bản/tập con: ", n_runs)
        println(io, "- Minsup tương đối cố định: ", minsup, "; min_count = ceil(minsup × số giao dịch tập con).")
        println(io, "- Số giao dịch Retail đầy đủ: ", n_total, "; độ dịch ID: +1.")
        println(io, "- Seed: ", seed, "; bộ sinh: Random.MersenneTwister; chọn bằng randperm.")
        println(io, "- Giới hạn thời gian mỗi tiến trình (giây): ", timeout)
        println(io, "- SHA-256 Retail gốc: ", file_sha256(joinpath(PROJECT_DIR, "data", "benchmark", "raw", "retail.dat")))
        println(io, "- SHA-256 Retail chuẩn hóa đầy đủ: ", file_sha256(full_input))
        println(io, "- SHA-256 JAR SPMF: ", file_sha256(joinpath(PROJECT_DIR, "data", "benchmark", "tools", "spmf.jar")))
        println(io, "- Phiên bản Java: java_version.txt.\n")
        println(io, "## Cách lấy tập con\n")
        println(io, "Tạo một hoán vị duy nhất của chỉ số các dòng Retail. Mỗi mức lấy floor(N × phần trăm / 100) ",
            "chỉ số đầu tiên của cùng hoán vị, rồi sắp lại theo thứ tự dòng gốc. Tập nhỏ nằm trong tập lớn.")
        println(io, "Giữ nguyên các giao dịch trùng nhau: chọn theo chỉ số dòng, không khử trùng nội dung. ",
            "Mức 100% giữ đúng toàn bộ dữ liệu chuẩn hóa. File đầu vào và chỉ số dòng nằm trong data/benchmark/processed/scalability/, được Git-ignore.\n")
        for subset in subsets
            println(io, "- ", subset.percent, "%: ", subset.n_transactions, " giao dịch; min_count=", ceil(Int, minsup * subset.n_transactions))
            println(io, "  - SHA-256 đầu vào: ", file_sha256(subset.input_path))
            println(io, "  - SHA-256 chỉ số dòng: ", file_sha256(subset.indices_path))
            println(io, "  - SHA-256 tham chiếu SPMF: ", file_sha256(joinpath(output_dir, "spmf", "retail_$(subset.percent)pct.txt")))
        end
        println(io, "\n## Phạm vi đo\n")
        println(io, "Mỗi mẫu dùng tiến trình Julia mới và chỉ chạy một backend. Đọc input trước; warm-up một lần ",
            "trên đúng toàn bộ tập con và cùng minsup; GC; sau đó @elapsed đo một lần mine. ",
            "Không tính khởi động, đọc dữ liệu, warm-up/JIT, GC trước phép đo, ghi output hoặc correctness. ",
            "GC phát sinh bên trong mine vẫn nằm trong thời gian đo.")
        println(io, "Đảo thứ tự Set/BitVector giữa các lần đo. Báo cáo trung vị, min/max và từng mẫu gốc. ",
            "Phép đo là wall-clock của mine sau warm-up, không ghép với runtime toàn tiến trình ở processes/.")
        println(io, "Tạo SPMF reference cho từng tập con ngoài phần đo. Mỗi output Julia phải khớp toàn bộ itemset/support. ",
            "SPMF chỉ kiểm chứng correctness, không có đường thời gian SPMF trong thí nghiệm này.")
        println(io, "Giữ minsup tương đối cố định; số frequent itemset có thể thay đổi do phân bố tập con và làm tròn ngưỡng. ",
            "Không yêu cầu runtime hoặc số itemset tăng đơn điệu. Không dùng kết quả năm điểm để chứng minh độ phức tạp tổng quát.\n")
        println(io, "## Mã SHA-256 của mã nguồn tại thời điểm đo\n")
        paths = [joinpath(@__DIR__, name) for name in ("benchmark_scalability.jl", "scalability_worker.jl",
            "benchmark_peak_ram.jl", "benchmark_processes.jl")]
        append!(paths, [joinpath(root, file) for (root, _, files) in walkdir(joinpath(PROJECT_DIR, "src"))
            for file in files if endswith(file, ".jl")])
        push!(paths, joinpath(PROJECT_DIR, "Project.toml"))
        manifest = joinpath(PROJECT_DIR, "Manifest.toml")
        isfile(manifest) && push!(paths, manifest)
        for path in sort(paths)
            println(io, "- ", relpath(path, PROJECT_DIR), ": ", file_sha256(path))
        end
        println(io, "\nKhông cần package Julia bên ngoài; dùng thư viện chuẩn và EclatFIM cục bộ.")
        println(io, "Đề bài: https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/")
    end
end

function main(args = ARGS)
    n_runs, minsup, seed, timeout, output_dir = parse_options(args)
    for name in ("runs.csv", "summary.csv", "metadata.md")
        isfile(joinpath(output_dir, name)) && error("Đã có kết quả; chọn --output-dir mới")
    end
    retail = only(filter(c -> c.name == "retail", DATASETS))
    full_input = prepare_input(retail)
    subset_dir = joinpath(PROJECT_DIR, "data", "benchmark", "processed", "scalability")
    subsets, n_total = prepare_subsets(full_input, subset_dir; seed)
    mkpath(output_dir)
    scratch_parent = joinpath(PROJECT_DIR, "results", "benchmarks", "tmp")
    mkpath(scratch_parent)
    scratch = mktempdir(scratch_parent; prefix = "scalability_", cleanup = false)
    references = generate_references(subsets, minsup, output_dir, scratch, timeout)
    write_metadata(output_dir, subsets, n_total, n_runs, minsup, seed, timeout, full_input)
    open(joinpath(output_dir, "runs.csv"), "w") do raw_io
        open(joinpath(output_dir, "summary.csv"), "w") do summary_io
            write_row(raw_io, ("dataset", "percent", "n_total", "n_transactions", "minsup", "min_count",
                "backend", "measurement", "run_id", "order_in_pair", "mining_seconds", "n_itemsets",
                "julia_threads", "exact_match", "spmf_match", "status"))
            write_row(summary_io, ("dataset", "percent", "n_total", "n_transactions", "minsup", "min_count",
                "backend", "measurement", "n_runs", "n_itemsets", "median_seconds", "min_seconds", "max_seconds",
                "transactions_per_second", "exact_match", "spmf_match"))
            for subset in subsets
                reference = references[subset.percent]
                min_count = ceil(Int, minsup * subset.n_transactions)
                times = Dict(b => Float64[] for b in BACKENDS)
                println("Retail $(subset.percent)%: $(subset.n_transactions) giao dịch, $(length(reference)) itemsets")
                flush(stdout)
                for run_id in 1:n_runs
                    order = isodd(run_id) ? BACKENDS : reverse(BACKENDS)
                    for (position, backend) in enumerate(order)
                        stem = joinpath(scratch, "retail_$(subset.percent)pct_$(run_id)_$backend")
                        output, metrics_path = stem * ".txt", stem * ".csv"
                        try
                            run_command(worker_command(subset.input_path, output, metrics_path, minsup, backend), stem * ".log", timeout)
                            metrics = read_metrics(metrics_path)
                            metrics.n_transactions == subset.n_transactions || error("Sai số giao dịch")
                            actual = read_itemsets(output)
                            actual == reference || error("Itemset/support không khớp SPMF")
                            metrics.n_itemsets == length(actual) || error("Sai số itemset")
                            all(s -> min_count <= s <= subset.n_transactions, values(actual)) || error("Support ngoài miền")
                            push!(times[backend], metrics.mining_seconds)
                            write_row(raw_io, ("retail", subset.percent, n_total, subset.n_transactions, minsup, min_count,
                                backend, MEASUREMENT, run_id, position, metrics.mining_seconds, length(actual),
                                metrics.julia_threads, true, true, "ok"))
                            println("  lần=$run_id backend=$backend mine=$(round(1000 * metrics.mining_seconds; digits=3)) ms; khớp=true")
                            flush(stdout)
                        catch
                            write_row(raw_io, ("retail", subset.percent, n_total, subset.n_transactions, minsup, min_count,
                                backend, MEASUREMENT, run_id, position, "", "", "", false, false, "failed"))
                            rethrow()
                        end
                    end
                end
                for backend in BACKENDS
                    samples = times[backend]
                    elapsed = median(samples)
                    write_row(summary_io, ("retail", subset.percent, n_total, subset.n_transactions, minsup, min_count,
                        backend, MEASUREMENT, n_runs, length(reference), elapsed, minimum(samples), maximum(samples),
                        subset.n_transactions / elapsed, true, true))
                end
            end
        end
    end
    println("Hoàn tất scalability: $output_dir\nOutput và nhật ký tiến trình: $scratch")
    return output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module
