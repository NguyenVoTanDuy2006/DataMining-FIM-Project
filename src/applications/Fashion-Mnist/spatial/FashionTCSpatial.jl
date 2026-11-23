module FashionTCSpatial

using SHA
using Statistics
using TOML
using ..FashionTransactionIO: csv_fields, tryparse_compact_transaction, write_transaction_jsonl_row

export TC6Context, load_context, discover_sources, preflight_sources!,
    run_unit_checks!, run_variant!, validate_global_integrity!, finalize_outputs!,
    source_manifest

const TC6_SCHEMA_VERSION = 1
const EXPECTED_K = [16, 32, 64, 128, 256]
const EXPECTED_SEEDS = [42, 123, 2026]
const EXPECTED_IMAGES = 70_000
const GRID_SIZE = 7
const REQUIRED_SOURCE_FILES = [
    "patch_assignments.csv", "transactions.jsonl", "tid_image_mapping.csv",
    "config_snapshot.toml", "integrity_report.toml", "checkpoint.toml",
    "codebook.bin", "tc4_metrics.toml",
]
const ITEM_MAPPING_HEADER = ["item_id", "variant", "item_kind", "region_id",
    "region_label", "word_id", "stripe_id", "stripe_label", "relation_type",
    "word_a", "word_b"]

struct SourceRun
    run_id::String
    k::Int
    seed::Int
    path::String
end

struct TIDMapping
    tid::Int
    image_id::Int
    original_split::String
    original_index::Int
end

Base.:(==)(a::TIDMapping, b::TIDMapping) =
    a.tid == b.tid && a.image_id == b.image_id &&
    a.original_split == b.original_split && a.original_index == b.original_index

struct SourceData
    source::SourceRun
    observations::Vector{Vector{NTuple{3,Int}}}
    s0::Vector{Vector{Int}}
    mapping::Vector{TIDMapping}
    hashes::Dict{String,String}
    fit_status::String
    converged::Bool
    retained_patch_count::Int
end

mutable struct TC6Context
    config_path::String
    repo_root::String
    source_root::String
    output_root::String
    config::Dict{String,Any}
    profile::String
    sources::Vector{SourceRun}
    mapping_hash::String
    source_rows::Vector{Dict{String,Any}}
    results::Dict{Tuple{Int,Int,String},Dict{String,Any}}
    preflight_complete::Bool
end

_sha256(path::AbstractString) = bytes2hex(open(sha256, path))

function _absolute_path(repo_root::String, path::String)
    return normpath(isabspath(path) ? path : joinpath(repo_root, path))
end

function _path_contains(parent::String, child::String)
    rel = relpath(child, parent)
    return rel == "." || !(rel == ".." || startswith(rel, "../"))
end

function _require(condition::Bool, message::AbstractString)
    condition || throw(ArgumentError(String(message)))
    return nothing
end

function _validate_config(config::Dict{String,Any}, repo_root::String)
    run = get(config, "run", Dict{String,Any}())
    source = get(config, "source", Dict{String,Any}())
    ext = get(config, "tc6_spatial_extension", Dict{String,Any}())
    execution = get(config, "execution", Dict{String,Any}())

    _require(get(run, "mode", "") == "spatial_extension", "run.mode must be spatial_extension")
    _require(get(run, "overwrite_production_artifacts", true) == false,
        "overwrite_production_artifacts must be false")
    _require(get(run, "fail_fast", false) == true, "fail_fast must be true")
    _require(get(source, "training_method", "") == "raw_full_batch_kmeans",
        "source.training_method must be raw_full_batch_kmeans")
    _require(get(source, "method_alias", "") == "B0", "source.method_alias must be B0")
    _require(Int.(get(source, "k_candidates", Int[])) == EXPECTED_K,
        "source.k_candidates must contain all five canonical K values in order")
    _require(Int.(get(source, "random_seeds", Int[])) == EXPECTED_SEEDS,
        "source.random_seeds must contain all three canonical seeds in order")
    _require(get(source, "expected_codebooks", 0) == 15, "source.expected_codebooks must be 15")
    _require(get(source, "expected_images", 0) == EXPECTED_IMAGES,
        "source.expected_images must be 70,000")
    _require(Int.(get(source, "expected_patch_grid", Int[])) == [7, 7],
        "source.expected_patch_grid must be [7, 7]")
    _require(get(source, "patch_order", "") == "row_major", "source.patch_order must be row_major")
    _require(get(source, "require_completed_integrity", false) == true,
        "completed source integrity is required")
    _require(get(source, "reuse_s0_without_rewrite", false) == true,
        "S0 must be reused read-only")

    _require(get(ext, "variants_to_generate", String[]) == ["S1", "S3", "S6-B"],
        "Only variants S1, S3, and S6-B may be generated")
    _require(get(ext, "reference_variant", "") == "S0", "reference_variant must be S0")
    for key in ("one_image_one_transaction", "preserve_empty", "deduplicate", "sort_items")
        _require(get(ext, key, false) == true, "tc6_spatial_extension.$key must be true")
    end
    _require(get(ext, "include_labels", true) == false, "Labels must not enter transactions")
    _require(get(ext, "transactions_format", "") == "jsonl", "transactions_format must be jsonl")

    s1 = get(ext, "s1", Dict{String,Any}())
    s3 = get(ext, "s3", Dict{String,Any}())
    s6 = get(ext, "s6b", Dict{String,Any}())
    _require(get(s1, "region_layout", "") == "grid_2x2" &&
        get(s1, "row_break_after", 0) == 3 && get(s1, "col_break_after", 0) == 3,
        "S1 must use the fixed 3+4 by 3+4 grid")
    _require(get(s3, "stripe_layout", "") == "horizontal_1x3" &&
        Int.(get(s3, "rows_per_stripe", Int[])) == [2, 3, 2],
        "S3 must use horizontal stripes of 2, 3, and 2 rows")
    _require(get(s6, "relation_types", String[]) == ["ABOVE", "LEFT_OF"] &&
        get(s6, "distance", "") == "manhattan_patch_grid" &&
        get(s6, "min_distance", 0) == 1 && get(s6, "max_distance", 0) == 2,
        "S6-B must use ABOVE/LEFT_OF at Manhattan distance 1..2")
    _require(get(s6, "pair_semantics", "") == "exists_distinct_retained_patch_pair",
        "S6-B pair_semantics is unsupported")
    _require(get(s6, "allow_same_word_on_distinct_patches", false) == true &&
        get(s6, "emit_both_relations_for_diagonal_pairs", false) == true &&
        get(s6, "include_global_words", true) == false,
        "S6-B same-word/diagonal/global-word settings are invalid")

    profile = get(execution, "profile", "full")
    _require(profile in ("full", "smoke"), "execution.profile must be full or smoke")
    if profile == "smoke"
        k = get(execution, "smoke_k", 0)
        seed = get(execution, "smoke_seed", 0)
        limit = get(execution, "smoke_image_count", 0)
        _require(k in EXPECTED_K && seed in EXPECTED_SEEDS,
            "Smoke K/seed must select one of the canonical source runs")
        _require(1 <= limit < EXPECTED_IMAGES, "Smoke image count must be in 1:69,999")
    end

    source_root = _absolute_path(repo_root, String(run["source_root"]))
    output_root = _absolute_path(repo_root, String(run["output_root"]))
    _require(source_root != output_root && !_path_contains(source_root, output_root) &&
        !_path_contains(output_root, source_root),
        "source_root and output_root must be separate, non-nested directories")
    isdir(source_root) || throw(ArgumentError("S0 source_root does not exist: $source_root"))
    return source_root, output_root, String(profile)
end

function load_context(config_path::AbstractString; repo_root=pwd())
    repo_root = normpath(abspath(String(repo_root)))
    config_path = normpath(abspath(String(config_path)))
    isfile(config_path) || throw(ArgumentError("TC6 config not found: $config_path"))
    config = TOML.parsefile(config_path)
    source_root, output_root, profile = _validate_config(config, repo_root)
    return TC6Context(config_path, repo_root, source_root, output_root, config, profile,
        SourceRun[], "", Dict{String,Any}[], Dict{Tuple{Int,Int,String},Dict{String,Any}}(), false)
end

