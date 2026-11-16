module PeakRAMBenchmark

using Dates
using Statistics: median

# Reuse the existing dataset grids, normalization and strict itemset parser.
# This module is only in the controller, never loaded by the measured worker.
module ProcessBenchmark
    include("benchmark_processes.jl")
end
using .ProcessBenchmark: DATASETS, PROJECT_DIR, prepare_input, read_itemsets,
    write_row, file_sha256

const MIB = 1024^2
const BACKENDS = (:set, :bitvector)
const METRICS_HEADER = "n_transactions,n_itemsets,pre_mine_peak_rss_bytes,peak_rss_bytes,julia_threads"

function middle_minsup(grid)
    !isempty(grid) && isodd(length(grid)) || throw(ArgumentError("Expected an odd minsup grid"))
    return grid[cld(length(grid), 2)]
end

function parse_options(args)
    options = Dict("--dataset" => "all", "--runs" => "5",
        "--timeout-seconds" => "600",
        "--output-dir" => joinpath(PROJECT_DIR, "results", "benchmarks", "peak_ram"))
    iseven(length(args)) || throw(ArgumentError("Each option requires a value"))
    for i in 1:2:length(args)
        haskey(options, args[i]) || throw(ArgumentError("Unknown option: $(args[i])"))
        options[args[i]] = args[i + 1]
    end
    n_runs = parse(Int, options["--runs"])
    n_runs > 0 || throw(ArgumentError("Runs must be positive"))
    timeout = parse(Float64, options["--timeout-seconds"])
    isfinite(timeout) && timeout > 0 || throw(ArgumentError("Timeout must be positive and finite"))
    configs = filter(c -> options["--dataset"] in ("all", c.name), DATASETS)
    isempty(configs) && throw(ArgumentError("Unknown dataset"))
    return configs, n_runs, timeout, abspath(options["--output-dir"])
end

function read_metrics(path)
    lines = readlines(path)
    length(lines) == 2 && lines[1] == METRICS_HEADER || error("Invalid worker metrics: $path")
    fields = parse.(Int, split(lines[2], ","))
    length(fields) == 5 || error("Invalid metric columns")
    n_transactions, n_itemsets, before, peak, n_threads = fields
    n_transactions > 0 && n_itemsets >= 0 && 0 < before <= peak && n_threads == 1 ||
        error("Invalid worker counters: $path")
    return (n_transactions = n_transactions, n_itemsets = n_itemsets,
        pre_mine_peak_rss_bytes = before, peak_rss_bytes = peak, julia_threads = n_threads)
end

function run_command(command, log_path, timeout)
    open(log_path, "w") do io
        process = run(pipeline(command; stdout = io, stderr = io); wait = false)
        outcome = timedwait(() -> process_exited(process), timeout; pollint = 0.1)
        if outcome == :timed_out
            kill(process)
            wait(process)
            error("Worker timeout after $timeout seconds; log: $log_path")
        end
        wait(process)
        success(process) || error("Worker failed (exit $(process.exitcode)); log: $log_path")
    end
end

function worker_command(input_path, output_path, metrics_path, minsup, backend)
    worker_path = joinpath(@__DIR__, "peak_ram_worker.jl")
    return `$(Base.julia_cmd()) --startup-file=no --history-file=no --threads=1 --project=$PROJECT_DIR $worker_path $input_path $output_path $metrics_path $minsup $backend`
end

function reference_path(output_dir, config)
    return joinpath(output_dir, "spmf", "$(config.name)_$(middle_minsup(config.minsups)).txt")
end

function generate_references(configs, inputs, output_dir, scratch, timeout)
    java = Sys.which("java")
    isnothing(java) && error("Java is required to regenerate exact SPMF references")
    jar = joinpath(PROJECT_DIR, "data", "benchmark", "tools", "spmf.jar")
    isfile(jar) || error("Missing SPMF JAR: $jar")
    mkpath(joinpath(output_dir, "spmf"))
    references = Dict{String, Dict{Tuple{Vararg{Int}}, Int}}()
    for c in configs
        minsup_percent = string(100 * middle_minsup(c.minsups), "%")
        output = reference_path(output_dir, c)
        command = `$java -jar $jar run Eclat $(inputs[c.name]) $output $minsup_percent`
        run_command(command, joinpath(scratch, "$(c.name)_spmf.log"), timeout)
        references[c.name] = read_itemsets(output)
    end
    open(joinpath(output_dir, "java_version.txt"), "w") do io
        run(pipeline(`$java -version`; stdout = io, stderr = io))
    end
    return references
end

