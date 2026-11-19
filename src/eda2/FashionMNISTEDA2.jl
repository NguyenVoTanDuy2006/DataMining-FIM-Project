module FashionMNISTEDA2

using Random
using SHA
using Serialization
using Statistics
using TOML

export EDA2Context, load_context, discover_inputs, run_analysis_a!, run_common_pilot!,
    prepare_shortlist!, run_deep_pilot!, prepare_pattern_review!, write_inconclusive_report!, output_path

const EXPECTED_K = [16, 32, 64, 128, 256]
const EXPECTED_SEEDS = [42, 123, 2026]
const VARIANTS = ["S0", "S1", "S3"]
const EXPECTED_CODEBOOKS = length(EXPECTED_K) * length(EXPECTED_SEEDS)
const EXPECTED_DATABASES = EXPECTED_CODEBOOKS * length(VARIANTS)
const EXPECTED_IMAGES = 70_000
const VERIFIED_LINEAGE_SOURCES = Dict{String,String}()
const INPUT_TRANSACTION_HASHES = Dict{String,String}()
const CLASS_NAMES = ["T-shirt/top", "Trouser", "Pullover", "Dress", "Coat",
    "Sandal", "Shirt", "Sneaker", "Bag", "Ankle boot"]

struct DatabaseSpec
    database_id::String
    k::Int
    seed::Int
    variant::String
    run_dir::String
    source_dir::String
end

mutable struct EDA2Context
    repo_root::String
    config_path::String
    config::Dict{String,Any}
    output_root::String
    baseline_root::String
    spatial_root::String
    specs::Vector{DatabaseSpec}
    labels::Vector{Int}
    image_ids::Vector{Int}
end

_sha256(path) = bytes2hex(open(sha256, path))
function _input_transaction_hash(path)
    if isfile(path) && !haskey(INPUT_TRANSACTION_HASHES,path)
        INPUT_TRANSACTION_HASHES[path]=_sha256(path)
    end
    return get(INPUT_TRANSACTION_HASHES,path,"")
end
_run_name(k, seed, variant) = "FashionMNIST_T2_$(variant)_B0_K$(k)_seed$(seed)"
_canonical_run(k, seed) = "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
function _theoretical_size(variant, k)
    variant == "S0" && return k
    variant == "S1" && return 4k
    variant == "S3" && return 3k
    throw(ArgumentError("Unsupported EDA2 variant: $variant"))
end
output_path(ctx::EDA2Context, parts...) = joinpath(ctx.output_root, parts...)

function _absolute(repo_root, path)
    normpath(isabspath(String(path)) ? String(path) : joinpath(repo_root, String(path)))
end

function _path_contains(parent, child)
    rel=relpath(child,parent)
    rel=="." || !(rel==".." || startswith(rel,"../"))
end

function load_context(config_path::AbstractString; repo_root=pwd())
    repo_root = normpath(abspath(String(repo_root)))
    config_path = normpath(abspath(String(config_path)))
    isfile(config_path) || throw(ArgumentError("EDA2 config not found: $config_path"))
    config = TOML.parsefile(config_path)
    run = get(config, "run", Dict{String,Any}())
    input = get(config, "input", Dict{String,Any}())
    baseline = _absolute(repo_root, get(input, "baseline_root", "results/fashion/tc/tc6_configs/S0"))
    spatial = _absolute(repo_root, get(input, "spatial_root", "results/fashion/tc/tc6_configs"))
    out = _absolute(repo_root, get(run, "output_root", "results/fashion/eda2/v2"))
    Int(get(input,"expected_images",0))==EXPECTED_IMAGES || throw(ArgumentError("input.expected_images must be 70,000"))
    Int.(get(input,"expected_k",Int[]))==EXPECTED_K || throw(ArgumentError("input.expected_k differs from the fixed EDA2 design"))
    Int.(get(input,"expected_seeds",Int[]))==EXPECTED_SEEDS || throw(ArgumentError("input.expected_seeds differs from the fixed EDA2 design"))
    String.(get(input,"variants",String[]))==VARIANTS || throw(ArgumentError("input.variants differs from the fixed EDA2 design"))
    pilot=get(config,"pilot",Dict{String,Any}())
    0<Float64(get(pilot,"common_minsup_fraction",0.03))<=1 || throw(ArgumentError("common minsup must be in (0,1]"))
    Int(get(pilot,"common_max_itemset_length",2))>=1 || throw(ArgumentError("common max itemset length must be positive"))
    Float64.(get(pilot,"minsup_fractions",[0.01,0.03,0.05,0.10]))==[0.01,0.03,0.05,0.10] || throw(ArgumentError("C3 minsup fractions must use the common grid [0.01, 0.03, 0.05, 0.10]"))
    Int(get(pilot,"deep_max_itemset_length",0))>=1 || throw(ArgumentError("deep_max_itemset_length must be positive"))
    Int(get(pilot,"deep_repetitions",0))>=1 || throw(ArgumentError("deep_repetitions must be positive"))
    resources=get(config,"resources",Dict{String,Any}())
    Float64(get(resources,"per_database_timeout_seconds",0))>0 || throw(ArgumentError("C1 timeout must be positive"))
    Float64(get(resources,"deep_timeout_seconds",0))>0 || throw(ArgumentError("C3 timeout must be positive"))
    Int(get(resources,"max_pair_candidates",0))>0 || throw(ArgumentError("max_pair_candidates must be positive"))
    Int(get(resources,"max_itemsets_per_run",0))>0 || throw(ArgumentError("max_itemsets_per_run must be positive"))
    sampling=get(config,"sampling",Dict{String,Any}())
    Int(get(sampling,"jaccard_pair_sample_size",0))>0 || throw(ArgumentError("Jaccard pair sample size must be positive"))
    Int(get(sampling,"class_within_pair_target",0))>0 && Int(get(sampling,"class_between_pair_target",0))>0 || throw(ArgumentError("B5 pair targets must be positive"))
    for input_root in (baseline, spatial)
        !_path_contains(input_root,out) || throw(ArgumentError("EDA2 output must not be inside a TC input root: $out"))
        !_path_contains(out,input_root) || throw(ArgumentError("EDA2 output and TC input roots must not contain one another"))
    end
    isdir(baseline) || throw(ArgumentError("S0 input root does not exist: $baseline"))
    isdir(spatial) || throw(ArgumentError("TC6 input root does not exist: $spatial"))
    mkpath(out)
    snapshot_path=joinpath(out,"config_snapshot.toml")
    if isfile(snapshot_path)
        _sha256(snapshot_path)==_sha256(config_path) ||
            throw(ArgumentError("EDA2 config differs from the existing output snapshot; use a fresh output_root for a new run"))
    else
        cp(config_path,snapshot_path;force=true)
    end
    return EDA2Context(repo_root, config_path, config, out, baseline, spatial,
        DatabaseSpec[], Int[], Int[])
end

function discover_inputs(ctx::EDA2Context)
    specs = DatabaseSpec[]
    for k in EXPECTED_K, seed in EXPECTED_SEEDS, variant in VARIANTS
        run_id = _run_name(k, seed, variant)
        root = variant == "S0" ? ctx.baseline_root : joinpath(ctx.spatial_root, variant)
        run_dir = joinpath(root, run_id)
        source_dir = joinpath(ctx.baseline_root, _canonical_run(k, seed))
        push!(specs, DatabaseSpec("B0_K$(k)_seed$(seed)_$(variant)", k, seed, variant, run_dir, source_dir))
    end
    ctx.specs = specs
    return copy(specs)
end

function _csv_fields(line::AbstractString)
    fields, buffer, quoted = String[], IOBuffer(), false
    i = firstindex(line)
    while i <= lastindex(line)
        ch = line[i]
        if ch == '"'
            ni = nextind(line, i)
            if quoted && ni <= lastindex(line) && line[ni] == '"'
                print(buffer, '"'); i = ni
            else
                quoted = !quoted
            end
        elseif ch == ',' && !quoted
            push!(fields, String(take!(buffer)))
        else
            print(buffer, ch)
        end
        i = nextind(line, i)
    end
    quoted && error("Unterminated quoted CSV field")
    push!(fields, String(take!(buffer)))
    return fields
end

_csv_escape(value) = begin
    s = string(value)
    (occursin(',', s) || occursin('"', s) || occursin('\n', s)) ? "\"$(replace(s, "\""=>"\"\""))\"" : s
end

function _write_csv(path, header, rows)
    mkpath(dirname(path))
    tmp = path * ".partial"
    open(tmp, "w") do io
        println(io, join(_csv_escape.(header), ','))
        for row in rows
            length(row) == length(header) || error("CSV row width mismatch for $path")
            println(io, join(_csv_escape.(row), ','))
        end
    end
    mv(tmp, path; force=true)
    open(path,"r") do io
        eof(io) && error("CSV read-back found an empty artifact: $path")
        _csv_fields(readline(io))==String.(header) || error("CSV schema read-back mismatch: $path")
    end
    return path
end

function _record_phase!(ctx,phase,status,details=Dict{String,Any}())
    path=output_path(ctx,"execution","run_summary.toml")
    summary=isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
    summary[phase]=merge(Dict{String,Any}("status"=>status,"updated_unix_seconds"=>time()),Dict{String,Any}(details))
    mkpath(dirname(path)); tmp=path*".partial"
    open(tmp,"w") do io; TOML.print(io,summary); end
    mv(tmp,path;force=true)
    return path
end

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

function _parse_transaction(line, path, line_number)
    m = match(r"^\{\"tid\":(\d+),\"image_id\":(\d+),\"items\":\[([0-9,]*)\]\}$", line)
    isnothing(m) && error("Unsupported JSONL record at $path:$line_number")
    items = isempty(m.captures[3]) ? Int[] : parse.(Int, split(m.captures[3], ','))
    return parse(Int, m.captures[1]), parse(Int, m.captures[2]), items
end

