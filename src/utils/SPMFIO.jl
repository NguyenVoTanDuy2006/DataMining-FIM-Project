"""Read transactions and frequent itemsets in SPMF text format."""

function _parse_spmf_item(token::AbstractString, line_number::Int)::Int
    item = tryparse(Int, token)
    item === nothing && throw(
        ArgumentError("Invalid item '$token' on line $line_number")
    )
    item > 0 || throw(
        ArgumentError("Item IDs must be positive on line $line_number")
    )
    return item
end

function read_spmf_transactions(io::IO)::Vector{Vector{Int}}
    transactions = Vector{Vector{Int}}()

    for (line_number, line) in enumerate(eachline(io))
        transaction = Int[]
        for token in split(strip(line))
            push!(transaction, _parse_spmf_item(token, line_number))
        end
        push!(transactions, transaction)
    end

    return transactions
end

function read_spmf_transactions(path::AbstractString)::Vector{Vector{Int}}
    open(path, "r") do io
        return read_spmf_transactions(io)
    end
end

function _validate_output_itemset(itemset, support)
    itemset isa Tuple || throw(ArgumentError("Itemset keys must be tuples"))
    support isa Integer && support > 0 || throw(
        ArgumentError("Support counts must be positive integers")
    )

    previous = 0
    for item in itemset
        item isa Integer && item > previous || throw(
            ArgumentError("Output itemsets must contain sorted positive IDs")
        )
        previous = item
    end
    isempty(itemset) && throw(ArgumentError("Empty itemsets are not supported"))
end

function write_spmf_itemsets(io::IO, itemsets::AbstractDict)
    ordered_itemsets = sort(collect(keys(itemsets)))

    for itemset in ordered_itemsets
        support = itemsets[itemset]
        _validate_output_itemset(itemset, support)
        println(io, join(itemset, " "), " #SUP: ", support)
    end

    return nothing
end

function write_spmf_itemsets(path::AbstractString, itemsets::AbstractDict)
    open(path, "w") do io
        write_spmf_itemsets(io, itemsets)
    end
    return nothing
end

function read_spmf_itemsets(io::IO)::Dict{Tuple{Vararg{Int}}, Int}
    itemsets = Dict{Tuple{Vararg{Int}}, Int}()

    for (line_number, line) in enumerate(eachline(io))
        stripped = strip(line)
        isempty(stripped) && continue

        match_result = match(
            r"^(.*?)\s*#SUP:\s*([0-9]+)\s*$",
            stripped
        )
        match_result === nothing && throw(
            ArgumentError("Invalid SPMF output on line $line_number")
        )

        item_text = strip(match_result.captures[1])
        isempty(item_text) && throw(
            ArgumentError("Empty itemset on line $line_number")
        )

        items = Int[]
        for token in split(item_text)
            item = _parse_spmf_item(token, line_number)
            push!(items, item)
        end

        length(unique(items)) == length(items) || throw(
            ArgumentError("Duplicate item in itemset on line $line_number")
        )
        sort!(items)
        itemset = Tuple(items)
        haskey(itemsets, itemset) && throw(
            ArgumentError("Duplicate itemset on line $line_number")
        )
        support = parse(Int, match_result.captures[2])
        support > 0 || throw(
            ArgumentError("Support counts must be positive on line $line_number")
        )
        itemsets[itemset] = support
    end

    return itemsets
end

function read_spmf_itemsets(path::AbstractString)::Dict{Tuple{Vararg{Int}}, Int}
    open(path, "r") do io
        return read_spmf_itemsets(io)
    end
end

"""Return missing, extra, and support-mismatched itemsets."""
function compare_itemsets(actual::AbstractDict, expected::AbstractDict)
    missing = sort([key for key in keys(expected) if !haskey(actual, key)])
    extra = sort([key for key in keys(actual) if !haskey(expected, key)])
    support_mismatches = sort([
        (key, actual[key], expected[key])
        for key in keys(actual)
        if haskey(expected, key) && actual[key] != expected[key]
    ])

    return (
        missing = missing,
        extra = extra,
        support_mismatches = support_mismatches,
    )
end