function write_metadata(output_dir, configs, n_runs, timeout, inputs)
    open(joinpath(output_dir, "metadata.md"), "w") do io
        println(io, "# Thông tin phép đo Peak RAM\n")
        println(io, "- Thời điểm địa phương: ", now())
        println(io, "- Julia: ", VERSION, "; hệ điều hành: ", Sys.KERNEL, "; kiến trúc: ", Sys.ARCH)
        println(io, "- CPU: ", Sys.CPU_NAME, "; số CPU logic: ", Sys.CPU_THREADS)
        println(io, "- RAM máy (GiB): ", round(Sys.total_memory() / 2.0^30; digits = 2))
        println(io, "- Số luồng của tiến trình đo: 1; số lần đo mỗi phiên bản/tập dữ liệu: ", n_runs)
        println(io, "- Giới hạn thời gian mỗi tiến trình đo (giây): ", timeout)
        println(io, "- Đại lượng đo: Sys.maxrss(), đơn vị byte; MiB = byte / 1024^2.")
        println(io, "- Trên Windows, bộ đếm đỉnh là PeakWorkingSetSize qua GetProcessMemoryInfo.")
        println(io, "- Phạm vi: từ lúc khởi động tiến trình đến khi mine hoàn tất, trước khi ghi kết quả.")
        println(io, "- Bao gồm môi trường thực thi, nạp package/JIT, chạy khởi động trên dữ liệu nhỏ, đọc đầu vào và cấp phát khi khai thác.")
        println(io, "- Mỗi mẫu tạo tiến trình mới, chạy khởi động phiên bản được chọn trên cùng bộ dữ liệu nhỏ, ",
            "rồi thu gom rác (GC) trước khi đọc toàn bộ đầu vào và một lần nữa trước khi gọi mine.")
        println(io, "- Bộ đếm đỉnh của tiến trình không thể đặt lại. pre_mine_peak_rss_bytes chỉ phục vụ chẩn đoán; ",
            "không lấy hiệu hai mức đỉnh để coi là Peak RAM riêng của thuật toán.")
        println(io, "- Thứ tự chạy hai phiên bản được đảo giữa các lần đo. Không lấy mẫu theo chu kỳ; đọc bộ đếm mức cao nhất của hệ điều hành.")
        println(io, "- Báo cáo trung vị và mức nhỏ nhất/lớn nhất quan sát được của các đỉnh tiến trình độc lập; không phải khoảng tin cậy.")
        println(io, "- Khi thất bại, giữ trạng thái/lỗi và nhật ký tiến trình; không báo mẫu thất bại là đạt.\n")
        println(io, "## Lựa chọn tập dữ liệu và minsup\n")
        println(io, "Chọn điểm thứ tư (điểm giữa) trong mỗi dải bảy ngưỡng minsup thử nghiệm, ",
            "không lấy trung bình cộng hai đầu dải. Giữ nguyên các giỏ hàng trùng nhau.\n")
        for c in configs
            reference = reference_path(output_dir, c)
            println(io, "- ", c.name, ": N=", c.n_transactions, "; độ dịch ID=", c.offset,
                "; dải minsup=", c.minsups, "; mức được chọn=", middle_minsup(c.minsups))
            println(io, "  - SHA-256 dữ liệu gốc: ", file_sha256(joinpath(PROJECT_DIR, "data", "benchmark", "raw", c.name * ".dat")))
            println(io, "  - SHA-256 dữ liệu đã chuẩn hóa: ", file_sha256(inputs[c.name]))
            println(io, "  - SHA-256 tham chiếu SPMF được tạo mới: ", file_sha256(reference))
        end
        println(io, "\nTham chiếu SPMF được tạo mới từ đúng đầu vào đã chuẩn hóa trước khi đo RAM; ",
            "Java chạy riêng, không thuộc tiến trình được đo RAM.")
        println(io, "SHA-256 tệp JAR SPMF: ", file_sha256(joinpath(PROJECT_DIR, "data", "benchmark", "tools", "spmf.jar")))
        println(io, "Phiên bản Java: xem java_version.txt")
        println(io, "\n## Mã SHA-256 của mã nguồn tại thời điểm đo\n")
        paths = [joinpath(@__DIR__, f) for f in
            ("benchmark_peak_ram.jl", "peak_ram_worker.jl", "benchmark_processes.jl")]
        append!(paths, [joinpath(root, f) for (root, _, files) in walkdir(joinpath(PROJECT_DIR, "src"))
            for f in files if endswith(f, ".jl")])
        push!(paths, joinpath(PROJECT_DIR, "Project.toml"))
        manifest = joinpath(PROJECT_DIR, "Manifest.toml")
        isfile(manifest) && push!(paths, manifest)
        for path in sort(paths)
            println(io, "- ", relpath(path, PROJECT_DIR), ": ", file_sha256(path))
        end
        println(io, "\nThư viện phụ thuộc: chỉ dùng thư viện chuẩn Julia và package EclatFIM cục bộ.")
        println(io, "Không lấy mẫu ngẫu nhiên; sử dụng toàn bộ giao dịch của từng cơ sở dữ liệu.")
        println(io, "\nTài liệu tham khảo: [Julia Sys.maxrss](https://docs.julialang.org/en/v1/base/base/#Base.Sys.maxrss), ",
            "[bộ đếm Windows](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters), ",
            "[đề bài](https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/).")
    end
