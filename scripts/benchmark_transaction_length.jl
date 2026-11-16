module TransactionLengthBenchmark

using Dates
using Random
using Statistics: median

include("benchmark_scalability.jl")
using .ScalabilityBenchmark: run_command, worker_command, read_metrics
using .ScalabilityBenchmark.PeakRAMBenchmark.ProcessBenchmark: PROJECT_DIR, read_itemsets,
    write_row, file_sha256

const LENGTHS = [4, 8, 12, 16, 20]
const BACKENDS = (:set, :bitvector)
const MEASUREMENT = "mine_after_full_database_warmup"

function validate_design(n_transactions, n_items, lengths)
    n_transactions > 0 && n_items > 0 || throw(ArgumentError("N và M phải dương"))
    !isempty(lengths) && issorted(lengths) && allunique(lengths) &&
        all(l -> 1 <= l <= n_items, lengths) || throw(ArgumentError("Độ dài phải tăng dần, duy nhất và thuộc [1, M]"))
end

function parse_options(args)
    options = Dict("--runs" => "5", "--minsup" => "0.05", "--seed" => "20261116",
        "--transactions" => "5000", "--items" => "64", "--lengths" => "4,8,12,16,20",
        "--timeout-seconds" => "600",
        "--output-dir" => joinpath(PROJECT_DIR, "results", "benchmarks", "transaction_length"))
    iseven(length(args)) || throw(ArgumentError("Mỗi tùy chọn cần một giá trị"))
    for i in 1:2:length(args)
        haskey(options, args[i]) || throw(ArgumentError("Tùy chọn lạ: $(args[i])"))
        options[args[i]] = args[i + 1]
    end
    n_runs, n_transactions, n_items, seed = parse.(Int,
        [options["--runs"], options["--transactions"], options["--items"], options["--seed"]])
    lengths = parse.(Int, split(options["--lengths"], ","))
    validate_design(n_transactions, n_items, lengths)
    n_runs > 0 && seed >= 0 || throw(ArgumentError("Số lần đo phải dương, seed không âm"))
    minsup, timeout = parse.(Float64, [options["--minsup"], options["--timeout-seconds"]])
    isfinite(minsup) && 0 < minsup <= 1 || throw(ArgumentError("minsup phải thuộc (0, 1]"))
    isfinite(timeout) && timeout > 0 || throw(ArgumentError("Timeout phải dương và hữu hạn"))
    return (n_runs = n_runs, n_transactions = n_transactions, n_items = n_items,
        lengths = lengths, minsup = minsup, seed = seed, timeout = timeout,
        output_dir = abspath(options["--output-dir"]))
end

function generate_databases(n_transactions, n_items, lengths; seed = 20261116)
    validate_design(n_transactions, n_items, lengths)
    rng = MersenneTwister(seed)
    databases = Dict(l => Vector{Int}[] for l in lengths)
    for _ in 1:n_transactions
        # Each TID has its own permutation, reused only across lengths for that TID.
        permutation = randperm(rng, n_items)
        for l in lengths
            push!(databases[l], sort(permutation[1:l]))
        end
    end
    return databases
end

function prepare_databases(options, data_dir)
    databases = generate_databases(options.n_transactions, options.n_items, options.lengths; seed = options.seed)
    mkpath(data_dir)
    cases = NamedTuple[]
    for l in options.lengths
        transactions = databases[l]
        observed = Set{Int}()
        for transaction in transactions
            length(transaction) == l && allunique(transaction) || error("Giao dịch sinh sai độ dài")
            union!(observed, transaction)
        end
        # Keep the observed vocabulary fixed too; never hide a changing-M confound.
        length(observed) == options.n_items || error("CSDL chưa chứa đủ M item; tăng N hoặc chọn seed khác")
        path = joinpath(data_dir, "synthetic_L$(l)_spmf.txt")
        open(path, "w") do io
            for transaction in transactions
                println(io, join(transaction, " "))
            end
        end
        push!(cases, (transaction_length = l, mean_length = sum(length, transactions) / length(transactions),
            observed_items = length(observed), total_occurrences = sum(length, transactions), input_path = path))
    end
    return cases
end

function verify_nested_references(references, lengths)
    for (small, large) in zip(lengths[1:end-1], lengths[2:end])
        previous, current = references[small], references[large]
        all(haskey(current, key) && current[key] >= support for (key, support) in previous) ||
            error("Vi phạm quan hệ lồng nhau: itemset/support giảm khi thêm item vào từng giao dịch")
    end
end

