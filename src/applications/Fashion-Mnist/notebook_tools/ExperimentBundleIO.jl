module ExperimentBundleIO

using CodecZlib
using Dates
using SHA
using Tar
using TOML

export validate_relative_path, write_bundle, read_bundle, write_s0_source_bundle,
    build_tc6_handoff, file_inventory, archive_sha256,
    write_fit_checkpoint_bundle, restore_fit_checkpoint_bundle!,
    write_eda2_stage_bundle, write_full_experiment_bundle

const SCHEMA_VERSION = 1
const EXPECTED_K = (16, 32, 64, 128, 256)
const EXPECTED_SEEDS = (42, 123, 2026)
const EXPECTED_IMAGES = 70_000
const SPATIAL_VARIANTS = ("S1", "S3", "S6-B")
const S0_REQUIRED_FILES = (
    "patch_assignments.csv", "transactions.jsonl", "tid_image_mapping.csv",
    "image_metadata.csv", "config_snapshot.toml", "integrity_report.toml",
    "checkpoint.toml", "codebook.bin", "tc4_metrics.toml",
)

"""Validate a relative POSIX bundle path and return its canonical spelling."""
function validate_relative_path(path::AbstractString)
    value = String(path)
    isempty(value) && throw(ArgumentError("Bundle paths cannot be empty"))
    isabspath(value) && throw(ArgumentError("Bundle path must be relative: $value"))
    occursin('\\', value) && throw(ArgumentError("Bundle paths must use POSIX separators: $value"))
    occursin(':', value) && throw(ArgumentError("Bundle path contains a drive or stream marker: $value"))
    occursin('\0', value) && throw(ArgumentError("Bundle path contains a NUL byte"))
    parts = split(value, '/'; keepempty=true)
    any(part -> part in ("", ".", ".."), parts) &&
        throw(ArgumentError("Bundle path contains an empty, dot, or parent component: $value"))
    return value
end

archive_sha256(path::AbstractString) = bytes2hex(open(sha256, path))

function file_inventory(root::AbstractString; exclude=Set(["manifest.toml"]))
    base = abspath(String(root))
    isdir(base) || throw(ArgumentError("Bundle root does not exist: $base"))
    rows = Dict{String,Any}[]
    seen = Set{String}()
    for (directory, dirs, files) in walkdir(base; follow_symlinks=false)
        for name in dirs
            path = joinpath(directory, name)
            islink(path) && throw(ArgumentError("Bundle source contains a symbolic link: $path"))
        end
        for name in files
            full_path = joinpath(directory, name)
            islink(full_path) && throw(ArgumentError("Bundle source contains a symbolic link: $full_path"))
            isfile(full_path) || throw(ArgumentError("Unsupported bundle source member: $full_path"))
            relative = validate_relative_path(replace(relpath(full_path, base), '\\' => '/'))
            relative in exclude && continue
            relative in seen && throw(ArgumentError("Duplicate bundle path: $relative"))
            push!(seen, relative)
            push!(rows, Dict{String,Any}(
                "path" => relative,
                "size_bytes" => filesize(full_path),
                "sha256" => bytes2hex(open(sha256, full_path)),
            ))
        end
    end
    sort!(rows; by=row -> row["path"])
    return rows
end

function _validate_manifest_inventory!(root::String, manifest::Dict{String,Any}, headers)
    get(manifest, "schema_version", 0) == SCHEMA_VERSION ||
        throw(ArgumentError("Unsupported bundle schema_version=$(get(manifest, "schema_version", "missing")); expected $SCHEMA_VERSION"))
    kind = get(manifest, "bundle_kind", "")
    kind in ("fashion_s0_source", "fashion_tc6_spatial_handoff", "fashion_eda2_analysis",
        "fashion_eda2_checkpoint", "fashion_eda2_stage", "fashion_full_experiment") ||
        throw(ArgumentError("Unsupported bundle_kind: $kind"))
    entries = get(manifest, "files", nothing)
    entries isa Vector || throw(ArgumentError("Bundle manifest must contain a files array"))

    listed = Dict{String,Tuple{Int,String}}()
    for entry in entries
        entry isa AbstractDict || throw(ArgumentError("Malformed bundle file inventory entry"))
        relative = validate_relative_path(get(entry, "path", ""))
        haskey(listed, relative) && throw(ArgumentError("Duplicate path in bundle manifest: $relative"))
        size = get(entry, "size_bytes", -1)
        size isa Integer && size >= 0 || throw(ArgumentError("Invalid size_bytes for $relative"))
        digest = get(entry, "sha256", "")
        digest isa AbstractString && occursin(r"^[0-9a-f]{64}$", digest) ||
            throw(ArgumentError("Invalid SHA-256 digest for $relative"))
        push!(listed, relative => (Int(size), String(digest)))
    end

    members = Dict{String,Symbol}()
    for header in headers
        raw_path = header.type == :directory && endswith(header.path, "/") ? chop(header.path; tail=1) : header.path
        path = validate_relative_path(raw_path)
        haskey(members, path) && throw(ArgumentError("Duplicate normalized archive path: $path"))
        header.type in (:file, :directory) ||
            throw(ArgumentError("Unsupported archive member type $(header.type): $path"))
        header.size >= 0 || throw(ArgumentError("Negative archive member size: $path"))
        members[path] = header.type
    end
    get(members, "manifest.toml", nothing) == :file ||
        throw(ArgumentError("Bundle must contain a root manifest.toml file"))
    regular = Set(path for (path, kind) in members if kind == :file && path != "manifest.toml")
    Set(keys(listed)) == regular || begin
        missing = sort!(collect(setdiff(regular, Set(keys(listed)))))
        unlisted = sort!(collect(setdiff(Set(keys(listed)), regular)))
        throw(ArgumentError("Bundle file inventory mismatch; missing=$missing unlisted=$unlisted"))
    end
    for (relative, (size, digest)) in listed
        full_path = joinpath(root, split(relative, '/')...)
        isfile(full_path) || throw(ArgumentError("Missing bundle file: $relative"))
        filesize(full_path) == size || throw(ArgumentError("Size mismatch for bundle file: $relative"))
        bytes2hex(open(sha256, full_path)) == digest ||
            throw(ArgumentError("SHA-256 mismatch for bundle file: $relative"))
    end
    return manifest
end

function _validate_local_inventory!(root::String, manifest::Dict{String,Any})
    entries = get(manifest, "files", Any[])
    entries isa Vector || throw(ArgumentError("Source bundle manifest must contain a files array"))
    expected = Dict{String,Tuple{Int,String}}()
    for entry in entries
        entry isa AbstractDict || throw(ArgumentError("Malformed source bundle inventory entry"))
        relative = validate_relative_path(entry["path"])
        haskey(expected, relative) && throw(ArgumentError("Duplicate source bundle path: $relative"))
        expected[relative] = (Int(entry["size_bytes"]), String(entry["sha256"]))
        path = joinpath(root, split(relative, '/')...)
        isfile(path) || throw(ArgumentError("Missing source bundle file: $relative"))
        filesize(path) == entry["size_bytes"] || throw(ArgumentError("Source bundle size mismatch: $relative"))
        bytes2hex(open(sha256, path)) == entry["sha256"] ||
            throw(ArgumentError("Source bundle SHA-256 mismatch: $relative"))
    end
    actual = Dict(String(row["path"]) => (Int(row["size_bytes"]), String(row["sha256"]))
        for row in file_inventory(root))
    expected == actual || throw(ArgumentError("Source bundle inventory does not match the files on disk"))
    return true
end

function _validate_s0_manifest!(root::String, manifest::Dict{String,Any})
    get(manifest, "expected_run_count", 0) == 15 ||
        throw(ArgumentError("S0 bundle expected_run_count must be 15"))
    get(manifest, "image_count_per_run", 0) == EXPECTED_IMAGES ||
        throw(ArgumentError("S0 bundle image_count_per_run must be 70,000"))
    runs = get(manifest, "runs", nothing)
    runs isa Vector && length(runs) == 15 ||
        throw(ArgumentError("S0 bundle must enumerate exactly 15 canonical source runs"))
    expected = Set("FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
        for k in EXPECTED_K for seed in EXPECTED_SEEDS)
    ids = String[]
    files = Set(row["path"] for row in manifest["files"])
    for run in runs
        run isa AbstractDict || throw(ArgumentError("Malformed S0 run manifest row"))
        run_id = String(get(run, "run_id", ""))
        push!(ids, run_id)
        run_id in expected || throw(ArgumentError("Unexpected S0 run identity: $run_id"))
        match_result = match(r"^FashionMNIST_T2_S0_B0_K(\d+)_seed(\d+)$", run_id)
        Int(get(run, "k", -1)) == parse(Int, match_result.captures[1]) &&
            Int(get(run, "seed", -1)) == parse(Int, match_result.captures[2]) ||
            throw(ArgumentError("S0 run K/seed fields do not match identity: $run_id"))
        status = String(get(run, "status", ""))
        status in ("COMPLETED", "FAILED", "MISSING") ||
            throw(ArgumentError("Unsupported S0 run status $status for $run_id"))
        prefix = "S0/$run_id/"
        run_files = filter(path -> startswith(path, prefix), collect(files))
        if status == "COMPLETED"
            get(run, "integrity", "") == "PASS" ||
                throw(ArgumentError("Completed S0 run is not integrity PASS: $run_id"))
            get(run, "image_count", 0) == EXPECTED_IMAGES ||
                throw(ArgumentError("Completed S0 run must contain 70,000 images: $run_id"))
            required = Set(prefix * name for name in S0_REQUIRED_FILES)
            issubset(required, Set(run_files)) ||
                throw(ArgumentError("Completed S0 run is missing required artifacts: $run_id"))
        elseif !isempty(run_files)
            throw(ArgumentError("Non-completed S0 run must not contain staged artifacts: $run_id"))
        end
    end
    Set(ids) == expected || throw(ArgumentError("S0 run identities are duplicated or incomplete"))
    expected_status = all(String(run["status"]) == "COMPLETED" for run in runs) ? "COMPLETED" : "PARTIAL"
    get(manifest, "status", "") == expected_status ||
        throw(ArgumentError("S0 bundle status does not match its run rows; expected $expected_status"))
    return manifest