function _metadata!(spec::DatabaseSpec)
    required = spec.variant == "S0" ?
        ["transactions.jsonl", "tid_image_mapping.csv", "image_metadata.csv", "tc4_metrics.toml", "codebook.bin", "patch_assignments.csv", "integrity_report.toml", "checkpoint.toml", "config_snapshot.toml"] :
        ["transactions.jsonl", "tid_image_mapping.csv", "item_mapping.csv", "encoding_stats.toml", "integrity_report.toml", "checkpoint.toml", "config_snapshot.toml", "source_artifacts.toml"]
    missing = filter(f -> !isfile(joinpath(spec.run_dir, f)), required)
    isempty(missing) || error("$(spec.database_id) missing artifacts: $(join(missing, ", "))")
    integrity = TOML.parsefile(joinpath(spec.run_dir, "integrity_report.toml"))
    checkpoint = TOML.parsefile(joinpath(spec.run_dir, "checkpoint.toml"))
    get(integrity, "status", "") == "PASS" || error("$(spec.database_id) source integrity is not PASS")
    get(checkpoint, "status", "") == "COMPLETED" || error("$(spec.database_id) checkpoint is not COMPLETED")
    get(checkpoint,"run_id",basename(spec.run_dir))==basename(spec.run_dir) || error("$(spec.database_id) checkpoint run ID mismatch")
    get(integrity, "transaction_count", 0) == EXPECTED_IMAGES || error("$(spec.database_id) denominator is not 70,000")
    if spec.variant == "S0"
        cfg = TOML.parsefile(joinpath(spec.run_dir, "config_snapshot.toml"))
        get(cfg, "run_id", "") == basename(spec.run_dir) || error("S0 run ID mismatch")
        get(cfg, "k", 0) == spec.k && get(cfg, "seed", -1) == spec.seed || error("S0 K/seed mismatch")
        tc2=get(cfg,"tc2_patch_filtering",Dict{String,Any}())
        get(tc2,"foreground_threshold",-1)==29 && get(tc2,"threshold_comparison","")=="strict_greater" ||
            error("S0 must use the verified TC2 grayscale threshold 29 with strict-greater comparison")
        get(cfg,"tc4_method","")=="raw_full_batch_kmeans" || error("S0 training method is not B0 raw full-batch K-means")
        get(integrity, "codebook_shape", Int[]) in ([16, spec.k], [spec.k, 16]) || error("Unexpected codebook shape")
        get(integrity,"codebook_sha256","")==_sha256(joinpath(spec.run_dir,"codebook.bin")) ||
            error("S0 codebook digest does not match integrity_report.toml")
    else
        lineage = TOML.parsefile(joinpath(spec.run_dir, "source_artifacts.toml"))
        get(lineage, "source_run_id", "") == basename(spec.source_dir) || error("Spatial source lineage mismatch")
        get(lineage, "k", 0) == spec.k && get(lineage, "seed", -1) == spec.seed || error("Spatial K/seed mismatch")
        basename(String(get(lineage,"source_run_path",""))) == basename(spec.source_dir) || error("Spatial source path mismatch")
        source_hashes=get(lineage,"sha256",Dict{String,Any}())
        for (filename,expected_hash) in source_hashes
            source_path=joinpath(spec.source_dir,filename)
            isfile(source_path) || error("Spatial lineage source file is missing: $source_path")
            if haskey(VERIFIED_LINEAGE_SOURCES,source_path)
                VERIFIED_LINEAGE_SOURCES[source_path]==expected_hash || error("Conflicting lineage checksum: $source_path")
            else
                _sha256(source_path)==expected_hash || error("Spatial lineage checksum mismatch: $source_path")
                VERIFIED_LINEAGE_SOURCES[source_path]=String(expected_hash)
            end
        end
        spatial_config=TOML.parsefile(joinpath(spec.run_dir,"config_snapshot.toml"))
        get(spatial_config,"variant","")==spec.variant || error("Spatial config variant mismatch")
        get(spatial_config,"k",0)==spec.k && get(spatial_config,"seed",-1)==spec.seed || error("Spatial config K/seed mismatch")
        checks=get(integrity,"checks",Dict{String,Any}())
        for key in ("tid_mapping_matches_source","support_denominator_valid","items_sorted_unique_in_range",
            "source_checkpoint_completed","transaction_readback_valid","source_integrity_pass",
            "item_mapping_roundtrip_valid","variant_specific_invariant_valid")
            get(checks,key,false)==true || error("$(spec.database_id) integrity check $key is not PASS")
        end
        map_header, map_rows = _read_csv(joinpath(spec.run_dir, "item_mapping.csv"))
        required=spec.variant=="S1" ? ("item_id","variant","region_id","word_id") : ("item_id","variant","stripe_id","word_id")
        all(in(map_header),required) || error("Spatial item mapping schema mismatch: $(spec.run_dir)")
        mapped=Set{Int}()
        for row in map_rows
            item=parse(Int,row["item_id"])
            item in mapped && error("Duplicate item mapping for item $item in $(spec.run_dir)")
            push!(mapped,item)
            row["variant"]==spec.variant || error("Item mapping variant mismatch for item $item")
            if spec.variant=="S1"
                region,word=parse(Int,row["region_id"]),parse(Int,row["word_id"])
                item==(region-1)*spec.k+word || error("S1 item mapping formula mismatch for item $item")
                1<=region<=4 && 1<=word<=spec.k || error("S1 item mapping field out of range")
            else
                stripe,word=parse(Int,row["stripe_id"]),parse(Int,row["word_id"])
                item==(stripe-1)*spec.k+word || error("S3 item mapping formula mismatch for item $item")
                1<=stripe<=3 && 1<=word<=spec.k || error("S3 item mapping field out of range")
            end
        end
        expected_mapping=Set(1:_theoretical_size(spec.variant,spec.k))
        mapped==expected_mapping || error("Spatial item mapping is incomplete or out of range: $(spec.run_dir)")
    end
    return integrity
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
    txs = Vector{Vector{Int}}(undef, EXPECTED_IMAGES)
    path = joinpath(spec.run_dir, "transactions.jsonl")
    open(path, "r") do io
        for (i, line) in enumerate(eachline(io))
            i <= EXPECTED_IMAGES || error("Too many records in $path")
            tid, image, items = _parse_transaction(line, path, i)
            tid == i && image == images[i] || error("TID/image mismatch at $path:$i")
            issorted(items) && allunique(items) || error("Items unsorted or duplicate at $path:$i")
            all(x -> 1 <= x <= _theoretical_size(spec.variant, spec.k), items) || error("Item out of range at $path:$i")
            capacity=min(_theoretical_size(spec.variant,spec.k),49)
            length(items)<=capacity || error("Transaction length exceeds encoding capacity at $path:$i")
            if !isnothing(compare_s0)
                sort!(unique!([(item - 1) % spec.k + 1 for item in items])) == compare_s0[i] || error("$(spec.variant) projection mismatch at TID $i")
                isempty(items) == isempty(compare_s0[i]) || error("$(spec.variant) empty status mismatch at TID $i")
            end
            txs[i] = items
        end
    end
    length(txs) == EXPECTED_IMAGES || error("$(spec.database_id) does not have 70,000 records")
    return txs
end

function _read_labels!(ctx)
    isempty(ctx.specs) && discover_inputs(ctx)
    spec = first(filter(s -> s.variant == "S0", ctx.specs))
    _, rows = _read_csv(joinpath(spec.run_dir, "image_metadata.csv"))
    length(rows) == EXPECTED_IMAGES || error("image_metadata.csv must contain 70,000 records")
    by_image = Dict(parse(Int, row["image_id"]) => parse(Int, row["class_label"]) for row in rows)
    _, images, _ = _read_tid_mapping(joinpath(spec.run_dir, "tid_image_mapping.csv"))
    labels = [get(by_image, image, -1) for image in images]
    all(x -> 0 <= x <= 9, labels) || error("Image labels are missing or outside 0:9")
    counts = [count(==(c), labels) for c in 0:9]
    all(==(7_000), counts) || error("Expected 7,000 labels in each of 10 classes")
    ctx.labels, ctx.image_ids = labels, images
    return labels, images
end

function _rand_pairs(rng, indices, target)
    n = length(indices)
    max_pairs = n * (n - 1) ÷ 2
    target = min(target, max_pairs)
    out, seen = Tuple{Int,Int}[], Set{Tuple{Int,Int}}()
    while length(out) < target
        a, b = rand(rng, indices), rand(rng, indices)
        a == b && continue
        pair = a < b ? (a, b) : (b, a)
        pair in seen && continue
        push!(seen, pair); push!(out, pair)
    end
    sort!(out)
    return out
end

function _make_pair_manifests!(ctx)
    params = get(ctx.config, "sampling", Dict{String,Any}())
    rng = MersenneTwister(Int(get(params, "pair_sampling_seed", 2026)))
    n_pairs = Int(get(params, "jaccard_pair_sample_size", 20_000))
    all_tids = collect(1:EXPECTED_IMAGES)
    pairs = _rand_pairs(rng, all_tids, n_pairs)
    _write_csv(output_path(ctx, "transactions", "jaccard_pair_manifest.csv"),
        ["tid_a", "tid_b", "seed"], [[a, b, Int(get(params, "pair_sampling_seed", 2026))] for (a, b) in pairs])

    labels = ctx.labels
    class_seed=Int(get(params, "class_pair_sampling_seed", 2026))
    class_rng=MersenneTwister(class_seed)
    class_tids = [findall(==(c), labels) for c in 0:9]
    within_target = Int(get(params, "class_within_pair_target", 50_000))
    between_target = Int(get(params, "class_between_pair_target", 50_000))
    within_per = div(within_target, 10)
    within = Tuple{Int,Int,Int,Int}[]
    for c in 0:9
        append!(within, [(a, b, c, c) for (a, b) in _rand_pairs(class_rng, class_tids[c+1], within_per)])
    end
    classes = [(a, b) for a in 0:9 for b in a+1:9]
    quotas = fill(div(between_target, length(classes)), length(classes))
    for i in 1:rem(between_target, length(classes)); quotas[i] += 1; end
    between = Tuple{Int,Int,Int,Int}[]
    for (i, (a, b)) in enumerate(classes)
        left, right, seen = class_tids[a+1], class_tids[b+1], Set{Tuple{Int,Int}}()
        quota = min(quotas[i], length(left) * length(right))
        while length(seen) < quota
            t1, t2 = rand(class_rng, left), rand(class_rng, right)
            pair = t1 < t2 ? (t1, t2) : (t2, t1)
            push!(seen, pair)
        end
        append!(between, [(a1, b1, a, b) for (a1, b1) in sort!(collect(seen))])
    end
    class_rows = Vector{Vector{Any}}()
    for (a, b, c, d) in within
        push!(class_rows, [a, b, c, d, "within", "class_$c", Int(get(params, "class_pair_sampling_seed", 2026))])
    end
    for (a, b, c, d) in between
        push!(class_rows, [a, b, c, d, "between", "class_$(c)_$(d)", Int(get(params, "class_pair_sampling_seed", 2026))])
    end
    class_manifest_path=output_path(ctx, "transactions", "class_similarity_pair_manifest.csv")
    _write_csv(class_manifest_path,
        ["tid_a", "tid_b", "class_a", "class_b", "pair_type", "sampling_stratum", "seed"], class_rows)
    return pairs, class_rows, _sha256(class_manifest_path)
end

_jaccard(a, b) = (isempty(a) && isempty(b)) ? 1.0 : (isempty(a) || isempty(b)) ? 0.0 : length(intersect(a, b)) / length(union(a, b))
function _quantile_summary(values)
    isempty(values) && return (NaN, NaN, NaN, NaN, NaN, NaN, NaN)
    q = quantile(Float64.(values), [0.0, 0.05, 0.25, 0.5, 0.75, 0.95, 1.0])
    return (mean(values), q[4], q[2], q[3], q[5], q[6], q[7])
end

