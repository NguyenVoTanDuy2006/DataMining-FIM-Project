"""Mine with an absolute integer minimum-support count."""
function mine(transactions::AbstractVector{<:AbstractVector{<:Integer}}, min_count::Integer;
    backend::Symbol=:set, max_length::Integer=typemax(Int),
    deadline::Union{Nothing,Real}=nothing, max_itemsets::Integer=typemax(Int))
    return mine_count(transactions, min_count; backend, max_length, deadline, max_itemsets)
end

"""Mine with a relative minimum-support fraction in (0, 1]."""
function _mine_relative(transactions::AbstractVector{<:AbstractVector{<:Integer}}, minsup::Real,
    backend::Symbol)
    0 < minsup <= 1 || throw(ArgumentError("minsup must be in (0, 1]"))
    backend in (:set, :bitvector) || throw(ArgumentError("Unsupported backend: $backend"))
    isempty(transactions) && return Dict{Tuple{Vararg{Int}},Int}()
    min_count = ceil(Int, minsup * length(transactions))
    return mine_count(transactions, min_count; backend)
end

mine(transactions::AbstractVector{<:AbstractVector{<:Integer}}, minsup::Real;
    backend::Symbol=:set) = _mine_relative(transactions, minsup, backend)

"""Compatibility entry point for the original Set backend."""
mine_baseline(transactions::Vector{Vector{Int}}, minsup::Real) =
    _mine_relative(transactions, minsup, :set)

"""Compatibility entry point for the original BitVector backend."""
mine_optimized(transactions::Vector{Vector{Int}}, minsup::Real) =
    _mine_relative(transactions, minsup, :bitvector)

"""Count each positive item once per transaction."""
function count_item_supports(transactions::Vector{Vector{Int}})::Dict{Int,Int}
    supports = Dict{Int,Int}()
    last_seen_tid = Dict{Int,Int}()
    for (tid, transaction) in enumerate(transactions), item in transaction
        item > 0 || throw(ArgumentError("Item IDs must be positive"))
        if get(last_seen_tid, item, 0) != tid
            supports[item] = get(supports, item, 0) + 1
            last_seen_tid[item] = tid
        end
    end
    return supports
end

"""Build pruned dense TID vectors, retaining the original helper contract."""
function build_vertical_bitvector(transactions::Vector{Vector{Int}}, min_count::Int=1)
    min_count > 0 || throw(ArgumentError("min_count must be positive"))
    supports = count_item_supports(transactions)
    vertical = Dict{Int,BitVector}(
        item => falses(length(transactions))
        for (item, support) in supports if support >= min_count)
    for (tid, transaction) in enumerate(transactions), item in transaction
        tids = get(vertical, item, nothing)
        !isnothing(tids) && (tids[tid] = true)
    end
    return vertical
end