end

function _expected_s0_run_id(k::Int, seed::Int)
    return "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
end

function _expected_variant_run_id(k::Int, seed::Int, variant::String)
    return replace(_expected_s0_run_id(k, seed), "_S0_" => "_$(replace(variant, "-" => ""))_")
end

function _validate_identity_statuses!(rows, variants; field, expected_count, root, transaction=true)
    rows isa Vector && length(rows) == expected_count ||
        throw(ArgumentError("$field must contain exactly $expected_count identity rows"))
    expected = Set((k, seed, variant) for k in EXPECTED_K for seed in EXPECTED_SEEDS for variant in variants)
    actual = Set{Tuple{Int,Int,String}}()
    for row in rows
        row isa AbstractDict || throw(ArgumentError("Malformed row in $field"))
        k, seed = Int(get(row, "k", -1)), Int(get(row, "seed", -1))
        variant = String(get(row, "variant", ""))
        key = (k, seed, variant)
        key in actual && throw(ArgumentError("Duplicate identity in $field: $key"))
        push!(actual, key)
        key in expected || throw(ArgumentError("Unexpected identity in $field: $key"))
        run_id = String(get(row, "run_id", ""))
        wanted_id = variant == "S0" ? _expected_s0_run_id(k, seed) : _expected_variant_run_id(k, seed, variant)
        run_id == wanted_id || throw(ArgumentError("Run identity mismatch in $field: $run_id"))
        get(row, "source_run_id", wanted_id) == _expected_s0_run_id(k, seed) ||
            throw(ArgumentError("Source lineage mismatch in $field for $run_id"))
        status = String(get(row, "status", ""))
        status in ("COMPLETED", "FAILED", "NOT_RUN") ||
            throw(ArgumentError("Unsupported status $status in $field for $run_id"))
        integrity = String(get(row, "integrity", ""))
        expected_integrity = status == "COMPLETED" ? "PASS" : status == "FAILED" ? "FAIL" : "NOT_CHECKED"
        integrity == expected_integrity || throw(ArgumentError("Status/integrity mismatch in $field for $run_id"))
        if transaction && status == "COMPLETED"
            get(row, "transaction_count", 0) == EXPECTED_IMAGES ||
                throw(ArgumentError("Completed transaction identity is not 70,000 records: $run_id"))
            folder = variant == "S6-B" ? "S6B" : variant
            path = variant == "S0" ? joinpath(root, "s0_source", "S0", run_id, "transactions.jsonl") :
                joinpath(root, folder, run_id, "transactions.jsonl")
            isfile(path) || throw(ArgumentError("Completed transaction artifact is missing: $path"))
        end
    end
    actual == expected || throw(ArgumentError("$field identities are incomplete"))
    return count(row -> get(row, "status", "") == "COMPLETED", rows)
end

function _validate_portable_eda2_database_manifest!(root::String)
    path = joinpath(root, "eda2_database_manifest.toml")
    isfile(path) || throw(ArgumentError("Final experiment bundle is missing eda2_database_manifest.toml"))
    manifest = TOML.parsefile(path)
    get(manifest, "profile", "") == "full" && get(manifest, "eda2_ready", false) == true &&
        get(manifest, "database_count", 0) == 60 ||
        throw(ArgumentError("Portable EDA2 database manifest must declare 60 full databases"))
    databases = get(manifest, "databases", nothing)
    databases isa Vector && length(databases) == 60 ||
        throw(ArgumentError("Portable EDA2 database manifest must list all 60 databases"))

    expected = Set((k, seed, variant) for k in EXPECTED_K for seed in EXPECTED_SEEDS
        for variant in ("S0", SPATIAL_VARIANTS...))
    seen = Set{Tuple{Int,Int,String}}()
    for database in databases
        variant = String(get(database, "variant", ""))
        k, seed = Int(get(database, "k", -1)), Int(get(database, "seed", -1))
        key = (k, seed, variant)
        key in expected && !(key in seen) ||
            throw(ArgumentError("Unexpected or duplicate EDA2 database identity: $key"))
        push!(seen, key)
        run_id = String(get(database, "database_id", ""))
        wanted_id = variant == "S0" ? _expected_s0_run_id(k, seed) :
            _expected_variant_run_id(k, seed, variant)
        run_id == wanted_id || throw(ArgumentError("EDA2 database run identity mismatch: $run_id"))

        transaction_rel = validate_relative_path(String(get(database, "transaction_path", "")))
        transaction_path = joinpath(root, split(transaction_rel, '/')...)
        isfile(transaction_path) || throw(ArgumentError("EDA2 transaction is missing: $transaction_rel"))
        get(database, "transaction_count", 0) == EXPECTED_IMAGES ||
            throw(ArgumentError("EDA2 transaction does not contain 70,000 records: $run_id"))
        bytes2hex(open(sha256, transaction_path)) == get(database, "transaction_sha256", "") ||
            throw(ArgumentError("EDA2 transaction checksum mismatch: $run_id"))

        for field in ("source_codebook_path", "source_run_path", "source_lineage")
            relative = validate_relative_path(String(get(database, field, "")))
            artifact = joinpath(root, split(relative, '/')...)
            (field == "source_run_path" ? isdir(artifact) : isfile(artifact)) ||
                throw(ArgumentError("EDA2 lineage artifact is missing: $relative"))
        end
        mapping = String(get(database, "item_mapping_ref", ""))
        if !startswith(mapping, "implicit:")
            relative = validate_relative_path(mapping)
            isfile(joinpath(root, split(relative, '/')...)) ||
                throw(ArgumentError("EDA2 item mapping is missing: $relative"))
        end
    end
    seen == expected || throw(ArgumentError("Portable EDA2 database identities are incomplete"))
    return manifest
end

function _validate_fit_checkpoint_manifest!(root::String, manifest::Dict{String,Any})
    get(manifest, "expected_fit_count", 0) == 15 ||
        throw(ArgumentError("Fit checkpoint must declare 15 expected fits"))
    statuses = get(manifest, "fit_statuses", nothing)
    statuses isa Vector && length(statuses) == 15 ||
        throw(ArgumentError("Fit checkpoint must enumerate all 15 K–seed identities"))
    expected = Set(_expected_s0_run_id(k, seed) for k in EXPECTED_K for seed in EXPECTED_SEEDS)
    actual = Set{String}()
    files = Set(String(entry["path"]) for entry in get(manifest, "files", Any[]))
    for row in statuses
        row isa AbstractDict || throw(ArgumentError("Malformed fit checkpoint status row"))
        run_id = String(get(row, "run_id", ""))
        run_id in expected || throw(ArgumentError("Unexpected fit checkpoint identity: $run_id"))
        run_id in actual && throw(ArgumentError("Duplicate fit checkpoint identity: $run_id"))
        push!(actual, run_id)
        match_result = match(r"^FashionMNIST_T2_S0_B0_K(\d+)_seed(\d+)$", run_id)
        Int(get(row, "k", -1)) == parse(Int, match_result.captures[1]) &&
            Int(get(row, "seed", -1)) == parse(Int, match_result.captures[2]) ||
            throw(ArgumentError("Fit checkpoint K/seed fields mismatch: $run_id"))
        status = String(get(row, "status", ""))
        status in ("COMPLETED", "FAILED", "NOT_RUN") ||
            throw(ArgumentError("Unsupported fit checkpoint status $status for $run_id"))
        if status == "COMPLETED"
            for name in ("checkpoint.toml", "codebook.bin", "tc4_metrics.toml", "config_snapshot.toml")
                relative = "fits/$run_id/$name"
                relative in files || throw(ArgumentError("Completed fit is missing $relative"))
                isfile(joinpath(root, split(relative, '/')...)) ||
                    throw(ArgumentError("Completed fit file is absent from archive: $relative"))
            end
            checkpoint = TOML.parsefile(joinpath(root, "fits", run_id, "checkpoint.toml"))
            get(checkpoint, "run_id", "") == run_id && get(checkpoint, "status", "") != "FAILED" ||
                throw(ArgumentError("Completed fit checkpoint identity/status mismatch: $run_id"))
            get(checkpoint, "codebook_sha256", "") == bytes2hex(open(sha256, joinpath(root, "fits", run_id, "codebook.bin"))) ||
                throw(ArgumentError("Fit checkpoint codebook checksum mismatch: $run_id"))
        end
    end
    actual == expected || throw(ArgumentError("Fit checkpoint identities are duplicated or incomplete"))
    for field in ("source_commit", "notebook_sha256", "configuration_sha256", "julia_version",
        "clustering_version", "preprocessing_fingerprint")
        value = String(get(manifest, field, ""))
        isempty(value) && throw(ArgumentError("Fit checkpoint is missing provenance field $field"))
    end
    dataset_hashes = get(manifest, "dataset_archive_sha256", nothing)
    dataset_hashes isa AbstractDict && length(dataset_hashes) == 4 ||
        throw(ArgumentError("Fit checkpoint must record hashes for all four dataset archives"))
    return manifest