function discover_sources(context::TC6Context)
    discovered = Dict{Tuple{Int,Int},SourceRun}()
    for name in readdir(context.source_root)
        path = joinpath(context.source_root, name)
        isdir(path) || continue
        m = match(r"^FashionMNIST_T2_S0_B0_K(\d+)_seed(\d+)$", name)
        isnothing(m) && continue
        k, seed = parse(Int, m.captures[1]), parse(Int, m.captures[2])
        key = (k, seed)
        haskey(discovered, key) && error("Conflicting S0 source folders for K=$k seed=$seed")
        discovered[key] = SourceRun(name, k, seed, path)
    end

    expected = [(k, seed) for k in EXPECTED_K for seed in EXPECTED_SEEDS]
    missing = filter(key -> !haskey(discovered, key), expected)
    extras = filter(key -> !(key in expected), collect(keys(discovered)))
    isempty(missing) || error("Missing canonical S0 source runs: $missing under $(context.source_root)")
    isempty(extras) || error("Unexpected S0 source runs: $extras under $(context.source_root)")
    context.sources = [discovered[key] for key in expected]
    return copy(context.sources)
end

_csv_fields(line::AbstractString) = csv_fields(line; identify_line=true)

function _header_indices(header::Vector{String}, required::Vector{String}, path::String)
    length(header) == length(unique(header)) || error("Duplicate CSV headers in $path")
    missing = filter(name -> !(name in header), required)
    isempty(missing) || error("Missing CSV columns in $path: $missing")
    return Dict(name => findfirst(==(name), header)::Int for name in header)
end

function _read_mapping(path::String)
    rows = TIDMapping[]
    seen_images = Set{Int}()
    open(path, "r") do io
        eof(io) && error("Empty TID mapping: $path")
        header = _csv_fields(readline(io))
        index = _header_indices(header,
            ["tid", "image_id", "original_split", "original_index"], path)
        for line in eachline(io)
            fields = _csv_fields(line)
            length(fields) == length(header) || error("Malformed TID mapping row in $path")
            line_number = length(rows) + 1
            tid = parse(Int, fields[index["tid"]])
            image_id = parse(Int, fields[index["image_id"]])
            split = fields[index["original_split"]]
            original_index = parse(Int, fields[index["original_index"]])
            tid == line_number || error("TID mapping is unordered/non-contiguous at row $line_number in $path")
            image_id > 0 && !(image_id in seen_images) ||
                error("TID mapping has invalid or duplicate image_id=$image_id in $path")
            split in ("train", "test") || error("Unexpected original_split=$split in $path")
            original_index > 0 || error("Invalid original_index=$original_index in $path")
            push!(rows, TIDMapping(tid, image_id, split, original_index))
            push!(seen_images, image_id)
        end
    end
    length(rows) == EXPECTED_IMAGES || error("TID mapping has $(length(rows)) rows, expected $EXPECTED_IMAGES: $path")
    return rows
end

function _parse_transaction(line::AbstractString, path::String, line_number::Int)
    row = tryparse_compact_transaction(line; numeric_only=true)
    isnothing(row) && error("Invalid S0 JSONL record at $path:$line_number")
    return row
end

function _read_s0(path::String, mapping::Vector{TIDMapping}, k::Int)
    transactions = Vector{Vector{Int}}()
    open(path, "r") do io
        for (line_number, line) in enumerate(eachline(io))
            line_number <= EXPECTED_IMAGES || error("Too many S0 records in $path")
            record = _parse_transaction(line, path, line_number)
            record.tid == mapping[line_number].tid || error("S0 TID mismatch at record $line_number in $path")
            record.image_id == mapping[line_number].image_id ||
                error("S0 image_id mismatch at TID $(record.tid) in $path")
            issorted(record.items) && allunique(record.items) ||
                error("S0 items must be sorted and unique at TID $(record.tid) in $path")
            all(item -> 1 <= item <= k, record.items) ||
                error("S0 item is outside 1:$k at TID $(record.tid) in $path")
            push!(transactions, record.items)
        end
    end
    length(transactions) == EXPECTED_IMAGES ||
        error("S0 has $(length(transactions)) records, expected $EXPECTED_IMAGES: $path")
    return transactions
end

function _source_metadata(source::SourceRun, context::TC6Context)
    missing = filter(file -> !isfile(joinpath(source.path, file)), REQUIRED_SOURCE_FILES)
    isempty(missing) || error("$(source.run_id) is missing source files: $missing")
    config = TOML.parsefile(joinpath(source.path, "config_snapshot.toml"))
    checkpoint = TOML.parsefile(joinpath(source.path, "checkpoint.toml"))
    integrity = TOML.parsefile(joinpath(source.path, "integrity_report.toml"))
    metrics = TOML.parsefile(joinpath(source.path, "tc4_metrics.toml"))

    get(config, "run_id", "") == source.run_id || error("config_snapshot run_id mismatch: $(source.run_id)")
    get(config, "k", 0) == source.k && get(config, "seed", -1) == source.seed ||
        error("config_snapshot K/seed mismatch: $(source.run_id)")
    get(config, "tc4_method", "") == "raw_full_batch_kmeans" ||
        error("$(source.run_id) is not a B0 raw_full_batch_kmeans source")
    patch = get(config, "tc1_patch_extraction", Dict{String,Any}())
    get(patch, "patch_size", Int[]) == [4, 4] && get(patch, "stride", Int[]) == [4, 4] ||
        error("$(source.run_id) does not use 4x4 stride-4 patches")
    get(patch, "patch_id_base", 0) == 1 && get(patch, "patch_order", "") == "row_major" ||
        error("$(source.run_id) patch_id base/order is not verified 1-based row-major")
    get(config, "threshold", -1) == 29 || error("$(source.run_id) threshold metadata is not 29")
    filtering = get(config, "tc2_patch_filtering", Dict{String,Any}())
    get(filtering, "foreground_threshold", -1) == 29 &&
        get(filtering, "threshold_comparison", "") == "strict_greater" ||
        error("$(source.run_id) TC2 metadata is not strict pixel > 29")

    get(checkpoint, "status", "") == "COMPLETED" || error("$(source.run_id) checkpoint is not COMPLETED")
    get(checkpoint, "method", "") == "raw_full_batch_kmeans" &&
        get(checkpoint, "k", 0) == source.k && get(checkpoint, "seed", -1) == source.seed ||
        error("$(source.run_id) checkpoint method/K/seed mismatch")
    get(integrity, "status", "") == "PASS" || error("$(source.run_id) source integrity is not PASS")
    for field in ("transactions_valid", "patch_assignments_csv_valid", "tid_mapping_valid",
        "support_denominator_valid", "assignments_valid", "codebook_checkpoint_matches")
        get(integrity, field, false) == true || error("$(source.run_id) source integrity check $field is not PASS")
    end
    get(integrity, "image_count", 0) == EXPECTED_IMAGES &&
        get(integrity, "transaction_count", 0) == EXPECTED_IMAGES &&
        get(integrity, "support_denominator", 0) == EXPECTED_IMAGES ||
        error("$(source.run_id) source integrity denominator is not 70,000")
    get(metrics, "method", "") == "raw_full_batch_kmeans" &&
        get(metrics, "k", source.k) == source.k || error("$(source.run_id) tc4_metrics mismatch")

    hashes = Dict(file => _sha256(joinpath(source.path, file)) for file in REQUIRED_SOURCE_FILES)
    get(checkpoint, "codebook_sha256", "") == hashes["codebook.bin"] ||
        error("$(source.run_id) codebook checksum differs from checkpoint")
    fit_status = String(get(checkpoint, "fit_status", "UNKNOWN"))
    converged = Bool(get(checkpoint, "converged", get(metrics, "converged", true)))
    return config, checkpoint, integrity, metrics, hashes, fit_status, converged
end

