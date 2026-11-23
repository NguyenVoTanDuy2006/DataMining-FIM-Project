"""TC4: smoke fit một model; full fit lưới K×seed theo cùng bước TC."""
function run_tc4!(state::TCState)
    _require_previous(state, 4)
    config = state.config["tc4_codebook"]
    runs = state.data[:mode] == "smoke" ?
        [(state.config["run"]["run_id"], config["k"], config["seed"])] :
        [("T2_K$(k)_seed$(seed)", k, seed)
            for k in config["k_candidates"] for seed in config["random_seeds"]]
    models = Dict{String,Any}()
    fit_summaries = NamedTuple[]
    fingerprints = Dict{String,String}()
    expected_dim = state.config["tc3_feature_extraction"]["dimension"]
    backend = _backend(state)

    for (run_id, k, seed) in runs
        fingerprint = _fit_fingerprint(state, k, seed)
        fingerprints[run_id] = fingerprint
        started = time()
        model = _load_fit_checkpoint(state, run_id, k, seed, fingerprint)
        resumed = !isnothing(model)
        if !resumed
            model = fit_kmeans(state.data[:train_desc]; k, seed,
                maxiter=config["max_iterations"], tolerance=config["tolerance"])
        end
        elapsed = time() - started
        state.data[:timings]["kmeans_initialization_seconds"] =
            get(state.data[:timings], "kmeans_initialization_seconds", 0.0) +
            (isfinite(model.initialization_seconds) ? model.initialization_seconds : 0.0)
        state.data[:timings]["kmeans_fit_seconds"] =
            get(state.data[:timings], "kmeans_fit_seconds", 0.0) + model.fit_seconds
        size(model.centroids) == (expected_dim, k) && all(isfinite, model.centroids) ||
            error("Kích thước/giá trị codebook không hợp lệ cho $run_id")
        run_dir = _run_output_dir(state, run_id)
        mkpath(run_dir)
        open(joinpath(run_dir, "codebook.bin"), "w") do io
            serialize(io, model.centroids)
        end
        if resumed
            drive_checkpoint = _checkpoint_dir(state, run_id, fingerprint)
            local_checkpoint = joinpath(run_dir, "fit_checkpoint")
            mkpath(local_checkpoint)
            checkpoint_transfer_started = time()
            for filename in ("codebook.bin", "iteration_history.csv", "checkpoint.toml")
                cp(joinpath(drive_checkpoint, filename), joinpath(local_checkpoint, filename))
            end
            bytes2hex(open(sha256, joinpath(local_checkpoint, "codebook.bin"))) ==
                bytes2hex(open(sha256, joinpath(drive_checkpoint, "codebook.bin"))) ||
                error("Codebook tải từ checkpoint không khớp SHA-256")
            bytes2hex(open(sha256, joinpath(local_checkpoint, "iteration_history.csv"))) ==
                bytes2hex(open(sha256, joinpath(drive_checkpoint, "iteration_history.csv"))) ||
                error("Iteration history tải từ checkpoint không khớp SHA-256")
            checkpoint_seconds = time() - checkpoint_transfer_started
        else
            checkpoint_seconds = _save_fit_checkpoint!(
                state, run_id, k, seed, fingerprint, model, run_dir)
        end
        state.data[:timings]["checkpoint_drive_seconds"] =
            get(state.data[:timings], "checkpoint_drive_seconds", 0.0) + checkpoint_seconds
        models[run_id] = (; centroids=model.centroids, objective=model.objective,
            iterations=model.iterations, converged=model.converged,
            stop_reason=model.stop_reason, history=model.history, backend=model.backend,
            initialization_seconds=model.initialization_seconds,
            fit_seconds=model.fit_seconds, library=model.library,
            library_version=model.library_version, initialization=model.initialization,
            maxiter=model.maxiter, tolerance=model.tolerance, resumed)
        push!(fit_summaries, (; run_id, k, seed, shape=size(model.centroids),
            iterations=model.iterations, converged=model.converged,
            stop_reason=model.stop_reason, objective=model.objective,
            initialization_seconds=model.initialization_seconds,
            fit_seconds=model.fit_seconds, elapsed_seconds=elapsed,
            checkpoint_drive_seconds=checkpoint_seconds, resumed,
            backend=model.backend, library=model.library,
            library_version=model.library_version))
    end
    state.data[:run_ids] = first.(runs)
    state.data[:models] = models
    state.data[:fit_summaries] = fit_summaries
    state.data[:fit_fingerprints] = fingerprints
    state.data[:checkpoint_summaries] = fit_summaries
    state.checks["tc4_codebook_shape"] = "PASS"
    return _finish_stage!(state, 4, "Fit K-means codebook", fit_summaries)