end

function main(args = ARGS)
    configs, n_runs, timeout, output_dir = parse_options(args)
    for name in ("runs.csv", "summary.csv", "metadata.md")
        isfile(joinpath(output_dir, name)) && error("Output already exists; choose a new --output-dir")
    end
    # Regenerate references: older artifacts may have used a different item mapping.
    inputs = Dict(c.name => prepare_input(c) for c in configs)
    mkpath(output_dir)
    scratch_parent = joinpath(PROJECT_DIR, "results", "benchmarks", "tmp")
    mkpath(scratch_parent)
    scratch = mktempdir(scratch_parent; prefix = "peak_ram_", cleanup = false)
    references = generate_references(configs, inputs, output_dir, scratch, timeout)
    write_metadata(output_dir, configs, n_runs, timeout, inputs)
    open(joinpath(output_dir, "runs.csv"), "w") do raw_io
        open(joinpath(output_dir, "summary.csv"), "w") do summary_io
            write_row(raw_io, ("dataset", "backend", "minsup", "n_transactions", "min_count",
                "run_id", "order_in_pair", "peak_rss_bytes", "pre_mine_peak_rss_bytes",
                "n_itemsets", "julia_threads", "exact_match", "spmf_match", "status"))
            write_row(summary_io, ("dataset", "minsup", "n_transactions", "min_count", "n_itemsets",
                "n_runs", "baseline_median_mib", "optimized_median_mib", "baseline_min_mib",
                "baseline_max_mib", "optimized_min_mib", "optimized_max_mib",
                "optimized_over_baseline", "reduction_percent", "exact_match", "spmf_match"))
            for c in configs
                minsup = middle_minsup(c.minsups)
                min_count = ceil(Int, minsup * c.n_transactions)
                peaks = Dict(b => Int[] for b in BACKENDS)
                reference = references[c.name]
                println("Dataset=$(c.name), minsup=$minsup, expected itemsets=$(length(reference))")
                flush(stdout)
                for run_id in 1:n_runs
                    order = isodd(run_id) ? BACKENDS : reverse(BACKENDS)
                    for (position, backend) in enumerate(order)
                        stem = joinpath(scratch, "$(c.name)_$(run_id)_$backend")
                        output, metrics_path = stem * ".txt", stem * ".csv"
                        try
                            run_command(worker_command(inputs[c.name], output, metrics_path, minsup, backend),
                                stem * ".log", timeout)
                            metrics = read_metrics(metrics_path)
                            metrics.n_transactions == c.n_transactions || error("Wrong transaction count")
                            actual = read_itemsets(output)
                            actual == reference || error("Itemset/support mismatch with SPMF reference")
                            metrics.n_itemsets == length(actual) || error("Wrong itemset count")
                            all(s -> min_count <= s <= c.n_transactions, values(actual)) ||
                                error("Support outside valid range")
                            push!(peaks[backend], metrics.peak_rss_bytes)
                            write_row(raw_io, (c.name, backend, minsup, c.n_transactions, min_count,
                                run_id, position, metrics.peak_rss_bytes, metrics.pre_mine_peak_rss_bytes,
                                length(actual), metrics.julia_threads, true, true, "ok"))
                            println("  run=$run_id backend=$backend peak=$(round(metrics.peak_rss_bytes / MIB; digits=2)) MiB; exact=true")
                            flush(stdout)
                        catch
                            write_row(raw_io, (c.name, backend, minsup, c.n_transactions, min_count,
                                run_id, position, "", "", "", "", false, false, "failed"))
                            rethrow()
                        end
                    end
                end
                baseline, optimized = peaks[:set] ./ MIB, peaks[:bitvector] ./ MIB
                b, o = median(baseline), median(optimized)
                write_row(summary_io, (c.name, minsup, c.n_transactions, min_count, length(reference),
                    n_runs, b, o, minimum(baseline), maximum(baseline), minimum(optimized),
                    maximum(optimized), o / b, 100 * (1 - o / b), true, true))
            end
        end
    end
    println("Completed. Results: $output_dir\nWorker outputs/logs: $scratch")
    return output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module