function _transaction_metrics(spec, txs, pair_manifest, class_manifest, ctx)
    n = length(txs)
    lengths = length.(txs)
    supports = Dict{Int,Int}()
    unique_counts = Dict{Tuple{Vararg{Int}},Int}()
    for tx in txs
        key = Tuple(tx)
        unique_counts[key] = get(unique_counts, key, 0) + 1
        for item in tx
            supports[item] = get(supports, item, 0) + 1
        end
    end
    observed = sort!(collect(keys(supports)))
    counts = [supports[item] for item in observed]
    support_frac = counts ./ n
    support_cfg=get(ctx.config,"support",Dict{String,Any}())
    rare_max=Float64(get(support_cfg,"rare_support_max",0.01))
    ubiquitous_min=Float64(get(support_cfg,"ubiquitous_support_min",0.90))
    universe = _theoretical_size(spec.variant, spec.k)
    capacity=min(universe,49)
    metrics = Dict{String,Any}(
        "database_id"=>spec.database_id, "K"=>spec.k, "seed"=>spec.seed, "variant"=>spec.variant, "N"=>n,
        "empty_count"=>count(isempty, txs), "nonempty_count"=>count(tx -> !isempty(tx), txs),
        "empty_rate"=>count(isempty,txs)/n,"length1_count"=>count(==(1),lengths),"length1_fraction"=>count(==(1),lengths)/n,
        "mean_length"=>mean(lengths), "median_length"=>median(lengths), "std_length"=>std(lengths),
        "min_length"=>minimum(lengths), "max_length"=>maximum(lengths),
        "p5_length"=>quantile(lengths, 0.05), "p25_length"=>quantile(lengths, 0.25),
        "p75_length"=>quantile(lengths, 0.75), "p95_length"=>quantile(lengths, 0.95), "p99_length"=>quantile(lengths, 0.99),
        "observed_universe"=>length(observed), "theoretical_universe"=>universe,
        "length_capacity"=>capacity,"length_capacity_ratio"=>maximum(lengths)/capacity,
        "density_theoretical"=>sum(lengths)/(n*universe), "density_observed"=>(isempty(observed) ? 0.0 : sum(lengths)/(n*length(observed))),
        "unique_transaction_count"=>length(unique_counts), "unique_ratio"=>length(unique_counts)/n,
        "duplicate_ratio"=>1-length(unique_counts)/n, "support_min"=>isempty(observed) ? NaN : minimum(support_frac),
        "support_median"=>isempty(observed) ? NaN : median(support_frac), "support_mean"=>isempty(observed) ? NaN : mean(support_frac),
        "support_p5"=>isempty(observed) ? NaN : quantile(support_frac, 0.05), "support_p95"=>isempty(observed) ? NaN : quantile(support_frac, 0.95),
        "support_max"=>isempty(observed) ? NaN : maximum(support_frac), "integrity_status"=>"PASS")
    support_rows = [[spec.database_id, spec.k, spec.seed, spec.variant, item, supports[item], supports[item]/n] for item in observed]
    support_path = output_path(ctx, "transactions", "item_support_by_database", "$(spec.database_id).csv")
    _write_csv(support_path, ["database_id", "K", "seed", "variant", "item_id", "support_count", "support_fraction"], support_rows)
    repeated=sort!([entry for entry in collect(unique_counts) if last(entry)>1];by=entry->(-last(entry),first(entry)))
    duplicate_rows=[[spec.database_id,spec.variant,join(first(entry)," "),join([_decode_item(spec.variant,item,spec.k) for item in first(entry)],";"),last(entry),length(first(entry))]
        for entry in repeated[1:min(100,length(repeated))]]
    _write_csv(output_path(ctx,"transactions","repeated_transactions", "$(spec.database_id).csv"),
        ["database_id","variant","item_ids_raw_namespace","decoded_items","multiplicity","length"],duplicate_rows)
    threshold_rows = Vector{Vector{Any}}()
    thresholds = Float64.(get(get(ctx.config, "pilot", Dict{String,Any}()), "minsup_fractions", [0.01, 0.03, 0.05, 0.10]))
    for fraction in thresholds
        cutoff = ceil(Int, fraction*n)
        frequent = count(>=(cutoff), counts)
        push!(threshold_rows, [spec.database_id, spec.k, spec.seed, spec.variant, fraction, cutoff, frequent,
            length(observed), universe, isempty(observed) ? 0.0 : frequent/length(observed), frequent/universe,
            metrics["support_min"],metrics["support_median"],metrics["support_mean"],metrics["support_p5"],metrics["support_p95"],metrics["support_max"],
            count(<=(rare_max),support_frac),count(>=(ubiquitous_min),support_frac)])
    end
    pair_values = [_jaccard(txs[a], txs[b]) for (a,b) in pair_manifest]
    qj = _quantile_summary(pair_values)
    both_empty = count(pair -> isempty(txs[pair[1]]) && isempty(txs[pair[2]]), pair_manifest)
    one_empty = count(pair -> xor(isempty(txs[pair[1]]), isempty(txs[pair[2]])), pair_manifest)
    metrics["jaccard_pair_count"] = length(pair_values)
    metrics["jaccard_mean"] = mean(pair_values); metrics["jaccard_median"] = median(pair_values)
    metrics["jaccard_p5"] = quantile(pair_values, 0.05); metrics["jaccard_p95"] = quantile(pair_values, 0.95)
    metrics["jaccard_both_empty_pairs"] = both_empty; metrics["jaccard_one_empty_pairs"] = one_empty
    within_vals, between_vals = Float64[], Float64[]
    within_both, between_both, within_one, between_one = 0, 0, 0, 0
    class_rows, between_rows = Vector{Vector{Any}}(), Vector{Vector{Any}}()
    class_buckets = Dict{Int,Vector{Float64}}(c=>Float64[] for c in 0:9)
    between_buckets = Dict{Tuple{Int,Int},Vector{Float64}}()
    class_both = Dict{Int,Int}(c=>0 for c in 0:9)
    class_one = Dict{Int,Int}(c=>0 for c in 0:9)
    between_both_by_pair = Dict{Tuple{Int,Int},Int}()
    between_one_by_pair = Dict{Tuple{Int,Int},Int}()
    for row in class_manifest
        a, b = Int(row[1]), Int(row[2]); ca, cb = Int(row[3]), Int(row[4]); kind = String(row[5])
        score = _jaccard(txs[a], txs[b])
        both = isempty(txs[a]) && isempty(txs[b])
        if kind == "within"
            both && (within_both += 1)
            both && (class_both[ca]+=1)
            xor(isempty(txs[a]),isempty(txs[b])) && (within_one+=1; class_one[ca]+=1)
            !both && push!(within_vals, score)
            !both && push!(class_buckets[ca], score)
        else
            both && (between_both += 1)
            both && (between_both_by_pair[(ca,cb)]=get(between_both_by_pair,(ca,cb),0)+1)
            xor(isempty(txs[a]),isempty(txs[b])) && (between_one+=1; between_one_by_pair[(ca,cb)]=get(between_one_by_pair,(ca,cb),0)+1)
            !both && push!(between_vals, score)
            !both && push!(get!(between_buckets, (ca,cb), Float64[]), score)
        end
    end
    for c in 0:9
        vals = class_buckets[c]
        push!(class_rows, [spec.database_id, spec.k, spec.seed, spec.variant, c, length(vals), class_both[c], class_one[c], isempty(vals) ? "" : mean(vals), isempty(vals) ? "" : median(vals), isempty(vals) ? "" : quantile(vals,0.05), isempty(vals) ? "" : quantile(vals,0.25), isempty(vals) ? "" : quantile(vals,0.75), isempty(vals) ? "" : quantile(vals,0.95)])
    end
    for (ca,cb) in [(a,b) for a in 0:9 for b in a+1:9]
        vals = get(between_buckets, (ca,cb), Float64[])
        push!(between_rows, [spec.database_id, spec.k, spec.seed, spec.variant, ca, cb, length(vals), get(between_both_by_pair,(ca,cb),0), get(between_one_by_pair,(ca,cb),0), isempty(vals) ? "" : mean(vals), isempty(vals) ? "" : median(vals), isempty(vals) ? "" : quantile(vals,0.05), isempty(vals) ? "" : quantile(vals,0.25), isempty(vals) ? "" : quantile(vals,0.75), isempty(vals) ? "" : quantile(vals,0.95)])
    end
    metrics["within_valid_pairs"] = length(within_vals); metrics["between_valid_pairs"] = length(between_vals)
    metrics["within_mean_jaccard"] = isempty(within_vals) ? NaN : mean(within_vals)
    metrics["between_mean_jaccard"] = isempty(between_vals) ? NaN : mean(between_vals)
    for (prefix,values) in (("within",within_vals),("between",between_vals))
        for (name,q) in (("median",0.50),("p5",0.05),("p25",0.25),("p75",0.75),("p95",0.95))
            metrics["$(prefix)_$(name)_jaccard"]=isempty(values) ? NaN : quantile(values,q)
        end
    end
    metrics["separation_gap"] = isempty(within_vals) || isempty(between_vals) ? NaN : mean(within_vals)-mean(between_vals)
    metrics["within_both_empty_pairs"] = within_both; metrics["between_both_empty_pairs"] = between_both
    metrics["within_one_empty_pairs"] = within_one; metrics["between_one_empty_pairs"] = between_one
    metrics["pair_discrimination_auc"] = _auc(within_vals, between_vals)
    return metrics, support_rows, threshold_rows, class_rows, between_rows
end

function _spatial_descriptive_rows(spec, txs)
    region_rows = Vector{Vector{Any}}()
    key = [spec.database_id, spec.k, spec.seed, spec.variant]
    spec.variant == "S0" && return region_rows, [key..., "PASS"]
    _, mapping = _read_csv(joinpath(spec.run_dir, "item_mapping.csv"))
    by_id = Dict(parse(Int, row["item_id"]) => row for row in mapping)
    labels=spec.variant=="S1" ? ["top_left","top_right","bottom_left","bottom_right"] : ["top","middle","bottom"]
    capacities=spec.variant=="S1" ? [9,12,12,16] : [14,21,14]
    counts=zeros(Int,length(labels))
    for tx in txs
        present=Set{Int}()
        for item in tx
            row=get(by_id,item,nothing)
            isnothing(row) && error("No spatial mapping for observed item $item")
            group=parse(Int,spec.variant=="S1" ? row["region_id"] : row["stripe_id"])
            push!(present,group)
        end
        for group in present; counts[group]+=1; end
    end
    for group in eachindex(labels)
        push!(region_rows,[spec.database_id,spec.k,spec.seed,spec.variant,group,labels[group],capacities[group],counts[group],counts[group]/EXPECTED_IMAGES])
    end
    return region_rows, [key..., "PROJECTION_AND_EMPTY_STATUS_PASS"]
end

function _length_histogram_rows(spec,txs)
    bins=[("0",0,0),("1",1,1),("2",2,2),("3-5",3,5),("6-10",6,10),
        ("11-20",11,20),("21-40",21,40),("41-80",41,80),("81-160",81,160),("161+",161,typemax(Int))]
    lengths=length.(txs)
    return [[spec.database_id,spec.k,spec.seed,spec.variant,label,count(x->lo<=x<=hi,lengths),
        count(x->lo<=x<=hi,lengths)/length(lengths)] for (label,lo,hi) in bins]
end

function _auc(within, between)
    (isempty(within) || isempty(between)) && return NaN
    wins = 0.0
    sorted_between = sort!(copy(between))
    for value in within
        wins += searchsortedfirst(sorted_between, value) - 1
        wins += (searchsortedlast(sorted_between, value)-searchsortedfirst(sorted_between, value)+1)/2
    end
    return wins/(length(within)*length(between))
end

function _centroid_svg(path, centroids, k)
    cols = min(16, k); rows = cld(k, cols)
    cell, tile = 14, 82
    width, height = max(860,40+cols*tile), max(620,60+rows*tile)
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/><text x=\"20\" y=\"28\" font-size=\"20\">K=$k centroid gallery (4×4 descriptors)</text>")
        for c in 1:k
            x0 = 20 + ((c-1)%cols)*tile; y0 = 50 + ((c-1)÷cols)*tile
            for r in 1:4, col in 1:4
                v = centroids[c, (col-1)*4+r]
                gray = round(Int, 255*clamp(v,0,1))
                println(io, "<rect x=\"$(x0+(col-1)*cell)\" y=\"$(y0+(r-1)*cell)\" width=\"$cell\" height=\"$cell\" fill=\"rgb($gray,$gray,$gray)\"/>")
            end
            println(io, "<text x=\"$x0\" y=\"$(y0+69)\" font-size=\"11\">word $c</text>")
        end
        println(io, "</svg>")
    end
end