function _normalize_patch_assignments(path::String, source::SourceRun,
    mapping::Vector{TIDMapping}, s0::Vector{Vector{Int}}, integrity::Dict{String,Any},
    source_config::Dict{String,Any})
    observations = [NTuple{3,Int}[] for _ in 1:EXPECTED_IMAGES]
    image_to_slot = Dict(row.image_id => slot for (slot, row) in enumerate(mapping))
    seen = falses(49, EXPECTED_IMAGES)
    patch_count = 0
    open(path, "r") do io
        eof(io) && error("Empty patch assignment CSV: $path")
        header = _csv_fields(readline(io))
        index = _header_indices(header, ["image_id", "patch_id", "word_id"], path)
        has_row_col = all(key -> haskey(index, key), ("patch_row", "patch_col"))
        has_row_col || begin
            patch = source_config["tc1_patch_extraction"]
            get(patch, "patch_id_base", 0) == 1 && get(patch, "patch_order", "") == "row_major" ||
                error("Cannot recover patch coordinates from patch_id in $path")
        end
        for (csv_line, line) in enumerate(eachline(io))
            fields = _csv_fields(line)
            length(fields) == length(header) || error("Malformed assignment row at $path:$(csv_line + 1)")
            image_id = parse(Int, fields[index["image_id"]])
            patch_id = parse(Int, fields[index["patch_id"]])
            word_id = parse(Int, fields[index["word_id"]])
            1 <= patch_id <= 49 || error("Invalid patch_id=$patch_id in $path:$(csv_line + 1)")
            1 <= word_id <= source.k || error("Invalid word_id=$word_id in $path:$(csv_line + 1)")
            slot = get(image_to_slot, image_id, 0)
            slot != 0 || error("Unknown image_id=$image_id in $path:$(csv_line + 1)")
            if has_row_col
                row = parse(Int, fields[index["patch_row"]])
                col = parse(Int, fields[index["patch_col"]])
            else
                row = (patch_id - 1) ÷ 7 + 1
                col = (patch_id - 1) % 7 + 1
            end
            1 <= row <= 7 && 1 <= col <= 7 || error("Patch coordinates out of range in $path:$(csv_line + 1)")
            expected_patch_id = (row - 1) * 7 + col
            expected_patch_id == patch_id || error("patch_id and coordinates disagree in $path:$(csv_line + 1)")
            !seen[patch_id, slot] || error("Duplicate retained (image_id,patch_id)=($image_id,$patch_id) in $path")
            seen[patch_id, slot] = true
            push!(observations[slot], (row, col, word_id))
            patch_count += 1
        end
    end
    patch_count == get(integrity, "assignment_count", -1) ||
        error("$(source.run_id) assignment count disagrees with integrity_report.toml")
    get(integrity, "patch_assignments_csv_lines", patch_count + 1) == patch_count + 1 ||
        error("$(source.run_id) assignment CSV line count disagrees with integrity_report.toml")

    for slot in 1:EXPECTED_IMAGES
        observed_words = sort!(unique!([entry[3] for entry in observations[slot]]))
        observed_words == s0[slot] ||
            error("$(source.run_id) retained-patch word projection differs from S0 at image $(mapping[slot].image_id)")
    end
    return observations, patch_count
end

function _load_source(source::SourceRun, context::TC6Context)
    config, checkpoint, integrity, metrics, hashes, fit_status, converged =
        _source_metadata(source, context)
    mapping_path = joinpath(source.path, "tid_image_mapping.csv")
    mapping = _read_mapping(mapping_path)
    s0 = _read_s0(joinpath(source.path, "transactions.jsonl"), mapping, source.k)
    isempty_count = count(isempty, s0)
    metadata = TOML.parsefile(joinpath(source.path, "integrity_report.toml"))
    get(metadata, "empty_count", isempty_count) == isempty_count ||
        error("$(source.run_id) S0 empty transaction count disagrees with integrity report")
    get(metadata, "nonempty_count", EXPECTED_IMAGES - isempty_count) == EXPECTED_IMAGES - isempty_count ||
        error("$(source.run_id) S0 nonempty transaction count disagrees with integrity report")
    observations, patch_count = _normalize_patch_assignments(
        joinpath(source.path, "patch_assignments.csv"), source, mapping, s0, integrity, config)
    return SourceData(source, observations, s0, mapping, hashes, fit_status, converged, patch_count)
end

function source_manifest(context::TC6Context)
    return deepcopy(context.source_rows)
end

function preflight_sources!(context::TC6Context)
    isempty(context.sources) && discover_sources(context)
    rows = Dict{String,Any}[]
    common_mapping_hash = ""
    for source in context.sources
        data = try
            _load_source(source, context)
        catch err
            error("TC6 source preflight failed for $(source.run_id) at $(source.path): $(sprint(showerror, err))")
        end
        mapping_hash = data.hashes["tid_image_mapping.csv"]
        isempty(common_mapping_hash) && (common_mapping_hash = mapping_hash)
        mapping_hash == common_mapping_hash || error("TID/image mapping differs across S0 sources at $(source.run_id)")
        push!(rows, Dict{String,Any}(
            "source_run_id"=>source.run_id, "k"=>source.k, "seed"=>source.seed,
            "method"=>"B0", "s0_path"=>relpath(joinpath(source.path, "transactions.jsonl"), context.repo_root),
            "assignments_path"=>relpath(joinpath(source.path, "patch_assignments.csv"), context.repo_root),
            "mapping_path"=>relpath(joinpath(source.path, "tid_image_mapping.csv"), context.repo_root),
            "codebook_path"=>relpath(joinpath(source.path, "codebook.bin"), context.repo_root),
            "source_integrity"=>"PASS", "source_hash_or_identifier"=>data.hashes["transactions.jsonl"],
            "mapping_sha256"=>mapping_hash, "retained_patch_count"=>data.retained_patch_count,
            "s0_empty_count"=>count(isempty, data.s0), "fit_status"=>data.fit_status,
            "converged"=>data.converged, "file_hashes"=>data.hashes,
        ))
        println("[TC6 preflight] PASS $(source.run_id) | assignments=$(data.retained_patch_count) | fit_status=$(data.fit_status) | converged=$(data.converged)")
    end
    length(rows) == 15 || error("TC6 preflight did not validate all 15 source runs")
    context.mapping_hash = common_mapping_hash
    context.source_rows = rows
    context.preflight_complete = true
    return source_manifest(context)
end

function _region(row::Int, col::Int)
    return row <= 3 ? (col <= 3 ? 1 : 2) : (col <= 3 ? 3 : 4)
end

_stripe(row::Int) = row <= 2 ? 1 : (row <= 5 ? 2 : 3)
_s1_id(region::Int, word::Int, k::Int) = (region - 1) * k + word
_s3_id(stripe::Int, word::Int, k::Int) = (stripe - 1) * k + word
_s6_id(relation::Int, a::Int, b::Int, k::Int) = (relation - 1) * k^2 + (a - 1) * k + b

function _decode_item(variant::String, item::Int, k::Int)
    if variant == "S1"
        1 <= item <= 4k || error("S1 item $item outside 1:$(4k)")
        return ((item - 1) ÷ k + 1, (item - 1) % k + 1)
    elseif variant == "S3"
        1 <= item <= 3k || error("S3 item $item outside 1:$(3k)")
        return ((item - 1) ÷ k + 1, (item - 1) % k + 1)
    elseif variant == "S6-B"
        1 <= item <= 2k^2 || error("S6-B item $item outside 1:$(2k^2)")
        zero_based = item - 1
        relation = zero_based ÷ k^2 + 1
        pair = zero_based % k^2
        return (relation, pair ÷ k + 1, pair % k + 1)
    end
    error("Unsupported spatial variant $variant")
end

function _encode_s1(observations::Vector{NTuple{3,Int}}, k::Int)
    items = Int[]
    for (row, col, word) in observations
        push!(items, _s1_id(_region(row, col), word, k))
    end
    return sort!(unique!(items))
end

function _encode_s3(observations::Vector{NTuple{3,Int}}, k::Int)
    items = Int[]
    for (row, _, word) in observations
        push!(items, _s3_id(_stripe(row), word, k))
    end
    return sort!(unique!(items))
end

function _neighbor_pairs()
    pairs = NTuple{3,Int}[]
    for p in 1:49
        r1, c1 = (p - 1) ÷ 7 + 1, (p - 1) % 7 + 1
        for q in p+1:49
            r2, c2 = (q - 1) ÷ 7 + 1, (q - 1) % 7 + 1
            d = abs(r1 - r2) + abs(c1 - c2)
            1 <= d <= 2 && push!(pairs, (p, q, d))
        end
    end
    return pairs
end

const NEIGHBOR_PAIRS = _neighbor_pairs()

function _encode_s6(observations::Vector{NTuple{3,Int}}, k::Int; image_slot::Int=0,
    witnesses::Dict{Int,Tuple{Int,NTuple{3,Int},NTuple{3,Int}}}=Dict{Int,Tuple{Int,NTuple{3,Int},NTuple{3,Int}}}())
    words = zeros(Int, 49)
    for (row, col, word) in observations
        1 <= row <= 7 && 1 <= col <= 7 || throw(ArgumentError("S6-B coordinate out of bounds"))
        1 <= word <= k || throw(ArgumentError("S6-B word outside 1:$k"))
        patch_id = (row - 1) * 7 + col
        if words[patch_id] != 0 && words[patch_id] != word
            throw(ArgumentError("Conflicting words for the same patch position"))
        end
        words[patch_id] = word
    end
    items = Int[]
    eligible_pairs = 0
    occurrences = 0
    for (p, q, _) in NEIGHBOR_PAIRS
        wp, wq = words[p], words[q]
        (wp == 0 || wq == 0) && continue
        eligible_pairs += 1
        rp, cp = (p - 1) ÷ 7 + 1, (p - 1) % 7 + 1
        rq, cq = (q - 1) ÷ 7 + 1, (q - 1) % 7 + 1
        left_obs, right_obs = (rp, cp, wp), (rq, cq, wq)
        if rp != rq
            a, b = rp < rq ? (wp, wq) : (wq, wp)
            id = _s6_id(1, a, b, k)
            push!(items, id)
            get!(witnesses, id, (image_slot, left_obs, right_obs))
            occurrences += 1
        end
        if cp != cq
            a, b = cp < cq ? (wp, wq) : (wq, wp)
            id = _s6_id(2, a, b, k)
            push!(items, id)
            get!(witnesses, id, (image_slot, left_obs, right_obs))
            occurrences += 1
        end
    end
    length(NEIGHBOR_PAIRS) == 226 || error("S6-B neighbor geometry must contain 226 pairs")
    return sort!(unique!(items)), eligible_pairs, occurrences
