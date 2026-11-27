const VERIFIED_LINEAGE_SOURCES = Dict{String,String}()
const INPUT_TRANSACTION_HASHES = Dict{String,String}()
const EXPECTED_SPATIAL_SOURCE_FILES = Set((
    "patch_assignments.csv", "transactions.jsonl", "tid_image_mapping.csv",
    "config_snapshot.toml", "integrity_report.toml", "checkpoint.toml",
    "codebook.bin", "tc4_metrics.toml",
))

function _validate_source_lineage_hashes(source_hashes)
    source_hashes isa AbstractDict || error("Spatial source lineage sha256 must be a table")
    names = Set(String(name) for name in keys(source_hashes))
    names == EXPECTED_SPATIAL_SOURCE_FILES ||
        error("Spatial source lineage must checksum exactly the expected S0 artifacts")
    for (name, digest) in source_hashes
        filename = String(name)
        filename == basename(filename) && filename in EXPECTED_SPATIAL_SOURCE_FILES ||
            error("Unexpected spatial lineage source filename: $filename")
        digest isa AbstractString && occursin(r"^[0-9a-f]{64}$", digest) ||
            error("Invalid S0 lineage SHA-256 for $filename")
    end
    return Dict(String(name) => String(digest) for (name, digest) in source_hashes)
end

function _validate_spatial_config_snapshot(config, variant, k, seed, source_run_id, run_id)
    get(config, "encoding_version", "") == "tc6-spatial-v1.0" ||
        error("Unsupported spatial encoding version")
    get(config, "variant", "") == variant && get(config, "run_id", "") == run_id ||
        error("Spatial config snapshot run identity mismatch")
    get(config, "source_run_id", "") == source_run_id || error("Spatial config S0 source identity mismatch")
    get(config, "k", 0) == k && get(config, "seed", -1) == seed ||
        error("Spatial config snapshot K/seed mismatch")
    get(config, "transaction_count", 0) == EXPECTED_IMAGES &&
        get(config, "support_denominator", 0) == EXPECTED_IMAGES ||
        error("Spatial config snapshot denominator is not 70,000")
    get(config, "method_alias", "") == "B0" &&
        get(config, "training_method", "") == "raw_full_batch_kmeans" ||
        error("Spatial config snapshot does not preserve the S0 training method")
    get(config, "labels_in_items", true) == false && get(config, "transaction_format", "") == "jsonl" ||
        error("Spatial config snapshot violates the transaction contract")

    rules = get(config, "spatial_rules", nothing)
    rules isa AbstractDict || error("Spatial config snapshot is missing spatial_rules")
    expected_s1 = Dict{String,Any}("row_break_after" => 3, "col_break_after" => 3,
        "region_layout" => ["top_left", "top_right", "bottom_left", "bottom_right"],
        "item_id_formula" => "(region_id - 1) * K + word_id")
    expected_s3 = Dict{String,Any}("rows_per_stripe" => [2, 3, 2],
        "item_id_formula" => "(stripe_id - 1) * K + word_id")
    expected_s6b = Dict{String,Any}("relation_types" => ["ABOVE", "LEFT_OF"],
        "min_manhattan_distance" => 1, "max_manhattan_distance" => 2,
        "same_word_on_distinct_patches" => true,
        "item_id_formula" => "(relation_index - 1) * K^2 + (word_a - 1) * K + word_b")
    get(rules, "s1", nothing) == expected_s1 || error("Spatial S1 layout rules are incompatible")
    get(rules, "s3", nothing) == expected_s3 || error("Spatial S3 layout rules are incompatible")
    get(rules, "s6b", nothing) == expected_s6b || error("Spatial S6-B neighbor rules are incompatible")
    return true
end

