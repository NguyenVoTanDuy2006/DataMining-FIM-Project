using Dates
using SHA
using Statistics: median

const PROJECT_DIR = normpath(joinpath(@__DIR__, ".."))
const BACKENDS = ("julia_set", "julia_bitvector", "spmf_eclat")
const DATASETS = [
    (name = "retail", offset = 1, n_transactions = 88162,
        minsups = [0.10, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005]),
    (name = "chess", offset = 0, n_transactions = 3196,
        minsups = [0.95, 0.925, 0.90, 0.875, 0.85, 0.825, 0.80]),
    (name = "mushroom", offset = 0, n_transactions = 8124,
        minsups = [0.95, 0.90, 0.80, 0.70, 0.60, 0.50, 0.40]),
    (name = "T10I4D100K", offset = 1, n_transactions = 100000,
        minsups = [0.03, 0.025, 0.02, 0.015, 0.01, 0.0075, 0.005]),
]

function parse_options(args)
    options = Dict(
        "--dataset" => "all", "--runs" => "5", "--minsup" => "",
        "--output-dir" => joinpath(PROJECT_DIR, "results", "benchmarks", "processes"),
    )
    iseven(length(args)) || throw(ArgumentError("Mỗi tùy chọn cần một giá trị"))
    for i in 1:2:length(args)
        haskey(options, args[i]) || throw(ArgumentError("Tùy chọn lạ: $(args[i])"))
        options[args[i]] = args[i + 1]
    end
    n_runs = parse(Int, options["--runs"])
    n_runs > 0 || throw(ArgumentError("Số lần đo phải dương"))
    configs = filter(c -> options["--dataset"] in ("all", c.name), DATASETS)
    isempty(configs) && throw(ArgumentError("Tên dataset không hợp lệ"))
    if !isempty(options["--minsup"])
        minsup = parse(Float64, options["--minsup"])
        0 < minsup <= 1 || throw(ArgumentError("minsup phải thuộc (0, 1]"))
        configs = [merge(c, (minsups = [minsup],)) for c in configs]
    end
    return configs, n_runs, abspath(options["--output-dir"])
end

file_sha256(path) = open(io -> bytes2hex(sha256(io)), path)

function prepare_input(config)
    raw_path = joinpath(PROJECT_DIR, "data", "benchmark", "raw", config.name * ".dat")
    # Dùng bản chuẩn hóa riêng, không ghi đè dữ liệu thực hành trước đó.
    input_path = joinpath(PROJECT_DIR, "data", "benchmark", "processed",
        "processes", config.name * "_spmf.txt")
    mkpath(dirname(input_path))
    n_transactions = 0
    open(input_path, "w") do io
        for line in eachline(raw_path)
            items = parse.(Int, split(line)) .+ config.offset
            isempty(items) && error("Gặp giao dịch rỗng trong $(config.name)")
            all(>(0), items) || error("ID phải dương")
            length(unique(items)) == length(items) || error("Item bị lặp trong giỏ")
            sort!(items)
            println(io, join(items, " "))
            n_transactions += 1
        end
    end
    n_transactions == config.n_transactions || error("Sai số giao dịch $(config.name)")
    return input_path
end

function read_itemsets(path)
    itemsets = Dict{Tuple{Vararg{Int}}, Int}()
    # Đọc xong và đóng file trước khi phân tích, kể cả khi gặp dữ liệu sai.
    for line in readlines(path)
        line = strip(line)
        (isempty(line) || startswith(line, "@")) && continue
        parts = split(line, "#SUP:")
        length(parts) == 2 || error("Dòng kết quả không hợp lệ: $line")
        key = Tuple(sort(parse.(Int, split(parts[1]))))
        isempty(key) && error("Itemset rỗng trong kết quả")
        length(unique(key)) == length(key) || error("Item lặp trong itemset")
        haskey(itemsets, key) && error("Itemset bị ghi lặp: $key")
        support_count = parse(Int, strip(parts[2]))
        support_count > 0 || error("Support count phải dương")
        itemsets[key] = support_count
    end
    return itemsets
end

function measure_command(command, log_path)
    # Chỉ đo tiến trình con; đọc và so sánh kết quả nằm ngoài đồng hồ.
    elapsed = open(log_path, "w") do io
        redirected = pipeline(command; stdout = io, stderr = io)
        @elapsed run(redirected)
    end
    return elapsed
end

function write_row(io, values)
    println(io, join(values, ","))
    flush(io)
end

