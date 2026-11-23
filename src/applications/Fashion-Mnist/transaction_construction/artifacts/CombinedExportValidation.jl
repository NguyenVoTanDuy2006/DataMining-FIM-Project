function _write_centroids_csv(path, centroids)
    open(path, "w") do io
        println(io, "word_id,pixel_index,centroid_value")
        for word_id in axes(centroids, 2), pixel_index in axes(centroids, 1)
            println(io, word_id, ',', pixel_index, ',', centroids[pixel_index, word_id])
        end
    end
    return path
end

function _write_tc7_manifest!(state, run_id, run_dir, book, records, integrity)
    state.config["run"]["mode"] == "release" || return nothing
    artifacts = Dict{String,Any}()
    for (name, filename) in (
        "transactions" => "transactions.jsonl",
        "codebook" => "codebook.bin",
        "centroids" => "centroids.csv",
        "patch_assignments" => "patch_assignments.csv",
        "tid_image_mapping" => "tid_image_mapping.csv",
        "image_metadata" => "image_metadata.csv",
        "config" => "config_snapshot.toml",
        "integrity_report" => "integrity_report.toml",
    )
        path = joinpath(run_dir, filename)
        artifacts[name] = Dict("path" => relpath(path, state.repo_root), "sha256" => _sha256(path))
    end
    dataset_manifest_path = joinpath(state.repo_root, state.config["run"]["dataset_manifest_path"])
    manifest = Dict{String,Any}(
        "schema_version" => 1,
        "run_id" => state.config["run"]["run_id"],
        "tc_run_id" => run_id,
        "status" => integrity["status"],
        "dataset_manifest_path" => relpath(dataset_manifest_path, state.repo_root),
        "dataset_manifest_sha256" => _sha256(dataset_manifest_path),
        "dataset" => "Fashion-MNIST",
        "image_count" => length(state.image_ids),
        "transaction_count" => length(records),
        "empty_transaction_count" => count(record -> isempty(record.items), records),
        "support_denominator" => length(records),
        "transaction_sha256" => artifacts["transactions"]["sha256"],
        "configuration" => Dict("codebook" => "B0", "K" => book.k, "seed" => book.seed,
            "transaction_variant" => "S0", "patch_size" => [4, 4], "foreground_threshold" => 29,
            "descriptor" => "raw_pixels_16d", "image_id_scheme" => "split:zero_based_index"),
        "archive_sha256" => state.archive_hashes,
        "artifacts" => artifacts,
        "created_at_unix" => time(),
    )
    path = joinpath(state.output_root, "transactions", "tc7_manifest.toml")
    mkpath(dirname(path))
    open(path * ".tmp", "w") do io
        TOML.print(io, manifest)
        flush(io)
    end
    mv(path * ".tmp", path; force=true)
    return path
end

