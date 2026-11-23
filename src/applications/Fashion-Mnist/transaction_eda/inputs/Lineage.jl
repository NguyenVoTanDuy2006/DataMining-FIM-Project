const VERIFIED_LINEAGE_SOURCES = Dict{String,String}()
const INPUT_TRANSACTION_HASHES = Dict{String,String}()

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
