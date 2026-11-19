# TODO(TV2): Run the four benchmark datasets with common measurement settings.
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using Statistics: median

using EclatFIM: mine

function read_transactions(path; item_offset = 0)
    transactions = Vector{Vector{Int}}()

    for line in eachline(path)
        items = split(line)
        transaction = parse.(Int, items) .+ item_offset
        push!(transactions, transaction)
    end

    return transactions
end


function measure_baseline(transactions, minsup; n_runs = 5)
    # Chạy trước một lần để Julia biên dịch.
    mine(transactions, minsup; backend = :set)

    # Lưu thời gian của từng lần chạy, đơn vị giây.
    times = Float64[]

    for run_id in 1:n_runs
        elapsed = @elapsed begin
            mine(transactions, minsup; backend = :set)
        end

        push!(times, elapsed)
        println("Lần ", run_id, ": ", elapsed, " giây")
    end

    return times
end


function benchmark_dataset(transactions, minsup_values)
    results = NamedTuple[]

    for minsup in minsup_values
        println("\nĐang đo minsup = ", minsup)

        # Chạy riêng để lấy số itemset, không tính lần này vào thời gian đo.
        frequent_itemsets = mine(
            transactions, minsup; backend = :set
        )
        n_itemsets = length(frequent_itemsets)

        # Đo nhiều lần sau warm-up.
        times = measure_baseline(transactions, minsup)
        runtime_seconds = median(times)

        result = (
            minsup = minsup,
            n_itemsets = n_itemsets,
            runtime_seconds = runtime_seconds,
            run_times = times,
        )
        push!(results, result)

        println(
            "minsup = ", minsup,
            " | itemsets = ", n_itemsets,
            " | median = ", runtime_seconds, " giây"
        )
    end

    return results
end


function write_benchmark_csv(path, dataset, results)
    # Tạo thư mục chứa kết quả nếu chưa có.
    mkpath(dirname(path))

    open(path, "w") do io
        println(
            io,
            "dataset,backend,minsup,n_itemsets,median_seconds"
        )

        for result in results
            row = (
                dataset,
                "set",
                result.minsup,
                result.n_itemsets,
                result.runtime_seconds,
            )

            println(io, join(row, ","))
        end
    end
end

function write_raw_benchmark_csv(path, dataset, results)
    mkpath(dirname(path))

    open(path, "w") do io
        println(
            io,
            "dataset,backend,minsup,n_itemsets,run_id,runtime_seconds"
        )

        for result in results
            # Mỗi lần đo được lưu thành một dòng riêng.
            for (run_id, elapsed) in enumerate(result.run_times)
                row = (
                    dataset,
                    "set",
                    result.minsup,
                    result.n_itemsets,
                    run_id,
                    elapsed,
                )

                println(io, join(row, ","))
            end
        end
    end
end

function write_spmf(path, transactions)
    mkpath(dirname(path))

    # Mở file một lần, ghi mỗi giao dịch thành một dòng.
    open(path, "w") do io
        for transaction in transactions
            println(io, join(transaction, " "))
        end
    end
end

# path = joinpath(
#     @__DIR__, "..", "data", "benchmark", "raw", "retail.dat"
# )

# transactions = read_transactions(path; item_offset = 1)
# minsup = 0.1
# n_transactions = length(transactions)
# min_count = ceil(Int, minsup * n_transactions)

# frequent_itemsets = mine(
#     transactions,
#     minsup;
#     backend = :set
# )

# times = measure_baseline(transactions, minsup)

# # Dải thử ban đầu dành riêng cho Retail.
# minsup_values = [0.10, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005]
# results = benchmark_dataset(transactions, minsup_values)


# output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "retail_baseline.csv"
# )

# write_benchmark_csv(output_path, "retail", results)
# println("Đã lưu: ", output_path)


# raw_output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "retail_baseline_runs.csv"
# )
# write_raw_benchmark_csv(raw_output_path, "retail", results)
# println("Đã lưu từng lần đo: ", raw_output_path)


# Chess 
# path = joinpath(
#     @__DIR__, "..", "data", "benchmark", "raw", "chess.dat"
# )

# transactions = read_transactions(path; item_offset = 0)

# println("Số giao dịch: ", length(transactions))
# println("Số item trong giao dịch đầu: ", length(transactions[1]))

# # Chạy thử một ngưỡng cao trước.
# minsup_values = [0.95, 0.925, 0.90, 0.875, 0.85, 0.825, 0.80]
# results = benchmark_dataset(transactions, minsup_values)

# # Lưu bảng median.
# output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "chess_baseline.csv"
# )

# write_benchmark_csv(output_path, "chess", results)

# # Lưu từng lần đo.
# raw_output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "chess_baseline_runs.csv"
# )

# write_raw_benchmark_csv(raw_output_path, "chess", results)

# println("\nBảng kết quả Chess:")

# for result in results
#     println(
#         "minsup = ", result.minsup,
#         " | itemsets = ", result.n_itemsets,
#         " | median = ", result.runtime_seconds, " giây"
#     )
# end

#MushRoom
# path = joinpath(
#     @__DIR__, "..", "data", "benchmark", "raw", "mushroom.dat"
# )

# transactions = read_transactions(path; item_offset = 0)

# println("Số giao dịch: ", length(transactions))
# println("Số item trong giao dịch đầu: ", length(transactions[1]))


# minsup_values = [0.95, 0.90, 0.80, 0.70, 0.60, 0.50, 0.40]
# results = benchmark_dataset(transactions, minsup_values)

# output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "mushroom_baseline.csv"
# )

# write_benchmark_csv(output_path, "mushroom", results)

# raw_output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "mushroom_baseline_runs.csv"
# )

# write_raw_benchmark_csv(raw_output_path, "mushroom", results)

# println("\nBảng kết quả Mushroom:")

# for result in results
#     println(
#         "minsup = ", result.minsup,
#         " | itemsets = ", result.n_itemsets,
#         " | median = ", result.runtime_seconds, " giây"
#     )
# end


path = joinpath(
    @__DIR__, "..", "data", "benchmark", "raw", "T10I4D100K.dat"
)

transactions = read_transactions(path; item_offset = 1)

println("Số giao dịch: ", length(transactions))
println("ID nhỏ nhất: ", minimum(minimum.(transactions)))

minsup_values = [0.03, 0.025, 0.02, 0.015, 0.01, 0.0075, 0.005]
results = benchmark_dataset(transactions, minsup_values)


# output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "T10I4D100K_baseline.csv"
# )

# write_benchmark_csv(output_path, "T10I4D100K", results)

# raw_output_path = joinpath(
#     @__DIR__, "..", "results", "benchmarks",
#     "T10I4D100K_baseline_runs.csv"
# )

# write_raw_benchmark_csv(raw_output_path, "T10I4D100K", results)

# println("\nBảng kết quả T10I4D100K:")

# for result in results
#     println(
#         "minsup = ", result.minsup,
#         " | itemsets = ", result.n_itemsets,
#         " | median = ", result.runtime_seconds, " giây"
#     )
# end

spmf_input_path = joinpath(
    @__DIR__, "..", "data", "benchmark", "processed",
    "T10I4D100K_spmf.txt"
)

write_spmf(spmf_input_path, transactions)

println("Đã xuất đầu vào SPMF: ", spmf_input_path)