end

function _projection(items::Vector{Int}, variant::String, k::Int)
    words = Int[]
    for item in items
        decoded = _decode_item(variant, item, k)
        push!(words, variant == "S6-B" ? decoded[2] : decoded[2])
        variant == "S6-B" && push!(words, decoded[3])
    end
    return sort!(unique!(words))
end

function _validate_witness(item::Int, witness, variant_k::Int, observations::Vector{NTuple{3,Int}})
    slot, p, q = witness
    slot > 0 || return false
    p != q || return false
    p in observations && q in observations || return false
    abs(p[1] - q[1]) + abs(p[2] - q[2]) in 1:2 || return false
    relation, a, b = _decode_item("S6-B", item, variant_k)
    relation == 1 && p[1] != q[1] || relation == 2 && p[2] != q[2] || return false
    expected_a, expected_b = if relation == 1
        p[1] < q[1] ? (p[3], q[3]) : (q[3], p[3])
    else
        p[2] < q[2] ? (p[3], q[3]) : (q[3], p[3])
    end
    return (a, b) == (expected_a, expected_b)
end

function _check_projection(transactions::Vector{Vector{Int}}, source::SourceData,
    variant::String, k::Int, count::Int)
    variant in ("S1", "S3") || return true
    for i in 1:count
        _projection(transactions[i], variant, k) == source.s0[i] ||
            error("$variant projection differs from S0 at image $(source.mapping[i].image_id)")
        isempty(transactions[i]) == isempty(source.s0[i]) ||
            error("$variant empty status differs from S0 at image $(source.mapping[i].image_id)")
    end
    return true
end

function _run_id(source::SourceRun, variant::String, profile::String, image_count::Int)
    base = replace(source.run_id, "_S0_"=>"_$(replace(variant, "-"=>""))_")
    return profile == "smoke" ? "$(base)_SMOKE$(image_count)" : base
end

_variant_folder(variant::String) = variant == "S6-B" ? "S6B" : variant

function _output_run_dir(context::TC6Context, variant::String, run_id::String)
    return joinpath(context.output_root, _variant_folder(variant), run_id)
end

function _output_limit(context::TC6Context)
    return context.profile == "full" ? EXPECTED_IMAGES : Int(context.config["execution"]["smoke_image_count"])
end

function _selected_sources(context::TC6Context)
    if context.profile == "full"
        return context.sources
    end
    k = Int(context.config["execution"]["smoke_k"])
    seed = Int(context.config["execution"]["smoke_seed"])
    return filter(source -> source.k == k && source.seed == seed, context.sources)
end

function _variant_mapping(variant::String, ids::Vector{Int}, k::Int)
    rows = Vector{Vector{String}}()
    for id in ids
        decoded = _decode_item(variant, id, k)
        if variant == "S1"
            region, word = decoded
            label = ("top_left", "top_right", "bottom_left", "bottom_right")[region]
            push!(rows, [string(id), variant, "region_word", string(region), label,
                string(word), "", "", "", "", ""])
        elseif variant == "S3"
            stripe, word = decoded
            label = ("top", "middle", "bottom")[stripe]
            push!(rows, [string(id), variant, "stripe_word", "", "", string(word),
                string(stripe), label, "", "", ""])
        else
            relation, a, b = decoded
            label = relation == 1 ? "ABOVE" : "LEFT_OF"
            push!(rows, [string(id), variant, "relation", "", "", "", "", "",
                label, string(a), string(b)])
        end
    end
    return rows
end

function _write_csv(path::String, header::Vector{String}, rows::Vector{Vector{String}})
    _write_atomic(path, io -> begin
        println(io, join(header, ','))
        for row in rows
            length(row) == length(header) || error("CSV row width differs from header for $path")
            println(io, join(row, ','))
        end
    end)
    return path
end

function _write_atomic(path::String, writer::Function)
    mkpath(dirname(path))
    tmp = path * ".partial"
    open(tmp, "w") do io
        writer(io)
        flush(io)
    end
    mv(tmp, path; force=true)
    return path
end

function _write_toml(path::String, data)
    return _write_atomic(path, io -> TOML.print(io, data))
end

function _statistics(transactions::Vector{Vector{Int}})
    lengths = length.(transactions)
    return Dict{String,Any}(
        "transaction_count"=>length(transactions),
        "empty_count"=>count(isempty, transactions),
        "nonempty_count"=>count(tx -> !isempty(tx), transactions),
        "observed_item_count"=>length(Set(item for tx in transactions for item in tx)),
        "min_transaction_length"=>(isempty(lengths) ? 0 : minimum(lengths)),
        "mean_transaction_length"=>(isempty(lengths) ? 0.0 : mean(lengths)),
        "median_transaction_length"=>(isempty(lengths) ? 0.0 : median(lengths)),
        "max_transaction_length"=>(isempty(lengths) ? 0 : maximum(lengths)),
    )
end

function _write_transactions(path::String, transactions::Vector{Vector{Int}}, mapping::Vector{TIDMapping})
    length(transactions) == length(mapping) || error("Transaction and mapping lengths differ")
    _write_atomic(path, io -> begin
        for (tx, row) in zip(transactions, mapping)
            write_transaction_jsonl_row(io, row.tid, row.image_id, tx)
        end
    end)
end

function _copy_or_subset_mapping(source_path::String, output_path::String,
    mapping::Vector{TIDMapping}, count::Int, profile::String)
    if profile == "full"
        cp(source_path, output_path; force=true)
        return
    end
    _write_atomic(output_path, io -> begin
        open(source_path, "r") do source_io
            println(io, readline(source_io))
            for _ in 1:count
                println(io, readline(source_io))
            end
        end
    end)
end

function _write_source_artifacts(path::String, context::TC6Context, data::SourceData)
    names = Dict(file => relpath(joinpath(data.source.path, file), context.repo_root)
        for file in REQUIRED_SOURCE_FILES)
    hashes = copy(data.hashes)
    source = Dict{String,Any}(
        "source_run_id"=>data.source.run_id,
        "source_run_path"=>relpath(data.source.path, context.repo_root),
        "source_root"=>relpath(context.source_root, context.repo_root),
        "method"=>"B0", "training_method"=>"raw_full_batch_kmeans",
        "k"=>data.source.k, "seed"=>data.source.seed,
        "fit_status"=>data.fit_status, "converged"=>data.converged,
        "source_files"=>names, "sha256"=>hashes,
        "codebook_is_reference_only"=>true,
    )
    _write_toml(path, source)
end

function _build_config_snapshot(context::TC6Context, data::SourceData, variant::String, count::Int)
    run = context.config["run"]
    ext = context.config["tc6_spatial_extension"]
    return Dict{String,Any}(
        "schema_version"=>TC6_SCHEMA_VERSION,
        "encoding_version"=>"tc6-spatial-v1.0",
        "profile"=>context.profile,
        "variant"=>variant,
        "run_id"=>_run_id(data.source, variant, context.profile, count),
        "method_alias"=>"B0", "training_method"=>"raw_full_batch_kmeans",
        "k"=>data.source.k, "seed"=>data.source.seed,
        "transaction_count"=>count, "support_denominator"=>count,
        "source_run_id"=>data.source.run_id,
        "source_config_path"=>relpath(joinpath(data.source.path, "config_snapshot.toml"), context.repo_root),
        "source_tc_config"=>TOML.parsefile(joinpath(data.source.path, "config_snapshot.toml")),
        "spatial_rules"=>Dict{String,Any}(
            "s1"=>Dict("row_break_after"=>3, "col_break_after"=>3,
                "region_layout"=>["top_left", "top_right", "bottom_left", "bottom_right"],
                "item_id_formula"=>"(region_id - 1) * K + word_id"),
            "s3"=>Dict("rows_per_stripe"=>[2, 3, 2],
                "item_id_formula"=>"(stripe_id - 1) * K + word_id"),
            "s6b"=>Dict("relation_types"=>["ABOVE", "LEFT_OF"],
                "min_manhattan_distance"=>1, "max_manhattan_distance"=>2,
                "same_word_on_distinct_patches"=>true,
                "item_id_formula"=>"(relation_index - 1) * K^2 + (word_a - 1) * K + word_b"),
        ),
        "source_root"=>String(run["source_root"]),
        "overwrite_production_artifacts"=>false,
        "labels_in_items"=>false,
        "transaction_format"=>"jsonl",
    )