function run_tc7!(state::TCv2State)
    _require_stage(state, 7)
    results = NamedTuple[]
    for run_id in state.run_ids
        run_dir = state.run_dirs[run_id]
        checkpoint_path = joinpath(run_dir, "checkpoint.toml")
        checkpoint = TOML.parsefile(checkpoint_path)
        already_completed = get(checkpoint, "status", "") == "COMPLETED"
        if already_completed && !haskey(checkpoint, "fit_status")
            previous_metrics = TOML.parsefile(joinpath(run_dir, "tc4_metrics.toml"))
            checkpoint["fit_status"] = get(previous_metrics, "status", "UNKNOWN")
        end
        book = _load_codebook(joinpath(run_dir, "codebook.bin"))
        words = open(deserialize, joinpath(run_dir, "assignments.bin"))
        expected_words = length(state.descriptor_index)
        codebook_ok = size(book.centroids, 1) == 16 && size(book.centroids, 2) == book.k &&
            all(isfinite, book.centroids) && all(x -> 0 <= x <= 1, book.centroids)
        assignment_ok = length(words) == expected_words && all(w -> 1 <= w <= book.k, words)
        records = [_parse_transaction_line(line) for line in eachline(joinpath(run_dir, "transactions.jsonl"))]
        n = length(state.image_ids)
        output_image_ids = _expected_output_image_ids(state)
        transaction_ok = length(records) == n && [r.tid for r in records] == collect(1:n) &&
            [r.image_id for r in records] == output_image_ids &&
            all(r -> issorted(r.items) && length(r.items) == length(unique(r.items)) &&
                length(r.items) <= min(book.k,49) && all(i -> 1 <= i <= book.k, r.items), records)
        mapping_ok = countlines(joinpath(run_dir, "tid_image_mapping.csv")) == n + 1
        if mapping_ok
            open(joinpath(run_dir, "tid_image_mapping.csv"), "r") do io
                release = state.config["run"]["mode"] == "release"
                mapping_ok = readline(io) == (release ? "tid,image_id,split,source_index" :
                    "tid,image_id,original_split,original_index")
                for (tid, line) in enumerate(eachline(io))
                    source_index = release ? state.original_indices[tid] - 1 : state.original_indices[tid]
                    expected_line = "$tid,$(output_image_ids[tid]),$(state.original_splits[tid]),$source_index"
                    mapping_ok &= line == expected_line
                end
            end
        end
        record_count = length(records)
        empty_count = count(r -> isempty(r.items), records)
        denominator_ok = record_count == n && n == length(unique(r.tid for r in records)) &&
            empty_count + count(r -> !isempty(r.items), records) == n
        config_snapshot = Dict("run_id"=>run_id, "tc4_method"=>book.method,
            "k"=>book.k, "seed"=>book.seed, "threshold"=>29,
            "mode"=>state.config["run"]["mode"],
            "dataset_manifest_path"=>get(state.config["run"], "dataset_manifest_path", ""),
            "data_archive_sha256"=>state.archive_hashes,
            "tc1_patch_extraction"=>state.config["tc1_patch_extraction"],
            "tc2_patch_filtering"=>state.config["tc2_patch_filtering"],
            "tc3_feature_extraction"=>state.config["tc3_feature_extraction"],
            "tc4_codebook"=>state.config["tc4_codebook"], "julia_version"=>string(VERSION))
        if !already_completed
            open(joinpath(run_dir, "config_snapshot.toml"), "w") do io
                TOML.print(io, config_snapshot)
            end
        end
        assignment_csv_path = joinpath(run_dir, "patch_assignments.csv")
        release = state.config["run"]["mode"] == "release"
        image_id_map = _release_image_id_map(state)
        assignment_csv_lines = countlines(assignment_csv_path)
        assignment_csv_ok = assignment_csv_lines == expected_words + 1
        if assignment_csv_ok
            open(assignment_csv_path, "r") do io
                assignment_csv_ok = readline(io) == "image_id,patch_id,patch_row,patch_col,word_id"
                for (i, line) in enumerate(eachline(io))
                    row = state.descriptor_index[i]
                    image_id = isnothing(image_id_map) ? row.image_id : image_id_map[row.image_id]
                    expected_line = "$(image_id),$(row.patch_id),$(row.patch_row),$(row.patch_col),$(words[i])"
                    assignment_csv_ok &= line == expected_line
                end
            end
        end
        codebook_hash_ok = checkpoint["codebook_sha256"] == _sha256(joinpath(run_dir, "codebook.bin")) &&
            checkpoint["method"] == book.method && checkpoint["k"] == book.k && checkpoint["seed"] == book.seed
        integrity = Dict("status"=>(codebook_ok && codebook_hash_ok && assignment_ok && assignment_csv_ok && transaction_ok && mapping_ok && denominator_ok ? "PASS" : "FAIL"),
            "image_count"=>n, "tid_count"=>length(unique(r.tid for r in records)),
            "transaction_count"=>record_count, "empty_count"=>empty_count,
            "nonempty_count"=>record_count-empty_count, "support_denominator"=>record_count,
            "descriptor_count"=>expected_words, "assignment_count"=>length(words),
            "codebook_shape"=>collect(size(book.centroids)), "codebook_finite"=>codebook_ok,
            "assignments_valid"=>assignment_ok, "transactions_valid"=>transaction_ok,
            "patch_assignments_csv_lines"=>assignment_csv_lines,
            "patch_assignments_csv_valid"=>assignment_csv_ok,
            "codebook_checkpoint_matches"=>codebook_hash_ok,
            "tid_mapping_valid"=>mapping_ok, "support_denominator_valid"=>denominator_ok,
            "codebook_sha256"=>_sha256(joinpath(run_dir, "codebook.bin")))
        if !already_completed
            open(joinpath(run_dir, "integrity_report.toml"), "w") do io
                TOML.print(io, integrity)
            end
        end
        integrity["status"] == "PASS" || error("TC7 read-back validation failed for $run_id")
        if release
            centroids_path = joinpath(run_dir, "centroids.csv")
            _write_centroids_csv(centroids_path, book.centroids)
        end
        if !already_completed
            checkpoint["fit_status"] = get(checkpoint, "status", "UNKNOWN")
            checkpoint["status"] = "COMPLETED"
            checkpoint["completed_at_unix"] = time()
            open(checkpoint_path, "w") do io
                TOML.print(io, checkpoint)
            end
        end
        manifest_path = _write_tc7_manifest!(state, run_id, run_dir, book, records, integrity)
        push!(results, (; run_id, status="COMPLETED", fit_status=get(checkpoint, "fit_status", get(checkpoint, "status", "UNKNOWN")), transactions=record_count,
            empty=empty_count, support_denominator=record_count, manifest_path))
    end
    summary_path = joinpath(state.output_root, "tc_v2_run_summary.toml")
    open(summary_path, "w") do io
        TOML.print(io, Dict("mode"=>state.config["run"]["mode"],
            "method"=>state.config["tc4_codebook"]["training_method"],
            "image_count"=>length(state.image_ids), "codebook_count"=>length(results),
            "run_ids"=>state.run_ids, "status"=>"COMPLETED", "elapsed_seconds"=>time()-state.started_at,
            "checks"=>state.checks))
    end
    _set_stage!(state, 7, "tc7_reload_integrity_validation", all(r -> r.status == "COMPLETED", results))
    return (; summary_path, runs=results, output_root=state.output_root,
        elapsed_seconds=time()-state.started_at)
end