function write_metadata(output_dir, configs, n_runs, java_path, jar_path, inputs)
    version_path = joinpath(output_dir, "java_version.txt")
    open(version_path, "w") do io
        run(pipeline(`$java_path -version`; stdout = io, stderr = io))
    end
    open(joinpath(output_dir, "metadata.md"), "w") do io
        println(io, "# Cấu hình lần đo\n")
        println(io, "- Thời điểm địa phương: ", now())
        println(io, "- Julia: ", VERSION)
        println(io, "- CPU: ", Sys.CPU_NAME)
        println(io, "- Số CPU logic: ", Sys.CPU_THREADS)
        println(io, "- Số luồng Julia: ", Threads.nthreads())
        println(io, "- Hệ điều hành: ", Sys.KERNEL, " / ", Sys.ARCH)
        println(io, "- RAM máy (GiB): ", round(Sys.total_memory() / 2.0^30; digits = 2))
        println(io, "- Số lần ghi nhận mỗi backend / cấu hình: ", n_runs)
        println(io, "- Java: `", java_path, "`; phiên bản trong java_version.txt")
        println(io, "- SHA-256 spmf.jar: `", file_sha256(jar_path), "`")
        println(io, "- SHA-256 chương trình điều khiển tại thời điểm đo: `", file_sha256(@__FILE__), "`")
        println(io, "- SHA-256 mine_once.jl tại thời điểm đo: `",
            file_sha256(joinpath(@__DIR__, "mine_once.jl")), "`\n")
        println(io, "Mã chạy lại nằm trong scripts/. Chỉ lưu checksum, không sao chép mã nguồn; ",
            "checksum có thể khác nếu sửa script sau lần đo.\n")
        println(io, "## Phương pháp\n")
        println(io, "Mỗi lần tạo tiến trình mới. Tính khởi động runtime, nạp package/lớp, ",
            "JIT, đọc dữ liệu, dựng TID-set, khai thác và ghi file kết quả/log.")
        println(io, "Chuẩn hóa dữ liệu, tạo lệnh, mở log và đối chiếu kết quả không tính vào thời gian.")
        println(io, "Mỗi cấu hình chạy chuẩn bị một lần cho mỗi backend; các lần đo sau vẫn ",
            "tạo tiến trình mới và vẫn tính JIT. Không phải đo cold disk cache.")
        println(io, "Chạy tuần tự, xoay vòng thứ tự ba chương trình giữa các lần; lấy median, ",
            "giữ min/max và mọi số đo gốc. Đối chiếu toàn bộ Dict của hai backend Julia với SPMF.")
        println(io, "Giữ cùng số giao dịch, ID và minsup; Julia Set baseline, Julia BitVector tối ưu và SPMF Eclat. ",
            "Không so trực tiếp với các CSV đo mine sau warm-up trước đó.")
        println(io, "Không đo peak RSS, không dùng Maximum memory usage của Java thay cho peak RSS.\n")
        for source in ("src/algorithm/EclatBaseline.jl", "src/algorithm/EclatOptimized.jl", "Manifest.toml")
            println(io, "- SHA-256 ", source, ": `", file_sha256(joinpath(PROJECT_DIR, source)), "`")
        end
        println(io, "## Dữ liệu\n")
        for config in configs
            println(io, "- ", config.name, ": ", config.n_transactions,
                " giao dịch; ID +", config.offset, "; minsup = ", config.minsups,
                "; SHA-256 đầu vào: `", file_sha256(inputs[config.name]), "`")
        end
        println(io, "\nNguồn SPMF: https://www.philippe-fournier-viger.com/spmf/download.php")
        println(io, "Nguồn dữ liệu: https://fimi.uantwerpen.be/data/")
    end
end

