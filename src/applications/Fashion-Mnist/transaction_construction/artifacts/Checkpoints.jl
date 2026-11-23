function _backend(state::TCState)
    return get(state.data, :backend, get(get(state.config, "execution", Dict()), "backend", "cpu"))
end

function _fit_fingerprint(state::TCState, k, seed)
    config = state.config
    values = Dict(
        "backend" => _backend(state),
        "julia_version" => string(VERSION),
        "backend_library_version" => string(Base.pkgversion(Clustering)),
        "data_archive_sha256" => state.data[:archive_checksums],
        "train_descriptor_sha256" => state.data[:descriptor_checksums]["train"],
        "validation_descriptor_sha256" => state.data[:descriptor_checksums]["validation"],
        "k" => k,
        "seed" => seed,
        "max_iterations" => config["tc4_codebook"]["max_iterations"],
        "tolerance" => config["tc4_codebook"]["tolerance"],
        "initialization" => "K-means++",
        "algorithm" => "Lloyd full-batch squared Euclidean",
        "patch_config" => config["tc1_patch_extraction"],
        "filter_config" => config["tc2_patch_filtering"],
        "feature_config" => config["tc3_feature_extraction"],
    )
    canonical = join(["$key=$(repr(values[key]))" for key in sort!(collect(keys(values)))], "\n")
    return bytes2hex(sha256(codeunits(canonical)))
end

function _checkpoint_dir(state::TCState, run_id, fingerprint)
    return joinpath(state.output_root, "checkpoints", _backend(state), run_id, fingerprint)
end

function _history_rows(history)
    return [(row.iteration, row.objective, row.objective_delta,
        row.max_centroid_shift, row.cost_increased) for row in history]
end

function _write_iteration_history(path, history)
    return _write_csv(path,
        ["iteration", "objective", "objective_delta", "max_centroid_shift", "cost_increased"],
        _history_rows(history))
end

function _read_iteration_history(path)
    lines = readlines(path)
    length(lines) <= 1 && return NamedTuple[]
    return [(;
        iteration=parse(Int, fields[1]),
        objective=parse(Float64, fields[2]),
        objective_delta=parse(Float64, fields[3]),
        max_centroid_shift=parse(Float64, fields[4]),
        cost_increased=parse(Bool, fields[5]),
    ) for fields in (split(line, ',') for line in lines[2:end])]
end

function _load_fit_checkpoint(state::TCState, run_id, k, seed, fingerprint)
    checkpoint = _checkpoint_dir(state, run_id, fingerprint)
    metadata_path = joinpath(checkpoint, "checkpoint.toml")
    codebook_path = joinpath(checkpoint, "codebook.bin")
    history_path = joinpath(checkpoint, "iteration_history.csv")
    isfile(metadata_path) || return nothing
    isfile(codebook_path) && isfile(history_path) ||
        throw(ArgumentError("Checkpoint không hoàn chỉnh: $checkpoint"))
    metadata = TOML.parsefile(metadata_path)
    get(metadata, "complete", false) || throw(ArgumentError("Checkpoint chưa hoàn tất: $checkpoint"))
    metadata["fingerprint"] == fingerprint || throw(ArgumentError("Fingerprint checkpoint không khớp: $checkpoint"))
    metadata["backend"] == _backend(state) || throw(ArgumentError("Không thể dùng checkpoint backend khác"))
    metadata["run_id"] == run_id || throw(ArgumentError("run_id trong checkpoint không khớp"))
    metadata["k"] == k && metadata["seed"] == seed ||
        throw(ArgumentError("K hoặc seed trong checkpoint không khớp"))
    metadata["train_descriptor_sha256"] == state.data[:descriptor_checksums]["train"] ||
        throw(ArgumentError("Checkpoint dùng descriptor train khác"))
    metadata["validation_descriptor_sha256"] == state.data[:descriptor_checksums]["validation"] ||
        throw(ArgumentError("Checkpoint dùng descriptor validation khác"))
    bytes2hex(open(sha256, codebook_path)) == metadata["codebook_sha256"] ||
        throw(ArgumentError("Checksum codebook trong checkpoint không khớp"))
    bytes2hex(open(sha256, history_path)) == metadata["history_sha256"] ||
        throw(ArgumentError("Checksum iteration history trong checkpoint không khớp"))
    centroids = open(deserialize, codebook_path)
    size(centroids) == (state.config["tc3_feature_extraction"]["dimension"], k) ||
        throw(ArgumentError("Kích thước codebook trong checkpoint sai"))
    return (; centroids, objective=Float64(metadata["objective"]),
        iterations=Int(metadata["iterations"]), converged=Bool(metadata["converged"]),
        stop_reason=String(metadata["stop_reason"]), history=_read_iteration_history(history_path),
        initialization_seconds=Float64(get(metadata, "initialization_seconds", NaN)),
        fit_seconds=Float64(get(metadata, "fit_seconds", NaN)),
        library=String(metadata["library"]), library_version=String(metadata["library_version"]),
        initialization=String(metadata["initialization"]), maxiter=Int(metadata["max_iterations"]),
        tolerance=Float64(metadata["tolerance"]),
        backend=String(metadata["backend"]), resumed=true)