function _codebook_analysis!(ctx)
    rows = Vector{Vector{Any}}()
    stability = Vector{Vector{Any}}()
    flags = Vector{Vector{Any}}()
    for k in EXPECTED_K, seed in EXPECTED_SEEDS
        spec = first(filter(s -> s.k == k && s.seed == seed && s.variant == "S0", ctx.specs))
        integrity = _metadata!(spec)
        metrics = TOML.parsefile(joinpath(spec.run_dir, "tc4_metrics.toml"))
        get(metrics,"k",0)==k && get(metrics,"seed",-1)==seed || error("TC4 metrics K/seed mismatch for $(spec.database_id)")
        get(metrics,"method","")=="raw_full_batch_kmeans" || error("TC4 metrics method mismatch for $(spec.database_id)")
        centroids = _read_codebook(joinpath(spec.run_dir, "codebook.bin"), k)
        gallery = output_path(ctx, "codebook", "figures", "centroids_K$(k)_seed$(seed).svg")
        mkpath(dirname(gallery)); _centroid_svg(gallery, centroids, k)
        status = String(get(metrics, "converged", false) ? "CONVERGED" : "NON_CONVERGED")
        empty = Int(get(metrics, "empty_clusters", 0) isa Vector ? length(metrics["empty_clusters"]) : metrics["empty_clusters"])
        flag = empty > 0 ? "DEGENERATE_WARNING" : status
        push!(rows, ["B0", k, seed, _canonical_run(k,seed), relpath(spec.run_dir,ctx.repo_root),
            get(metrics,"distance","unknown"), get(metrics,"distortion_mean_squared",""),
            get(metrics,"occupancy_fraction",""), empty, get(metrics,"normalized_entropy",""),
            get(metrics,"top_cluster_share",""), status, flag, get(metrics,"iterations",""),
            get(metrics,"library_version",""), get(metrics,"seed_stability_ari_mean",""),
            get(metrics,"stability_sample_size",""), get(integrity,"codebook_sha256","")])
        push!(flags, [k, seed, flag, get(metrics,"stop_reason",""), get(metrics,"converged",false)])
    end
    previous_distortion=nothing
    for k in EXPECTED_K
        vals = [parse(Float64,string(r[7])) for r in rows if r[2]==k && r[7] != ""]
        occ = [parse(Float64,string(r[8])) for r in rows if r[2]==k && r[8] != ""]
        ari = [parse(Float64,string(r[16])) for r in rows if r[2]==k && r[16] != ""]
        current_distortion=isempty(vals) ? nothing : mean(vals)
        improvement=isnothing(previous_distortion) || isnothing(current_distortion) || previous_distortion==0 ? "" : (previous_distortion-current_distortion)/previous_distortion
        push!(stability, [k, length(vals), isempty(vals) ? "" : mean(vals), isempty(vals) ? "" : std(vals),
            isempty(vals) ? "" : minimum(vals), isempty(vals) ? "" : maximum(vals), isempty(occ) ? "" : mean(occ), isempty(occ) ? "" : std(occ),
            isempty(ari) ? "" : mean(ari), isempty(ari) ? "" : std(ari), improvement,
            "Saved TC4 ARI only; cohort provenance must be reviewed"])
        previous_distortion=current_distortion
    end
    _write_csv(output_path(ctx,"codebook","codebook_metrics_15.csv"),
        ["method","K","seed","codebook_id","source_path","distortion_definition","distortion","occupancy","empty_clusters","cluster_entropy_norm","top1_cluster_share","convergence_status","flags","iterations","clustering_version","seed_stability_ari_mean_saved","stability_sample_size_saved","codebook_sha256"], rows)
    _write_csv(output_path(ctx,"codebook","codebook_metrics_by_k.csv"),
        ["K","seed_count","distortion_mean","distortion_std","distortion_min","distortion_max","occupancy_mean","occupancy_std","saved_ari_mean","saved_ari_std","relative_improvement_vs_previous_K","stability_note"], stability)
    _write_csv(output_path(ctx,"codebook","seed_stability_by_k.csv"),
        ["K","seed_count","distortion_mean","distortion_std","distortion_min","distortion_max","occupancy_mean","occupancy_std","saved_ari_mean","saved_ari_std","relative_improvement_vs_previous_K","stability_note"], stability)
    _write_csv(output_path(ctx,"codebook","codebook_flags.csv"), ["K","seed","flag","stop_reason","converged"], flags)
    return rows
end

function _write_input_manifest(ctx, status_rows)
    header = ["database_id","method","K","seed","variant","source_root","run_path","transactions_path","codebook_path_or_ref","item_mapping_path_or_ref","tid_mapping_path","integrity_path","config_path","source_sha256","record_count","status","issue"]
    rows = Vector{Vector{Any}}()
    statuses = Dict(String(r[1]) => r for r in status_rows)
    for spec in ctx.specs
        source = spec.variant == "S0" ? spec.run_dir : spec.source_dir
        txpath = joinpath(spec.run_dir,"transactions.jsonl")
        sha = _input_transaction_hash(txpath)
        row = get(statuses,spec.database_id,nothing)
        status = isnothing(row) ? "NOT_RUN" : row[2]
        issue = isnothing(row) ? "" : row[3]
        push!(rows,[spec.database_id,"B0",spec.k,spec.seed,spec.variant,relpath(source,ctx.repo_root),relpath(spec.run_dir,ctx.repo_root),
            relpath(txpath,ctx.repo_root),relpath(joinpath(source,"codebook.bin"),ctx.repo_root),
            spec.variant=="S0" ? "" : relpath(joinpath(spec.run_dir,"item_mapping.csv"),ctx.repo_root),
            relpath(joinpath(spec.run_dir,"tid_image_mapping.csv"),ctx.repo_root),relpath(joinpath(spec.run_dir,"integrity_report.toml"),ctx.repo_root),
            relpath(joinpath(spec.run_dir,"config_snapshot.toml"),ctx.repo_root),sha,EXPECTED_IMAGES,status,issue])
    end
    _write_csv(output_path(ctx,"input_manifest.csv"),header,rows)
end

function _record_validation!(ctx,validation,row)
    push!(validation,row)
    _write_input_manifest(ctx,validation)
    _write_csv(output_path(ctx,"validation_report.csv"),["database_id","status","issue","record_count","empty_count"],validation)
    spec=first(filter(s->s.database_id==row[1],ctx.specs))
    checkpoint=Dict("database_id"=>row[1],"status"=>row[2],"issue"=>row[3],"record_count"=>row[4],
        "source_sha256"=>_input_transaction_hash(joinpath(spec.run_dir,"transactions.jsonl")),
        "config_sha256"=>_sha256(ctx.config_path),"updated_unix_seconds"=>time())
    path=output_path(ctx,"execution","checkpoints","analysis_a_$(row[1]).toml")
    mkpath(dirname(path)); tmp=path*".partial"
    open(tmp,"w") do io; TOML.print(io,checkpoint); end
    mv(tmp,path;force=true)
end