function main(args = ARGS)
    configs, n_runs, output_dir = parse_options(args)
    java_path = Sys.which("java")
    isnothing(java_path) && error("Không tìm thấy java trong PATH")
    jar_path = joinpath(PROJECT_DIR, "data", "benchmark", "tools", "spmf.jar")
    isfile(jar_path) || error("Thiếu spmf.jar: $jar_path")
    worker_path = joinpath(@__DIR__, "mine_once.jl")
    isfile(worker_path) && filesize(worker_path) > 0 || error("Thiếu chương trình mine_once.jl")
    mkpath(output_dir)
    # Thư mục mới cho từng lần chạy, giữ log và kết quả con để truy vết.
    scratch_parent = joinpath(PROJECT_DIR, "results", "benchmarks", "tmp")
    mkpath(scratch_parent)
    scratch_dir = mktempdir(scratch_parent;
        prefix = "processes_", cleanup = false)
    inputs = Dict(c.name => prepare_input(c) for c in configs)
    write_metadata(output_dir, configs, n_runs, java_path, jar_path, inputs)
    julia_executable = Base.julia_cmd()
    raw_path = joinpath(output_dir, "runs.csv")
    summary_path = joinpath(output_dir, "summary.csv")
    total_configs = sum(length(c.minsups) for c in configs)
    completed = 0

    open(raw_path, "w") do raw_io
        open(summary_path, "w") do summary_io
            write_row(raw_io, ("dataset", "backend", "measurement", "minsup",
                "n_transactions", "min_count", "run_id", "runtime_seconds",
                "n_itemsets", "exact_match"))
            write_row(summary_io, ("dataset", "measurement", "minsup", "n_transactions",
                "min_count", "n_itemsets", "n_runs", "julia_median_seconds",
                "spmf_median_seconds", "julia_min_seconds", "julia_max_seconds",
                "spmf_min_seconds", "spmf_max_seconds", "julia_over_spmf",
                "optimized_median_seconds", "optimized_min_seconds", "optimized_max_seconds",
                "optimized_over_spmf", "set_over_optimized", "exact_match"))
            for config in configs, minsup in config.minsups
                input_path = inputs[config.name]
                min_count = ceil(Int, minsup * config.n_transactions)
                times = Dict(backend => Float64[] for backend in BACKENDS)
                expected = nothing
                println("\n[$(completed + 1)/$total_configs] $(config.name), minsup=$minsup")
                flush(stdout)
                for run_id in 0:n_runs
                    outputs = Dict{String, String}()
                    commands = Dict{String, Cmd}()
                    for backend in BACKENDS
                        prefix = joinpath(scratch_dir,
                            "$(config.name)_$(minsup)_$(run_id)_$(backend)")
                        output_path = prefix * ".txt"
                        outputs[backend] = output_path
                        if backend != "spmf_eclat"
                            representation = backend == "julia_set" ? "set" : "bitvector"
                            commands[backend] = `$julia_executable --startup-file=no --history-file=no --threads=1 --project=$PROJECT_DIR $worker_path $input_path $output_path $minsup $representation`
                        else
                            percent = string(minsup * 100, "%")
                            commands[backend] = `$java_path -jar $jar_path run Eclat $input_path $output_path $percent`
                        end
                    end
                    # Lượt 0 chuẩn bị cache; xoay vòng thứ tự để giảm thiên lệch vị trí.
                    order = circshift(collect(BACKENDS), mod(run_id, length(BACKENDS)))
                    elapsed = Dict{String, Float64}()
                    for backend in order
                        elapsed[backend] = measure_command(commands[backend], outputs[backend] * ".log")
                    end
                    julia_itemsets = read_itemsets(outputs["julia_set"])
                    optimized_itemsets = read_itemsets(outputs["julia_bitvector"])
                    spmf_itemsets = read_itemsets(outputs["spmf_eclat"])
                    julia_itemsets == optimized_itemsets == spmf_itemsets || error(
                        "Sai lệch kết quả $(config.name), minsup=$minsup, lần=$run_id")
                    all(count -> min_count <= count <= config.n_transactions,
                        values(julia_itemsets)) || error("Support count ngoài miền hợp lệ")
                    if isnothing(expected)
                        expected = julia_itemsets
                    else
                        expected == julia_itemsets || error("Kết quả không ổn định giữa các lần chạy")
                    end
                    run_id == 0 && continue
                    for backend in BACKENDS
                        push!(times[backend], elapsed[backend])
                        write_row(raw_io, (config.name, backend, "end_to_end_fresh_process",
                            minsup, config.n_transactions, min_count, run_id,
                            elapsed[backend], length(julia_itemsets), true))
                    end
                end
                jt, ot, st = times["julia_set"], times["julia_bitvector"], times["spmf_eclat"]
                jm, om, sm = median(jt), median(ot), median(st)
                write_row(summary_io, (config.name, "end_to_end_fresh_process", minsup,
                    config.n_transactions, min_count, length(expected), n_runs,
                    jm, sm, minimum(jt), maximum(jt), minimum(st), maximum(st), jm / sm,
                    om, minimum(ot), maximum(ot), om / sm, jm / om, true))
                completed += 1
                println("  itemsets=$(length(expected)) | Julia=$(round(jm; digits=4))s",
                    " | BitVector=$(round(om; digits=4))s | SPMF=$(round(sm; digits=4))s | khớp=true")
                flush(stdout)
            end
        end
    end
    println("\nHoàn tất $completed cấu hình. Kết quả: $output_dir")
    println("Log và output từng tiến trình: $scratch_dir")
    return output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
