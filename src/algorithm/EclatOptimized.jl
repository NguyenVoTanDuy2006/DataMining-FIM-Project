function build_vertical_bitvector(
    transactions::Vector{Vector{Int}}
)::Dict{Int, BitVector}
    n = length(transactions)
    vertical = Dict{Int, BitVector}()

    for (tid, transaction) in enumerate(transactions)
        for item in transaction
            item > 0 || throw(
                ArgumentError("Item IDs must be positive")
            )

            if !haskey(vertical, item)
                vertical[item] = falses(n)
            end

            vertical[item][tid] = true
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

    for transaction in transactions, item in transaction
        item > 0 || throw(ArgumentError("item IDs must be positive"))
    end

    isempty(transactions) && return results

    min_count = ceil(Int, minsup * length(transactions))
    vertical = build_vertical_bitvector(transactions)
    candidates = get_frequent_items_bitvector(vertical, min_count)

    eclat_dfs_bitvector!(results, Int[], candidates, min_count)
    return results
end
