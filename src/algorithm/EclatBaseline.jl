"""Mine frequent itemsets with the selected vertical Eclat backend.

`min_count` is an absolute support count. Empty transactions count in the
database denominator, while duplicate items within a transaction are ignored.
The default `:set` backend preserves the baseline behavior; `:bitvector` uses
dense TID lists. `max_length`, `deadline`, and `max_itemsets` provide additive
limits for bounded exploratory runs. A limit raises an exception; partial
output is never returned as a complete result.
"""
function mine_count(transactions::AbstractVector{<:AbstractVector{<:Integer}}, min_count::Integer;
    backend::Symbol=:set, max_length::Integer=typemax(Int), deadline::Union{Nothing,Real}=nothing,
    max_itemsets::Integer=typemax(Int))
    if backend == :bitvector
        return mine_bitvector(transactions, min_count;
            max_length, deadline, max_itemsets)
    end
    backend == :set || throw(ArgumentError("Unsupported backend: $backend"))
    min_count > 0 || throw(ArgumentError("min_count must be positive"))
    max_length > 0 || throw(ArgumentError("max_length must be positive"))
    max_itemsets > 0 || throw(ArgumentError("max_itemsets must be positive"))
    vertical = Dict{Int,Set{Int}}()
    for (tid, transaction) in enumerate(transactions)
        !isnothing(deadline) && time() > deadline && throw(InterruptException())
        for item in unique(transaction)
            item > 0 || throw(ArgumentError("Item IDs must be positive"))
            push!(get!(vertical, Int(item), Set{Int}()), tid)
        end
    end

    result = Dict{Tuple{Vararg{Int}},Int}()
    function visit(prefix::Tuple, candidates::Vector{Tuple{Int,Set{Int}}})
        for i in eachindex(candidates)
            !isnothing(deadline) && time() > deadline && throw(InterruptException())
            item, tids = candidates[i]
            length(tids) >= min_count || continue
            itemset = (prefix..., item)
            result[itemset] = length(tids)
            length(result) > max_itemsets && throw(OverflowError("max_itemsets exceeded"))
            length(itemset) >= max_length && continue
            suffix = Tuple{Int,Set{Int}}[]
            for j in (i + 1):length(candidates)
                !isnothing(deadline) && time() > deadline && throw(InterruptException())
                next_item, next_tids = candidates[j]
                common = intersect(tids, next_tids)
                length(common) >= min_count && push!(suffix, (next_item, common))
            end
            visit(itemset, suffix)
        end
    end

    candidates = [(item, tids) for (item, tids) in sort!(collect(vertical); by=first)
        if length(tids) >= min_count]
    visit((), candidates)
    return result
end
