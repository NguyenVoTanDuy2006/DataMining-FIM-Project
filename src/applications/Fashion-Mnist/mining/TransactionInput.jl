"""Read-only view of the JSONL rows used by Fashion-MNIST FIM."""
struct FIMInput
    transactions::Vector{Vector{Int}}
    tid::Vector{Int}
    image_id::Vector{Union{Int,String}}
    input_sha256::String
    singleton_support::Dict{Int,Int}
    empty_count::Int
    pair_6_26_support::Int
end

"""
    load_transactions(path; expected_n=nothing, expected_items=1:32,
                      require_nonempty=false, unique_mapping=false)

Parse the project's compact one-object-per-line transaction JSONL without
adding a JSON package dependency. Each source line remains one transaction;
TID and image ID are retained in parallel vectors and are never mined as items.
"""
function load_transactions(path::AbstractString; expected_n::Union{Nothing,Int}=nothing,
    expected_items=1:32, require_nonempty::Bool=false, unique_mapping::Bool=false)
    transactions = Vector{Vector{Int}}()
    tids = Int[]
    image_ids = Union{Int,String}[]
    singleton = Dict(item => 0 for item in expected_items)
    empty_count = 0
    pair_6_26 = 0

    open(path, "r") do io
        for (line_number, line) in enumerate(eachline(io))
            isempty(strip(line)) && throw(ArgumentError("Blank JSONL line at row $line_number"))
            (; tid, image_id, items) = parse_mining_record(line)
            all(item -> item in expected_items, items) ||
                throw(ArgumentError("Item outside configured range at row $line_number"))
            require_nonempty && isempty(items) &&
                throw(ArgumentError("Empty transaction at row $line_number"))

            push!(transactions, items)
            push!(tids, tid)
            push!(image_ids, image_id)
            if isempty(items)
                empty_count += 1
            else
                for item in items
                    singleton[item] = get(singleton, item, 0) + 1
                end
                pair_6_26 += (6 in items && 26 in items)
            end
        end
    end

    expected_n !== nothing && length(transactions) != expected_n &&
        throw(ArgumentError("Expected $expected_n transactions; read $(length(transactions))"))
    if unique_mapping
        length(unique(tids)) == length(tids) || throw(ArgumentError("Duplicate TID in source"))
        length(unique(image_ids)) == length(image_ids) || throw(ArgumentError("Duplicate image_id in source"))
    end

    digest = bytes2hex(sha256(read(path)))
    return FIMInput(transactions, tids, image_ids, digest, singleton, empty_count, pair_6_26)
end
