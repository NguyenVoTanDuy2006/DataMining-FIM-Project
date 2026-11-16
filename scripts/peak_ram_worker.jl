module PeakRAMWorker

using EclatFIM: mine, read_spmf_transactions, write_spmf_itemsets

const METRICS_HEADER = "n_transactions,n_itemsets,pre_mine_peak_rss_bytes,peak_rss_bytes,julia_threads"

function run_worker(input_path, output_path, metrics_path, minsup, backend)
    backend in (:set, :bitvector) || throw(ArgumentError("Backend must be set or bitvector"))
    isfinite(minsup) && 0 < minsup <= 1 || throw(ArgumentError("minsup must be in (0, 1]"))

    # Compile the chosen miner and the common parser on the same small database.
    # The OS high-water mark cannot be reset: this warm-up remains in process peak RSS.
    toy = read_spmf_transactions(IOBuffer("1 2 3\n1 2\n2 3\n"))
    mine(toy, 0.5; backend)
    Sys.maxrss()
    GC.gc()

    transactions = read_spmf_transactions(input_path)
    isempty(transactions) && throw(ArgumentError("Empty benchmark database"))
    GC.gc()
    pre_mine_peak_rss_bytes = Sys.maxrss()
    itemsets = mine(transactions, minsup; backend)
    # Keep both input and output alive while reading the process high-water mark.
    peak_rss_bytes = GC.@preserve transactions itemsets begin
        Sys.maxrss()
    end
    0 < pre_mine_peak_rss_bytes <= peak_rss_bytes || error("Invalid OS peak RSS counter")

    # Capture memory BEFORE sorting/serializing the output or writing metrics.
    mkpath(dirname(output_path))
    mkpath(dirname(metrics_path))
    write_spmf_itemsets(output_path, itemsets)
    metrics = (
        n_transactions = length(transactions), n_itemsets = length(itemsets),
        pre_mine_peak_rss_bytes = pre_mine_peak_rss_bytes,
        peak_rss_bytes = peak_rss_bytes, julia_threads = Threads.nthreads(),
    )
    open(metrics_path, "w") do io
        println(io, METRICS_HEADER)
        println(io, join(values(metrics), ","))
    end
    return metrics
end

function main(args = ARGS)
    length(args) == 5 || throw(ArgumentError(
        "Usage: peak_ram_worker.jl INPUT OUTPUT METRICS MINSUP set|bitvector"))
    input_path, output_path, metrics_path, minsup_text, backend_text = args
    return run_worker(input_path, output_path, metrics_path,
        parse(Float64, minsup_text), Symbol(backend_text))
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module