end

function _encode_variant(data::SourceData, variant::String, count::Int)
    k = data.source.k
    transactions = Vector{Vector{Int}}(undef, count)
    witnesses = Dict{Int,Tuple{Int,NTuple{3,Int},NTuple{3,Int}}}()
    eligible_pairs = 0
    relation_occurrences = 0
    for i in 1:count
        observations = data.observations[i]
        if variant == "S1"
            transactions[i] = _encode_s1(observations, k)
        elseif variant == "S3"
            transactions[i] = _encode_s3(observations, k)
        elseif variant == "S6-B"
            transactions[i], pairs, occurrences = _encode_s6(observations, k;
                image_slot=i, witnesses=witnesses)
            eligible_pairs += pairs
            relation_occurrences += occurrences
        else
            error("Unsupported spatial variant: $variant")
        end
    end
    _check_projection(transactions, data, variant, k, count)
    return transactions, witnesses, eligible_pairs, relation_occurrences
end

function _read_output_transactions(path::String, mapping::Vector{TIDMapping}, variant::String,
    k::Int, expected_count::Int)
    transactions = Vector{Vector{Int}}()
    upper = variant == "S1" ? min(4k, 49) : variant == "S3" ? min(3k, 49) : min(2k^2, 298)
    item_upper = variant == "S1" ? 4k : variant == "S3" ? 3k : 2k^2
    open(path, "r") do io
        for (line_number, line) in enumerate(eachline(io))
            line_number <= expected_count || error("Too many output records in $path")
            record = _parse_transaction(line, path, line_number)
            record.tid == mapping[line_number].tid && record.image_id == mapping[line_number].image_id ||
                error("Output TID/image mismatch in $path at row $line_number")
            issorted(record.items) && allunique(record.items) ||
                error("Output items are not strictly sorted/unique in $path at row $line_number")
            length(record.items) <= upper || error("Output transaction exceeds $variant length bound")
            all(item -> 1 <= item <= item_upper, record.items) ||
                error("Output item outside $variant namespace at row $line_number")
            push!(transactions, record.items)
        end
    end
    length(transactions) == expected_count ||
        error("Output $path has $(length(transactions)) records; expected $expected_count")
    return transactions
end

function _read_item_mapping(path::String, variant::String, k::Int)
    ids = Int[]
    seen = Set{Int}()
    open(path, "r") do io
        eof(io) && error("Empty item mapping: $path")
        header = _csv_fields(readline(io))
        index = _header_indices(header, ITEM_MAPPING_HEADER, path)
        for line in eachline(io)
            fields = _csv_fields(line)
            length(fields) == length(header) || error("Malformed item mapping row in $path")
            id = parse(Int, fields[index["item_id"]])
            id > 0 && !(id in seen) || error("Duplicate/nonpositive item_id=$id in $path")
            fields[index["variant"]] == variant || error("Wrong variant in item mapping $path")
            expected_kind = variant == "S1" ? "region_word" : variant == "S3" ? "stripe_word" : "relation"
            fields[index["item_kind"]] == expected_kind || error("Wrong item_kind in item mapping $path")
            decoded = _decode_item(variant, id, k)
            if variant == "S1"
                region, word = decoded
                parse(Int, fields[index["region_id"]]) == region || error("S1 region mapping mismatch in $path")
                parse(Int, fields[index["word_id"]]) == word || error("S1 word mapping mismatch in $path")
            elseif variant == "S3"
                stripe, word = decoded
                parse(Int, fields[index["stripe_id"]]) == stripe || error("S3 stripe mapping mismatch in $path")
                parse(Int, fields[index["word_id"]]) == word || error("S3 word mapping mismatch in $path")
            else
                relation, a, b = decoded
                fields[index["relation_type"]] == (relation == 1 ? "ABOVE" : "LEFT_OF") ||
                    error("S6-B relation mapping mismatch in $path")
                parse(Int, fields[index["word_a"]]) == a && parse(Int, fields[index["word_b"]]) == b ||
                    error("S6-B word-pair mapping mismatch in $path")
            end
            push!(ids, id)
            push!(seen, id)
        end
    end
    return ids
end

function _validate_output(path::String, context::TC6Context, data::SourceData,
    variant::String, count::Int, witnesses::Dict{Int,Tuple{Int,NTuple{3,Int},NTuple{3,Int}}};
    require_integrity::Bool=true)
    tx_path = joinpath(path, "transactions.jsonl")
    tx = _read_output_transactions(tx_path, data.mapping, variant, data.source.k, count)
    _check_projection(tx, data, variant, data.source.k, count)
    tx_ids = Set(item for transaction in tx for item in transaction)
    map_ids = _read_item_mapping(joinpath(path, "item_mapping.csv"), variant, data.source.k)
    length(map_ids) == length(unique(map_ids)) || error("Item mappings are not one-to-one")
    Set(map_ids) == tx_ids || error("Observed item IDs and item_mapping.csv differ")
    for item in tx_ids
        _decode_item(variant, item, data.source.k)
    end
    if variant == "S6-B"
        for item in tx_ids
            witness = get(witnesses, item, nothing)
            isnothing(witness) && error("S6-B observed item $item has no retained-patch witness")
            slot, _, _ = witness
            1 <= slot <= count && item in tx[slot] || error("S6-B witness not present in read-back transaction")
            _validate_witness(item, witness, data.source.k, data.observations[slot]) ||
                error("S6-B witness geometry failed for item $item")
        end
    end

    mapping_path = joinpath(path, "tid_image_mapping.csv")
    output_mapping = _read_mapping_subset(mapping_path, data.mapping, count)
    if context.profile == "full"
        _sha256(mapping_path) == data.hashes["tid_image_mapping.csv"] ||
            error("Full output TID mapping is not byte-identical to S0")
    end
    snapshot = TOML.parsefile(joinpath(path, "config_snapshot.toml"))
    get(snapshot, "variant", "") == variant && get(snapshot, "k", 0) == data.source.k &&
        get(snapshot, "seed", -1) == data.source.seed || error("Output config snapshot identity mismatch")
    get(snapshot, "transaction_count", 0) == count &&
        get(snapshot, "support_denominator", 0) == count &&
        get(snapshot, "labels_in_items", true) == false || error("Output config contract mismatch")
    lineage = TOML.parsefile(joinpath(path, "source_artifacts.toml"))
    get(lineage, "source_run_id", "") == data.source.run_id &&
        get(lineage, "k", 0) == data.source.k && get(lineage, "seed", -1) == data.source.seed ||
        error("Output source lineage identity mismatch")
    get(lineage, "sha256", Dict{String,Any}()) == data.hashes ||
        error("Output source artifact hashes differ from verified preflight hashes")
    stats = TOML.parsefile(joinpath(path, "encoding_stats.toml"))
    actual_stats = _statistics(tx)
    for key in ("transaction_count", "empty_count", "nonempty_count", "observed_item_count",
        "min_transaction_length", "max_transaction_length")
        get(stats, key, -1) == actual_stats[key] || error("Read-back statistic $key mismatch")
    end
    isapprox(Float64(get(stats, "mean_transaction_length", -1.0)),
        Float64(actual_stats["mean_transaction_length"]); atol=1e-12) || error("Read-back mean length mismatch")
    isapprox(Float64(get(stats, "median_transaction_length", -1.0)),
        Float64(actual_stats["median_transaction_length"]); atol=1e-12) || error("Read-back median length mismatch")
    get(stats, "support_denominator", -1) == count || error("Wrong support denominator in $path")
    actual_stats["empty_count"] + actual_stats["nonempty_count"] == count ||
        error("Output empty/nonempty counts do not sum to denominator")
    if require_integrity
        integrity = TOML.parsefile(joinpath(path, "integrity_report.toml"))
        get(integrity, "status", "") == "PASS" || error("Output integrity report is not PASS")
        get(integrity, "transaction_count", 0) == count || error("Output integrity count mismatch")
        get(integrity, "source_mapping_sha256", "") == data.hashes["tid_image_mapping.csv"] ||
            error("Output source mapping lineage mismatch")
        get(integrity, "source_transaction_sha256", "") == data.hashes["transactions.jsonl"] ||
            error("Output source S0 lineage mismatch")
        get(integrity, "transaction_sha256", "") == _sha256(tx_path) ||
            error("Transaction artifact checksum mismatch")
        get(integrity, "item_mapping_sha256", "") == _sha256(joinpath(path, "item_mapping.csv")) ||
            error("Item mapping artifact checksum mismatch")
        checkpoint = TOML.parsefile(joinpath(path, "checkpoint.toml"))
        get(checkpoint, "status", "") == "COMPLETED" || error("Completed output checkpoint is not COMPLETED")
        get(checkpoint, "transaction_sha256", "") == _sha256(tx_path) ||
            error("Checkpoint transaction checksum mismatch")
        get(checkpoint, "integrity_report_sha256", "") == _sha256(joinpath(path, "integrity_report.toml")) ||
            error("Checkpoint integrity checksum mismatch")
    end
    length(output_mapping) == count || error("Output TID mapping row count mismatch")
    return tx, actual_stats
