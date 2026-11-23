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
    image_id = _decode_image_id(matched.captures[1], matched.captures[2])
    if image_id isa Int && image_id <= 0
        throw(ArgumentError("Legacy numeric image_id must be positive"))
    end
    return image_id
end

"""Read a mining input row, allowing whitespace and different field ordering."""
function parse_mining_record(line::AbstractString)
    tid = _integer_field(line, "tid")
    image_id = _image_id_field(line)
    items = _items_field(line)
    return (; tid, image_id, items)
end
