"""TC7: xuất metadata, reload artifacts, kiểm tra Eclat và lập smoke report."""
function run_tc7!(state::TCState; notebook_fresh_kernel::Bool=true)
    _require_previous(state, 7)
    state.data[:mode] == "full" && return _finish_full_run!(state; notebook_fresh_kernel)
    config = state.config
    output_root = state.work_root
    train_tx, validation_tx = state.data[:train_tx], state.data[:validation_tx]
    run_id = only(state.data[:run_ids])
    model = state.data[:models][run_id]
    eclat_config = config["eclat_smoke"]
    fixture = [[1, 2], [1, 3], Int[], [1, 2, 3]]
    patterns = mine(fixture, eclat_config["minsup_count"])
    fixture_valid = length(fixture) == 4 && patterns[(1,)] == 3 && patterns[(2,)] == 2 &&
        patterns[(1, 2)] == 2 && count(tx -> all(item -> item in tx, (2, 3)), fixture) == 1 &&
        !haskey(patterns, (2, 3))
    all_transactions = vcat(train_tx, validation_tx)
    frequent = mine(all_transactions, eclat_config["minsup_count"])
    _write_csv(joinpath(output_root, "eclat_frequent_itemsets.csv"), ["itemset", "support_count"],
        [(join(key, ' '), count) for (key, count) in sort!(collect(frequent); by=first)])
    direct_support(items) = count(tx -> all(item -> item in tx, items), all_transactions)
    selected = [(1,), (2,), (1, 2), (1, 3)]
    support_valid = all(items -> get(frequent, items, 0) == direct_support(items), selected)
    state.checks["tc7_reload_and_eclat_support"] = fixture_valid && support_valid ? "PASS" : "FAIL"
    state.checks["tc7_pilot"] = "PASS"
    verifier = joinpath(FASHION_MNIST_ROOT, "transaction_construction", "scripts",
        "verify_fashion_tc_artifacts.jl")
    Base.run(`$(Base.julia_cmd()) --compiled-modules=existing $verifier $(abspath(output_root))`)
    state.checks["tc7_fresh_process_reload"] = "PASS"
    reloaded_codebook = open(deserialize, joinpath(output_root, "codebook.bin"))
    state.checks["tc7_reload_equal"] = reloaded_codebook == model.centroids ? "PASS" : "FAIL"
    reloaded_assignments = open(deserialize, joinpath(output_root, "assignments.bin"))
    state.checks["tc7_assignment_reload_equal"] =
        reloaded_assignments.train_words == state.data[:train_words] &&
        reloaded_assignments.valid_words == state.data[:validation_words] ? "PASS" : "FAIL"
    read_transactions(path) = [isempty(strip(line)) ? Int[] : parse.(Int, split(strip(line))) for line in eachline(path)]
    state.checks["tc7_transaction_reload_equal"] =
        read_transactions(joinpath(output_root, "train_transactions.txt")) == train_tx &&
        read_transactions(joinpath(output_root, "validation_transactions.txt")) == validation_tx ? "PASS" : "FAIL"
    tau = state.data[:tau]
    run = config["run"]
    open(joinpath(output_root, "effective_config.toml"), "w") do io
        TOML.print(io, config)
    end
    kmeans = model
    open(joinpath(output_root, "run_metadata.toml"), "w") do io
        TOML.print(io, Dict("julia_version" => string(VERSION), "run_id" => run["run_id"], "mode" => "smoke",
            "seed" => config["tc4_codebook"]["seed"], "sample_seed" => config["dataset"]["sample_seed"],
            "threshold" => tau, "train_image_ids" => state.data[:train_ids],
            "validation_image_ids" => state.data[:validation_ids],
            "retained_train_descriptors" => size(state.data[:train_desc], 2),
            "retained_validation_descriptors" => size(state.data[:validation_desc], 2),
            "train_patch_duplicate_rate" => state.data[:patch_duplicate_summary]["train"].duplicate_rate,
            "train_unique_patches" => state.data[:patch_duplicate_summary]["train"].unique,
            "validation_patch_duplicate_rate" => state.data[:patch_duplicate_summary]["validation"].duplicate_rate,
            "validation_unique_patches" => state.data[:patch_duplicate_summary]["validation"].unique,
            "kmeans_iterations" => kmeans.iterations, "kmeans_objective" => kmeans.objective,
            "kmeans_converged" => kmeans.converged,
            "kmeans_wall_seconds" => state.data[:fit_summaries][1].elapsed_seconds,
            "kmeans_backend" => kmeans.backend, "kmeans_stop_reason" => kmeans.stop_reason,
            "kmeans_initialization_seconds" => kmeans.initialization_seconds,
            "kmeans_fit_seconds" => kmeans.fit_seconds,
            "kmeans_library" => kmeans.library, "kmeans_library_version" => kmeans.library_version,
            "kmeans_initialization" => kmeans.initialization, "kmeans_maxiter" => kmeans.maxiter,
            "kmeans_tolerance" => kmeans.tolerance,
            "timings" => state.data[:timings], "peak_rss_bytes" => Sys.maxrss(),
            "source_archive_sha256" => state.data[:archive_checksums],
            "descriptor_cache_sha256" => state.data[:descriptor_checksums],
            "eclat_frequent_itemsets_minsup_2" => length(frequent)))
    end
    archive = _archive_run!(state, run_id, "tc7")
    state.data[:timings]["archive_pack_seconds"] =
        get(state.data[:timings], "archive_pack_seconds", 0.0) + archive.pack_seconds
    state.data[:timings]["drive_archive_copy_seconds"] =
        get(state.data[:timings], "drive_archive_copy_seconds", 0.0) + archive.drive_copy_seconds
    pipeline_status = all(==("PASS"), values(state.checks)) ? "PASS" : "FAIL"
    notebook_status = notebook_fresh_kernel ? "PASS" : "NOT_RUN"
    overall_status = pipeline_status == "PASS" && notebook_fresh_kernel ? "PASS" : "INCOMPLETE"
    report = Dict("run_id" => run["run_id"], "mode" => "smoke", "status" => overall_status,
        "pipeline_status" => pipeline_status, "notebook_fresh_kernel" => notebook_status,
        "config_path" => state.config_path, "effective_config_path" => joinpath(output_root, "effective_config.toml"),
        "elapsed_seconds" => time() - state.started_at, "train_images" => length(state.data[:train_ids]),
        "validation_images" => length(state.data[:validation_ids]),
        "train_patches_before_filter" => length(state.data[:train_patches]),
        "validation_patches_before_filter" => length(state.data[:validation_patches]),
        "train_retained_descriptors" => size(state.data[:train_desc], 2),
        "validation_retained_descriptors" => size(state.data[:validation_desc], 2),
        "tau_train" => tau, "kmeans_fit_count" => 1, "kmeans_k" => config["tc4_codebook"]["k"],
        "kmeans_initialization_seconds" => kmeans.initialization_seconds,
        "kmeans_fit_seconds" => kmeans.fit_seconds,
        "assignment_seconds" => only(state.data[:assignment_summaries]).assignment_seconds,
        "checkpoint_drive_seconds" => state.data[:fit_summaries][1].checkpoint_drive_seconds,
        "checkpoint_resumed" => state.data[:fit_summaries][1].resumed,
        "train_transactions" => length(train_tx), "validation_transactions" => length(validation_tx),
        "transaction_count" => length(all_transactions), "checks" => state.checks,
        "archive_path" => archive.path, "archive_sha256" => archive.sha256,
        "archive_pack_seconds" => archive.pack_seconds,
        "archive_drive_copy_seconds" => archive.drive_copy_seconds)
    run_id_json = _json_escape(run["run_id"])
    config_path_json = _json_escape(state.config_path)
    effective_config_path_json = _json_escape(report["effective_config_path"])
    report_path = joinpath(output_root, "smoke_test_report.json")
    open(report_path, "w") do io
        print(io, "{\n  \"run_id\": \"$run_id_json\",\n  \"mode\": \"smoke\",\n  \"status\": \"$overall_status\",\n  \"pipeline_status\": \"$pipeline_status\",\n  \"notebook_fresh_kernel\": \"$notebook_status\",\n  \"config_path\": \"$config_path_json\",\n  \"effective_config_path\": \"$effective_config_path_json\",\n  \"elapsed_seconds\": $(report["elapsed_seconds"]),\n  \"tau_train\": $tau,\n  \"train_images\": $(report["train_images"]),\n  \"validation_images\": $(report["validation_images"]),\n  \"train_patches_before_filter\": $(report["train_patches_before_filter"]),\n  \"validation_patches_before_filter\": $(report["validation_patches_before_filter"]),\n  \"train_retained_descriptors\": $(report["train_retained_descriptors"]),\n  \"validation_retained_descriptors\": $(report["validation_retained_descriptors"]),\n  \"kmeans_fit_count\": 1,\n  \"kmeans_k\": $(report["kmeans_k"]),\n  \"kmeans_initialization_seconds\": $(_json_number(report["kmeans_initialization_seconds"])),\n  \"kmeans_fit_seconds\": $(report["kmeans_fit_seconds"]),\n  \"assignment_seconds\": $(report["assignment_seconds"]),\n  \"checkpoint_drive_seconds\": $(report["checkpoint_drive_seconds"]),\n  \"checkpoint_resumed\": $(report["checkpoint_resumed"]),\n  \"train_transactions\": $(report["train_transactions"]),\n  \"validation_transactions\": $(report["validation_transactions"]),\n  \"archive_path\": \"$(_json_escape(archive.path))\",\n  \"archive_sha256\": \"$(archive.sha256)\",\n  \"archive_pack_seconds\": $(archive.pack_seconds),\n  \"archive_drive_copy_seconds\": $(archive.drive_copy_seconds),\n  \"checks\": {")
        print(io, join(["\n    \"$key\": \"$(state.checks[key])\"" for key in sort!(collect(keys(state.checks)))], ","), "\n  }\n}\n")
    end
    drive_report = joinpath(state.output_root, basename(report_path))
    cp(report_path, drive_report; force=true)
    bytes2hex(open(sha256, report_path)) == bytes2hex(open(sha256, drive_report)) ||
        error("Smoke report trên Drive không khớp SHA-256")
    pipeline_status == "PASS" || error("TC smoke pipeline failed; xem smoke_test_report.json")
    return _finish_stage!(state, 7, "Export, reload và Eclat", report)