end

function _read_mapping_subset(path::String, expected::Vector{TIDMapping}, count::Int)
    rows = TIDMapping[]
    open(path, "r") do io
        eof(io) && error("Empty output TID mapping: $path")
        header = _csv_fields(readline(io))
        index = _header_indices(header, ["tid", "image_id", "original_split", "original_index"], path)
        for (line_number, line) in enumerate(eachline(io))
            line_number <= count || error("Too many output mapping rows in $path")
            fields = _csv_fields(line)
            actual = TIDMapping(parse(Int, fields[index["tid"]]), parse(Int, fields[index["image_id"]]),
                fields[index["original_split"]], parse(Int, fields[index["original_index"]]))
            actual == expected[line_number] || error("TID mapping differs from source at row $line_number")
            push!(rows, actual)
        end
    end
    length(rows) == count || error("Output mapping has $(length(rows)) rows, expected $count")
    return rows
end

function _run_one(context::TC6Context, data::SourceData, variant::String, count::Int)
    run_id = _run_id(data.source, variant, context.profile, count)
    output_dir = _output_run_dir(context, variant, run_id)
    checkpoint_path = joinpath(output_dir, "checkpoint.toml")
    mkpath(output_dir)
    if isfile(checkpoint_path)
        checkpoint = TOML.parsefile(checkpoint_path)
        if get(checkpoint, "status", "") == "COMPLETED"
            get(checkpoint, "variant", "") == variant && get(checkpoint, "source_run_id", "") == data.source.run_id ||
                error("Completed output folder has conflicting identity: $output_dir")
            get(checkpoint, "source_transaction_sha256", "") == data.hashes["transactions.jsonl"] ||
                error("Completed output source S0 changed; refusing overwrite: $output_dir")
            get(checkpoint, "source_assignments_sha256", "") == data.hashes["patch_assignments.csv"] ||
                error("Completed output source assignments changed; refusing overwrite: $output_dir")
            empty_witnesses = Dict{Int,Tuple{Int,NTuple{3,Int},NTuple{3,Int}}}()
            transactions, witnesses, _, _ = _encode_variant(data, variant, count)
            if variant == "S6-B"
                merge!(empty_witnesses, witnesses)
            end
            readback, stats = _validate_output(output_dir, context, data, variant, count, empty_witnesses)
            readback == transactions || error("Completed output no longer matches deterministic encoder: $output_dir")
            return Dict{String,Any}("run_id"=>run_id, "source_run_id"=>data.source.run_id,
                "variant"=>variant, "k"=>data.source.k, "seed"=>data.source.seed,
                "status"=>"COMPLETED", "integrity"=>"PASS", "transaction_count"=>count,
                "empty_count"=>stats["empty_count"], "output_path"=>relpath(output_dir, context.repo_root),
                "transaction_sha256"=>_sha256(joinpath(output_dir, "transactions.jsonl")),
                "source_fit_status"=>get(stats, "source_fit_status", data.fit_status),
                "source_converged"=>get(stats, "source_converged", data.converged),
                "warnings"=>get(stats, "warnings", String[]),
                "encoding_seconds"=>get(stats, "encoding_seconds", 0.0),
                "elapsed_seconds"=>get(checkpoint, "elapsed_seconds", 0.0),
                "resumed_completed_output"=>true)
        end
    end

    started = time()
    checkpoint = Dict{String,Any}("schema_version"=>TC6_SCHEMA_VERSION,
        "run_id"=>run_id, "source_run_id"=>data.source.run_id, "variant"=>variant,
        "k"=>data.source.k, "seed"=>data.source.seed, "status"=>"RUNNING",
        "transaction_count"=>count, "started_at_unix"=>started)
    _write_toml(checkpoint_path, checkpoint)
    try
        encode_started = time()
        transactions, witnesses, eligible_pairs, occurrences = _encode_variant(data, variant, count)
        encode_seconds = time() - encode_started
        _write_transactions(joinpath(output_dir, "transactions.jsonl"), transactions, data.mapping[1:count])
        item_ids = sort!(unique!([item for tx in transactions for item in tx]))
        mapping_rows = _variant_mapping(variant, item_ids, data.source.k)
        _write_csv(joinpath(output_dir, "item_mapping.csv"), ITEM_MAPPING_HEADER, mapping_rows)
        _copy_or_subset_mapping(joinpath(data.source.path, "tid_image_mapping.csv"),
            joinpath(output_dir, "tid_image_mapping.csv"), data.mapping, count, context.profile)
        snapshot = _build_config_snapshot(context, data, variant, count)
        _write_toml(joinpath(output_dir, "config_snapshot.toml"), snapshot)
        _write_source_artifacts(joinpath(output_dir, "source_artifacts.toml"), context, data)

        stats = _statistics(transactions)
        stats["schema_version"] = TC6_SCHEMA_VERSION
        stats["variant"] = variant
        stats["k"] = data.source.k
        stats["seed"] = data.source.seed
        stats["support_denominator"] = count
        stats["retained_patch_count"] = sum(length(data.observations[i]) for i in 1:count)
        stats["eligible_neighbor_pairs_processed"] = eligible_pairs
        stats["relation_occurrences_before_dedup"] = occurrences
        stats["observed_item_count"] = length(item_ids)
        stats["encoding_seconds"] = encode_seconds
        stats["readback_seconds"] = 0.0
        stats["source_fit_status"] = data.fit_status
        stats["source_converged"] = data.converged
        stats["warnings"] = data.converged ? String[] : ["Source TC4 fit status: $(data.fit_status); source remains integrity-valid."]
        _write_toml(joinpath(output_dir, "encoding_stats.toml"), stats)

        readback_started = time()
        readback, check_stats = _validate_output(output_dir, context, data, variant, count, witnesses;
            require_integrity=false)
        readback == transactions || error("Read-back transactions differ from encoder output")
        stats["readback_seconds"] = time() - readback_started
        _write_toml(joinpath(output_dir, "encoding_stats.toml"), stats)
        _ = TOML.parsefile(joinpath(output_dir, "config_snapshot.toml"))
        _ = TOML.parsefile(joinpath(output_dir, "source_artifacts.toml"))
        reread_stats = TOML.parsefile(joinpath(output_dir, "encoding_stats.toml"))
        get(reread_stats, "transaction_count", 0) == count || error("Final stats read-back failed")

        checks = Dict{String,Any}(
            "source_checkpoint_completed"=>true,
            "source_integrity_pass"=>true,
            "source_s0_projection_valid"=>true,
            "source_assignment_coordinates_valid"=>true,
            "transaction_readback_valid"=>true,
            "tid_mapping_matches_source"=>true,
            "items_sorted_unique_in_range"=>true,
            "item_mapping_roundtrip_valid"=>true,
            "support_denominator_valid"=>(check_stats["transaction_count"] == count),
            "empty_and_nonempty_counts_sum"=>(check_stats["empty_count"] + check_stats["nonempty_count"] == count),
            "variant_specific_invariant_valid"=>true,
        )
        report = Dict{String,Any}(
            "schema_version"=>TC6_SCHEMA_VERSION, "status"=>"PASS",
            "source_run_id"=>data.source.run_id, "variant"=>variant,
            "k"=>data.source.k, "seed"=>data.source.seed,
            "transaction_count"=>count, "unique_tid_count"=>count,
            "image_count"=>count, "support_denominator"=>count,
            "empty_count"=>check_stats["empty_count"],
            "nonempty_count"=>check_stats["nonempty_count"],
            "source_mapping_sha256"=>data.hashes["tid_image_mapping.csv"],
            "source_transaction_sha256"=>data.hashes["transactions.jsonl"],
            "source_assignments_sha256"=>data.hashes["patch_assignments.csv"],
            "source_codebook_sha256"=>data.hashes["codebook.bin"],
            "applicable_checks"=>(variant in ("S1", "S3") ?
                ["S0 projection equality for every image"] : ["S6-B witness geometry for every observed item"]),
            "not_applicable_checks"=>(variant in ("S1", "S3") ?
                ["S6-B witnesses"] : ["S0 projection equality"]),
            "transaction_sha256"=>_sha256(joinpath(output_dir, "transactions.jsonl")),
            "item_mapping_sha256"=>_sha256(joinpath(output_dir, "item_mapping.csv")),
            "checks"=>checks,
        )
        all(values(checks)) || error("At least one TC6 integrity check did not pass")
        _write_toml(joinpath(output_dir, "integrity_report.toml"), report)
        checkpoint["source_transaction_sha256"] = data.hashes["transactions.jsonl"]
        checkpoint["source_assignments_sha256"] = data.hashes["patch_assignments.csv"]
        checkpoint["transaction_sha256"] = report["transaction_sha256"]
        checkpoint["integrity_report_sha256"] = _sha256(joinpath(output_dir, "integrity_report.toml"))
        checkpoint["completed_at_unix"] = time()
        checkpoint["elapsed_seconds"] = time() - started
        checkpoint["status"] = "COMPLETED"
        _write_toml(checkpoint_path, checkpoint)
        completed = TOML.parsefile(checkpoint_path)
        final_report = TOML.parsefile(joinpath(output_dir, "integrity_report.toml"))
        get(completed, "status", "") == "COMPLETED" && get(final_report, "status", "") == "PASS" ||
            error("Final checkpoint/integrity read-back failed")
        _validate_output(output_dir, context, data, variant, count, witnesses)

        return Dict{String,Any}("run_id"=>run_id, "source_run_id"=>data.source.run_id,
            "variant"=>variant, "k"=>data.source.k, "seed"=>data.source.seed,
            "status"=>"COMPLETED", "integrity"=>"PASS", "transaction_count"=>count,
            "empty_count"=>check_stats["empty_count"], "output_path"=>relpath(output_dir, context.repo_root),
            "transaction_sha256"=>report["transaction_sha256"],
            "source_fit_status"=>data.fit_status, "source_converged"=>data.converged,
            "warnings"=>stats["warnings"], "encoding_seconds"=>stats["encoding_seconds"],
            "elapsed_seconds"=>checkpoint["elapsed_seconds"], "resumed_completed_output"=>false)
    catch err
        checkpoint["status"] = "FAILED"
        checkpoint["failure_reason"] = sprint(showerror, err)
        checkpoint["failed_at_unix"] = time()
        try
            _write_toml(checkpoint_path, checkpoint)
        catch
        end
        rethrow()
    end