end

function _validate_experiment_stage_manifest!(root::String, manifest::Dict{String,Any}; full::Bool)
    wanted_kind = full ? "fashion_full_experiment" : "fashion_eda2_stage"
    get(manifest, "bundle_kind", "") == wanted_kind || throw(ArgumentError("Unexpected experiment bundle kind"))
    get(manifest, "scope", "") == "S0_S1_S3_S6-B" ||
        throw(ArgumentError("Experiment bundle must include S0, S1, S3, and S6-B"))
    get(manifest, "expected_fit_count", 0) == 15 || throw(ArgumentError("Experiment bundle must declare 15 fits"))
    get(manifest, "expected_transaction_sets", 0) == 60 ||
        throw(ArgumentError("Experiment bundle must declare 60 transaction sets"))
    get(manifest, "expected_spatial_runs", 0) == 45 ||
        throw(ArgumentError("Experiment bundle must declare 45 spatial runs"))
    fit_statuses = get(manifest, "fit_statuses", nothing)
    fit_statuses isa Vector && length(fit_statuses) == 15 ||
        throw(ArgumentError("Experiment bundle must enumerate all 15 fits"))
    expected_fit_ids = Set(_expected_s0_run_id(k, seed) for k in EXPECTED_K for seed in EXPECTED_SEEDS)
    Set(String(row["run_id"]) for row in fit_statuses) == expected_fit_ids ||
        throw(ArgumentError("Experiment bundle fit identities are duplicated or incomplete"))

    nested_root = joinpath(root, "s0_source")
    nested_manifest_path = joinpath(nested_root, "manifest.toml")
    isfile(nested_manifest_path) || throw(ArgumentError("Experiment bundle is missing s0_source/manifest.toml"))
    nested_manifest = TOML.parsefile(nested_manifest_path)
    get(nested_manifest, "bundle_kind", "") == "fashion_s0_source" ||
        throw(ArgumentError("Nested S0 package has an unexpected bundle kind"))
    _validate_local_inventory!(nested_root, nested_manifest)
    _validate_s0_manifest!(nested_root, nested_manifest)

    transaction_variants = ("S0", SPATIAL_VARIANTS...)
    completed_transactions = _validate_identity_statuses!(get(manifest, "transaction_statuses", nothing),
        transaction_variants; field="transaction_statuses", expected_count=60, root)
    spatial_variants = SPATIAL_VARIANTS
    expected_spatial = 45
    completed_spatial = _validate_identity_statuses!(get(manifest, "spatial_statuses", nothing),
        spatial_variants; field="spatial_statuses", expected_count=expected_spatial, root, transaction=false)
    for row in manifest["spatial_statuses"]
        if get(row, "status", "") == "COMPLETED"
            variant = String(row["variant"])
            folder = variant == "S6-B" ? "S6B" : variant
            path = joinpath(root, folder, String(row["run_id"]), "transactions.jsonl")
            isfile(path) || throw(ArgumentError("Completed spatial transaction file is missing: $path"))
            get(row, "transaction_count", 0) == EXPECTED_IMAGES ||
                throw(ArgumentError("Completed spatial run is not 70,000 records"))
        end
    end
    isfile(joinpath(root, "spatial_extension_run_summary.toml")) ||
        throw(ArgumentError("Experiment bundle is missing spatial_extension_run_summary.toml"))
    if completed_spatial == 45
        _validate_portable_eda2_database_manifest!(root)
    elseif isfile(joinpath(root, "eda2_database_manifest.toml"))
        _validate_portable_eda2_database_manifest!(root)
    end
    get(manifest, "completed_transaction_sets", -1) == completed_transactions ||
        throw(ArgumentError("completed_transaction_sets disagrees with transaction statuses"))
    get(manifest, "completed_spatial_runs", -1) == completed_spatial ||
        throw(ArgumentError("completed_spatial_runs disagrees with spatial statuses"))
    get(manifest, "phase_statuses", nothing) isa AbstractDict ||
        throw(ArgumentError("Experiment bundle phase_statuses must be a table"))
    get(manifest, "status", "") in ("COMPLETED", "PARTIAL", "FAILED") ||
        throw(ArgumentError("Unsupported experiment bundle status"))
    return manifest
end

function _validate_kind!(root::String, manifest::Dict{String,Any})
    kind = manifest["bundle_kind"]
    if kind == "fashion_s0_source"
        _validate_s0_manifest!(root, manifest)
    elseif kind == "fashion_tc6_spatial_handoff"
        get(manifest, "scope", "") == "S0_S1_S3_S6-B" ||
            throw(ArgumentError("TC6 handoff scope must be S0_S1_S3_S6-B"))
        get(manifest, "expected_s0_runs", 0) == 15 && get(manifest, "expected_spatial_runs", 0) == 45 ||
            throw(ArgumentError("TC6 handoff must declare 15 S0 and 45 spatial runs"))
        for field in ("source_manifest_sha256", "input_archive_sha256", "producer_notebook_sha256", "producer_config_sha256")
            value = String(get(manifest, field, "UNRECORDED"))
            value == "UNRECORDED" || occursin(r"^[0-9a-f]{64}$", value) ||
                throw(ArgumentError("TC6 provenance field $field must be a lowercase SHA-256 digest or UNRECORDED"))
        end
        if get(manifest, "producer_config_sha256", "UNRECORDED") != "UNRECORDED"
            config_path = joinpath(root, "producer_runtime_config.toml")
            isfile(config_path) || throw(ArgumentError("TC6 handoff is missing producer_runtime_config.toml"))
            bytes2hex(open(sha256, config_path)) == manifest["producer_config_sha256"] ||
                throw(ArgumentError("TC6 producer runtime config checksum mismatch"))
        end
        source_runs = get(manifest, "source_runs", nothing)
        source_runs isa Vector && length(source_runs) == 15 ||
            throw(ArgumentError("TC6 handoff must enumerate all 15 S0 source runs"))
        source_ids = Set(String(run["run_id"]) for run in source_runs)
        expected_source_ids = Set(_canonical_s0_id(k, seed)
            for k in EXPECTED_K for seed in EXPECTED_SEEDS)
        source_ids == expected_source_ids ||
            throw(ArgumentError("TC6 handoff S0 source identities are duplicated or incomplete"))
        all(run -> get(run, "status", "") == "COMPLETED" &&
            get(run, "integrity", "") == "PASS" &&
            get(run, "image_count", 0) == EXPECTED_IMAGES, source_runs) ||
            throw(ArgumentError("TC6 handoff requires 15 completed, integrity-checked S0 sources"))
        for run in source_runs
            run_id = String(run["run_id"])
            match_result = match(r"^FashionMNIST_T2_S0_B0_K(\d+)_seed(\d+)$", run_id)
            isnothing(match_result) && throw(ArgumentError("Invalid TC6 S0 source identity: $run_id"))
            Int(run["k"]) == parse(Int, match_result.captures[1]) &&
                Int(run["seed"]) == parse(Int, match_result.captures[2]) ||
                throw(ArgumentError("TC6 S0 source K/seed fields do not match identity: $run_id"))
        end
        files = Set(String(row["path"]) for row in manifest["files"])
        for run_id in expected_source_ids
            required = Set("S0/$run_id/$name" for name in S0_REQUIRED_FILES)
            issubset(required, files) || throw(ArgumentError("TC6 handoff S0 source is incomplete: $run_id"))
        end
        runs = get(manifest, "spatial_runs", nothing)
        runs isa Vector && length(runs) == 45 ||
            throw(ArgumentError("TC6 handoff must enumerate all 45 expected spatial run/variant pairs"))
        expected = Set((k, seed, variant) for k in EXPECTED_K for seed in EXPECTED_SEEDS for variant in SPATIAL_VARIANTS)
        actual = Set((Int(run["k"]), Int(run["seed"]), String(run["variant"])) for run in runs)
        actual == expected || throw(ArgumentError("TC6 handoff spatial run identities are duplicated or incomplete"))
        for run in runs
            status = String(get(run, "status", ""))
            status in ("COMPLETED", "FAILED", "NOT_RUN") ||
                throw(ArgumentError("Unsupported TC6 spatial status $status for $(get(run, "run_id", "unknown"))"))
            expected_integrity = status == "COMPLETED" ? "PASS" : status == "FAILED" ? "FAIL" : "NOT_CHECKED"
            get(run, "integrity", "") == expected_integrity ||
                throw(ArgumentError("TC6 status/integrity mismatch for $(get(run, "run_id", "unknown"))"))
            source_run_id = _canonical_s0_id(Int(run["k"]), Int(run["seed"]))
            get(run, "source_run_id", "") == source_run_id ||
                throw(ArgumentError("TC6 spatial source lineage mismatch for $(get(run, "run_id", "unknown"))"))
            variant = String(run["variant"])
            expected_run_id = replace(source_run_id, "_S0_" => "_$(replace(variant, "-" => ""))_")
            get(run, "run_id", "") == expected_run_id ||
                throw(ArgumentError("TC6 spatial run identity does not match its source and variant: $(get(run, "run_id", "unknown"))"))
            if status == "COMPLETED"
                get(run, "integrity", "") == "PASS" &&
                    get(run, "transaction_count", 0) == EXPECTED_IMAGES ||
                    throw(ArgumentError("Completed TC6 run lacks 70,000 records or integrity PASS"))
                variant_root = String(run["variant"])
                run_prefix = "$variant_root/$(run["run_id"])/"
                run_prefix * "transactions.jsonl" in files ||
                    throw(ArgumentError("Completed TC6 run is missing its transaction file: $(run["run_id"])"))
            end
        end
        completed = count(run -> run["status"] == "COMPLETED", runs)
        get(manifest, "completed_spatial_runs", -1) == completed ||
            throw(ArgumentError("TC6 completed_spatial_runs disagrees with per-run statuses"))
        expected_status = completed == 45 ? "COMPLETED" : completed == 0 ? "FAILED" : "PARTIAL"
        get(manifest, "status", "") == expected_status ||
            throw(ArgumentError("TC6 handoff status disagrees with run rows; expected $expected_status"))
        eda2_ready = get(manifest, "eda2_ready", false)
        eda2_ready isa Bool || throw(ArgumentError("TC6 eda2_ready must be a Boolean"))
        if eda2_ready && !(completed == 45 && expected_status == "COMPLETED")
            throw(ArgumentError("TC6 handoff cannot be EDA2-ready unless all 45 spatial runs completed"))
        end
        database_manifest_path = "eda2_database_manifest.toml"
        if eda2_ready
            database_manifest_path in files ||
                throw(ArgumentError("EDA2-ready TC6 handoff is missing its database manifest"))
            database_manifest = TOML.parsefile(joinpath(root, database_manifest_path))
            get(database_manifest, "profile", "") == "full" &&
                get(database_manifest, "eda2_ready", false) == true &&
                get(database_manifest, "database_count", 0) == 60 ||
                throw(ArgumentError("TC6 database manifest does not declare 60 EDA2-ready inputs"))
            databases = get(database_manifest, "databases", Any[])
            length(databases) == 60 || throw(ArgumentError("TC6 database manifest must list 60 databases"))
            for database in databases
                relative = validate_relative_path(String(get(database, "transaction_path", "")))
                transaction_path = joinpath(root, split(relative, '/')...)
                isfile(transaction_path) ||
                    throw(ArgumentError("TC6 database manifest points outside the handoff inventory: $relative"))
                bytes2hex(open(sha256, transaction_path)) == get(database, "transaction_sha256", "") ||
                    throw(ArgumentError("TC6 database manifest transaction hash mismatch: $relative"))
            end
        elseif database_manifest_path in files
            throw(ArgumentError("TC6 handoff includes a finalized database manifest but is not marked EDA2-ready"))
        end
    elseif kind == "fashion_eda2_analysis"
        get(manifest, "scope", "") in ("S0_ONLY", "FULL_S0_S1_S3_S6B") ||
            throw(ArgumentError("EDA2 result bundle has an unsupported scope"))
        get(manifest, "status", "") in ("COMPLETED", "PARTIAL", "FAILED") ||
            throw(ArgumentError("EDA2 result bundle has an unsupported status"))
        phase_statuses = get(manifest, "phase_statuses", Dict{String,Any}())
        phase_statuses isa AbstractDict || throw(ArgumentError("EDA2 phase_statuses must be a table"))
        allowed_phases = ("COMPLETED", "COMPUTED", "PARTIAL", "FAILED", "COMPLETED_WITH_CENSORING",
            "AWAITING_HUMAN_REVIEW", "UNAVAILABLE", "NOT_REQUESTED")
        all(value -> value in allowed_phases, values(phase_statuses)) ||
            throw(ArgumentError("EDA2 phase_statuses contains an unsupported value"))
    elseif kind == "fashion_eda2_checkpoint"
        _validate_fit_checkpoint_manifest!(root, manifest)
    elseif kind == "fashion_eda2_stage"
        _validate_experiment_stage_manifest!(root, manifest; full=false)
    elseif kind == "fashion_full_experiment"
        _validate_experiment_stage_manifest!(root, manifest; full=true)
    end
    return manifest
