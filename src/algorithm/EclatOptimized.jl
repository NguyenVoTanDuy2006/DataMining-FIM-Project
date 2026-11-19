"""Count transaction support once per item, preserving duplicate transactions."""
function count_item_supports(transactions::Vector{Vector{Int}})::Dict{Int, Int}
    supports = Dict{Int, Int}()
    last_seen_tid = Dict{Int, Int}()
    for (tid, transaction) in enumerate(transactions), item in transaction
        item > 0 || throw(ArgumentError("Item IDs must be positive"))
        # transaction chỉ đóng góp 1 lần support của items
        if get(last_seen_tid, item, 0) != tid
            supports[item] = get(supports, item, 0) + 1
            last_seen_tid[item] = tid
        end
    end
    return supports
end

function build_vertical_bitvector(
    transactions::Vector{Vector{Int}},
    min_count::Int = 1,
)::Dict{Int, BitVector}
    min_count > 0 || throw(ArgumentError("min_count must be positive"))
    n = length(transactions)
    supports = count_item_supports(transactions)
    vertical = Dict{Int, BitVector}()
    for (item, support) in supports
        if support >= min_count
            vertical[item] = falses(n)
        end
    end

    for (tid, transaction) in enumerate(transactions)
        for item in transaction
            tids = get(vertical, item, nothing)
            if tids !== nothing
                tids[tid] = true
            end
        end
    end

    return vertical
end

function get_frequent_items_bitvector(
    vertical::Dict{Int, BitVector},
    min_count::Int
)::Vector{Tuple{Int, BitVector}}
    candidates = Tuple{Int, BitVector}[]

    for item in sort(collect(keys(vertical)))
        tids = vertical[item]

        if count(tids) >= min_count
            push!(candidates, (item, tids))
        end
    end

    return candidates
end

function eclat_dfs_bitvector!(
    results::Dict{Tuple{Vararg{Int}}, Int},
    prefix::Vector{Int},
    candidates::Vector{Tuple{Int, BitVector}},
    min_count::Int
)::Nothing
    for i in eachindex(candidates)
        item, tids = candidates[i]
        new_prefix = [prefix; item]
        results[Tuple(new_prefix)] = count(tids)

        next_candidates = Tuple{Int, BitVector}[]

        for j in (i + 1):length(candidates)
            next_item, next_tids = candidates[j]

            # shortcut: allocate intersections until profiling justifies scratch buffers.
            common_tids = tids .& next_tids

            if count(common_tids) >= min_count
                push!(next_candidates, (next_item, common_tids))
            end
        end

        if !isempty(next_candidates)
            eclat_dfs_bitvector!(
                results,
                new_prefix,
                next_candidates,
                min_count
            )
        end
    end

    return nothing
end

function mine_optimized(
    transactions::Vector{Vector{Int}},
    minsup::Real
)::Dict{Tuple{Vararg{Int}}, Int}
    if !(0 < minsup <= 1)
        throw(ArgumentError("minsup must be in (0, 1]"))
    end

    results = Dict{Tuple{Vararg{Int}}, Int}()

    isempty(transactions) && return results

    min_count = ceil(Int, minsup * length(transactions))
    # Validate/count every item first; allocate dense vectors only after pruning.
    vertical = build_vertical_bitvector(transactions, min_count)
    candidates = get_frequent_items_bitvector(vertical, min_count)

    eclat_dfs_bitvector!(results, Int[], candidates, min_count)
    return results
end