end

function _save_fit_checkpoint!(state::TCState, run_id, k, seed, fingerprint, model, run_dir)
    local_checkpoint = joinpath(run_dir, "fit_checkpoint")
    mkpath(local_checkpoint)
    codebook_path = joinpath(local_checkpoint, "codebook.bin")
    history_path = joinpath(local_checkpoint, "iteration_history.csv")
    open(codebook_path, "w") do io
        serialize(io, Matrix{Float32}(model.centroids))
    end
    _write_iteration_history(history_path, model.history)
    metadata = Dict(
        "complete" => true,
        "fingerprint" => fingerprint,
        "backend" => _backend(state),
        "run_id" => run_id,
        "k" => k,
        "seed" => seed,
        "julia_version" => string(VERSION),
        "library" => model.library,
        "library_version" => model.library_version,
        "initialization" => model.initialization,
        "max_iterations" => model.maxiter,
        "tolerance" => model.tolerance,
        "iterations" => model.iterations,
        "converged" => model.converged,
        "stop_reason" => model.stop_reason,
        "objective" => model.objective,
        "initialization_seconds" => model.initialization_seconds,
        "fit_seconds" => model.fit_seconds,
        "train_descriptor_sha256" => state.data[:descriptor_checksums]["train"],
        "validation_descriptor_sha256" => state.data[:descriptor_checksums]["validation"],
        "source_archive_sha256" => state.data[:archive_checksums],
        "codebook_sha256" => bytes2hex(open(sha256, codebook_path)),
        "history_sha256" => bytes2hex(open(sha256, history_path)),
    )
    metadata_path = joinpath(local_checkpoint, "checkpoint.toml")
    open(metadata_path, "w") do io
        TOML.print(io, metadata; sorted=true)
    end

    target = _checkpoint_dir(state, run_id, fingerprint)
    mkpath(dirname(target))
    ispath(target) && throw(ArgumentError("Đích checkpoint đã tồn tại nhưng không được nạp: $target"))
    temporary_target = mktempdir(dirname(target); prefix=".$(basename(target)).tmp-")
    transfer_started = time()
    try
        for filename in ("codebook.bin", "iteration_history.csv")
            cp(joinpath(local_checkpoint, filename), joinpath(temporary_target, filename))
        end
        for filename in ("codebook.bin", "iteration_history.csv")
            source = joinpath(local_checkpoint, filename)
            copied = joinpath(temporary_target, filename)
            bytes2hex(open(sha256, source)) == bytes2hex(open(sha256, copied)) ||
                error("Checkpoint Drive không khớp checksum: $filename")
        end
        cp(metadata_path, joinpath(temporary_target, "checkpoint.toml"))
        bytes2hex(open(sha256, metadata_path)) ==
            bytes2hex(open(sha256, joinpath(temporary_target, "checkpoint.toml"))) ||
            error("Checkpoint metadata trên Drive không khớp checksum")
        mv(temporary_target, target)
    finally
        isdir(temporary_target) && rm(temporary_target; recursive=true, force=true)
    end
    return time() - transfer_started
end

function _run_output_dir(state::TCState, run_id)
    return state.data[:mode] == "smoke" ? state.work_root : joinpath(state.work_root, "runs", run_id)
end

function _canonical_sha(value)
    return bytes2hex(sha256(codeunits(repr(value))))
end

function _run_name(method, k, seed)
    suffix = method == "raw_full_batch_kmeans" ? "B0" : "Q20"
    return "FashionMNIST_T2_S0_$(suffix)_K$(k)_seed$(seed)"
end

function _run_directory(state, run_id)
    state.config["run"]["mode"] == "release" && return joinpath(state.output_root, "transactions")
    return joinpath(state.output_root, run_id)
end

function _write_fit_checkpoint!(state, run_id, k, seed, fingerprint, model, metrics)
    run_dir = _run_directory(state, run_id)
    mkpath(run_dir)
    codebook_path = joinpath(run_dir, "codebook.bin")
    open(codebook_path, "w") do io
        serialize(io, (; centroids=model.centroids, layout="16xK_descriptors_as_columns",
            word_id_base=1, k, seed, method=state.config["tc4_codebook"]["training_method"]))
    end
    open(joinpath(run_dir, "tc4_metrics.toml"), "w") do io
        TOML.print(io, metrics)
    end
    checkpoint = Dict("run_id"=>run_id, "fingerprint"=>fingerprint, "method"=>state.config["tc4_codebook"]["training_method"],
        "k"=>k, "seed"=>seed, "status"=>metrics["status"], "codebook_sha256"=>_sha256(codebook_path),
        "julia_version"=>string(VERSION), "library"=>model.library,
        "library_version"=>model.library_version, "iterations"=>model.iterations,
        "converged"=>model.converged, "fit_seconds"=>model.fit_seconds)
    open(joinpath(run_dir, "checkpoint.toml"), "w") do io
        TOML.print(io, checkpoint)
    end
end

function _load_codebook(path)
    return open(deserialize, path)
end