end

function _tar_headers(archive_path::String)
    open(archive_path, "r") do compressed
        stream = GzipDecompressorStream(compressed)
        try
            return Tar.list(stream; raw=true, strict=false)
        finally
            close(stream)
        end
    end
end

function _extract_archive!(archive_path::String, destination::String)
    open(archive_path, "r") do compressed
        stream = GzipDecompressorStream(compressed)
        try
            Tar.extract(stream, destination; copy_symlinks=false, set_permissions=false)
        finally
            close(stream)
        end
    end
end

"""Safely validate and extract a `.tar.gz` bundle into a fresh staging directory."""
function read_bundle(archive_path::AbstractString; expected_kind=nothing, destination=nothing)
    archive = abspath(String(archive_path))
    islink(archive) && throw(ArgumentError("Bundle archive must not be a symbolic link: $archive"))
    isfile(archive) || throw(ArgumentError("Bundle archive not found: $archive"))
    headers = _tar_headers(archive)
    for header in headers
        raw_path = header.type == :directory && endswith(header.path, "/") ? chop(header.path; tail=1) : header.path
        validate_relative_path(raw_path)
        header.type in (:file, :directory) ||
            throw(ArgumentError("Unsupported archive member type $(header.type): $(header.path)"))
    end
    stage = isnothing(destination) ? mktempdir() : abspath(String(destination))
    if !isnothing(destination)
        ispath(stage) && throw(ArgumentError("Bundle staging path already exists: $stage"))
        mkpath(dirname(stage))
        mkdir(stage)
    end
    try
        _extract_archive!(archive, stage)
        manifest_path = joinpath(stage, "manifest.toml")
        isfile(manifest_path) || throw(ArgumentError("Bundle is missing root manifest.toml"))
        manifest = try
            TOML.parsefile(manifest_path)
        catch err
            throw(ArgumentError("Could not parse bundle manifest.toml: $(sprint(showerror, err))"))
        end
        _validate_manifest_inventory!(stage, manifest, headers)
        kind = get(manifest, "bundle_kind", "")
        !isnothing(expected_kind) && kind != expected_kind &&
            throw(ArgumentError("Expected bundle_kind=$expected_kind, received $kind"))
        _validate_kind!(stage, manifest)
        return (; root=stage, manifest, archive_sha256=archive_sha256(archive))
    catch
        rm(stage; recursive=true, force=true)
        rethrow()
    end
end

function _gzip_tar!(root::String, destination::String)
    open(destination, "w") do output
        stream = GzipCompressorStream(output)
        try
            Tar.create(root, stream; portable=true)
        finally
            close(stream)
        end
    end
    return destination
end

"""Write a directory as a checksummed, manifest-bearing `.tar.gz` bundle."""
function write_bundle(root::AbstractString, destination::AbstractString,
    fields::AbstractDict; preserve_manifest::Bool=false, overwrite::Bool=false)
    source = abspath(String(root))
    target = abspath(String(destination))
    isdir(source) || throw(ArgumentError("Bundle root does not exist: $source"))
    ispath(target) && !overwrite && throw(ArgumentError("Refusing to overwrite bundle archive: $target"))
    mkpath(dirname(target))
    manifest_path = joinpath(source, "manifest.toml")
    if preserve_manifest
        isfile(manifest_path) || throw(ArgumentError("preserve_manifest=true requires manifest.toml"))
    else
        manifest = Dict{String,Any}(String(k) => v for (k, v) in fields)
        manifest["schema_version"] = SCHEMA_VERSION
        manifest["files"] = file_inventory(source)
        open(manifest_path, "w") do io
            TOML.print(io, manifest)
        end
    end
    temp_target = target * ".tmp"
    try
        _gzip_tar!(source, temp_target)
        mv(temp_target, target; force=overwrite)
    catch
        rm(temp_target; force=true)
        rethrow()
    end
    return target
end

function _canonical_s0_id(k::Int, seed::Int)
    "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
end

function _source_revision(run_dir::String)
    for file in ("checkpoint.toml", "config_snapshot.toml")
        path = joinpath(run_dir, file)
        isfile(path) || continue
        data = try TOML.parsefile(path) catch; continue end
        for key in ("source_generation_revision", "source_revision", "source_commit")
            value = get(data, key, "")
            !isempty(string(value)) && return string(value)
        end
    end
    return "UNRECORDED"
end

function _completed_source_run(run_dir::String, run_id::String)
    islink(run_dir) && return (false, "source run directory is a symbolic link")
    for name in S0_REQUIRED_FILES
        islink(joinpath(run_dir, name)) && return (false, "required artifact is a symbolic link: $name")
    end
    missing = [name for name in S0_REQUIRED_FILES if !isfile(joinpath(run_dir, name))]
    isempty(missing) || return (false, "missing required files: $(join(missing, ", "))")
    checkpoint = TOML.parsefile(joinpath(run_dir, "checkpoint.toml"))
    integrity = TOML.parsefile(joinpath(run_dir, "integrity_report.toml"))
    get(checkpoint, "run_id", "") == run_id || return (false, "checkpoint run_id mismatch")
    get(checkpoint, "status", "") == "COMPLETED" || return (false, "checkpoint status is not COMPLETED")
    get(integrity, "status", "") == "PASS" || return (false, "integrity status is not PASS")
    get(integrity, "transaction_count", 0) == EXPECTED_IMAGES || return (false, "transaction count is not 70,000")
    return (true, "")
end

