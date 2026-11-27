function _read_csv(path)
    open(path, "r") do io
        eof(io) && error("Empty CSV: $path")
        header = _csv_fields(readline(io))
        rows = [Dict(h => v for (h, v) in zip(header, _csv_fields(line))) for line in eachline(io)]
        all(length(row) == length(header) for row in rows) || error("Malformed CSV row in $path")
        return header, rows
    end
end

function _read_tid_mapping(path)
    header, rows = _read_csv(path)
    required = ("tid", "image_id", "original_split", "original_index")
    all(in(header), required) || error("TID mapping has unexpected schema: $path")
    length(rows) == EXPECTED_IMAGES || error("TID mapping must contain 70,000 rows: $path")
    tids, images = Int[], Int[]
    for (i, row) in enumerate(rows)
        tid, image = parse(Int, row["tid"]), parse(Int, row["image_id"])
        tid == i || error("TID mapping is not contiguous at row $i: $path")
        push!(tids, tid); push!(images, image)
        row["original_split"] in ("train", "test") || error("Invalid split in $path")
    end
    length(unique(images)) == EXPECTED_IMAGES || error("TID mapping image IDs are not unique: $path")
    return tids, images, rows
end

_transaction_length_capacity(variant, k) =
    min(_theoretical_size(variant, k), variant == "S6-B" ? 298 : 49)

function _parse_transaction(line, path, line_number)
    row = tryparse_compact_transaction(line; numeric_only=true)
    isnothing(row) && error("Unsupported JSONL record at $path:$line_number")
    return row.tid, row.image_id, row.items
end

function _read_codebook(path, k)
    value = open(deserialize, path)
    centroids = value isa NamedTuple && hasproperty(value, :centroids) ? value.centroids : value
    centroids isa AbstractMatrix || error("Unsupported serialized codebook layout: $path")
    size(centroids) in ((16, k), (k, 16)) || error("Expected codebook dimensions 16×K or K×16: $path")
    all(isfinite, centroids) || error("Non-finite centroid in $path")
    return Matrix{Float64}(size(centroids) == (16, k) ? permutedims(centroids) : centroids)
end

function _read_s0_transactions(spec)
    mapping_path = joinpath(spec.run_dir, "tid_image_mapping.csv")
    _, images, _ = _read_tid_mapping(mapping_path)
    txs = Vector{Vector{Int}}(undef, EXPECTED_IMAGES)
    path = joinpath(spec.run_dir, "transactions.jsonl")
    open(path, "r") do io
        for (i, line) in enumerate(eachline(io))
            i <= EXPECTED_IMAGES || error("Too many records in $path")
            tid, image, items = _parse_transaction(line, path, i)
            tid == i && image == images[i] || error("TID/image mapping mismatch at $path:$i")
            issorted(items) && allunique(items) || error("Items are not strictly sorted and unique at $path:$i")
            all(x -> 1 <= x <= spec.k, items) || error("Item outside 1:K at $path:$i")
            length(items)<=min(spec.k,49) || error("S0 transaction exceeds its length capacity at $path:$i")
            txs[i] = items
        end
    end
    length(txs) == EXPECTED_IMAGES || error("Expected 70,000 records in $path")
    return txs, images
end

function _read_transactions(spec, expected_images; compare_s0=nothing)
    _metadata!(spec)
    _, images, _ = _read_tid_mapping(joinpath(spec.run_dir, "tid_image_mapping.csv"))
    images == expected_images || error("Population/image mapping differs for $(spec.database_id)")
    _, mapping_rows = _read_csv(joinpath(spec.run_dir, "item_mapping.csv"))
    mapped_items = Set(parse(Int, row["item_id"]) for row in mapping_rows)
    txs = Vector{Vector{Int}}(undef, EXPECTED_IMAGES)
    path = joinpath(spec.run_dir, "transactions.jsonl")
    open(path, "r") do io
        for (i, line) in enumerate(eachline(io))
            i <= EXPECTED_IMAGES || error("Too many records in $path")
            tid, image, items = _parse_transaction(line, path, i)
            tid == i && image == images[i] || error("TID/image mismatch at $path:$i")
            issorted(items) && allunique(items) || error("Items unsorted or duplicate at $path:$i")
            all(x -> 1 <= x <= _theoretical_size(spec.variant, spec.k), items) || error("Item out of range at $path:$i")
            all(item -> item in mapped_items, items) || error("Transaction item has no item-mapping row at $path:$i")
            capacity = _transaction_length_capacity(spec.variant, spec.k)
            length(items)<=capacity || error("Transaction length exceeds encoding capacity at $path:$i")
            if !isnothing(compare_s0) && spec.variant in ("S1", "S3")
                sort!(unique!([(item - 1) % spec.k + 1 for item in items])) == compare_s0[i] ||
                    error("$(spec.variant) projection mismatch at TID $i")
                isempty(items) == isempty(compare_s0[i]) ||
                    error("$(spec.variant) empty status mismatch at TID $i")
            end
            txs[i] = items
        end
    end
    length(txs) == EXPECTED_IMAGES || error("$(spec.database_id) does not have 70,000 records")
    return txs
end

function _read_labels!(ctx)
    isempty(ctx.specs) && discover_inputs(ctx)
    sources = sort!([s for s in ctx.specs if s.variant == "S0"]; by=s -> (s.k, s.seed))
    for spec in sources
        try
            _metadata!(spec)
            _, rows = _read_csv(joinpath(spec.run_dir, "image_metadata.csv"))
            length(rows) == EXPECTED_IMAGES || error("image_metadata.csv must contain 70,000 records")
            ids = parse.(Int, getindex.(rows, "image_id"))
            labels_by_image = parse.(Int, getindex.(rows, "class_label"))
            length(unique(ids)) == EXPECTED_IMAGES || error("image_metadata.csv has duplicate image IDs")
            all(label -> 0 <= label <= 9, labels_by_image) || error("Image labels are outside 0:9")
            mapping_ids = Set(ids)
            _, images, _ = _read_tid_mapping(joinpath(spec.run_dir, "tid_image_mapping.csv"))
            Set(images) == mapping_ids || error("S0 labels and TID/image mapping identify different images")
            by_image = Dict(zip(ids, labels_by_image))
            labels = [by_image[image] for image in images]
            all(==(7_000), [count(==(class_id), labels) for class_id in 0:9]) ||
                error("Expected 7,000 labels in each of 10 classes")
            ctx.labels, ctx.image_ids = labels, images
            return labels, images
        catch
            continue
        end
    end
    ctx.labels, ctx.image_ids = Int[], Int[]
    return ctx.labels, ctx.image_ids
end
