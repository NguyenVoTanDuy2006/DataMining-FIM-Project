"""Mine frequent itemsets with dense BitVector TID lists.

This backend uses the same absolute `min_count` contract as `mine` and prunes
infrequent singleton items before allocating one bit vector per item.
"""
function mine_bitvector(transactions, min_count::Integer;
    max_length::Integer=typemax(Int), deadline::Union{Nothing,Real}=nothing,
    max_itemsets::Integer=typemax(Int))
    min_count > 0 || throw(ArgumentError("min_count must be positive"))
    max_length > 0 || throw(ArgumentError("max_length must be positive"))
    max_itemsets > 0 || throw(ArgumentError("max_itemsets must be positive"))

    n = length(transactions)
    result = Dict{Tuple{Vararg{Int}},Int}()
    n == 0 && return result

    supports = Dict{Int,Int}()
    last_seen_tid = Dict{Int,Int}()
    for (tid, transaction) in enumerate(transactions)
        !isnothing(deadline) && time() > deadline && throw(InterruptException())
        for raw_item in transaction
            raw_item > 0 || throw(ArgumentError("Item IDs must be positive"))
            item = Int(raw_item)
            if get(last_seen_tid, item, 0) != tid
                supports[item] = get(supports, item, 0) + 1
                last_seen_tid[item] = tid
            end
        end
    end

    vertical = Dict{Int,BitVector}(
        item => falses(n) for (item, support) in supports if support >= min_count)
    for (tid, transaction) in enumerate(transactions)
        for raw_item in transaction
            tids = get(vertical, Int(raw_item), nothing)
            !isnothing(tids) && (tids[tid] = true)
        end
    end

    function visit(prefix::Tuple, candidates::Vector{Tuple{Int,BitVector}})
        for i in eachindex(candidates)
            !isnothing(deadline) && time() > deadline && throw(InterruptException())
            item, tids = candidates[i]
            itemset = (prefix..., item)
            result[itemset] = count(tids)
            length(result) > max_itemsets && throw(OverflowError("max_itemsets exceeded"))
            length(itemset) >= max_length && continue

            suffix = Tuple{Int,BitVector}[]
            for j in (i + 1):length(candidates)
                !isnothing(deadline) && time() > deadline && throw(InterruptException())
                next_item, next_tids = candidates[j]
                common = tids .& next_tids
                count(common) >= min_count && push!(suffix, (next_item, common))
            end
            visit(itemset, suffix)
        end
    end

    candidates = [(item, vertical[item]) for item in sort!(collect(keys(vertical)))
        if supports[item] >= min_count]
    visit((), candidates)
    return result
end