end

function _write_progress_summary(context::TC6Context)
    rows = collect(values(context.results))
    sort!(rows; by=row -> (row["k"], row["seed"], row["variant"]))
    summary = Dict{String,Any}(
        "schema_version"=>TC6_SCHEMA_VERSION,
        "profile"=>context.profile,
        "source_root"=>relpath(context.source_root, context.repo_root),
        "output_root"=>relpath(context.output_root, context.repo_root),
        "expected_new_runs"=>(context.profile == "full" ? 45 : 3),
        "completed_new_runs"=>count(row -> row["status"] == "COMPLETED" && row["integrity"] == "PASS", rows),
        "runs"=>rows,
    )
    mkpath(context.output_root)
    _write_toml(joinpath(context.output_root, "spatial_extension_run_summary.toml"), summary)
    return summary
end

function run_variant!(context::TC6Context, variant::AbstractString)
    variant = String(variant)
    variant in ("S1", "S3", "S6-B") || throw(ArgumentError("Unsupported variant $variant"))
    context.preflight_complete || preflight_sources!(context)
    mkpath(context.output_root)
    count = _output_limit(context)
    sources = _selected_sources(context)
    isempty(sources) && error("No source runs selected for profile=$(context.profile)")
    for source in sources
        data = try
            _load_source(source, context)
        catch err
            error("TC6 load failed for $(source.run_id): $(sprint(showerror, err))")
        end
        data.hashes["tid_image_mapping.csv"] == context.mapping_hash ||
            error("TID mapping changed after source preflight for $(source.run_id)")
        started = time()
        result = _run_one(context, data, variant, count)
        context.results[(source.k, source.seed, variant)] = result
        _write_progress_summary(context)
        println("[TC6 $(variant)] $(result["status"]) $(result["run_id"]) | records=$(result["transaction_count"]) | empty=$(result["empty_count"]) | source=$(source.path) | output=$(result["output_path"]) | elapsed=$(round(time()-started; digits=2))s")
    end
    return sort!(collect(values(filter(pair -> pair.first[3] == variant, context.results))); by=row -> (row["k"], row["seed"]))
end

function validate_global_integrity!(context::TC6Context)
    context.preflight_complete || error("Source preflight must pass before global integrity checks")
    rows = Dict{String,Any}[]
    for source in context.sources
        source_row = only(filter(item -> item["source_run_id"] == source.run_id, context.source_rows))
        for file in REQUIRED_SOURCE_FILES
            _sha256(joinpath(source.path, file)) == source_row["file_hashes"][file] ||
                error("Source artifact changed after preflight: $(source.run_id)/$file")
        end
        push!(rows, Dict("source_run_id"=>source.run_id,
            "source_mapping_sha256"=>source_row["mapping_sha256"], "source_integrity"=>"PASS"))
    end
    for result in values(context.results)
        output_dir = joinpath(context.repo_root, String(result["output_path"]))
        checkpoint = TOML.parsefile(joinpath(output_dir, "checkpoint.toml"))
        integrity = TOML.parsefile(joinpath(output_dir, "integrity_report.toml"))
        get(checkpoint, "status", "") == "COMPLETED" && get(integrity, "status", "") == "PASS" ||
            error("Global integrity check failed for $(result["run_id"])")
        get(checkpoint, "transaction_sha256", "") == _sha256(joinpath(output_dir, "transactions.jsonl")) ||
            error("Global transaction checksum mismatch for $(result["run_id"])")
    end
    return Dict("source_runs"=>length(rows), "completed_spatial_runs"=>length(context.results),
        "source_integrity"=>"PASS", "spatial_integrity"=>"PASS")
end

function _manifest_source(source::SourceRun, context::TC6Context)
    run_path = relpath(source.path, context.repo_root)
    return Dict{String,Any}(
        "database_id"=>source.run_id, "variant"=>"S0", "method"=>"B0",
        "k"=>source.k, "seed"=>source.seed,
        "transaction_path"=>relpath(joinpath(source.path, "transactions.jsonl"), context.repo_root),
        "item_mapping_ref"=>"implicit: item_id equals word_id in 1:K",
        "source_codebook_path"=>relpath(joinpath(source.path, "codebook.bin"), context.repo_root),
        "source_run_path"=>run_path,
        "source_lineage"=>relpath(joinpath(source.path, "integrity_report.toml"), context.repo_root),
        "transaction_count"=>EXPECTED_IMAGES,
        "transaction_sha256"=>_sha256(joinpath(source.path, "transactions.jsonl")),
    )
end