"""Package the canonical S0 source matrix without refitting or modifying its runs."""
function write_s0_source_bundle(source_root::AbstractString, destination::AbstractString;
    packaging_source_commit="UNRECORDED")
    input_root = abspath(String(source_root))
    islink(input_root) && throw(ArgumentError("S0 source root must not be a symbolic link: $input_root"))
    isdir(input_root) || throw(ArgumentError("S0 source root not found: $input_root"))
    stage = mktempdir()
    try
        s0_root = joinpath(stage, "S0")
        mkpath(s0_root)
        runs = Dict{String,Any}[]
        for k in EXPECTED_K, seed in EXPECTED_SEEDS
            run_id = _canonical_s0_id(k, seed)
            run_dir = joinpath(input_root, run_id)
            status = "MISSING"
            reason = "source directory not found"
            integrity_status = "NOT_CHECKED"
            image_count = 0
            revision = "UNRECORDED"
            if isdir(run_dir)
                ok, reason = try
                    _completed_source_run(run_dir, run_id)
                catch err
                    (false, sprint(showerror, err))
                end
                revision = islink(run_dir) ? "UNRECORDED" : _source_revision(run_dir)
                if ok
                    status, reason, integrity_status, image_count = "COMPLETED", "", "PASS", EXPECTED_IMAGES
                    destination_run = joinpath(s0_root, run_id)
                    mkpath(destination_run)
                    for name in S0_REQUIRED_FILES
                        cp(joinpath(run_dir, name), joinpath(destination_run, name))
                    end
                else
                    status, integrity_status = "FAILED", "FAIL"
                end
            end
            row = Dict{String,Any}(
                "run_id" => run_id, "k" => k, "seed" => seed,
                "status" => status, "integrity" => integrity_status,
                "image_count" => image_count,
                "source_generation_revision" => revision,
            )
            !isempty(reason) && (row["issue"] = reason)
            push!(runs, row)
        end
        status = all(row -> row["status"] == "COMPLETED", runs) ? "COMPLETED" : "PARTIAL"
        write_bundle(stage, destination, Dict{String,Any}(
            "bundle_kind" => "fashion_s0_source",
            "created_at_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sssZ"),
            "packaging_source_commit" => String(packaging_source_commit),
            "image_count_per_run" => EXPECTED_IMAGES,
            "expected_run_count" => 15,
            "status" => status,
            "runs" => runs,
        ))
    finally
        rm(stage; recursive=true, force=true)
    end
    return String(destination)
end

function _copy_tree(source::String, destination::String)
    isdir(source) || return false
    for (directory, dirs, files) in walkdir(source; follow_symlinks=false)
        relative = relpath(directory, source)
        target_dir = relative == "." ? destination : joinpath(destination, relative)
        mkpath(target_dir)
        for name in dirs
            islink(joinpath(directory, name)) && throw(ArgumentError("Spatial output contains a symbolic link"))
        end
        for name in files
            from = joinpath(directory, name)
            islink(from) && throw(ArgumentError("Spatial output contains a symbolic link"))
            isfile(from) || throw(ArgumentError("Unsupported spatial output member: $from"))
            cp(from, joinpath(target_dir, name))
        end
    end
    return true
end

function _spatial_status(spatial_root::String, source_run::String, variant::String)
    run_id = replace(source_run, "_S0_" => "_$(replace(variant, "-" => ""))_")
    folder = variant == "S6-B" ? "S6B" : variant
    run_dir = joinpath(spatial_root, folder, run_id)
    checkpoint_path = joinpath(run_dir, "checkpoint.toml")
    status = "NOT_RUN"
    integrity = "NOT_CHECKED"
    issue = "No completed or failed checkpoint was found"
    transaction_count = 0
    if isfile(checkpoint_path)
        checkpoint = try TOML.parsefile(checkpoint_path) catch; Dict{String,Any}() end
        state = String(get(checkpoint, "status", "FAILED"))
        if state == "COMPLETED" && isfile(joinpath(run_dir, "integrity_report.toml"))
            report = TOML.parsefile(joinpath(run_dir, "integrity_report.toml"))
            checkpoint_matches = get(checkpoint, "run_id", "") == run_id &&
                get(checkpoint, "variant", "") == variant &&
                get(checkpoint, "k", 0) == parse(Int, match(r"_K(\d+)_seed", run_id).captures[1]) &&
                get(checkpoint, "seed", -1) == parse(Int, match(r"_seed(\d+)$", run_id).captures[1])
            if get(report, "status", "") == "PASS" && checkpoint_matches &&
                get(report, "transaction_count", 0) == EXPECTED_IMAGES
                status, integrity = "COMPLETED", "PASS"
                transaction_count = Int(get(report, "transaction_count", 0))
                issue = ""
            else
                status, integrity, issue = "FAILED", "FAIL", "Integrity report is not PASS"
            end
        else
            status, integrity = "FAILED", "FAIL"
            issue = String(get(checkpoint, "failure_reason", "Checkpoint status is $state"))
        end
    else
        summary_path = joinpath(spatial_root, "spatial_extension_run_summary.toml")
        if isfile(summary_path)
            summary = try TOML.parsefile(summary_path) catch; Dict{String,Any}() end
            row = findfirst(item -> get(item, "run_id", "") == run_id &&
                get(item, "variant", "") == variant, get(summary, "runs", Any[]))
            if !isnothing(row)
                result = summary["runs"][row]
                if get(result, "status", "") in ("FAILED", "COMPLETED")
                    status, integrity = "FAILED", "FAIL"
                    issue = String(get(result, "issue", "Run summary disagrees with its missing checkpoint"))
                end
            end
        end
        if status == "NOT_RUN" && isdir(run_dir)
            status, integrity, issue = "FAILED", "FAIL", "Output directory has no checkpoint"
        end
    end
    return (; run_id, run_dir, status, integrity, issue, transaction_count)
end

function _rebase_full_eda2_database_manifest!(spatial_root::String, archive_root::String)
    source_path = joinpath(spatial_root, "eda2_database_manifest.toml")
    islink(source_path) && throw(ArgumentError("TC6 database manifest must not be a symbolic link"))
    isfile(source_path) || return false
    manifest = TOML.parsefile(source_path)
    get(manifest, "profile", "") == "full" && get(manifest, "eda2_ready", false) == true &&
        get(manifest, "database_count", 0) == 60 ||
        throw(ArgumentError("Finalized TC6 database manifest is not EDA2-ready"))
    databases = get(manifest, "databases", nothing)
    databases isa Vector && length(databases) == 60 ||
        throw(ArgumentError("Finalized TC6 database manifest must list all 60 databases"))

    expected = Set((k, seed, variant) for k in EXPECTED_K for seed in EXPECTED_SEEDS
        for variant in ("S0", SPATIAL_VARIANTS...))
    seen = Set{Tuple{Int,Int,String}}()
    for database in databases
        variant = String(get(database, "variant", ""))
        k, seed = Int(get(database, "k", -1)), Int(get(database, "seed", -1))
        key = (k, seed, variant)
        key in expected && !(key in seen) ||
            throw(ArgumentError("Unexpected or duplicate TC6 database identity: $key"))
        push!(seen, key)
        run_id = String(get(database, "database_id", ""))
        source_run_id = _expected_s0_run_id(k, seed)
        expected_run_id = variant == "S0" ? source_run_id : _expected_variant_run_id(k, seed, variant)
        run_id == expected_run_id || throw(ArgumentError("TC6 database identity mismatch: $run_id"))

        folder = variant == "S0" ? joinpath("s0_source", "S0") :
            (variant == "S6-B" ? "S6B" : variant)
        transaction_rel = replace(joinpath(folder, run_id, "transactions.jsonl"), '\\' => '/')
        transaction_path = joinpath(archive_root, split(transaction_rel, '/')...)
        isfile(transaction_path) || throw(ArgumentError("Packaged transaction is missing: $transaction_rel"))
        get(database, "transaction_count", 0) == EXPECTED_IMAGES ||
            throw(ArgumentError("TC6 database does not have 70,000 records: $run_id"))
        digest = bytes2hex(open(sha256, transaction_path))
        get(database, "transaction_sha256", "") == digest ||
            throw(ArgumentError("TC6 transaction checksum mismatch: $run_id"))

        source_folder = joinpath("s0_source", "S0", source_run_id)
        source_codebook = replace(joinpath(source_folder, "codebook.bin"), '\\' => '/')
        source_run = replace(source_folder, '\\' => '/')
        source_lineage = variant == "S0" ? joinpath(source_folder, "integrity_report.toml") :
            joinpath(folder, run_id, "source_artifacts.toml")
        source_lineage = replace(source_lineage, '\\' => '/')
        for relative in (source_codebook, source_lineage)
            isfile(joinpath(archive_root, split(relative, '/')...)) ||
                throw(ArgumentError("Packaged TC6 lineage artifact is missing: $relative"))
        end
        database["transaction_path"] = transaction_rel
        database["source_codebook_path"] = source_codebook
        database["source_run_path"] = source_run
        database["source_lineage"] = source_lineage
        if variant == "S0"
            database["item_mapping_ref"] = "implicit: item_id equals word_id in 1:K"
        else
            item_mapping = replace(joinpath(folder, run_id, "item_mapping.csv"), '\\' => '/')
            isfile(joinpath(archive_root, split(item_mapping, '/')...)) ||
                throw(ArgumentError("Packaged TC6 item mapping is missing: $item_mapping"))
            database["item_mapping_ref"] = item_mapping
        end
    end
    seen == expected || throw(ArgumentError("TC6 database identities are incomplete"))
    open(joinpath(archive_root, "eda2_database_manifest.toml"), "w") do io
        TOML.print(io, manifest)
    end
    return true
end

