"""Mine frequent itemsets with a Set-based vertical Eclat DFS.

`min_count` is an absolute support count. Empty transactions count in the
database denominator, while duplicate items within a transaction are ignored.
"""
function mine(transactions::AbstractVector{<:AbstractVector{<:Integer}}, min_count::Integer; backend::Symbol=:set)
    backend == :set || throw(ArgumentError("Baseline backend supports only :set"))
    min_count > 0 || throw(ArgumentError("min_count must be positive"))
    vertical = Dict{Int,Set{Int}}()
    for (tid, transaction) in enumerate(transactions)
        for item in unique(transaction)
            item > 0 || throw(ArgumentError("Item IDs must be positive"))
            push!(get!(vertical, Int(item), Set{Int}()), tid)
        end
    end

    result = Dict{Tuple{Vararg{Int}},Int}()
    function visit(prefix::Tuple, candidates::Vector{Tuple{Int,Set{Int}}})
        for i in eachindex(candidates)
            item, tids = candidates[i]
            length(tids) >= min_count || continue
            itemset = (prefix..., item)
            result[itemset] = length(tids)
            suffix = Tuple{Int,Set{Int}}[]
            for j in (i + 1):length(candidates)
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