function generate_references(cases, options, scratch)
    java = Sys.which("java")
    isnothing(java) && error("Không tìm thấy Java")
    jar = joinpath(PROJECT_DIR, "data", "benchmark", "tools", "spmf.jar")
    isfile(jar) || error("Thiếu spmf.jar")
    mkpath(joinpath(options.output_dir, "spmf"))
    references = Dict{Int, Dict{Tuple{Vararg{Int}}, Int}}()
    for c in cases
        output = joinpath(options.output_dir, "spmf", "synthetic_L$(c.transaction_length).txt")
        command = `$java -jar $jar run Eclat $(c.input_path) $output $(string(100 * options.minsup, "%"))`
        run_command(command, joinpath(scratch, "L$(c.transaction_length)_spmf.log"), options.timeout)
        references[c.transaction_length] = read_itemsets(output)
    end
    verify_nested_references(references, options.lengths)
    open(joinpath(options.output_dir, "java_version.txt"), "w") do io
        run(pipeline(`$java -version`; stdout = io, stderr = io))
    end
    return references
end

function write_metadata(cases, options)
    open(joinpath(options.output_dir, "metadata.md"), "w") do io
        println(io, "# Thông tin phép đo ảnh hưởng độ dài giao dịch\n")
        println(io, "- Thời điểm địa phương: ", now())
        println(io, "- Julia: ", VERSION, "; hệ điều hành: ", Sys.KERNEL, "; kiến trúc: ", Sys.ARCH)
        println(io, "- CPU: ", Sys.CPU_NAME, "; số CPU logic: ", Sys.CPU_THREADS)
        println(io, "- RAM máy (GiB): ", round(Sys.total_memory() / 2.0^30; digits = 2))
        println(io, "- Số luồng tiến trình đo: 1; số lần đo mỗi phiên bản/CSDL: ", options.n_runs)
        println(io, "- N cố định: ", options.n_transactions, "; M cố định: ", options.n_items)
        println(io, "- Các độ dài: ", options.lengths, "; mỗi giao dịch có đúng L item, nên độ dài trung bình bằng L.")
        println(io, "- Minsup cố định: ", options.minsup, "; min_count cố định: ", ceil(Int, options.minsup * options.n_transactions))
        println(io, "- Seed: ", options.seed, "; bộ sinh: Random.MersenneTwister; phép chọn: randperm.")
        println(io, "- Giới hạn thời gian mỗi tiến trình (giây): ", options.timeout)
        println(io, "- SHA-256 JAR SPMF: ", file_sha256(joinpath(PROJECT_DIR, "data", "benchmark", "tools", "spmf.jar")))
        println(io, "- Phiên bản Java: java_version.txt.\n")
        println(io, "## Thiết kế CSDL tổng hợp\n")
        println(io, "Với mỗi TID, tạo một hoán vị ngẫu nhiên riêng của các item 1:M. Mỗi mức L lấy L item đầu ",
            "của cùng hoán vị cho TID đó, rồi sắp tăng dần. Các TID khác nhau dùng các hoán vị khác nhau.")
        println(io, "Khi tăng L, chỉ thêm item vào cùng giao dịch, giữ N và tập item quan sát được là M. ",
            "Không nhân bản CSDL hoặc chèn item trùng trong một giao dịch; giữ nguyên các giao dịch có nội dung trùng nhau.")
        println(io, "Mật độ bằng L/M, tổng số lần xuất hiện item bằng N×L. Các itemset/support của mức ngắn ",
            "không giảm ở mức dài khi min_count cố định. Đã kiểm tra quan hệ này trên các tham chiếu SPMF.")
        println(io, "Dữ liệu sinh nằm trong data/benchmark/processed/transaction_length/, được Git-ignore. ",
            "Đây là một họ CSDL có cùng seed, không phải các lần sinh dữ liệu độc lập.\n")
        for c in cases
            println(io, "- L=", c.transaction_length, ": độ dài trung bình=", c.mean_length,
                "; số item quan sát=", c.observed_items, "; tổng số lần xuất hiện=", c.total_occurrences,
                "; mật độ=", c.transaction_length / options.n_items)
            println(io, "  - SHA-256 đầu vào: ", file_sha256(c.input_path))
            println(io, "  - SHA-256 tham chiếu SPMF: ", file_sha256(joinpath(options.output_dir, "spmf", "synthetic_L$(c.transaction_length).txt")))
        end
        println(io, "\n## Phạm vi đo\n")
        println(io, "Dùng cùng worker với scalability. Mỗi mẫu tạo tiến trình Julia mới, một backend, một luồng. ",
            "Đọc input; warm-up một lần mine trên đúng toàn bộ CSDL/cùng minsup; GC; @elapsed đo một lần mine.")
        println(io, "Không tính khởi động, đọc input, warm-up/JIT, GC trước đo, ghi output và correctness. ",
            "GC bên trong mine vẫn được tính. Đảo thứ tự Set/BitVector giữa các lần; lưu trung vị, min/max và từng mẫu.")
        println(io, "SPMF chỉ tạo tham chiếu correctness ngoài phép đo. Mỗi output Julia phải khớp toàn bộ itemset/support. ",
            "Thí nghiệm này đo runtime và số itemset, không đo lại Peak RAM hoặc runtime SPMF.")
        println(io, "Tăng L đồng thời tăng mật độ và có thể làm tăng số ứng viên/output: đây là các cơ chế ảnh hưởng ",
            "của độ dài giao dịch, không phải phép đo tách riêng từng nguyên nhân. Một seed và dải tham số không đại diện mọi CSDL.\n")
        println(io, "## Mã SHA-256 của mã nguồn tại thời điểm đo\n")
        paths = [joinpath(@__DIR__, name) for name in ("benchmark_transaction_length.jl", "benchmark_scalability.jl",
            "scalability_worker.jl", "benchmark_peak_ram.jl", "benchmark_processes.jl")]
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
    options = parse_options(args)
    for name in ("runs.csv", "summary.csv", "metadata.md")
        isfile(joinpath(options.output_dir, name)) && error("Đã có kết quả; chọn --output-dir mới")
    end
    cases = prepare_databases(options, joinpath(PROJECT_DIR, "data", "benchmark", "processed", "transaction_length"))
    mkpath(options.output_dir)
    scratch_parent = joinpath(PROJECT_DIR, "results", "benchmarks", "tmp")
    mkpath(scratch_parent)
    scratch = mktempdir(scratch_parent; prefix = "transaction_length_", cleanup = false)
    references = generate_references(cases, options, scratch)
    write_metadata(cases, options)
    min_count = ceil(Int, options.minsup * options.n_transactions)
    dimensions = ("dataset", "transaction_length", "mean_length", "n_transactions", "n_items",
        "observed_items", "total_occurrences", "density", "minsup", "min_count", "backend", "measurement")
    open(joinpath(options.output_dir, "runs.csv"), "w") do raw_io
        open(joinpath(options.output_dir, "summary.csv"), "w") do summary_io
            write_row(raw_io, (dimensions..., "run_id", "order_in_pair", "mining_seconds", "n_itemsets",
                "julia_threads", "exact_match", "spmf_match", "status"))
            write_row(summary_io, (dimensions..., "n_runs", "n_itemsets", "median_seconds", "min_seconds", "max_seconds",
                "transactions_per_second", "exact_match", "spmf_match"))
            for c in cases
                l = c.transaction_length
                reference = references[l]
                times = Dict(b => Float64[] for b in BACKENDS)
                println("L=$l; N=$(options.n_transactions); M=$(options.n_items); itemsets=$(length(reference))")
                flush(stdout)
                dimensions_for = backend -> ("synthetic", l, c.mean_length, options.n_transactions, options.n_items,
                    c.observed_items, c.total_occurrences, l / options.n_items, options.minsup, min_count, backend, MEASUREMENT)
                for run_id in 1:options.n_runs
                    order = isodd(run_id) ? BACKENDS : reverse(BACKENDS)
                    for (position, backend) in enumerate(order)
                        stem = joinpath(scratch, "L$(l)_$(run_id)_$backend")
                        output, metrics_path = stem * ".txt", stem * ".csv"
                        try
                            run_command(worker_command(c.input_path, output, metrics_path, options.minsup, backend), stem * ".log", options.timeout)
                            metrics = read_metrics(metrics_path)
                            metrics.n_transactions == options.n_transactions || error("Sai số giao dịch")
                            actual = read_itemsets(output)
                            actual == reference || error("Itemset/support không khớp SPMF")
                            metrics.n_itemsets == length(actual) || error("Sai số itemset")
                            all(s -> min_count <= s <= options.n_transactions, values(actual)) || error("Support ngoài miền")
                            push!(times[backend], metrics.mining_seconds)
                            write_row(raw_io, (dimensions_for(backend)..., run_id, position, metrics.mining_seconds,
                                length(actual), metrics.julia_threads, true, true, "ok"))
                            println("  lần=$run_id backend=$backend mine=$(round(1000 * metrics.mining_seconds; digits=3)) ms; khớp=true")
                            flush(stdout)
                        catch
                            write_row(raw_io, (dimensions_for(backend)..., run_id, position, "", "", "", false, false, "failed"))
                            rethrow()
                        end
                    end
                end
                for backend in BACKENDS
                    samples = times[backend]
                    elapsed = median(samples)
                    write_row(summary_io, (dimensions_for(backend)..., options.n_runs, length(reference), elapsed,
                        minimum(samples), maximum(samples), options.n_transactions / elapsed, true, true))
                end
            end
        end
    end
    println("Hoàn tất thí nghiệm độ dài giao dịch: $(options.output_dir)\nOutput và nhật ký: $scratch")
    return options.output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module
