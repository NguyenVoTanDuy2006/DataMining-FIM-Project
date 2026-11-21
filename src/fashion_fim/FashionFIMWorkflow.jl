module FashionFIMWorkflow

using SHA
using EclatFIM: parse_image_id

export FIMInput, load_transactions

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

function _integer_field(line::AbstractString, field::AbstractString)
    pattern = Regex("\\\"" * field * "\\\"\\s*:\\s*(-?[0-9]+)")
    matches = collect(eachmatch(pattern, line))
    length(matches) == 1 || throw(ArgumentError("Expected exactly one integer field '$field'"))
    return parse(Int, matches[1].captures[1])
end

function _items_field(line::AbstractString)
    matches = collect(eachmatch(r"\"items\"\s*:\s*\[([^\]]*)\]", line))
    length(matches) == 1 || throw(ArgumentError("Expected exactly one items array"))
    payload = strip(matches[1].captures[1])
    isempty(payload) && return Int[]
    items = parse.(Int, strip.(split(payload, ',')))
    all(>(0), items) || throw(ArgumentError("Item IDs must be positive integers"))
    issorted(items) || throw(ArgumentError("items must be sorted ascending"))
    length(unique(items)) == length(items) || throw(ArgumentError("Duplicate items in transaction"))
    return items
end

function _image_id_field(line::AbstractString)
    matches = collect(eachmatch(r"\"image_id\"\s*:\s*(?:\"([^\"\\]*)\"|(-?[0-9]+))", line))
    length(matches) == 1 || throw(ArgumentError("Expected exactly one string or integer image_id field"))
    matched = only(matches)
    if !isnothing(matched.captures[1])
        image_id = String(matched.captures[1])
        parse_image_id(image_id)
        return image_id
    end
    image_id = parse(Int, matched.captures[2])
    image_id > 0 || throw(ArgumentError("Legacy numeric image_id must be positive"))
    return image_id
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
            tid = _integer_field(line, "tid")
            image_id = _image_id_field(line)
            items = _items_field(line)
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

end # module
