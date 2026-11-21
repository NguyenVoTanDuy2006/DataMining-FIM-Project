using EclatFIM
using Printf
using TOML

include(joinpath(@__DIR__, "..", "..", "src", "fashion_fim", "FashionFIMWorkflow.jl"))
using .FashionFIMWorkflow

function process_peak_rss_mb()
    Sys.islinux() || return "NA"
    usage = Vector{Clong}(undef, 18)
    result = ccall(:getrusage, Cint, (Cint, Ptr{Clong}), 0, usage)
    result == 0 || return "NA"
    return Float64(usage[5]) / 1024
end

struct OutputLimitExceeded <: Exception
    limit::Int
    observed::Int
    records::Int
    written_bytes::Int
end

function write_result(path, fields)
    temporary = path * ".tmp"
    open(temporary, "w") do io
        TOML.print(io, fields)
        flush(io)
    end
    mv(temporary, path; force=true)
end

function write_patterns(staging_path, patterns, min_count, output_limit_bytes, transaction_count)
    keys_sorted = sort!(collect(keys(patterns)); by=key -> (length(key), key))
    written_bytes = 0
    written_records = 0
    maximum_length = 0

    open(staging_path, "w") do io
        for key in keys_sorted
            support = Int(patterns[key])
            (1 <= length(key) <= 32) || error("Invalid itemset length: $key")
            issorted(key) && length(unique(key)) == length(key) || error("Non-canonical itemset key: $key")
            all(item -> 1 <= item <= 32, key) || error("Item outside 1:32 in $key")
            support >= min_count || error("Support below min_count for $key")
            support <= transaction_count || error("Support exceeds transaction count for $key")

            fraction = @sprintf("%.17g", support / transaction_count)
            line = "{\"items\":[$(join(key, ','))],\"length\":$(length(key))," *
                "\"support_count\":$support,\"support_fraction\":$fraction}\n"
            line_bytes = ncodeunits(line)
            if written_bytes + line_bytes > output_limit_bytes
                throw(OutputLimitExceeded(output_limit_bytes, written_bytes + line_bytes, written_records, written_bytes))
            end
            write(io, line)
            written_bytes += line_bytes
            written_records += 1
            maximum_length = max(maximum_length, length(key))
        end
        flush(io)
    end
    return (record_count=written_records, max_itemset_length=maximum_length,
        output_size_bytes=written_bytes)
end

function parse_worker_arguments(args)
    filtered = copy(args)
    backend = :set
    backend_index = findfirst(==("--backend"), filtered)
    if !isnothing(backend_index)
        backend_index < length(filtered) || error("--backend requires set or bitvector")
        backend_value = filtered[backend_index + 1]
        backend_value in ("set", "bitvector") || error("Unsupported backend: $backend_value")
        backend = Symbol(backend_value)
        deleteat!(filtered, backend_index:backend_index + 1)
    end
    length(filtered) in (5, 6) || error("Usage: run_mining_worker.jl INPUT STAGING RESULT MIN_COUNT OUTPUT_LIMIT_BYTES [EXPECTED_N] [--backend set|bitvector]")
    input_path, staging_path, result_path = filtered[1:3]
    min_count = parse(Int, filtered[4])
    output_limit_bytes = parse(Int, filtered[5])
    expected_n = length(filtered) == 6 ? parse(Int, filtered[6]) : 70_000
    return (; input_path, staging_path, result_path, min_count, output_limit_bytes, expected_n, backend)
end

function main(args)
    parsed = parse_worker_arguments(args)
    input_path, staging_path, result_path = parsed.input_path, parsed.staging_path, parsed.result_path
    min_count, output_limit_bytes, expected_n, backend =
        parsed.min_count, parsed.output_limit_bytes, parsed.expected_n, parsed.backend
    mkpath(dirname(staging_path))
    started = time()

    try
        loaded = load_transactions(input_path; expected_n, expected_items=1:32,
            require_nonempty=false, unique_mapping=true)
        patterns = EclatFIM.mine(loaded.transactions, min_count; backend)
        patterns isa Dict{Tuple{Vararg{Int}},Int} || error("Unexpected Eclat return type: $(typeof(patterns))")
        metrics = write_patterns(staging_path, patterns, min_count, output_limit_bytes, length(loaded.transactions))
        write_result(result_path, Dict{String,Any}(
            "worker_status" => isempty(patterns) ? "COMPLETED_ZERO" : "COMPLETED_FULL",
            "record_count" => metrics.record_count,
            "max_itemset_length" => metrics.max_itemset_length,
            "output_size_bytes" => metrics.output_size_bytes,
            "worker_runtime_seconds" => time() - started,
            "peak_rss_mb" => process_peak_rss_mb(),
            "input_sha256" => loaded.input_sha256,
            "backend" => string(backend),
            "transaction_count" => length(loaded.transactions),
            "min_count" => min_count,
            "error_type" => "",
            "error_message" => ""))
        println("Worker returned $(metrics.record_count) patterns for min_count=$min_count")
        return 0
    catch error_value
        if error_value isa OutputLimitExceeded
            write_result(result_path, Dict{String,Any}(
                "worker_status" => "OUTPUT_LIMIT",
                "backend" => string(backend),
                "record_count" => error_value.records,
                "observed_partial_itemsets" => error_value.records,
                "output_size_bytes" => error_value.written_bytes,
                "worker_runtime_seconds" => time() - started,
                "peak_rss_mb" => process_peak_rss_mb(),
                "min_count" => min_count,
                "error_type" => string(typeof(error_value)),
                "error_message" => "output_limit_bytes exceeded"))
            println(stderr, "Output limit reached: limit=$(error_value.limit), records=$(error_value.records)")
            return 73
        end
        write_result(result_path, Dict{String,Any}(
            "worker_status" => "FAILED",
            "backend" => string(backend),
            "worker_runtime_seconds" => time() - started,
            "peak_rss_mb" => process_peak_rss_mb(),
            "min_count" => min_count,
            "error_type" => string(typeof(error_value)),
            "error_message" => sprint(showerror, error_value)))
        showerror(stderr, error_value, catch_backtrace())
        println(stderr)
        return 1
    end
end

exit(main(ARGS))
