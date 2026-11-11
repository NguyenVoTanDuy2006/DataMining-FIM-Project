function build_vertical(
    transactions::Vector{Vector{Int}}
)::Dict{Int, Set{Int}}
    vertical = Dict{Int, Set{Int}}()

    for (tid, transaction) in enumerate(transactions)
        for item in transaction
            item > 0 || throw(
                ArgumentError("Item IDs must be positive")
            )

            if !haskey(vertical, item)
                vertical[item] = Set{Int}()
            end

            push!(vertical[item], tid)
        end
    end

    return vertical
end

function get_frequent_items(
    vertical::Dict{Int, Set{Int}},
    min_count::Int
)::Vector{Tuple{Int, Set{Int}}}
    candidates = Tuple{Int, Set{Int}}[]

    for item in sort(collect(keys(vertical)))
        tids = vertical[item]

        if length(tids) >= min_count
            push!(candidates, (item, tids))
        end
    end

    return candidates
end

function eclat_dfs!(
    results::Dict{Tuple{Vararg{Int}}, Int},
    prefix::Vector{Int},
    candidates::Vector{Tuple{Int, Set{Int}}},
    min_count::Int
)::Nothing
    for i in eachindex(candidates)
        item, tids = candidates[i]
        new_prefix = [prefix; item]
        results[Tuple(new_prefix)] = length(tids)

        next_candidates = Tuple{Int, Set{Int}}[]

        for j in (i + 1):length(candidates)
            next_item, next_tids = candidates[j]
            common_tids = intersect(tids, next_tids)

            if length(common_tids) >= min_count
                push!(next_candidates, (next_item, common_tids))
            end
        end

        if !isempty(next_candidates)
            eclat_dfs!(results, new_prefix, next_candidates, min_count)
        end
    end

    return nothing
end

function mine_baseline(
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
    vertical = build_vertical(transactions)
    candidates = get_frequent_items(vertical, min_count)

    eclat_dfs!(results, Int[], candidates, min_count)
    return results
end