function run_analysis_a!(ctx::EDA2Context)
    isempty(ctx.specs) && discover_inputs(ctx)
    _record_phase!(ctx,"analysis_a_b","RUNNING",Dict("expected_codebooks"=>EXPECTED_CODEBOOKS,"expected_databases"=>EXPECTED_DATABASES))
    mkpath(ctx.output_root)
    cp(ctx.config_path, output_path(ctx,"config_snapshot.toml"); force=true)
    _read_labels!(ctx)
    pair_manifest, class_manifest, class_manifest_hash = _make_pair_manifests!(ctx)
    jaccard_manifest_hash=_sha256(output_path(ctx,"transactions","jaccard_pair_manifest.csv"))
    codebook_rows = _codebook_analysis!(ctx)
    transaction_rows, support_summary, threshold_rows = Vector{Vector{Any}}(), Vector{Vector{Any}}(), Vector{Vector{Any}}()
    diversity_rows = Vector{Vector{Any}}()
    length_histogram=Vector{Vector{Any}}()
    paired_encoding=Vector{Vector{Any}}()
    class_summary, classwise, classpairs = Vector{Vector{Any}}(), Vector{Vector{Any}}(), Vector{Vector{Any}}()
    region_support, spatial_invariants = Vector{Vector{Any}}(), Vector{Vector{Any}}()
    validation = Vector{Vector{Any}}()
    _write_input_manifest(ctx,validation)
    _write_csv(output_path(ctx,"validation_report.csv"),["database_id","status","issue","record_count","empty_count"],validation)
    for k in EXPECTED_K, seed in EXPECTED_SEEDS
        specs = [s for s in ctx.specs if s.k==k && s.seed==seed]
        s0 = first(filter(s -> s.variant=="S0",specs))
        canonical_images = Int[]
        try
            println("EDA2 A/B: loading S0 for K=$k seed=$seed")
            flush(stdout)
            _metadata!(s0)
            s0tx, canonical_images = _read_s0_transactions(s0)
            for spec in sort(specs; by=s -> findfirst(==(s.variant),VARIANTS))
                try
                    println("  analyzing $(spec.database_id)")
                    flush(stdout)
                    txs = spec.variant=="S0" ? s0tx : _read_transactions(spec,canonical_images; compare_s0=s0tx)
                    if spec.variant!="S0"
                        length_delta=[length(txs[i])-length(s0tx[i]) for i in eachindex(s0tx)]
                        empty_mismatch=count(i->isempty(txs[i])!=isempty(s0tx[i]),eachindex(s0tx))
                        push!(paired_encoding,[spec.database_id,k,seed,spec.variant,EXPECTED_IMAGES,
                            mean(length_delta),median(length_delta),quantile(length_delta,0.05),
                            quantile(length_delta,0.95),empty_mismatch,empty_mismatch/EXPECTED_IMAGES])
                    end
                    metrics,supports,thresholds,within_rows,between_rows = _transaction_metrics(spec,txs,pair_manifest,class_manifest,ctx)
                    region_rows,invariant_row=_spatial_descriptive_rows(spec,txs)
                    append!(region_support,region_rows); push!(spatial_invariants,invariant_row)
                    append!(length_histogram,_length_histogram_rows(spec,txs))
                    push!(transaction_rows,[metrics[k] for k in ["database_id","K","seed","variant","N","empty_count","nonempty_count","empty_rate","length1_count","length1_fraction","min_length","mean_length","median_length","std_length","p5_length","p25_length","p75_length","p95_length","p99_length","max_length","length_capacity","length_capacity_ratio","observed_universe","theoretical_universe","density_theoretical","density_observed","unique_transaction_count","unique_ratio","duplicate_ratio","integrity_status"]])
                    append!(support_summary,thresholds); append!(threshold_rows,thresholds)
                    append!(classwise,within_rows); append!(classpairs,between_rows)
                    push!(diversity_rows,[spec.database_id,k,seed,spec.variant,EXPECTED_IMAGES,metrics["empty_count"],
                        metrics["unique_transaction_count"],metrics["unique_ratio"],metrics["duplicate_ratio"],metrics["jaccard_pair_count"],
                        metrics["jaccard_mean"],metrics["jaccard_median"],metrics["jaccard_p5"],metrics["jaccard_p95"],
                        metrics["jaccard_both_empty_pairs"],metrics["jaccard_one_empty_pairs"],jaccard_manifest_hash])
                    push!(class_summary,[spec.database_id,k,seed,spec.variant,EXPECTED_IMAGES,
                        metrics["within_mean_jaccard"],metrics["within_median_jaccard"],metrics["within_p5_jaccard"],metrics["within_p25_jaccard"],metrics["within_p75_jaccard"],metrics["within_p95_jaccard"],
                        metrics["between_mean_jaccard"],metrics["between_median_jaccard"],metrics["between_p5_jaccard"],metrics["between_p25_jaccard"],metrics["between_p75_jaccard"],metrics["between_p95_jaccard"],
                        metrics["separation_gap"],metrics["pair_discrimination_auc"],
                        metrics["within_valid_pairs"],metrics["between_valid_pairs"],metrics["within_both_empty_pairs"],metrics["between_both_empty_pairs"],
                        metrics["within_one_empty_pairs"],metrics["between_one_empty_pairs"],2026,class_manifest_hash])
                    _record_validation!(ctx,validation,[spec.database_id,"PASS","",EXPECTED_IMAGES,metrics["empty_count"]])
                    GC.gc(false)
                catch err
                    _record_validation!(ctx,validation,[spec.database_id,"BLOCKED",sprint(showerror,err),0,""])
                    get(get(ctx.config,"run",Dict{String,Any}()),"fail_fast_on_invalid_input",false) && rethrow()
                end
            end
        catch err
            for spec in specs
                any(r -> r[1]==spec.database_id, validation) || _record_validation!(ctx,validation,[spec.database_id,"BLOCKED",sprint(showerror,err),0,""])
            end
            get(get(ctx.config,"run",Dict{String,Any}()),"fail_fast_on_invalid_input",false) && rethrow()
        end
    end
    _write_input_manifest(ctx,validation)
    _write_csv(output_path(ctx,"transactions","transaction_metrics_45.csv"),
        ["database_id","K","seed","variant","N","empty_count","nonempty_count","empty_rate","length1_count","length1_fraction","min_length","mean_length","median_length","std_length","p5_length","p25_length","p75_length","p95_length","p99_length","max_length","length_capacity","length_capacity_ratio","observed_universe","theoretical_universe","density_theoretical","density_observed","unique_transaction_count","unique_ratio","duplicate_ratio","integrity_status"],transaction_rows)
    _write_csv(output_path(ctx,"transactions","paired_encoding_comparison.csv"),
        ["database_id","K","seed","variant","paired_tids","length_delta_mean_vs_s0","length_delta_median_vs_s0","length_delta_p5_vs_s0","length_delta_p95_vs_s0","empty_status_mismatches","empty_status_mismatch_fraction"],paired_encoding)
    _write_csv(output_path(ctx,"transactions","transaction_length_histogram_45.csv"),
        ["database_id","K","seed","variant","length_bin","transaction_count","fraction"],length_histogram)
    _write_csv(output_path(ctx,"transactions","item_support_summary_45.csv"),
        ["database_id","K","seed","variant","minsup_fraction","minsup_count","frequent_singletons","observed_items","theoretical_items","observed_item_fraction","theoretical_item_fraction","item_support_min","item_support_median","item_support_mean","item_support_p5","item_support_p95","item_support_max","rare_item_count","ubiquitous_item_count"],support_summary)
    _write_csv(output_path(ctx,"transactions","singleton_threshold_counts.csv"),
        ["database_id","K","seed","variant","minsup_fraction","minsup_count","frequent_singletons","observed_items","theoretical_items","observed_item_fraction","theoretical_item_fraction","item_support_min","item_support_median","item_support_mean","item_support_p5","item_support_p95","item_support_max","rare_item_count","ubiquitous_item_count"],threshold_rows)
    _write_csv(output_path(ctx,"transactions","transaction_diversity_45.csv"),
        ["database_id","K","seed","variant","N","empty_count","unique_transaction_count","unique_ratio","duplicate_ratio","jaccard_pair_count","jaccard_mean","jaccard_median","jaccard_p5","jaccard_p95","jaccard_both_empty_pairs","jaccard_one_empty_pairs","pair_manifest_sha256"],
        diversity_rows)
    _write_csv(output_path(ctx,"transactions","class_similarity_summary_45.csv"),
        ["database_id","K","seed","variant","N_labeled","within_mean_jaccard","within_median_jaccard","within_p5_jaccard","within_p25_jaccard","within_p75_jaccard","within_p95_jaccard","between_mean_jaccard","between_median_jaccard","between_p5_jaccard","between_p25_jaccard","between_p75_jaccard","between_p95_jaccard","separation_gap","pair_discrimination_auc","within_valid_pairs","between_valid_pairs","within_both_empty_pairs","between_both_empty_pairs","within_one_empty_pairs","between_one_empty_pairs","sampling_seed","pair_manifest_hash","status"],
        [[r...,"COMPUTED"] for r in class_summary])
    _write_csv(output_path(ctx,"transactions","classwise_similarity.csv"),
        ["database_id","K","seed","variant","class_id","valid_pairs","both_empty_pairs","one_empty_pairs","within_mean","within_median","within_p5","within_p25","within_p75","within_p95"],classwise)
    _write_csv(output_path(ctx,"transactions","class_pair_similarity.csv"),
        ["database_id","K","seed","variant","class_a","class_b","valid_pairs","both_empty_pairs","one_empty_pairs","between_mean","between_median","between_p5","between_p25","between_p75","between_p95"],classpairs)
    _write_csv(output_path(ctx,"transactions","region_support_summary.csv"),
        ["database_id","K","seed","variant","region_id","region_label","patch_slot_capacity","image_support_count","image_support_fraction"],region_support)
    _write_csv(output_path(ctx,"transactions","spatial_invariants_45.csv"),
        ["database_id","K","seed","variant","invariant_status"],spatial_invariants)
    issues=[r for r in validation if r[2]!="PASS"]
    _write_csv(output_path(ctx,"input_issues.csv"),["database_id","status","issue","run_path"],
        [[r[1],r[2],r[3],relpath(first(filter(s->s.database_id==r[1],ctx.specs)).run_dir,ctx.repo_root)] for r in issues])
    env = Dict("generated_unix_seconds"=>time(),"julia_version"=>string(VERSION),"database_count_expected"=>EXPECTED_DATABASES,
        "record_count_per_database"=>EXPECTED_IMAGES,"source_roots_read_only"=>true,"memory_cap_enforced"=>false,
        "machine"=>Sys.MACHINE,"kernel"=>string(Sys.KERNEL),"julia_threads"=>Threads.nthreads(),"total_memory_bytes"=>Sys.total_memory(),
        "codebook_count_validated"=>length(codebook_rows),"validated_database_count"=>count(r->r[2]=="PASS",validation),
        "config_sha256"=>_sha256(ctx.config_path),"project_sha256"=>_sha256(joinpath(ctx.repo_root,"Project.toml")),
        "manifest_sha256"=>isfile(joinpath(ctx.repo_root,"Manifest.toml")) ? _sha256(joinpath(ctx.repo_root,"Manifest.toml")) : "",
        "eda2_module_sha256"=>_sha256(joinpath(ctx.repo_root,"src","eda2","FashionMNISTEDA2.jl")),
        "eclat_baseline_sha256"=>_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl")),
        "notebook_sha256"=>_sha256(joinpath(ctx.repo_root,"notebook","UD2","EDA2_FashionMNIST_Transaction_Evaluation.ipynb")))
    open(output_path(ctx,"environment.toml"),"w") do io; TOML.print(io,env); end
    open(output_path(ctx,"validation_report.toml"),"w") do io
        TOML.print(io,Dict("expected_codebooks"=>EXPECTED_CODEBOOKS,"validated_codebooks"=>length(codebook_rows),
            "expected_databases"=>EXPECTED_DATABASES,"validated_databases"=>count(r->r[2]=="PASS",validation),
            "blocked_databases"=>count(r->r[2]!="PASS",validation),
            "blocked_database_ids"=>[String(r[1]) for r in validation if r[2]!="PASS"],
            "status"=>all(r->r[2]=="PASS",validation) ? "PASS" : "PARTIAL"))
    end
    _record_phase!(ctx,"analysis_a_b",count(r->r[2]=="PASS",validation)==EXPECTED_DATABASES ? "COMPLETED" : "PARTIAL",
        Dict("expected_databases"=>EXPECTED_DATABASES,"validated_databases"=>count(r->r[2]=="PASS",validation),"codebooks"=>length(codebook_rows)))
    return (codebooks=length(codebook_rows), databases=length(validation), passed=count(r->r[2]=="PASS",validation),
        output_root=ctx.output_root)
end

_core_mine(transactions,min_count;kwargs...) =
    getfield(parentmodule(@__MODULE__),:mine)(transactions,min_count;kwargs...)

function _read_transactions_bounded(path,deadline)
    transactions=Vector{Vector{Int}}()
    expired=false
    open(path,"r") do io
        for (line_number,line) in enumerate(eachline(io))
            if time()>deadline
                expired=true
                break
            end
            tid,_,items=_parse_transaction(line,path,line_number)
            tid==line_number || error("Non-contiguous TID in $path:$line_number")
            push!(transactions,items)
        end
    end
    expired && return nothing
    return transactions
end

function _support_distribution(values)
    isempty(values) && return ["","","","",""]
    q=quantile(Float64.(values),[0.05,0.50,0.95])
    return [minimum(values),q[1],q[2],q[3],maximum(values)]
end

function _bounded_eclat(path, min_count, max_length, timeout_s, max_pairs)
    started=time(); deadline=started+timeout_s
    transactions=_read_transactions_bounded(path,deadline)
    blank=["","","","",""]
    isnothing(transactions) && return (status="TIMEOUT", count1="", count2="", singleton_support=blank, pair_support=blank, elapsed=time()-started, active=0, reason="timeout while reading transactions")
    length(transactions)==EXPECTED_IMAGES || return (status="FAILED",count1="",count2="",singleton_support=blank,pair_support=blank,elapsed=time()-started,active=0,reason="transaction denominator is not 70,000")
    singleton_counts=Dict{Int,Int}()
    for tx in transactions
        time()>deadline && return (status="TIMEOUT",count1="",count2="",singleton_support=blank,pair_support=blank,elapsed=time()-started,active=0,reason="timeout while counting singleton supports")
        for item in unique(tx); singleton_counts[item]=get(singleton_counts,item,0)+1; end
    end
    active=count(>=(min_count),values(singleton_counts))
    pair_estimate=active*(active-1)÷2
    pair_estimate>max_pairs && return (status="ITEMSET_LIMIT", count1="", count2="", singleton_support=blank, pair_support=blank, elapsed=time()-started, active=active, reason="pair candidate estimate exceeds configured cap")
    result=try
        _core_mine(transactions,min_count;backend=:set,max_length=max_length,deadline=deadline,max_itemsets=max_pairs)
    catch err
        return (status=err isa InterruptException ? "TIMEOUT" : err isa OverflowError ? "ITEMSET_LIMIT" : "FAILED",
            count1="",count2="",singleton_support=blank,pair_support=blank,elapsed=time()-started,active=active,reason=sprint(showerror,err))
    end
    pairs=count(key->length(key)==2,keys(result))
    singleton_values=[support for support in values(singleton_counts) if support>=min_count]
    pair_values=[support for (key,support) in result if length(key)==2]
    return (status="COMPLETED_LENGTH_CAPPED",count1=active,count2=max_length>=2 ? pairs : 0,
        singleton_support=_support_distribution(singleton_values),pair_support=_support_distribution(pair_values),
        elapsed=time()-started,active=active,reason="exact through itemset length $max_length")
end