_sha256(path) = bytes2hex(open(sha256, path))
function _input_transaction_hash(path)
    if isfile(path) && !haskey(INPUT_TRANSACTION_HASHES,path)
        INPUT_TRANSACTION_HASHES[path]=_sha256(path)
    end
    return get(INPUT_TRANSACTION_HASHES,path,"")
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
        source_hashes=_validate_source_lineage_hashes(get(lineage,"sha256",nothing))
        for (filename,expected_hash) in source_hashes
            source_path=joinpath(spec.source_dir,filename)
            islink(source_path) && error("Spatial lineage source file must not be a symbolic link: $source_path")
            isfile(source_path) || error("Spatial lineage source file is missing: $source_path")
            if haskey(VERIFIED_LINEAGE_SOURCES,source_path)
                VERIFIED_LINEAGE_SOURCES[source_path]==expected_hash || error("Conflicting lineage checksum: $source_path")
            else
                _sha256(source_path)==expected_hash || error("Spatial lineage checksum mismatch: $source_path")
                VERIFIED_LINEAGE_SOURCES[source_path]=String(expected_hash)
            end
        end
        spatial_config=TOML.parsefile(joinpath(spec.run_dir,"config_snapshot.toml"))
        _validate_spatial_config_snapshot(spatial_config, spec.variant, spec.k, spec.seed,
            basename(spec.source_dir), basename(spec.run_dir))
        tx_path = joinpath(spec.run_dir, "transactions.jsonl")
        item_mapping_path = joinpath(spec.run_dir, "item_mapping.csv")
        tid_mapping_path = joinpath(spec.run_dir, "tid_image_mapping.csv")
        get(integrity, "variant", "") == spec.variant &&
            get(integrity, "source_run_id", "") == basename(spec.source_dir) &&
            get(integrity, "k", 0) == spec.k && get(integrity, "seed", -1) == spec.seed ||
            error("Spatial integrity report identity mismatch")
        get(checkpoint, "variant", "") == spec.variant &&
            get(checkpoint, "source_run_id", "") == basename(spec.source_dir) &&
            get(checkpoint, "k", 0) == spec.k && get(checkpoint, "seed", -1) == spec.seed ||
            error("Spatial checkpoint identity mismatch")
        get(integrity, "transaction_sha256", "") == _sha256(tx_path) &&
            get(checkpoint, "transaction_sha256", "") == _sha256(tx_path) ||
            error("Spatial transaction checksum mismatch")
        get(checkpoint, "integrity_report_sha256", "") ==
            _sha256(joinpath(spec.run_dir, "integrity_report.toml")) ||
            error("Spatial integrity report checksum mismatch")
        get(integrity, "item_mapping_sha256", "") == _sha256(item_mapping_path) ||
            error("Spatial item mapping checksum mismatch")
        get(integrity, "source_transaction_sha256", "") == source_hashes["transactions.jsonl"] &&
            get(integrity, "source_mapping_sha256", "") == source_hashes["tid_image_mapping.csv"] &&
            _sha256(tid_mapping_path) == source_hashes["tid_image_mapping.csv"] ||
            error("Spatial output source transaction or image mapping lineage mismatch")
        checks=get(integrity,"checks",Dict{String,Any}())
        for key in ("tid_mapping_matches_source","support_denominator_valid","items_sorted_unique_in_range",
            "source_checkpoint_completed","transaction_readback_valid","source_integrity_pass",
            "item_mapping_roundtrip_valid","variant_specific_invariant_valid")
            get(checks,key,false)==true || error("$(spec.database_id) integrity check $key is not PASS")
        end
        if spec.variant == "S6-B"
            for key in ("s6b_in_bounds_no_wrap_valid", "s6b_boundary_counts_within_capacity")
                get(checks, key, false) == true || error("$(spec.database_id) integrity check $key is not PASS")
            end
        end
        map_header, map_rows = _read_csv(joinpath(spec.run_dir, "item_mapping.csv"))
        required = spec.variant == "S1" ?
            ("item_id", "variant", "item_kind", "region_id", "word_id") :
            spec.variant == "S3" ?
            ("item_id", "variant", "item_kind", "stripe_id", "word_id") :
            ("item_id", "variant", "item_kind", "relation_type", "word_a", "word_b")
        all(in(map_header),required) || error("Spatial item mapping schema mismatch: $(spec.run_dir)")
        mapped=Set{Int}()
        for row in map_rows
            item=parse(Int,row["item_id"])
            item in mapped && error("Duplicate item mapping for item $item in $(spec.run_dir)")
            push!(mapped,item)
            row["variant"]==spec.variant || error("Item mapping variant mismatch for item $item")
            if spec.variant=="S1"
                row["item_kind"] == "region_word" || error("S1 item kind mismatch for item $item")
                region,word=parse(Int,row["region_id"]),parse(Int,row["word_id"])
                item==(region-1)*spec.k+word || error("S1 item mapping formula mismatch for item $item")
                1<=region<=4 && 1<=word<=spec.k || error("S1 item mapping field out of range")
            elseif spec.variant == "S3"
                row["item_kind"] == "stripe_word" || error("S3 item kind mismatch for item $item")
                stripe,word=parse(Int,row["stripe_id"]),parse(Int,row["word_id"])
                item==(stripe-1)*spec.k+word || error("S3 item mapping formula mismatch for item $item")
                1<=stripe<=3 && 1<=word<=spec.k || error("S3 item mapping field out of range")
            else
                row["item_kind"] == "relation" || error("S6-B item kind mismatch for item $item")
                relation = row["relation_type"] == "ABOVE" ? 1 :
                    row["relation_type"] == "LEFT_OF" ? 2 : 0
                a, b = parse(Int, row["word_a"]), parse(Int, row["word_b"])
                relation != 0 && 1 <= a <= spec.k && 1 <= b <= spec.k ||
                    error("S6-B relation mapping fields out of range for item $item")
                item == (relation - 1) * spec.k^2 + (a - 1) * spec.k + b ||
                    error("S6-B item mapping formula mismatch for item $item")
            end
        end
        if spec.variant != "S6-B"
            expected_mapping=Set(1:_theoretical_size(spec.variant,spec.k))
            mapped==expected_mapping || error("Spatial item mapping is incomplete or out of range: $(spec.run_dir)")
        end
    end
    return integrity
end