function _rebase_eda2_database_manifest!(spatial_root::String, stage::String)
    source_path = joinpath(spatial_root, "eda2_database_manifest.toml")
    islink(source_path) && throw(ArgumentError("TC6 database manifest must not be a symbolic link"))
    isfile(source_path) || return false
    manifest = TOML.parsefile(source_path)
    get(manifest, "profile", "") == "full" && get(manifest, "eda2_ready", false) == true &&
        get(manifest, "database_count", 0) == 60 ||
        throw(ArgumentError("Finalized TC6 database manifest is not EDA2-ready"))
    databases = get(manifest, "databases", nothing)
    databases isa Vector && length(databases) == 60 ||
        throw(ArgumentError("Finalized TC6 database manifest must list 60 databases"))
    expected = Set((k, seed, variant) for k in EXPECTED_K for seed in EXPECTED_SEEDS
        for variant in ("S0", SPATIAL_VARIANTS...))
    seen = Set{Tuple{Int,Int,String}}()
    for database in databases
        variant = String(get(database, "variant", ""))
        k, seed = Int(get(database, "k", -1)), Int(get(database, "seed", -1))
        variant in ("S0", SPATIAL_VARIANTS...) ||
            throw(ArgumentError("Unsupported variant in TC6 database manifest: $variant"))
        source_run_id = _canonical_s0_id(k, seed)
        run_id = String(get(database, "database_id", ""))
        expected_run_id = variant == "S0" ? source_run_id :
            replace(source_run_id, "_S0_" => "_$(replace(variant, "-" => ""))_")
        run_id == expected_run_id || throw(ArgumentError("TC6 database manifest identity mismatch: $run_id"))
        identity = (k, seed, variant)
        identity in seen && throw(ArgumentError("Duplicate TC6 database manifest identity: $identity"))
        push!(seen, identity)

        folder = variant == "S6-B" ? "S6B" : variant
        transaction_rel = variant == "S0" ? joinpath("S0", run_id, "transactions.jsonl") :
            joinpath(folder, run_id, "transactions.jsonl")
        transaction_rel = replace(transaction_rel, '\\' => '/')
        transaction_path = joinpath(stage, split(transaction_rel, '/')...)
        isfile(transaction_path) || throw(ArgumentError("TC6 database manifest transaction is missing: $transaction_rel"))
        get(database, "transaction_count", 0) == EXPECTED_IMAGES ||
            throw(ArgumentError("TC6 database manifest denominator is not 70,000: $run_id"))
        digest = bytes2hex(open(sha256, transaction_path))
        get(database, "transaction_sha256", "") == digest ||
            throw(ArgumentError("TC6 database manifest transaction checksum mismatch: $run_id"))

        source_codebook = joinpath("S0", source_run_id, "codebook.bin")
        source_lineage = variant == "S0" ?
            joinpath("S0", source_run_id, "integrity_report.toml") :
            joinpath(folder, run_id, "source_artifacts.toml")
        for relative in (source_codebook, source_lineage)
            isfile(joinpath(stage, relative)) ||
                throw(ArgumentError("TC6 database manifest artifact is missing: $relative"))
        end
        database["transaction_path"] = transaction_rel
        database["source_codebook_path"] = replace(source_codebook, '\\' => '/')
        database["source_run_path"] = replace(joinpath("S0", source_run_id), '\\' => '/')
        database["source_lineage"] = replace(source_lineage, '\\' => '/')
        mapping = String(get(database, "item_mapping_ref", ""))
        if variant != "S0" || !startswith(mapping, "implicit:")
            item_mapping = variant == "S0" ? joinpath("S0", run_id, "item_mapping.csv") :
                joinpath(folder, run_id, "item_mapping.csv")
            isfile(joinpath(stage, item_mapping)) ||
                throw(ArgumentError("TC6 database manifest item mapping is missing: $item_mapping"))
            database["item_mapping_ref"] = replace(item_mapping, '\\' => '/')
        end
    end
    seen == expected || throw(ArgumentError("TC6 database manifest identities are incomplete"))
    open(joinpath(stage, "eda2_database_manifest.toml"), "w") do io
        TOML.print(io, manifest)
    end
    return true
end

function _write_handoff_summary!(spatial_root::String, stage::String, spatial_runs, status, eda2_ready)
    summary_path = joinpath(spatial_root, "spatial_extension_run_summary.toml")
    islink(summary_path) && throw(ArgumentError("TC6 run summary must not be a symbolic link"))
    summary = if isfile(summary_path)
        TOML.parsefile(summary_path)
    else
        Dict{String,Any}("schema_version" => SCHEMA_VERSION, "profile" => "full")
    end
    summary["source_root"] = "S0"
    summary["output_root"] = "."
    summary["expected_new_runs"] = 45
    summary["completed_new_runs"] = count(row -> row["status"] == "COMPLETED", spatial_runs)
    summary["handoff_status"] = String(status)
    summary["eda2_manifest_path"] = eda2_ready ? "eda2_database_manifest.toml" : "UNAVAILABLE"
    summary["eda2_manifest_ready"] = Bool(eda2_ready)
    if haskey(summary, "runs") && summary["runs"] isa Vector
        for row in summary["runs"]
            variant = String(get(row, "variant", ""))
            run_id = String(get(row, "run_id", ""))
            variant in SPATIAL_VARIANTS ||
                throw(ArgumentError("Unexpected variant in TC6 run summary: $variant"))
            row["output_path"] = replace(joinpath(variant, run_id), '\\' => '/')
        end
    else
        summary["runs"] = spatial_runs
    end
    open(joinpath(stage, "spatial_extension_run_summary.toml"), "w") do io
        TOML.print(io, summary)
    end
    return summary
end

function _expected_fit_rows()
    return [(run_id=_canonical_s0_id(k, seed), k, seed)
        for k in EXPECTED_K for seed in EXPECTED_SEEDS]
end

"""Write the portable checkpoint archive after a TC4 fit has completed."""
function write_fit_checkpoint_bundle(source_root::AbstractString, destination::AbstractString;
    source_commit="UNRECORDED", notebook_sha256="UNRECORDED",
    configuration_sha256="UNRECORDED", julia_version=string(VERSION),
    clustering_version="UNRECORDED", dataset_archive_sha256=Dict{String,String}(),
    preprocessing_fingerprint="UNRECORDED", configuration_snapshot=Dict{String,Any}(),
    overwrite=true)
    source = abspath(String(source_root))
    isdir(source) || throw(ArgumentError("Fit checkpoint source root not found: $source"))
    length(dataset_archive_sha256) == 4 ||
        throw(ArgumentError("Four dataset archive checksums are required for a fit checkpoint"))
    stage = mktempdir()
    try
        fits_root = joinpath(stage, "fits")
        mkpath(fits_root)
        statuses = Dict{String,Any}[]
        for fit in _expected_fit_rows()
            run_dir = joinpath(source, fit.run_id)
            status, issue = "NOT_RUN", "Fit has no completed checkpoint yet"
            result_status = "NOT_RUN"
            if isdir(run_dir)
                required = ("checkpoint.toml", "codebook.bin", "tc4_metrics.toml")
                if all(name -> isfile(joinpath(run_dir, name)), required)
                    checkpoint = TOML.parsefile(joinpath(run_dir, "checkpoint.toml"))
                    metrics = TOML.parsefile(joinpath(run_dir, "tc4_metrics.toml"))
                    if get(checkpoint, "run_id", "") == fit.run_id &&
                        get(checkpoint, "k", -1) == fit.k && get(checkpoint, "seed", -1) == fit.seed &&
                        get(checkpoint, "status", "") != "FAILED" &&
                        get(checkpoint, "codebook_sha256", "") == bytes2hex(open(sha256, joinpath(run_dir, "codebook.bin")))
                        status, issue = "COMPLETED", ""
                        result_status = String(get(metrics, "status", "UNKNOWN"))
                        fit_dir = joinpath(fits_root, fit.run_id)
                        mkpath(fit_dir)
                        for name in required
                            cp(joinpath(run_dir, name), joinpath(fit_dir, name))
                        end
                        config_path = joinpath(run_dir, "config_snapshot.toml")
                        if isfile(config_path)
                            cp(config_path, joinpath(fit_dir, "config_snapshot.toml"))
                        else
                            open(joinpath(fit_dir, "config_snapshot.toml"), "w") do io
                                TOML.print(io, Dict{String,Any}(String(key) => value
                                    for (key, value) in configuration_snapshot); sorted=true)
                            end
                        end
                    else
                        status, issue = "FAILED", "Fit checkpoint identity or codebook checksum is invalid"
                    end
                elseif isfile(joinpath(run_dir, "checkpoint.toml"))
                    status, issue = "FAILED", "Fit checkpoint is incomplete"
                elseif !isempty(readdir(run_dir))
                    status, issue = "FAILED", "Fit output directory contains an incomplete artifact set"
                end
            end
            push!(statuses, Dict{String,Any}("run_id" => fit.run_id, "k" => fit.k,
                "seed" => fit.seed, "status" => status, "fit_result_status" => result_status,
                "issue" => issue))
        end
        fields = Dict{String,Any}(
            "bundle_kind" => "fashion_eda2_checkpoint",
            "created_at_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sssZ"),
            "source_commit" => String(source_commit),
            "notebook_sha256" => String(notebook_sha256),
            "configuration_sha256" => String(configuration_sha256),
            "julia_version" => String(julia_version),
            "clustering_version" => String(clustering_version),
            "dataset_archive_sha256" => Dict{String,Any}(String(k) => String(v) for (k, v) in dataset_archive_sha256),
            "preprocessing_fingerprint" => String(preprocessing_fingerprint),
            "resume_fingerprint" => Dict("source_commit" => String(source_commit),
                "configuration_sha256" => String(configuration_sha256),
                "julia_version" => String(julia_version), "clustering_version" => String(clustering_version),
                "preprocessing_fingerprint" => String(preprocessing_fingerprint),
                "dataset_archive_sha256" => Dict{String,Any}(String(k) => String(v) for (k, v) in dataset_archive_sha256)),
            "expected_fit_count" => 15,
            "completed_fit_count" => count(row -> row["status"] == "COMPLETED", statuses),
            "fit_statuses" => statuses,
        )
        write_bundle(stage, destination, fields; overwrite)
    finally
        rm(stage; recursive=true, force=true)
    end
    return String(destination)
