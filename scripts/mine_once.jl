using EclatFIM: mine

function main(args = ARGS)
    length(args) == 3 || throw(ArgumentError(
        "Cần truyền: đường dẫn đầu vào, đường dẫn đầu ra và minsup"
    ))
    input_path, output_path, minsup_text = args
    minsup = parse(Float64, minsup_text)

    # File đã chuẩn hóa nên giữ nguyên ID và giữ các giỏ giống nhau.
    transactions = Vector{Vector{Int}}()
    for line in eachline(input_path)
        isempty(strip(line)) && continue
        push!(transactions, parse.(Int, split(line)))
    end

    # Không warm-up trong tiến trình con: phép đo này tính cả JIT.
    itemsets = mine(transactions, minsup; backend = :set)

    mkpath(dirname(output_path))
    open(output_path, "w") do io
        for (itemset, support_count) in itemsets
            println(io, join(itemset, " "), " #SUP: ", support_count)
        end
    end
    println("Số itemset: ", length(itemsets))
    return length(itemsets)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