end

function run_tc4!(state::TCv2State)
    _require_stage(state, 4)
    config = state.config["tc4_codebook"]
    method = config["training_method"]
    method == "raw_full_batch_kmeans" || error(
        "training_method=q20_weighted_kmeans was selected, but no compatible Q20 backend is connected; no fallback was used")
    k_values = config["k_candidates"]
    seeds = config["random_seeds"]
    if state.config["run"]["mode"] == "full"
        k_values == [16,32,64,128,256] || error("Full mode K candidates differ from spec")
        seeds == [42,123,2026] || error("Full mode seeds differ from spec")
    elseif state.config["run"]["mode"] == "release"
        k_values == [32] && seeds == [123] || error("Release mode must fit only B0/K=32/seed=123")
    end
    size(state.descriptor_matrix, 2) >= maximum(k_values) || error("Not enough retained descriptors for max K")
    pairs = [(k, seed) for k in k_values for seed in seeds]
    println("[TC4] START method=$method | fits=$(length(pairs)) | K=$(join(k_values, ',')) | seeds=$(join(seeds, ',')) | descriptors=$(size(state.descriptor_matrix, 2)) | backend=Clustering.jl CPU")
    flush(stdout)
    for (fit_index, (k, seed)) in enumerate(pairs)
        run_id = _run_name(method, k, seed)
        run_dir = _run_directory(state, run_id)
        mkpath(run_dir)
        fingerprint = _canonical_sha((state.archive_hashes, method, k, seed,
            state.config["tc1_patch_extraction"], state.config["tc2_patch_filtering"],
            state.config["tc3_feature_extraction"], config, VERSION,
            size(state.descriptor_matrix), sum(state.descriptor_matrix), TC_V2_SCHEMA_VERSION))
        cp = joinpath(run_dir, "checkpoint.toml")
        codebook_path = joinpath(run_dir, "codebook.bin")
        model = nothing
        metrics = nothing
        maxiter = config["max_iterations"]
        tolerance = config["tolerance"]
        println("[TC4 $fit_index/$(length(pairs))] START $run_id | descriptors=$(size(state.descriptor_matrix, 2)) | maxiter=$maxiter | tol=$tolerance")
        flush(stdout)
        if isfile(cp) && isfile(codebook_path)
            saved = TOML.parsefile(cp)
            if saved["fingerprint"] == fingerprint && saved["codebook_sha256"] == _sha256(codebook_path)
                model = _load_codebook(codebook_path)
                metrics = TOML.parsefile(joinpath(run_dir, "tc4_metrics.toml"))
            else
                error("Existing output does not match this run; refusing to overwrite: $run_dir")
            end
        elseif isdir(run_dir) && !isempty(readdir(run_dir))
            existing_files = readdir(run_dir)
            retryable_failure = existing_files == ["checkpoint.toml"] && isfile(cp) &&
                !isfile(codebook_path) && begin
                    saved = TOML.parsefile(cp)
                    get(saved, "status", "") == "FAILED" &&
                        get(saved, "fingerprint", "") == fingerprint
                end
            if retryable_failure
                rm(cp; force=true)
            else
                error("Incomplete or unrecognized output exists; refusing to overwrite: $run_dir")
            end
        end
        if isnothing(metrics)
            try
                fitted = fit_kmeans(state.descriptor_matrix; k, seed,
                    maxiter=config["max_iterations"], tolerance=config["tolerance"])
                all(isfinite, fitted.centroids) || error("Non-finite centroids")
                all(x -> 0f0 <= x <= 1f0, fitted.centroids) || error("Centroid outside raw [0,1] space")
                metrics = _cluster_metrics(fitted, k, size(state.descriptor_matrix, 2))
                metrics["run_id"] = run_id
                metrics["method"] = method
                metrics["k"] = k
                metrics["seed"] = seed
                metrics["status"] = !isempty(metrics["empty_clusters"]) ? "DEGENERATE_WARNING" :
                    !fitted.converged ? "NON_CONVERGED" : "FITTED"
                model = (; centroids=fitted.centroids, library=fitted.library,
                    library_version=fitted.library_version, iterations=fitted.iterations,
                    converged=fitted.converged, fit_seconds=fitted.fit_seconds)
                _write_fit_checkpoint!(state, run_id, k, seed, fingerprint, fitted, metrics)
            catch err
                open(joinpath(run_dir, "checkpoint.toml"), "w") do io
                    TOML.print(io, Dict("run_id"=>run_id, "method"=>method, "k"=>k, "seed"=>seed,
                        "fingerprint"=>fingerprint, "status"=>"FAILED", "error"=>sprint(showerror, err)))
                end
                rethrow()
            end
        end
        metrics["run_id"] = run_id
        state.run_ids = vcat(state.run_ids, run_id)
        state.run_dirs[run_id] = run_dir
        state.checks["tc4_$(run_id)"] = metrics["status"]
        fit_status = metrics["status"]
        iterations = metrics["iterations"]
        converged = metrics["converged"]
        distortion = round(metrics["distortion_mean_squared"]; sigdigits=6)
        occupancy = metrics["occupancy_used"]
        top_share = round(metrics["top_cluster_share"]; digits=4)
        entropy = round(metrics["normalized_entropy"]; digits=4)
        fit_seconds = round(metrics["fit_seconds"]; digits=2)
        println("[TC4 $fit_index/$(length(pairs))] $fit_status $run_id | iterations=$iterations | converged=$converged | distortion=$distortion | occupancy=$occupancy/$k | top_share=$top_share | entropy=$entropy | fit=$(fit_seconds)s | checkpoint=$cp")
        flush(stdout)
    end

    # ARI uses one fixed descriptor sample for every seed and never participates
    # in fitting. Word IDs are compared only within each K and seed pair.
    rng = MersenneTwister(config["stability_seed"])
    sample_count = min(config["stability_sample_size"], size(state.descriptor_matrix, 2))
    stability_indices = sort!(randperm(rng, size(state.descriptor_matrix, 2))[1:sample_count])
    stability_X = state.descriptor_matrix[:, stability_indices]
    for k in k_values
        ids = filter(id -> occursin("_K$(k)_", id), state.run_ids)
        labels_by_run = Dict(id => assign_words(stability_X,
            _load_codebook(joinpath(state.run_dirs[id], "codebook.bin")).centroids; chunk_size=16_384)
            for id in ids)
        for id in ids
            others = filter(!=(id), ids)
            aris = [_adjusted_rand_index(labels_by_run[id], labels_by_run[other]) for other in others]
            metrics_path = joinpath(state.run_dirs[id], "tc4_metrics.toml")
            metrics = TOML.parsefile(metrics_path)
            metrics["seed_stability_ari_mean"] = isempty(aris) ? 1.0 : mean(aris)
            metrics["stability_sample_size"] = sample_count
            open(metrics_path, "w") do io
                TOML.print(io, metrics)
            end
        end
    end
    _write_tc4_summaries!(state, k_values)
    _set_stage!(state, 4, "tc4_codebooks_and_metrics", true)
    return (; method, codebooks=length(state.run_ids), run_ids=copy(state.run_ids),
        descriptors=size(state.descriptor_matrix, 2), status_counts=Dict(s=>count(==(s), values(state.checks)) for s in ("FITTED", "NON_CONVERGED", "DEGENERATE_WARNING")))
end