end

"""Stage fingerprint-compatible completed TC4 artifacts into a fresh run root."""
function restore_fit_checkpoint_bundle!(bundle_root::AbstractString, target_root::AbstractString,
    expected_fingerprints::AbstractDict)
    root = abspath(String(bundle_root))
    manifest = TOML.parsefile(joinpath(root, "manifest.toml"))
    get(manifest, "bundle_kind", "") == "fashion_eda2_checkpoint" ||
        throw(ArgumentError("Resume input is not a fashion_eda2_checkpoint"))
    _validate_local_inventory!(root, manifest)
    _validate_fit_checkpoint_manifest!(root, manifest)
    expected_ids = Set(String(key) for key in keys(expected_fingerprints))
    expected_ids == Set(row.run_id for row in _expected_fit_rows()) ||
        throw(ArgumentError("Expected fingerprint map does not cover the canonical 15 fits"))
    rows = Dict(String(row["run_id"]) => row for row in manifest["fit_statuses"])
    to_restore = String[]
    for fit in _expected_fit_rows()
        get(rows[fit.run_id], "status", "") == "COMPLETED" || continue
        checkpoint_path = joinpath(root, "fits", fit.run_id, "checkpoint.toml")
        checkpoint = TOML.parsefile(checkpoint_path)
        get(checkpoint, "fingerprint", "") == String(expected_fingerprints[fit.run_id]) ||
            throw(ArgumentError("Resume fingerprint mismatch for $(fit.run_id); no fit was staged"))
        push!(to_restore, fit.run_id)
    end
    target = abspath(String(target_root))
    mkpath(target)
    for run_id in to_restore
        destination = joinpath(target, run_id)
        ispath(destination) && !isempty(readdir(destination)) &&
            throw(ArgumentError("Refusing to overwrite existing fit output: $destination"))
        mkpath(destination)
        source = joinpath(root, "fits", run_id)
        for name in ("checkpoint.toml", "codebook.bin", "tc4_metrics.toml")
            cp(joinpath(source, name), joinpath(destination, name); force=true)
        end
    end
    return to_restore
end

function _stage_fit_statuses(s0_manifest)
    rows = Dict{String,Any}[]
    for run in s0_manifest["runs"]
        run_id = String(run["run_id"])
        checkpoint_path = joinpath("s0_source", "S0", run_id, "tc4_metrics.toml")
        result_status = "UNAVAILABLE"
        run["status"] == "COMPLETED" && (result_status = "COMPLETED")
        match_result = match(r"_K(\d+)_seed(\d+)$", run_id)
        push!(rows, Dict{String,Any}("run_id" => run_id,
            "k" => parse(Int, match_result.captures[1]), "seed" => parse(Int, match_result.captures[2]),
            "status" => run["status"] == "COMPLETED" ? "COMPLETED" :
                run["status"] == "MISSING" ? "NOT_RUN" : "FAILED",
            "fit_result_status" => result_status, "checkpoint_path" => checkpoint_path,
            "issue" => String(get(run, "issue", ""))))
    end
    return rows
end

function _eda2_phase_status(metadata, phase, default)
    summary = get(metadata, "eda2_phase_statuses", Dict{String,Any}())
    summary isa AbstractDict || return default
    record = get(summary, phase, nothing)
    record isa AbstractDict || return default
    return String(get(record, "status", default))
end

"""Create the portable EDA2 stage archive with all four transaction variants."""
function write_eda2_stage_bundle(s0_source_root::AbstractString, spatial_root::AbstractString,
    analysis_root::AbstractString, destination::AbstractString; metadata=Dict{String,Any}(), overwrite=false)
    s0_source = abspath(String(s0_source_root))
    spatial = abspath(String(spatial_root))
    analysis = abspath(String(analysis_root))
    isdir(analysis) || throw(ArgumentError("Part 1 analysis output not found: $analysis"))
    stage = mktempdir()
    temp_archive = joinpath(stage, "s0-source.tar.gz")
    try
        write_s0_source_bundle(s0_source, temp_archive;
            packaging_source_commit=String(get(metadata, "source_commit", "UNRECORDED")))
        source_package = read_bundle(temp_archive; expected_kind="fashion_s0_source",
            destination=joinpath(stage, "s0_source"))
        rm(temp_archive; force=true)
        s0_manifest = source_package.manifest
        transaction_statuses = Dict{String,Any}[]
        for run in s0_manifest["runs"]
            run_id = String(run["run_id"])
            status = String(run["status"]) == "MISSING" ? "NOT_RUN" : String(run["status"])
            push!(transaction_statuses, Dict{String,Any}("run_id" => run_id,
                "source_run_id" => run_id, "k" => Int(run["k"]), "seed" => Int(run["seed"]),
                "variant" => "S0", "status" => status,
                "integrity" => status == "COMPLETED" ? "PASS" : status == "FAILED" ? "FAIL" : "NOT_CHECKED",
                "transaction_count" => status == "COMPLETED" ? EXPECTED_IMAGES : 0,
                "issue" => String(get(run, "issue", ""))))
        end
        spatial_statuses = Dict{String,Any}[]
        for run in s0_manifest["runs"], variant in SPATIAL_VARIANTS
            source_run = String(run["run_id"])
            result = run["status"] == "COMPLETED" ? _spatial_status(spatial, source_run, variant) :
                (; run_id=_expected_variant_run_id(Int(run["k"]), Int(run["seed"]), variant),
                    run_dir="", status="NOT_RUN", integrity="NOT_CHECKED", issue="S0 source is incomplete", transaction_count=0)
            if !isempty(result.run_dir) && isdir(result.run_dir)
                folder = variant == "S6-B" ? "S6B" : variant
                _copy_tree(result.run_dir, joinpath(stage, folder, result.run_id))
            end
            row = Dict{String,Any}("run_id" => result.run_id, "source_run_id" => source_run,
                "k" => Int(run["k"]), "seed" => Int(run["seed"]), "variant" => variant,
                "status" => result.status, "integrity" => result.integrity,
                "transaction_count" => result.transaction_count, "issue" => result.issue)
            push!(spatial_statuses, row)
            push!(transaction_statuses, copy(row))
        end
        _copy_tree(analysis, joinpath(stage, "analysis"))
        fit_statuses = _stage_fit_statuses(s0_manifest)
        for row in fit_statuses
            metric_path = joinpath(stage, "s0_source", "S0", String(row["run_id"]), "tc4_metrics.toml")
            if isfile(metric_path)
                row["fit_result_status"] = String(get(TOML.parsefile(metric_path), "status", "UNKNOWN"))
            end
        end
        summary_path = joinpath(spatial, "spatial_extension_run_summary.toml")
        isfile(summary_path) || throw(ArgumentError("Spatial finalization summary not found: $summary_path"))
        cp(summary_path, joinpath(stage, "spatial_extension_run_summary.toml"))
        completed_transactions = count(row -> row["status"] == "COMPLETED", transaction_statuses)
        completed_spatial = count(row -> row["status"] == "COMPLETED", spatial_statuses)
        database_manifest_ready = completed_spatial == 45 &&
            _rebase_full_eda2_database_manifest!(spatial, stage)
        status = completed_transactions == 60 && completed_spatial == 45 ? "COMPLETED" :
            completed_transactions == 0 ? "FAILED" : "PARTIAL"
        fields = merge(Dict{String,Any}(
            "bundle_kind" => "fashion_eda2_stage", "scope" => "S0_S1_S3_S6-B",
            "created_at_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sssZ"),
            "status" => status, "expected_fit_count" => 15, "fit_statuses" => fit_statuses,
            "expected_transaction_sets" => 60, "completed_transaction_sets" => completed_transactions,
            "transaction_statuses" => transaction_statuses,
            "expected_spatial_runs" => 45, "completed_spatial_runs" => completed_spatial,
            "spatial_statuses" => spatial_statuses,
            "phase_statuses" => Dict("part1" => completed_transactions == 60 ? "COMPLETED" : "PARTIAL",
                "part2" => "NOT_RUN", "analysis" => _eda2_phase_status(metadata, "analysis_a_b", "UNAVAILABLE"),
                "k_recommendation" => String(get(metadata, "k_recommendation_status", "UNAVAILABLE")),
                "representation_recommendation" => String(get(metadata, "representation_recommendation_status", "UNAVAILABLE")),
                "c1" => _eda2_phase_status(metadata, "pilot_c1", "NOT_RUN"),
                "c2" => _eda2_phase_status(metadata, "pilot_c2", "NOT_RUN"),
                "c3" => _eda2_phase_status(metadata, "pilot_c3", "NOT_RUN"),
                "pattern_review" => _eda2_phase_status(metadata, "interpretability_review", "NOT_RUN"),
                "final_decision" => _eda2_phase_status(metadata, "final_decision", "NOT_RUN")),
            "recommendation_status" => "PROVISIONAL",
            "source_commit" => String(get(metadata, "source_commit", "UNRECORDED")),
            "notebook_sha256" => String(get(metadata, "notebook_sha256", "UNRECORDED")),
            "configuration_sha256" => String(get(metadata, "configuration_sha256", "UNRECORDED")),
            "julia_version" => String(get(metadata, "julia_version", string(VERSION))),
            "dataset_archive_sha256" => get(metadata, "dataset_archive_sha256", Dict{String,Any}()),
            "source_s0_manifest_sha256" => bytes2hex(open(sha256, joinpath(stage, "s0_source", "manifest.toml"))),
            "eda2_database_manifest_ready" => database_manifest_ready,
        ), Dict{String,Any}(String(key) => value for (key, value) in metadata))
        write_bundle(stage, destination, fields; overwrite)
    finally
        rm(stage; recursive=true, force=true)
    end
    return String(destination)