function _hydrate_completed_results!(context::TC6Context)
    count = _output_limit(context)
    variants = String.(context.config["tc6_spatial_extension"]["variants_to_generate"])
    for source in _selected_sources(context), variant in variants
        key = (source.k, source.seed, variant)
        haskey(context.results, key) && continue
        run_id = _run_id(source, variant, context.profile, count)
        output_dir = _output_run_dir(context, variant, run_id)
        checkpoint_path = joinpath(output_dir, "checkpoint.toml")
        isfile(checkpoint_path) || continue
        checkpoint = TOML.parsefile(checkpoint_path)
        get(checkpoint, "status", "") == "COMPLETED" || continue
        get(checkpoint, "run_id", "") == run_id &&
            get(checkpoint, "source_run_id", "") == source.run_id &&
            get(checkpoint, "variant", "") == variant &&
            get(checkpoint, "k", 0) == source.k && get(checkpoint, "seed", -1) == source.seed ||
            error("Completed output checkpoint identity mismatch: $output_dir")
        report = TOML.parsefile(joinpath(output_dir, "integrity_report.toml"))
        stats = TOML.parsefile(joinpath(output_dir, "encoding_stats.toml"))
        artifacts = TOML.parsefile(joinpath(output_dir, "source_artifacts.toml"))
        tx_path = joinpath(output_dir, "transactions.jsonl")
        item_mapping_path = joinpath(output_dir, "item_mapping.csv")
        mapping_path = joinpath(output_dir, "tid_image_mapping.csv")
        all(isfile(path) for path in (tx_path, item_mapping_path, mapping_path,
            joinpath(output_dir, "config_snapshot.toml"))) ||
            error("Completed output is missing required artifacts: $output_dir")
        get(report, "status", "") == "PASS" && get(report, "transaction_count", 0) == count ||
            error("Completed output integrity report is invalid: $output_dir")
        get(checkpoint, "transaction_sha256", "") == _sha256(tx_path) &&
            get(report, "transaction_sha256", "") == _sha256(tx_path) ||
            error("Completed output transaction checksum mismatch: $output_dir")
        get(report, "item_mapping_sha256", "") == _sha256(item_mapping_path) ||
            error("Completed output item mapping checksum mismatch: $output_dir")
        get(artifacts, "source_run_id", "") == source.run_id ||
            error("Completed output source lineage mismatch: $output_dir")
        get(artifacts, "sha256", Dict{String,Any}())["transactions.jsonl"] ==
            report["source_transaction_sha256"] || error("Completed output S0 lineage mismatch: $output_dir")
        if context.profile == "full"
            source_mapping_hash = get(artifacts, "sha256", Dict{String,Any}())["tid_image_mapping.csv"]
            _sha256(mapping_path) == source_mapping_hash ||
                error("Completed output TID mapping differs from its source: $output_dir")
        end
        get(stats, "transaction_count", 0) == count &&
            get(stats, "support_denominator", 0) == count ||
            error("Completed output stats denominator mismatch: $output_dir")
        context.results[key] = Dict{String,Any}(
            "run_id"=>run_id, "source_run_id"=>source.run_id,
            "variant"=>variant, "k"=>source.k, "seed"=>source.seed,
            "status"=>"COMPLETED", "integrity"=>"PASS", "transaction_count"=>count,
            "empty_count"=>get(stats, "empty_count", 0),
            "output_path"=>relpath(output_dir, context.repo_root),
            "transaction_sha256"=>_sha256(tx_path),
            "source_fit_status"=>get(stats, "source_fit_status", "UNKNOWN"),
            "source_converged"=>get(stats, "source_converged", true),
            "warnings"=>get(stats, "warnings", String[]),
            "encoding_seconds"=>get(stats, "encoding_seconds", 0.0),
            "elapsed_seconds"=>get(checkpoint, "elapsed_seconds", 0.0),
            "resumed_completed_output"=>true,
        )
    end
    return length(context.results)
end

function finalize_outputs!(context::TC6Context)
    context.preflight_complete || error("Run TC6 source preflight before finalization")
    _hydrate_completed_results!(context)
    expected_count = context.profile == "full" ? 45 : 3
    length(context.results) == expected_count ||
        error("Expected $expected_count spatial outputs, found $(length(context.results))")
    all(row -> row["status"] == "COMPLETED" && row["integrity"] == "PASS", values(context.results)) ||
        error("Not all spatial outputs are COMPLETED/PASS")
    global_report = validate_global_integrity!(context)
    summary = _write_progress_summary(context)

    databases = Dict{String,Any}[_manifest_source(source, context) for source in context.sources]
    for result in sort!(collect(values(context.results)); by=row -> (row["k"], row["seed"], row["variant"]))
        output_dir = joinpath(context.repo_root, String(result["output_path"]))
        source = only(filter(item -> item.run_id == result["source_run_id"], context.sources))
        push!(databases, Dict{String,Any}(
            "database_id"=>result["run_id"], "variant"=>result["variant"], "method"=>"B0",
            "k"=>result["k"], "seed"=>result["seed"],
            "transaction_path"=>relpath(joinpath(output_dir, "transactions.jsonl"), context.repo_root),
            "item_mapping_ref"=>relpath(joinpath(output_dir, "item_mapping.csv"), context.repo_root),
            "source_codebook_path"=>relpath(joinpath(source.path, "codebook.bin"), context.repo_root),
            "source_run_path"=>relpath(source.path, context.repo_root),
            "source_lineage"=>relpath(joinpath(output_dir, "source_artifacts.toml"), context.repo_root),
            "transaction_count"=>result["transaction_count"],
            "transaction_sha256"=>result["transaction_sha256"],
        ))
    end
    eda2_ready = context.profile == "full" && length(databases) == 60 &&
        all(row -> row["transaction_count"] == EXPECTED_IMAGES, databases)
    context.profile == "full" && !eda2_ready && error("Full EDA2 manifest must contain exactly 60 full databases")
    manifest = Dict{String,Any}(
        "schema_version"=>TC6_SCHEMA_VERSION,
        "profile"=>context.profile,
        "eda2_ready"=>eda2_ready,
        "database_count"=>length(databases),
        "source_s0_count"=>15,
        "spatial_output_count"=>length(context.results),
        "global_integrity"=>global_report,
        "databases"=>databases,
    )
    manifest_name = context.profile == "full" ? "eda2_database_manifest.toml" : "eda2_database_manifest_smoke.toml"
    _write_toml(joinpath(context.output_root, manifest_name), manifest)
    summary["global_integrity"] = global_report
    summary["eda2_manifest_path"] = relpath(joinpath(context.output_root, manifest_name), context.repo_root)
    summary["eda2_manifest_ready"] = eda2_ready
    _write_toml(joinpath(context.output_root, "spatial_extension_run_summary.toml"), summary)
    println("[TC6] FINALIZED profile=$(context.profile) | spatial=$(length(context.results)) | manifest=$(length(databases)) references | eda2_ready=$eda2_ready | output_root=$(context.output_root)")
    return (; summary, manifest)
end

function run_unit_checks!()
    @assert length(NEIGHBOR_PAIRS) == 226
    @assert count(pair -> begin
        p, q, _ = pair
        (p - 1) ÷ 7 != (q - 1) ÷ 7 && (p - 1) % 7 != (q - 1) % 7
    end, NEIGHBOR_PAIRS) == 72
    region_counts = [0, 0, 0, 0]
    for row in 1:7, col in 1:7
        region_counts[_region(row, col)] += 1
    end
    @assert region_counts == [9, 12, 12, 16]
    @assert _s1_id(1, 5, 64) == 5 && _s1_id(2, 12, 64) == 76 && _s1_id(3, 5, 64) == 133
    @assert _decode_item("S1", 133, 64) == (3, 5)
    @assert [_stripe(row) for row in 1:7] == [1, 1, 2, 2, 2, 3, 3]
    @assert _s3_id(3, 5, 128) == 261 && _decode_item("S3", 261, 128) == (3, 5)

    diagonal = NTuple{3,Int}[(1, 1, 5), (2, 2, 12)]
    s6, pairs, occurrences = _encode_s6(diagonal, 16)
    @assert pairs == 1 && occurrences == 2
    @assert s6 == sort([_s6_id(1, 5, 12, 16), _s6_id(2, 5, 12, 16)])
    @assert _decode_item("S6-B", _s6_id(1, 5, 12, 16), 16) == (1, 5, 12)
    vertical, _, vertical_occurrences = _encode_s6([(1, 1, 5), (3, 1, 12)], 16)
    @assert vertical == [_s6_id(1, 5, 12, 16)] && vertical_occurrences == 1
    too_far, _, _ = _encode_s6([(1, 1, 5), (3, 2, 12)], 16)
    @assert isempty(too_far)
    same_word, _, _ = _encode_s6([(1, 1, 5), (1, 2, 5)], 16)
    @assert same_word == [_s6_id(2, 5, 5, 16)]
    duplicate_patch, _, _ = _encode_s6([(1, 1, 5), (1, 1, 5)], 16)
    @assert isempty(duplicate_patch)
    repeated = [(1, 1, 5), (1, 2, 5), (2, 1, 12), (2, 2, 12)]
    repeated_items, _, _ = _encode_s6(repeated, 16)
    reversed_items, _, _ = _encode_s6(reverse(repeated), 16)
    @assert repeated_items == reversed_items
    @assert length(repeated_items) == length(unique(repeated_items))
    empty_items, _, _ = _encode_s6(NTuple{3,Int}[], 16)
    single_items, _, _ = _encode_s6([(7, 7, 2)], 16)
    @assert isempty(empty_items) && isempty(single_items)
    @assert isempty(_encode_s1(NTuple{3,Int}[], 16)) && isempty(_encode_s3(NTuple{3,Int}[], 16))
    @assert all(_validate_witness(id, (1, diagonal[1], diagonal[2]), 16, diagonal) for id in s6)
    return Dict("s1_regions_and_roundtrip"=>"PASS", "s3_stripes_and_roundtrip"=>"PASS",
        "s6b_neighbor_geometry_226_pairs_72_diagonals"=>"PASS",
        "s6b_direction_distance_same_word_dedup_order_empty_witness"=>"PASS")
end

end # module FashionTCSpatial