function run_common_pilot!(ctx::EDA2Context)
    manifest=output_path(ctx,"input_manifest.csv")
    isfile(manifest) || error("Run the structural phase first; input_manifest.csv is missing")
    rows=Vector{Vector{Any}}()
    outpath=output_path(ctx,"pilot_eclat","pilot_common_45.csv")
    support_headers=["frequent_1_support_min","frequent_1_support_p5","frequent_1_support_median","frequent_1_support_p95","frequent_1_support_max",
        "frequent_2_support_min","frequent_2_support_p5","frequent_2_support_median","frequent_2_support_p95","frequent_2_support_max"]
    checkpoint_header=["database_id","K","seed","variant","engine_name","engine_version","source_sha256","config_sha256","engine_source_sha256","adapter_source_sha256","minsup_fraction","minsup_count","max_length","completed_length","frequent_1_count","frequent_2_count",
        support_headers...,"runtime_s","peak_rss_bytes","status","censored","resumed","limit_reason"]
    prior=Dict{String,Dict{String,String}}()
    if isfile(outpath)
        _,old_rows=_read_csv(outpath)
        prior=Dict(r["database_id"]=>r for r in old_rows)
    end
    minsup=Float64(get(get(ctx.config,"pilot",Dict{String,Any}()),"common_minsup_fraction",0.03))
    max_len=Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"common_max_itemset_length",2))
    timeout=Float64(get(get(ctx.config,"resources",Dict{String,Any}()),"per_database_timeout_seconds",600))
    max_pairs=Int(get(get(ctx.config,"resources",Dict{String,Any}()),"max_pair_candidates",20_000_000))
    config_hash=_sha256(ctx.config_path)
    engine_hash=_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl"))
    adapter_hash=_sha256(joinpath(ctx.repo_root,"src","eda2","FashionMNISTEDA2.jl"))
    _,manifest_rows=_read_csv(manifest)
    for (row_index,row) in enumerate(manifest_rows)
        dbid=row["database_id"]; path=_absolute(ctx.repo_root,row["transactions_path"])
        println("C1 Eclat $(row_index)/$(length(manifest_rows)): $dbid")
        flush(stdout)
        actual_source_hash=isfile(path) ? _sha256(path) : ""
        if actual_source_hash!=row["source_sha256"]
            blocked_row=[dbid,row["K"],row["seed"],row["variant"],"EclatFIM.mine(:set)","max-length-v1",row["source_sha256"],config_hash,
                engine_hash,adapter_hash,minsup,ceil(Int,minsup*EXPECTED_IMAGES),max_len,"","",""]
            append!(blocked_row,fill("",length(support_headers)))
            append!(blocked_row,["","","SKIPPED_BLOCKED",true,false,"transaction source missing or changed after structural validation"])
            push!(rows,blocked_row)
            _write_csv(outpath,checkpoint_header,rows)
            continue
        end
        if row["status"]=="PASS" && Bool(get(get(ctx.config,"run",Dict{String,Any}()),"resume",true)) && haskey(prior,dbid)
            old=prior[dbid]
            if old["status"]=="COMPLETED_LENGTH_CAPPED" && old["source_sha256"]==row["source_sha256"] &&
                old["config_sha256"]==config_hash && old["engine_source_sha256"]==engine_hash && old["adapter_source_sha256"]==adapter_hash && parse(Float64,old["minsup_fraction"])==minsup &&
                parse(Int,old["minsup_count"])==ceil(Int,minsup*EXPECTED_IMAGES) && parse(Int,old["max_length"])==max_len
                resumed_row=[dbid,row["K"],row["seed"],row["variant"],old["engine_name"],old["engine_version"],old["source_sha256"],old["config_sha256"],
                    old["engine_source_sha256"],old["adapter_source_sha256"],old["minsup_fraction"],old["minsup_count"],old["max_length"],old["completed_length"],old["frequent_1_count"],old["frequent_2_count"]]
                append!(resumed_row,[old[h] for h in support_headers])
                append!(resumed_row,[old["runtime_s"],old["peak_rss_bytes"],old["status"],old["censored"],true,"reused matching completed checkpoint"])
                push!(rows,resumed_row)
                _write_csv(outpath,checkpoint_header,rows)
                continue
            end
        end
        if row["status"]!="PASS"
            blocked_row=[dbid,row["K"],row["seed"],row["variant"],"EclatFIM.mine(:set)","max-length-v1",row["source_sha256"],config_hash,engine_hash,adapter_hash,
                minsup,ceil(Int,minsup*EXPECTED_IMAGES),max_len,"","",""]
            append!(blocked_row,fill("",length(support_headers)))
            append!(blocked_row,["","","SKIPPED_BLOCKED",true,false,row["issue"]])
            push!(rows,blocked_row)
            _write_csv(outpath,checkpoint_header,rows)
            continue
        end
        result=try _bounded_eclat(path,ceil(Int,minsup*EXPECTED_IMAGES),max_len,timeout,max_pairs)
        catch err; (status="FAILED",count1="",count2="",singleton_support=fill("",5),pair_support=fill("",5),elapsed=0.0,active=0,reason=sprint(showerror,err)); end
        censored=result.status in ("TIMEOUT","MEMORY_LIMIT","ITEMSET_LIMIT","FAILED")
        result_row=[dbid,row["K"],row["seed"],row["variant"],"EclatFIM.mine(:set)","max-length-v1",row["source_sha256"],config_hash,engine_hash,adapter_hash,
            minsup,ceil(Int,minsup*EXPECTED_IMAGES),max_len,censored ? "" : max_len,censored ? "" : result.count1,censored ? "" : result.count2]
        append!(result_row,censored ? fill("",length(support_headers)) : vcat(result.singleton_support,result.pair_support))
        append!(result_row,[result.elapsed,"",result.status,censored,false,result.reason])
        push!(rows,result_row)
        _write_csv(outpath,checkpoint_header,rows)
        GC.gc(false)
    end
    open(output_path(ctx,"pilot_eclat","pilot_validation_report.toml"),"w") do io
        TOML.print(io,Dict("expected_runs"=>length(manifest_rows),"completed_or_censored_rows"=>length(rows),
            "engine_name"=>"EclatFIM.mine(:set)","engine_version"=>"max-length-v1","max_length"=>max_len,
            "minsup_fraction"=>minsup,"minsup_count"=>ceil(Int,minsup*EXPECTED_IMAGES),
            "timeout_seconds_per_database"=>timeout,"max_pair_candidates"=>max_pairs,
            "memory_cap_bytes_configured"=>get(get(ctx.config,"resources",Dict{String,Any}()),"memory_cap_bytes",0),
            "memory_cap_enforced"=>false,"peak_rss_measured"=>false,
            "eda2_module_sha256"=>_sha256(joinpath(ctx.repo_root,"src","eda2","FashionMNISTEDA2.jl")),
            "eclat_baseline_sha256"=>_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl"))))
    end
    completed=count(r->lowercase(string(r[30]))=="false" && r[29]=="COMPLETED_LENGTH_CAPPED",rows)
    _record_phase!(ctx,"pilot_c1",length(rows)==EXPECTED_DATABASES ? (completed==EXPECTED_DATABASES ? "COMPLETED" : "COMPLETED_WITH_CENSORING") : "PARTIAL",
        Dict("rows"=>length(rows),"completed"=>completed,"censored_or_blocked"=>length(rows)-completed))
    return (rows=length(rows),completed=completed,output=outpath)
end

function prepare_shortlist!(ctx::EDA2Context)
    source=output_path(ctx,"pilot_eclat","pilot_common_45.csv")
    isfile(source) || error("Run the common C1 pilot first")
    _,pilot_rows=_read_csv(source)
    length(pilot_rows)==EXPECTED_DATABASES && length(unique([r["database_id"] for r in pilot_rows]))==EXPECTED_DATABASES ||
        error("C1 must contain one explicit status row for each of $EXPECTED_DATABASES databases before C2")
    _,manifest_rows=_read_csv(output_path(ctx,"input_manifest.csv"))
    _,codebook_rows=_read_csv(output_path(ctx,"codebook","codebook_metrics_15.csv"))
    _,transaction_rows=_read_csv(output_path(ctx,"transactions","transaction_metrics_45.csv"))
    _,diversity_rows=_read_csv(output_path(ctx,"transactions","transaction_diversity_45.csv"))
    prior_path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    prior=Dict{Tuple{Int,Int},Dict{String,String}}()
    if isfile(prior_path)
        _,prior_rows=_read_csv(prior_path)
        for row in prior_rows
            prior[(parse(Int,row["K"]),parse(Int,row["seed"]))]=row
        end
    end
    validation=Dict(r["database_id"]=>r["status"] for r in manifest_rows)
    c1_status=Dict(r["database_id"]=>r["status"] for r in pilot_rows)
    out=Vector{Vector{Any}}()
    for k in EXPECTED_K, seed in EXPECTED_SEEDS
        dbs=[r for r in pilot_rows if parse(Int,r["K"])==k && parse(Int,r["seed"])==seed]
        statuses=join(sort!(unique(getindex.(dbs,"status"))),"|")
        invalid=any(get(validation,"B0_K$(k)_seed$(seed)_$(variant)","NOT_RUN")!="PASS" ||
            get(c1_status,"B0_K$(k)_seed$(seed)_$(variant)","NOT_RUN")=="SKIPPED_BLOCKED" for variant in VARIANTS)
        previous=get(prior,(k,seed),Dict{String,String}())
        selected=!invalid && lowercase(get(previous,"selected","false"))=="true"
        reason=invalid ? "INVALID_INPUT_BLOCKED" : selected ? get(previous,"decision_reason","REVIEW_REQUIRED") : "REVIEW_REQUIRED"
        codebook=first(filter(r->parse(Int,r["K"])==k && parse(Int,r["seed"])==seed,codebook_rows))
        evidence=String["distortion=$(codebook["distortion"])";"convergence=$(codebook["convergence_status"])";
            "saved_ari=$(codebook["seed_stability_ari_mean_saved"])";"c1_status=$(statuses)"]
        for variant in VARIANTS
            database_id="B0_K$(k)_seed$(seed)_$(variant)"
            pilot=first(filter(r->r["database_id"]==database_id,pilot_rows))
            transaction=first(filter(r->r["database_id"]==database_id,transaction_rows))
            diversity=first(filter(r->r["database_id"]==database_id,diversity_rows))
            append!(evidence,["$(variant)_C1_f1=$(pilot["frequent_1_count"])_f2=$(pilot["frequent_2_count"])_runtime_s=$(pilot["runtime_s"])";
                "$(variant)_length_mean=$(transaction["mean_length"])_p5=$(transaction["p5_length"])_p95=$(transaction["p95_length"])";
                "$(variant)_unique_ratio=$(diversity["unique_ratio"])_jaccard=$(diversity["jaccard_mean"])" ])
        end
        push!(out,[k,seed,_canonical_run(k,seed),selected,reason,statuses,join(evidence,";"),string(invalid),"eda2-v1.1"])
    end
    path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    _write_csv(path,["K","seed","codebook_id","selected","decision_reason","pilot_statuses","metrics_used","rejected_for_invalidity","selection_protocol_version","label_informed_selection"],
        [[r... ,"false"] for r in out])
    _record_phase!(ctx,"pilot_c2","AWAITING_HUMAN_REVIEW",Dict("decision_rows"=>length(out),"selected"=>0))
    return path
end

function _read_decisions(ctx)
    path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    _,rows=_read_csv(path)
    length(rows)==EXPECTED_CODEBOOKS && length(unique([(parse(Int,r["K"]),parse(Int,r["seed"])) for r in rows]))==EXPECTED_CODEBOOKS ||
        error("Shortlist must contain one decision row for each of the 15 codebooks")
    selected=[(parse(Int,r["K"]),parse(Int,r["seed"])) for r in rows if lowercase(r["selected"])=="true"]
    all(!isempty(r["decision_reason"]) && r["decision_reason"]!="REVIEW_REQUIRED" for r in rows if lowercase(r["selected"])=="true") ||
        error("Every selected (K,seed) needs a written decision_reason")
    manifest_path=output_path(ctx,"input_manifest.csv")
    c1_path=output_path(ctx,"pilot_eclat","pilot_common_45.csv")
    isfile(manifest_path) && isfile(c1_path) || error("Structural analysis and the common C1 pilot must finish before selecting codebooks")
    _,manifest=_read_csv(manifest_path); _,c1=_read_csv(c1_path)
    manifest_by_id=Dict(r["database_id"]=>r for r in manifest)
    c1_by_id=Dict(r["database_id"]=>r for r in c1)
    for (k,seed) in selected,variant in VARIANTS
        database_id="B0_K$(k)_seed$(seed)_$(variant)"
        haskey(manifest_by_id,database_id) && manifest_by_id[database_id]["status"]=="PASS" ||
            error("Cannot select invalid or blocked database: $database_id")
        haskey(c1_by_id,database_id) || error("Selected codebook is missing the common C1 status for $database_id")
        c1_by_id[database_id]["status"]!="SKIPPED_BLOCKED" || error("C1 marked selected database blocked: $database_id")
        txpath=_absolute(ctx.repo_root,manifest_by_id[database_id]["transactions_path"])
        _sha256(txpath)==manifest_by_id[database_id]["source_sha256"] || error("Selected transaction source changed after structural validation: $database_id")
    end
    return selected
end

function _mine_lengths(path,min_count,max_len,timeout,max_pairs)
    # C3 calls the repository Eclat engine; the length/resource limits are explicit.
    started=time(); deadline=started+timeout
    transactions=try
        _read_transactions_bounded(path,deadline)
    catch
        return nothing,"FAILED",time()-started
    end
    isnothing(transactions) && return nothing,"TIMEOUT",time()-started
    length(transactions)==EXPECTED_IMAGES || return nothing,"FAILED",time()-started
    try
        result=_core_mine(transactions,min_count;backend=:set,max_length=max_len,deadline=deadline,max_itemsets=max_pairs)
        return result,"COMPLETED_LENGTH_CAPPED",time()-started
    catch err
        status=err isa InterruptException ? "TIMEOUT" : err isa OverflowError ? "ITEMSET_LIMIT" : "FAILED"
        return nothing,status,time()-started
    end
end

function run_deep_pilot!(ctx::EDA2Context)
    selected=_read_decisions(ctx)
    isempty(selected) && error("No codebooks are selected. Review shortlist_decision.csv, set selected=true and document the reason.")
    minsups=Float64.(get(get(ctx.config,"pilot",Dict{String,Any}()),"minsup_fractions",[0.01,0.03,0.05,0.10]))
    max_len=Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"deep_max_itemset_length",4))
    timeout=Float64(get(get(ctx.config,"resources",Dict{String,Any}()),"deep_timeout_seconds",1800))
    max_sets=Int(get(get(ctx.config,"resources",Dict{String,Any}()),"max_itemsets_per_run",2_000_000))
    run_rows, count_rows, performance_rows=Vector{Vector{Any}}(),Vector{Vector{Any}}(),Vector{Vector{Any}}()
    run_header=["database_id","source_sha256","config_sha256","K","seed","variant","minsup_fraction","minsup_count","max_length","completion_status","warmup_status","warmup_runtime_s","runtime_median_s","runtime_max_s","peak_rss_bytes","output_ref","output_sha256","closed_maximal_status","repetitions","engine_source_sha256","adapter_source_sha256"]
    count_header=["database_id","K","seed","variant","minsup_fraction","minsup_count","itemset_count","status"]
    perf_header=["database_id","K","seed","variant","minsup_fraction","run_kind","repetition","status","runtime_s","peak_rss_bytes","memory_cap_enforced"]
    run_out=output_path(ctx,"pilot_eclat","pilot_deep_runs.csv")
    count_out=output_path(ctx,"pilot_eclat","pilot_itemset_counts.csv")
    perf_out=output_path(ctx,"pilot_eclat","performance_repetitions.csv")
    old_runs,old_counts,old_perf=Dict{Tuple{String,Float64},Dict{String,String}}(),Dict{Tuple{String,Float64},Vector{Dict{String,String}}}(),Dict{Tuple{String,Float64},Vector{Dict{String,String}}}()
    if isfile(run_out)
        _,previous=_read_csv(run_out)
        for row in previous; old_runs[(row["database_id"],parse(Float64,row["minsup_fraction"]))]=row; end
    end
    if isfile(count_out)
        _,previous=_read_csv(count_out)
        for row in previous; push!(get!(old_counts,(row["database_id"],parse(Float64,row["minsup_fraction"])),Dict{String,String}[]),row); end
    end
    if isfile(perf_out)
        _,previous=_read_csv(perf_out)
        for row in previous; push!(get!(old_perf,(row["database_id"],parse(Float64,row["minsup_fraction"])),Dict{String,String}[]),row); end
    end
    resume=Bool(get(get(ctx.config,"run",Dict{String,Any}()),"resume",true))
    config_hash=_sha256(ctx.config_path)
    engine_hash=_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl"))
    adapter_hash=_sha256(joinpath(ctx.repo_root,"src","eda2","FashionMNISTEDA2.jl"))
    for (k,seed) in selected, variant in VARIANTS, minsup in minsups
        println("C3 Eclat: K=$k seed=$seed variant=$variant minsup=$minsup")
        flush(stdout)
        spec=first(filter(s->s.k==k && s.seed==seed && s.variant==variant,ctx.specs))
        txpath=joinpath(spec.run_dir,"transactions.jsonl")
        source_hash=_input_transaction_hash(txpath)
        count=ceil(Int,minsup*EXPECTED_IMAGES)
        key=(spec.database_id,minsup)
        if resume && haskey(old_runs,key)
            old=old_runs[key]
            output_file=isempty(old["output_ref"]) ? "" : output_path(ctx,split(old["output_ref"],'/')...)
            if old["source_sha256"]==source_hash && old["config_sha256"]==config_hash && old["engine_source_sha256"]==engine_hash && old["adapter_source_sha256"]==adapter_hash && old["completion_status"]=="COMPLETED_LENGTH_CAPPED" &&
                isfile(output_file) && _sha256(output_file)==old["output_sha256"]
                push!(run_rows,[old[h] for h in run_header])
                for row in get(old_counts,key,Dict{String,String}[]); push!(count_rows,[row[h] for h in count_header]); end
                for row in get(old_perf,key,Dict{String,String}[]); push!(performance_rows,[row[h] for h in perf_header]); end
                _write_csv(run_out,run_header,run_rows)
                _write_csv(count_out,count_header,count_rows)
                _write_csv(perf_out,perf_header,performance_rows)
                continue
            end
        end
        _,warmup_status,warmup_runtime=_mine_lengths(txpath,count,max_len,timeout,max_sets)
        push!(performance_rows,[spec.database_id,k,seed,variant,minsup,"warmup",0,warmup_status,warmup_runtime,"",false])
        if warmup_status!="COMPLETED_LENGTH_CAPPED"
            push!(run_rows,[spec.database_id,source_hash,config_hash,k,seed,variant,minsup,count,max_len,"SKIPPED_WARMUP",warmup_status,warmup_runtime,"","","","","",
                "NOT_EXACT",0,engine_hash,adapter_hash])
            _write_csv(run_out,run_header,run_rows); _write_csv(count_out,count_header,count_rows); _write_csv(perf_out,perf_header,performance_rows)
            continue
        end
        repetitions=Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"deep_repetitions",3))
        outputs=Dict{Tuple{Vararg{Int}},Int}[]; statuses=String[]; runtimes=Float64[]
        for rep in 1:repetitions
            sets,status,elapsed=_mine_lengths(txpath,count,max_len,timeout,max_sets)
            push!(statuses,status); push!(runtimes,elapsed)
            push!(performance_rows,[spec.database_id,k,seed,variant,minsup,"measured",rep,status,elapsed,"",false])
            !isnothing(sets) && push!(outputs,sets)
            status in ("TIMEOUT","ITEMSET_LIMIT","FAILED") && break
        end
        status=all(==("COMPLETED_LENGTH_CAPPED"),statuses) ? "COMPLETED_LENGTH_CAPPED" : last(statuses)
        exact=length(outputs)==repetitions && all(==(first(outputs)),outputs)
        outref=""
        if exact
            outref=joinpath("pilot_eclat","itemsets","$(spec.database_id)","minsup_$(replace(string(minsup),"."=>"p")).csv")
            rows=[[join(key," "),length(key),support] for (key,support) in sort!(collect(first(outputs));by=x->(length(first(x)),first(x)))]
            _write_csv(output_path(ctx,split(outref,'/')...),["itemset","length","support_count"],rows)
            counts=Dict{Int,Int}(); for key in keys(first(outputs)); counts[length(key)]=get(counts,length(key),0)+1; end
            for len in 1:max_len; push!(count_rows,[spec.database_id,k,seed,variant,minsup,count,get(counts,len,0),status]); end
        end
        output_hash=isempty(outref) ? "" : _sha256(output_path(ctx,split(outref,'/')...))
        push!(run_rows,[spec.database_id,source_hash,config_hash,k,seed,variant,minsup,count,max_len,status,warmup_status,warmup_runtime,median(runtimes),maximum(runtimes),"",outref,output_hash,
            "NOT_EXACT",repetitions,engine_hash,adapter_hash])
        _write_csv(run_out,run_header,run_rows); _write_csv(count_out,count_header,count_rows); _write_csv(perf_out,perf_header,performance_rows)
    end
    _write_csv(output_path(ctx,"pilot_eclat","performance_summary.csv"),
        run_header,run_rows)
    completed_runs=count(r->r[10]=="COMPLETED_LENGTH_CAPPED",run_rows)
    open(output_path(ctx,"pilot_eclat","pilot_deep_validation_report.toml"),"w") do io
        TOML.print(io,Dict("expected_runs"=>length(selected)*length(VARIANTS)*length(minsups),"rows_written"=>length(run_rows),
            "completed_length_capped_runs"=>completed_runs,"selected_codebooks"=>length(selected),"variants_per_codebook"=>length(VARIANTS),
            "minsup_fractions"=>minsups,"max_itemset_length"=>max_len,"repetitions_configured"=>Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"deep_repetitions",3)),
            "memory_cap_enforced"=>false,"peak_rss_measured"=>false,"closed_maximal_status"=>"NOT_EXACT",
            "config_sha256"=>config_hash,"engine_source_sha256"=>engine_hash,"adapter_source_sha256"=>adapter_hash))
    end
    _record_phase!(ctx,"pilot_c3",completed_runs==length(run_rows) ? "COMPLETED_LENGTH_CAPPED" : "COMPLETED_WITH_CENSORING",
        Dict("runs"=>length(run_rows),"completed_length_capped"=>completed_runs,"selected_codebooks"=>length(selected)))
    return (runs=length(run_rows),selected=length(selected))
