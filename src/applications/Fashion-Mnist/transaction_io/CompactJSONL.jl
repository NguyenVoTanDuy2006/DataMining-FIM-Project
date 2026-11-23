function write_transaction_jsonl_row(io::IO, tid, image_id, items)
    image_value = image_id isa AbstractString ? "\"$image_id\"" : string(image_id)
    println(io, "{\"tid\":$tid,\"image_id\":$image_value,\"items\":[", join(items, ','), "]}")
end

function write_transaction_jsonl(path, transactions, image_ids)
    open(path, "w") do io
        for (tid, (items, image_id)) in enumerate(zip(transactions, image_ids))
            write_transaction_jsonl_row(io, tid, image_id, items)
        end
    end
end

function _decode_image_id(text, numeric)
    isnothing(text) && return parse(Int, numeric)
    image_id = String(text)
    parse_image_id(image_id)
    return image_id
end

function tryparse_compact_transaction(line; numeric_only::Bool=false)
    m = match(r"^\{\"tid\":(\d+),\"image_id\":(?:\"([^\"\\]+)\"|(\d+)),\"items\":\[([0-9]+(?:,[0-9]+)*)?\]\}$", line)
    isnothing(m) && return nothing
    numeric_only && !isnothing(m.captures[2]) && return nothing
    image_id = _decode_image_id(m.captures[2], m.captures[3])
    items = isnothing(m.captures[4]) ? Int[] : parse.(Int, split(m.captures[4], ','))
    return (; tid=parse(Int, m.captures[1]), image_id, items)
end

function parse_compact_transaction(line)
    row = tryparse_compact_transaction(line)
    isnothing(row) && error("Invalid transaction JSONL record: $line")
    return row
end