end

"""Finalize a validated all-variant EDA2 stage archive."""
function write_full_experiment_bundle(stage_archive::AbstractString, spatial_root::AbstractString,
    destination::AbstractString; metadata=Dict{String,Any}(), overwrite=false)
    spatial = abspath(String(spatial_root))
    stage_dir = mktempdir()
    try
        staged = read_bundle(stage_archive; expected_kind="fashion_eda2_stage", destination=joinpath(stage_dir, "part1"))
        _copy_tree(staged.root, joinpath(stage_dir, "full"))
        full_root = joinpath(stage_dir, "full")
        rm(joinpath(full_root, "manifest.toml"); force=true)
        spatial_statuses = [Dict{String,Any}(row) for row in staged.manifest["spatial_statuses"]]
        summary_path = joinpath(spatial, "spatial_extension_run_summary.toml")
        isfile(summary_path) || throw(ArgumentError("Spatial finalization summary not found: $summary_path"))
        summary = TOML.parsefile(summary_path)
        summary["source_root"] = "s0_source/S0"
        summary["output_root"] = "."
        summary["eda2_manifest_path"] = "UNAVAILABLE"
        summary["eda2_manifest_ready"] = false
        for row in get(summary, "runs", Any[])
            variant = String(get(row, "variant", ""))
            run_id = String(get(row, "run_id", ""))
            variant in SPATIAL_VARIANTS || throw(ArgumentError("Unexpected finalized spatial variant: $variant"))
            row["output_path"] = replace(joinpath(variant == "S6-B" ? "S6B" : variant, run_id), '\\' => '/')
        end
        completed_spatial = count(row -> row["status"] == "COMPLETED", spatial_statuses)
        completed_transactions = Int(staged.manifest["completed_transaction_sets"])
        status = completed_transactions == 60 && completed_spatial == 45 ? "COMPLETED" :
            completed_transactions == 0 && completed_spatial == 0 ? "FAILED" : "PARTIAL"
        database_manifest_ready = if isfile(joinpath(spatial, "eda2_database_manifest.toml"))
            _rebase_full_eda2_database_manifest!(spatial, full_root)
        else
            false
        end
        completed_spatial == 45 && !database_manifest_ready &&
            throw(ArgumentError("Finalized full run is missing the EDA2-ready 60-database manifest"))
        summary["eda2_manifest_path"] = database_manifest_ready ? "eda2_database_manifest.toml" : "UNAVAILABLE"
        summary["eda2_manifest_ready"] = database_manifest_ready
        open(joinpath(full_root, "spatial_extension_run_summary.toml"), "w") do io
            TOML.print(io, summary)
        end
        fields = Dict{String,Any}(String(key) => value for (key, value) in staged.manifest
            if key ∉ ("schema_version", "files", "bundle_kind", "status", "completed_spatial_runs", "spatial_statuses", "phase_statuses"))
        merge!(fields, Dict{String,Any}(String(key) => value for (key, value) in metadata))
        fields["bundle_kind"] = "fashion_full_experiment"
        fields["scope"] = "S0_S1_S3_S6-B"
        fields["status"] = status
        fields["expected_spatial_runs"] = 45
        fields["completed_spatial_runs"] = completed_spatial
        fields["spatial_statuses"] = spatial_statuses
        fields["phase_statuses"] = Dict("part1" => get(staged.manifest["phase_statuses"], "part1", "COMPLETED"),
            "analysis" => get(staged.manifest["phase_statuses"], "analysis", "UNAVAILABLE"),
            "k_recommendation" => get(staged.manifest["phase_statuses"], "k_recommendation", "UNAVAILABLE"),
            "representation_recommendation" => get(staged.manifest["phase_statuses"], "representation_recommendation", "UNAVAILABLE"),
            "c1" => get(staged.manifest["phase_statuses"], "c1", "NOT_RUN"),
            "c2" => get(staged.manifest["phase_statuses"], "c2", "NOT_RUN"),
            "c3" => get(staged.manifest["phase_statuses"], "c3", "NOT_RUN"),
            "pattern_review" => get(staged.manifest["phase_statuses"], "pattern_review", "NOT_RUN"),
            "final_decision" => get(staged.manifest["phase_statuses"], "final_decision", "NOT_RUN"),
            "part2" => completed_spatial == 45 ? "COMPLETED" : "PARTIAL")
        fields["eda2_database_manifest_ready"] = database_manifest_ready
        fields["source_stage_archive_sha256"] = archive_sha256(stage_archive)
        write_bundle(full_root, destination, fields; overwrite)
    finally
        rm(stage_dir; recursive=true, force=true)
    end
    return String(destination)
end

"""Create a self-contained S0/S1/S3/S6-B handoff with a row for every expected run."""
function build_tc6_handoff(s0_root::AbstractString, spatial_root::AbstractString,
    destination::AbstractString; producer_source_commit="UNRECORDED", julia_version=string(VERSION),
    producer_config_path=nothing, producer_notebook_sha256="UNRECORDED", input_archive_sha256="UNRECORDED")
    s0_bundle_root = abspath(String(s0_root))
    spatial = abspath(String(spatial_root))
    islink(s0_bundle_root) && throw(ArgumentError("S0 bundle root must not be a symbolic link"))
    islink(spatial) && throw(ArgumentError("TC6 spatial root must not be a symbolic link"))
    source_manifest_path = joinpath(s0_bundle_root, "manifest.toml")
    islink(source_manifest_path) && throw(ArgumentError("S0 source manifest must not be a symbolic link"))
    isfile(source_manifest_path) || throw(ArgumentError("S0 source bundle manifest not found: $source_manifest_path"))
    source_manifest = TOML.parsefile(source_manifest_path)
    _validate_local_inventory!(s0_bundle_root, source_manifest)
    _validate_s0_manifest!(s0_bundle_root, source_manifest)
    all(run -> run["status"] == "COMPLETED", source_manifest["runs"]) ||
        throw(ArgumentError("TC6 spatial handoff requires 15 completed S0 source runs"))
    source_s0 = joinpath(s0_bundle_root, "S0")
    stage = mktempdir()
    try
        _copy_tree(source_s0, joinpath(stage, "S0"))
        spatial_runs = Dict{String,Any}[]
        for run in source_manifest["runs"], variant in SPATIAL_VARIANTS
            source_run = String(run["run_id"])
            result = _spatial_status(spatial, source_run, variant)
            variant_root = joinpath(stage, variant)
            !isempty(result.run_dir) && isdir(result.run_dir) &&
                _copy_tree(result.run_dir, joinpath(variant_root, result.run_id))
            push!(spatial_runs, Dict{String,Any}(
                "run_id" => result.run_id, "source_run_id" => source_run,
                "variant" => variant, "k" => Int(run["k"]), "seed" => Int(run["seed"]),
                "status" => result.status, "integrity" => result.integrity,
                "transaction_count" => result.transaction_count, "issue" => result.issue,
            ))
        end
        completed = count(row -> row["status"] == "COMPLETED", spatial_runs)
        status = completed == 45 ? "COMPLETED" : completed == 0 ? "FAILED" : "PARTIAL"
        eda2_ready = completed == 45 && _rebase_eda2_database_manifest!(spatial, stage)
        _write_handoff_summary!(spatial, stage, spatial_runs, status, eda2_ready)
        config_sha256 = "UNRECORDED"
        if !isnothing(producer_config_path)
            config_source = abspath(String(producer_config_path))
            islink(config_source) && throw(ArgumentError("TC6 runtime config must not be a symbolic link"))
            isfile(config_source) || throw(ArgumentError("TC6 runtime config not found: $config_source"))
            cp(config_source, joinpath(stage, "producer_runtime_config.toml"))
            config_sha256 = bytes2hex(open(sha256, config_source))
        end
        source_hash = bytes2hex(open(sha256, source_manifest_path))
        write_bundle(stage, destination, Dict{String,Any}(
            "bundle_kind" => "fashion_tc6_spatial_handoff",
            "scope" => "S0_S1_S3_S6-B",
            "status" => status,
            "producer_source_commit" => String(producer_source_commit),
            "julia_version" => String(julia_version),
            "source_manifest_sha256" => source_hash,
            "input_archive_sha256" => String(input_archive_sha256),
            "producer_notebook_sha256" => String(producer_notebook_sha256),
            "producer_config_sha256" => config_sha256,
            "expected_s0_runs" => 15,
            "expected_spatial_runs" => 45,
            "completed_spatial_runs" => completed,
            "eda2_ready" => eda2_ready,
            "source_runs" => source_manifest["runs"],
            "spatial_runs" => spatial_runs,
        ))
    finally
        rm(stage; recursive=true, force=true)
    end
    return String(destination)
end

end # module ExperimentBundleIO