end

function _decode_item(variant,item,k)
    if variant=="S0"
        return "word_$item"
    elseif variant=="S1"
        region=(item-1)÷k+1; word=(item-1)%k+1
        return "region$(region)_word$(word)"
    elseif variant=="S3"
        stripe=(item-1)÷k+1; word=(item-1)%k+1
        label=("TOP","MIDDLE","BOTTOM")[stripe]
        return "$(label)_word$(word)"
    else
        throw(ArgumentError("Unsupported EDA2 variant: $variant"))
    end
end

function prepare_pattern_review!(ctx::EDA2Context)
    deep_path=output_path(ctx,"pilot_eclat","pilot_deep_runs.csv")
    isfile(deep_path) || error("Run C3 before preparing pattern review")
    _,deep_rows=_read_csv(deep_path)
    selected=_read_decisions(ctx)
    selection_rows,interpretation_rows=Vector{Vector{Any}}(),Vector{Vector{Any}}()
    for (k,seed) in selected, variant in VARIANTS
        database_id="B0_K$(k)_seed$(seed)_$(variant)"
        run=first(filter(r->r["database_id"]==database_id && parse(Float64,r["minsup_fraction"])==0.03,deep_rows))
        run["completion_status"]=="COMPLETED_LENGTH_CAPPED" || continue
        isempty(run["output_ref"]) && continue
        itemset_path=output_path(ctx,split(run["output_ref"],'/')...)
        _,item_rows=_read_csv(itemset_path)
        by_length=Dict{Int,Vector{Tuple{Vector{Int},Int}}}()
        for row in item_rows
            items=parse.(Int,split(row["itemset"],' ')); support=parse(Int,row["support_count"])
            push!(get!(by_length,length(items),Tuple{Vector{Int},Int}[]),(items,support))
        end
        representatives=Vector{Tuple{String,Vector{Int},Int}}()
        for length_value in sort!(collect(keys(by_length)))
            candidates=sort!(by_length[length_value];by=x->(x[2],x[1]))
            for (band,q) in (("LOW",0.25),("MID",0.50),("HIGH",0.75))
                index=clamp(round(Int,q*(length(candidates)-1))+1,1,length(candidates))
                itemset,support=candidates[index]
                any(x->x[2]==itemset,representatives) || push!(representatives,(band,itemset,support))
            end
        end
        spec=first(filter(s->s.database_id==database_id,ctx.specs))
        example_tids=[Int[] for _ in representatives]
        txpath=joinpath(spec.run_dir,"transactions.jsonl")
        open(txpath,"r") do io
            for (tid,line) in enumerate(eachline(io))
                _,_,tx=_parse_transaction(line,txpath,tid)
                for (i,(_,itemset,_)) in enumerate(representatives)
                    length(example_tids[i])>=5 && continue
                    all(item->item in tx,itemset) && push!(example_tids[i],tid)
                end
                all(t->length(t)>=5,example_tids) && break
            end
        end
        for (i,(band,itemset,support)) in enumerate(representatives)
            pattern_id="$(database_id)_m003_l$(length(itemset))_$(band)"
            decoded=join([_decode_item(variant,item,k) for item in itemset],";")
            tids=join(example_tids[i],";")
            push!(selection_rows,[pattern_id,database_id,k,seed,variant,0.03,join(itemset," "),length(itemset),support,support/EXPECTED_IMAGES,band,
                "nearest p25/p50/p75 support quantile per itemset length"])
            push!(interpretation_rows,[pattern_id,database_id,k,seed,variant,join(itemset," "),decoded,support,support/EXPECTED_IMAGES,tids,"",
                "true",
                "pending","pending","pending","pending"])
        end
    end
    _write_csv(output_path(ctx,"interpretability","pattern_selection_manifest.csv"),
        ["pattern_id","database_id","K","seed","variant","minsup_fraction","itemset","length","support_count","support_fraction","support_band","selection_rule"],selection_rows)
    _write_csv(output_path(ctx,"interpretability","pattern_interpretability.csv"),
        ["pattern_id","database_id","K","seed","variant","itemset","decoded_items","support_count","support_fraction","example_tids","patch_coordinates","decodable","visual_coherence","nontriviality","redundancy","annotator_notes"],interpretation_rows)
    _record_phase!(ctx,"interpretability_review","PENDING_HUMAN_ANNOTATION",Dict("patterns"=>length(selection_rows)))
    return (patterns=length(selection_rows),)
