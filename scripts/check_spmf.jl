import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using EclatFIM: mine

function read_spmf_itemsets(path)
    itemsets = Dict{Tuple{Vararg{Int}}, Int}()

    for line in eachline(path)
        line = strip(line)

        # Bỏ dòng trống và dòng metadata.
        if isempty(line) || startswith(line, "@")
            continue
        end

        # Tách phần item và phần support count.
        parts = split(line, "#SUP:")

        items = parse.(Int, split(parts[1]))
        support_count = parse(Int, strip(parts[2]))

        # Sắp xếp để khóa có cùng quy ước với Julia.
        itemset = Tuple(sort(items))
        itemsets[itemset] = support_count
    end

    return itemsets
end

function run_spmf(jar_path, input_path, output_path, minsup)
    mkpath(dirname(output_path))

    # Đổi tỉ lệ Julia sang phần trăm cho SPMF.
    minsup_percent = string(minsup * 100, "%")

    # Tạo và thực thi lệnh chạy Java.
    command = `java -jar $jar_path run Eclat $input_path $output_path $minsup_percent`
    run(command)
end

function check_dataset(
    dataset, transactions, input_path, jar_path, minsup_values
)
    results = NamedTuple[]

    for minsup in minsup_values
        println("\nĐang kiểm tra minsup = ", minsup)

        # Mỗi ngưỡng có một file kết quả SPMF riêng.
        output_path = joinpath(
            @__DIR__, "..", "results", "benchmarks", "spmf",
            string(dataset, "_", minsup, ".txt")
        )

        run_spmf(jar_path, input_path, output_path, minsup)

        spmf_itemsets = read_spmf_itemsets(output_path)
        julia_itemsets = mine(
            transactions, minsup; backend = :set
        )

        is_match = julia_itemsets == spmf_itemsets

        result = (
            minsup = minsup,
            n_julia = length(julia_itemsets),
            n_spmf = length(spmf_itemsets),
            exact_match = is_match,
        )
        push!(results, result)

        println(result)

        # Dừng tại ngưỡng đầu tiên có sai lệch.
        @assert is_match "Julia và SPMF khác nhau tại minsup = $minsup"
    end

    return results
end

function write_correctness_csv(path, dataset, results)
    mkpath(dirname(path))

    open(path, "w") do io
        println(
            io,
            "dataset,backend,minsup,n_julia,n_spmf,exact_match"
        )

        for result in results
            row = (
                dataset,
                "set",
                result.minsup,
                result.n_julia,
                result.n_spmf,
                result.exact_match,
            )

            println(io, join(row, ","))
        end
    end
end

function prepare_spmf_input(raw_path, output_path; item_offset = 0)
    transactions = Vector{Vector{Int}}()

    for line in eachline(raw_path)
        transaction = parse.(Int, split(line)) .+ item_offset
        push!(transactions, transaction)
    end

    mkpath(dirname(output_path))

    open(output_path, "w") do io
        for transaction in transactions
            println(io, join(transaction, " "))
        end
    end

    # Julia sẽ dùng đúng các giao dịch vừa ghi cho SPMF.
    return transactions
end

# dataset = "retail"
# item_offset = 1
# minsup_values = [0.10, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005]

# dataset = "chess"
# item_offset = 0

# minsup_values = [0.95, 0.925, 0.90, 0.875, 0.85, 0.825, 0.80]

dataset = "mushroom"
item_offset = 0

minsup_values = [0.95, 0.90, 0.80, 0.70, 0.60, 0.50, 0.40]

raw_path = joinpath(
    @__DIR__, "..", "data", "benchmark", "raw",
    string(dataset, ".dat")
)

input_path = joinpath(
    @__DIR__, "..", "data", "benchmark", "processed",
    string(dataset, "_spmf.txt")
)

# Dịch ID theo cấu hình của từng bộ dữ liệu.
transactions = prepare_spmf_input(
    raw_path, input_path; item_offset = item_offset
)

jar_path = joinpath(
    @__DIR__, "..", "data", "benchmark", "tools", "spmf.jar"
)

correctness_results = check_dataset(
    dataset, transactions, input_path, jar_path, minsup_values
)

correctness_path = joinpath(
    @__DIR__, "..", "results", "benchmarks",
    string(dataset, "_correctness.csv")
)

write_correctness_csv(
    correctness_path, dataset, correctness_results
)

println("Đã lưu correctness: ", correctness_path)
