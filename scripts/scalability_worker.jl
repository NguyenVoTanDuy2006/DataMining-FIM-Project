module ScalabilityWorker

using EclatFIM: mine, read_spmf_transactions, write_spmf_itemsets

const METRICS_HEADER = "n_transactions,n_itemsets,mining_seconds,julia_threads"

function run_worker(input_path, output_path, metrics_path, minsup, backend)
    backend in (:set, :bitvector) || throw(ArgumentError("Backend phải là set hoặc bitvector"))
    isfinite(minsup) && 0 < minsup <= 1 || throw(ArgumentError("minsup phải thuộc (0, 1]"))
    transactions = read_spmf_transactions(input_path)
    isempty(transactions) && throw(ArgumentError("Tập dữ liệu không được rỗng"))

    # Warm up on this exact subset so the measured call has traversed its code paths.
    mine(transactions, minsup; backend)
    GC.gc()
    itemsets = Dict{Tuple{Vararg{Int}}, Int}()
    mining_seconds = @elapsed itemsets = mine(transactions, minsup; backend)
    mining_seconds > 0 || error("Thời gian đo không hợp lệ")

    # Input loading, warm-up, explicit GC and output serialization are outside @elapsed.
    mkpath(dirname(output_path))
    mkpath(dirname(metrics_path))
    write_spmf_itemsets(output_path, itemsets)
    metrics = (n_transactions = length(transactions), n_itemsets = length(itemsets),
        mining_seconds = mining_seconds, julia_threads = Threads.nthreads())
    open(metrics_path, "w") do io
        println(io, METRICS_HEADER)
        println(io, join(values(metrics), ","))
    end
    return metrics
end

function main(args = ARGS)
    length(args) == 5 || throw(ArgumentError(
        "Cần truyền: INPUT OUTPUT METRICS MINSUP set|bitvector"))
    input_path, output_path, metrics_path, minsup_text, backend_text = args
    return run_worker(input_path, output_path, metrics_path,
        parse(Float64, minsup_text), Symbol(backend_text))
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module