end

function write_inconclusive_report!(ctx::EDA2Context)
    mkpath(output_path(ctx,"final"))
    metrics_path=output_path(ctx,"transactions","transaction_metrics_45.csv")
    diversity_path=output_path(ctx,"transactions","transaction_diversity_45.csv")
    similarity_path=output_path(ctx,"transactions","class_similarity_summary_45.csv")
    pilot_path=output_path(ctx,"pilot_eclat","pilot_common_45.csv")
    deep_path=output_path(ctx,"pilot_eclat","pilot_deep_runs.csv")
    pattern_path=output_path(ctx,"interpretability","pattern_interpretability.csv")
    shortlist_path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    metric_rows=isfile(metrics_path) ? last(_read_csv(metrics_path)) : Dict{String,String}[]
    manifest_rows=isfile(output_path(ctx,"input_manifest.csv")) ? last(_read_csv(output_path(ctx,"input_manifest.csv"))) : Dict{String,String}[]
    diversity_rows=isfile(diversity_path) ? last(_read_csv(diversity_path)) : Dict{String,String}[]
    similarity_rows=isfile(similarity_path) ? last(_read_csv(similarity_path)) : Dict{String,String}[]
    pilot_rows=isfile(pilot_path) ? last(_read_csv(pilot_path)) : Dict{String,String}[]
    deep_rows=isfile(deep_path) ? last(_read_csv(deep_path)) : Dict{String,String}[]
    pattern_rows=isfile(pattern_path) ? last(_read_csv(pattern_path)) : Dict{String,String}[]
    shortlist_rows=isfile(shortlist_path) ? last(_read_csv(shortlist_path)) : Dict{String,String}[]
    metrics_by_db=Dict(r["database_id"]=>r for r in metric_rows)
    diversity=Dict(r["database_id"]=>r for r in diversity_rows)
    similarity=Dict(r["database_id"]=>r for r in similarity_rows)
    pilot=Dict(r["database_id"]=>r for r in pilot_rows)
    deep_by_db=Dict{String,Vector{Dict{String,String}}}(); for r in deep_rows; push!(get!(deep_by_db,r["database_id"],Dict{String,String}[]),r); end
    pattern_count=Dict{String,Int}(); for r in pattern_rows; pattern_count[r["database_id"]]=get(pattern_count,r["database_id"],0)+1; end
    selected_keys=Set("B0_K$(r["K"])_seed$(r["seed"])" for r in shortlist_rows if lowercase(r["selected"])=="true")
    shortlist_by_key=Dict("B0_K$(r["K"])_seed$(r["seed"])"=>r for r in shortlist_rows)
    comparison=Vector{Vector{Any}}()
    base_rows=isempty(manifest_rows) ? metric_rows : manifest_rows
    for base in base_rows
        dbid=base["database_id"]; m=get(metrics_by_db,dbid,Dict{String,String}())
        d=get(diversity,dbid,Dict{String,String}()); s=get(similarity,dbid,Dict{String,String}()); p=get(pilot,dbid,Dict{String,String}())
        deep=get(deep_by_db,dbid,Dict{String,String}[])
        deep_complete=isempty(deep) ? "" : count(r->r["completion_status"]=="COMPLETED_LENGTH_CAPPED",deep)
        deep_censored=isempty(deep) ? "" : count(r->r["completion_status"] in ("TIMEOUT","ITEMSET_LIMIT","FAILED","SKIPPED_WARMUP"),deep)
        deep_times=[parse(Float64,r["runtime_median_s"]) for r in deep if !isempty(r["runtime_median_s"])]
        k=get(m,"K",get(base,"K","")); seed=get(m,"seed",get(base,"seed","")); variant=get(m,"variant",get(base,"variant",""))
        shortlist_key="B0_K$(k)_seed$(seed)"
        decision=get(shortlist_by_key,shortlist_key,Dict{String,String}())
        source_status=get(base,"status",get(m,"integrity_status","NOT_RUN"))
        pattern_rows_value=isfile(pattern_path) ? get(pattern_count,dbid,0) : ""
        shortlist_selected=isfile(shortlist_path) ? shortlist_key in selected_keys : ""
        label_informed=isempty(decision) ? "" : get(decision,"label_informed_selection","false")
        closed_status=isempty(deep) ? "NOT_RUN" : "NOT_EXACT"
        interpretability_status=!isfile(pattern_path) ? "NOT_RUN" : get(pattern_count,dbid,0)>0 ? "PENDING_HUMAN_REVIEW" : "NO_COMPLETED_PATTERN_FAMILY"
        push!(comparison,[dbid,get(base,"run_path",""),get(base,"transactions_path",""),get(base,"source_sha256",""),
            k,seed,variant,source_status,get(m,"empty_rate",""),get(m,"mean_length",""),get(m,"density_theoretical",""),
            get(d,"jaccard_mean",""),get(s,"within_mean_jaccard",""),get(s,"between_mean_jaccard",""),get(s,"separation_gap",""),
            get(s,"pair_discrimination_auc",""),get(p,"status","NOT_RUN"),get(p,"frequent_1_count",""),get(p,"frequent_2_count",""),
            deep_complete,deep_censored,isempty(deep_times) ? "" : median(deep_times),pattern_rows_value,
            shortlist_selected,closed_status,interpretability_status,label_informed,"INCONCLUSIVE"])
    end
    _write_csv(output_path(ctx,"final","comparative_summary.csv"),
        ["database_id","run_path","transactions_path","source_sha256","K","seed","variant","integrity_status","empty_rate","mean_length","density_theoretical","jaccard_mean","within_mean_jaccard_posthoc","between_mean_jaccard_posthoc","class_similarity_gap_posthoc","class_similarity_auc_posthoc","c1_status","c1_frequent_1_count","c1_frequent_2_count","c3_completed_runs","c3_censored_runs","c3_median_runtime_s","interpretability_patterns","shortlist_selected","closed_maximal_status","interpretability_status","label_informed_selection","decision_status"],comparison)
    _write_csv(output_path(ctx,"final","tradeoff_candidates.csv"),
        ["database_id","run_path","transactions_path","source_sha256","K","seed","variant","integrity_status","empty_rate","mean_length","density_theoretical","jaccard_mean","within_mean_jaccard_posthoc","between_mean_jaccard_posthoc","class_similarity_gap_posthoc","class_similarity_auc_posthoc","c1_status","c1_frequent_1_count","c1_frequent_2_count","c3_completed_runs","c3_censored_runs","c3_median_runtime_s","interpretability_patterns","shortlist_selected","closed_maximal_status","interpretability_status","label_informed_selection","decision_status"],comparison)
    open(output_path(ctx,"final","final_selection.md"),"w") do io
        println(io,"# EDA2 final selection\n")
        println(io,"**Status: INCONCLUSIVE.** This status remains until the required EDA2 evidence and human review are complete.\n")
        println(io,"The notebook does not select a configuration from distortion, raw itemset count, or class-label similarity alone. Review `pilot_eclat/shortlist_decision.csv`, C3 results and interpretability evidence before recording a final choice.\n")
        println(io,"Source transaction databases and codebooks remain read-only.")
    end
    open(output_path(ctx,"final","EDA2_summary_report.md"),"w") do io
        println(io,"# EDA2 summary\n\nDecision status: **INCONCLUSIVE**.\n")
        println(io,"Generated from the checked input manifest and completed analysis phases. Missing, censored, or unreviewed phases are not interpreted as zero-quality results. See `validation_report.toml` and pilot status tables.")
    end
    _record_phase!(ctx,"final_decision","INCONCLUSIVE",Dict("comparative_rows"=>length(comparison),"automated_winner_selected"=>false))
    return output_path(ctx,"final","final_selection.md")
end

end # module