end

function _finish_full_run!(state::TCState; notebook_fresh_kernel)
    config = state.config
    export_config = config["tc7_export_validation"]
    expected_train = export_config["expected_train_transactions"]
    expected_validation = export_config["expected_validation_transactions"]
    length(state.data[:train_ids]) == expected_train || error("Số ảnh train full sai")
    length(state.data[:validation_ids]) == expected_validation || error("Số ảnh validation full sai")
    summaries = NamedTuple[]
    for fit in state.data[:fit_summaries]
        run_dir = _run_output_dir(state, fit.run_id)
        assignments = open(deserialize, joinpath(run_dir, "assignments.bin"))
        train_tx_count = countlines(joinpath(run_dir, "train_transactions.txt"))
        validation_tx_count = countlines(joinpath(run_dir, "validation_transactions.txt"))
        train_tx_count == expected_train && validation_tx_count == expected_validation ||
            error("TC7 transaction count sai ở $(fit.run_id)")
        length(assignments.train_words) == size(state.data[:train_desc], 2) ||
            error("Train assignments không khớp descriptor ở $(fit.run_id)")
        length(assignments.valid_words) == size(state.data[:validation_desc], 2) ||
            error("Validation assignments không khớp descriptor ở $(fit.run_id)")
        assignment = only(filter(row -> row.run_id == fit.run_id,
            state.data[:assignment_summaries]))
        archive = _archive_run!(state, fit.run_id, "tc7")
        state.data[:timings]["archive_pack_seconds"] =
            get(state.data[:timings], "archive_pack_seconds", 0.0) + archive.pack_seconds
        state.data[:timings]["drive_archive_copy_seconds"] =
            get(state.data[:timings], "drive_archive_copy_seconds", 0.0) + archive.drive_copy_seconds
        push!(summaries, merge(fit, (;
            train_descriptors=size(state.data[:train_desc], 2),
            validation_descriptors=size(state.data[:validation_desc], 2),
            train_transactions=train_tx_count, validation_transactions=validation_tx_count,
            assignment_seconds=assignment.assignment_seconds,
            archive_path=archive.path, archive_sha256=archive.sha256,
            archive_pack_seconds=archive.pack_seconds,
            archive_drive_copy_seconds=archive.drive_copy_seconds)))
    end
    status = notebook_fresh_kernel && length(summaries) ==
        length(config["tc4_codebook"]["k_candidates"]) * length(config["tc4_codebook"]["random_seeds"]) ? "PASS" : "INCOMPLETE"
    state.checks["tc7_full_exports"] = status
    _write_csv(joinpath(state.output_root, "benchmark_summary.csv"),
        ["run_id", "k", "seed", "backend", "train_descriptors", "validation_descriptors",
            "train_transactions", "validation_transactions", "iterations", "converged",
            "stop_reason", "objective", "initialization_seconds", "fit_seconds",
            "assignment_seconds", "checkpoint_drive_seconds", "archive_pack_seconds",
            "archive_drive_copy_seconds",
            "resumed", "library_version", "archive_path", "archive_sha256"],
        [(r.run_id, r.k, r.seed, r.backend, r.train_descriptors, r.validation_descriptors,
            r.train_transactions, r.validation_transactions, r.iterations, r.converged,
            r.stop_reason, r.objective, r.initialization_seconds, r.fit_seconds,
            r.assignment_seconds, r.checkpoint_drive_seconds, r.archive_pack_seconds,
            r.archive_drive_copy_seconds,
            r.resumed, r.library_version, r.archive_path, r.archive_sha256)
            for r in summaries])
    open(joinpath(state.output_root, "run_metadata.toml"), "w") do io
        TOML.print(io, Dict("mode" => "full", "run_id" => config["run"]["run_id"],
            "julia_version" => string(VERSION), "train_images" => length(state.data[:train_ids]),
            "backend" => _backend(state), "work_root" => state.work_root,
            "validation_images" => length(state.data[:validation_ids]), "tau_train" => state.data[:tau],
            "threshold_fit_split" => "train", "train_descriptors" => size(state.data[:train_desc], 2),
            "validation_descriptors" => size(state.data[:validation_desc], 2),
            "train_patch_duplicate_rate" => state.data[:patch_duplicate_summary]["train"].duplicate_rate,
            "train_unique_patches" => state.data[:patch_duplicate_summary]["train"].unique,
            "validation_patch_duplicate_rate" => state.data[:patch_duplicate_summary]["validation"].duplicate_rate,
            "validation_unique_patches" => state.data[:patch_duplicate_summary]["validation"].unique,
            "run_count" => length(summaries), "timings" => state.data[:timings],
            "source_archive_sha256" => state.data[:archive_checksums]))
    end
    report = (; mode="full", status, notebook_fresh_kernel, run_count=length(summaries),
        train_transactions=expected_train, validation_transactions=expected_validation,
        output_root=state.output_root, checks=state.checks)
    open(joinpath(state.output_root, "full_run_report.toml"), "w") do io
        TOML.print(io, Dict("mode" => report.mode, "status" => report.status,
            "notebook_fresh_kernel" => report.notebook_fresh_kernel, "run_count" => report.run_count,
            "train_transactions" => report.train_transactions,
            "validation_transactions" => report.validation_transactions,
            "run_ids" => [r.run_id for r in summaries], "checks" => state.checks))
    end
    return _finish_stage!(state, 7, "Export và kiểm tra full artifacts", report)
end
