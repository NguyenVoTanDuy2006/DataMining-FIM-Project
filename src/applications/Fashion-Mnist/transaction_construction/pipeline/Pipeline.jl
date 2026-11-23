"""Chuẩn bị phiên TC, tách thư mục làm việc local khỏi đích lưu checkpoint/Drive."""
function _prepare_split_run(config_path, config; data_dir, repo_root, output_root, work_root)
    run = config["run"]
    mode = run["mode"]
    configured_output = _repo_path(repo_root, run["output_root"])
    output_root = isnothing(output_root) ? configured_output : normpath(abspath(output_root))
    work_root = isnothing(work_root) ? mktempdir(prefix="fashion-tc-work-") : normpath(abspath(work_root))
    backend = get(get(config, "execution", Dict()), "backend", "cpu")
    backend == "cpu" || throw(ArgumentError("execution.backend hiện chỉ hỗ trợ cpu"))
    dataset_config = config["dataset"]
    patch_config = config["tc1_patch_extraction"]
    filter_config = config["tc2_patch_filtering"]
    codebook_config = config["tc4_codebook"]
    mode == "smoke" && run["run_id"] != "T2_K8_seed42" && error("Smoke run_id phải là T2_K8_seed42")
    patch_config["patch_size"] == [4, 4] && patch_config["stride"] == [4, 4] ||
        throw(ArgumentError("TC notebook hiện hỗ trợ patch 4×4, stride 4"))
    if mode == "smoke"
        occursin(joinpath("tc", "smoke", "T2_K8_seed42"), configured_output) ||
            throw(ArgumentError("Smoke artifacts phải nằm trong thư mục riêng T2_K8_seed42"))
        dataset_config["selection"] == "stratified_deterministic" || error("Smoke yêu cầu lấy mẫu phân tầng")
        config["tc0_preprocessing"]["fit_split"] == "smoke_train_only" || error("Smoke yêu cầu fit Q10 trên train")
        filter_config["experiment"] == "T2" && !filter_config["run_other_filter_variants"] ||
            error("Smoke chỉ chạy T2")
        codebook_config["number_of_fits"] == 1 && !codebook_config["run_k_grid"] ||
            error("Smoke chỉ cho phép một lần fit")
    else
        occursin(joinpath("tc", "benchmark"), configured_output) ||
            throw(ArgumentError("Full output phải nằm trong results/fashion/tc/benchmark"))
        dataset_config["use_original_split"] || error("Full phải giữ nguyên split gốc")
        codebook_config["image_sampling"] == false && codebook_config["descriptor_sampling"] == false ||
            error("Full phải dùng toàn bộ ảnh và descriptor train")
    end
    output_root == work_root && throw(ArgumentError("work_root và output_root phải khác nhau"))
    isdir(work_root) && !isempty(readdir(work_root)) &&
        throw(ArgumentError("Thư mục làm việc local phải rỗng: $work_root"))
    mkpath(output_root)
    mkpath(work_root)
    return TCState(abspath(config_path), abspath(data_dir), output_root, work_root,
        config, Dict{String,String}(), Dict{Symbol,Any}(
            :mode => mode, :backend => backend,
            :timings => Dict{String,Float64}(),
        ), time())
end

function _prepare_combined_run(config_path, config; repo_root, data_dir,
    dataset_manifest_path)
    run = config["run"]
    dataset = config["dataset"]
    mode = run["mode"]
    mode in ("smoke", "full", "release") || error("run.mode must be smoke, full, or release")
    config["execution"]["backend"] == "cpu" ||
        error("CPU notebook rejects non-CPU execution.backend")
    config["tc2_patch_filtering"]["foreground_threshold"] == 29 ||
        error("TC v2 requires the fixed foreground threshold 29")
    config["tc2_patch_filtering"]["threshold_comparison"] == "strict_greater" ||
        error("TC v2 requires the strict pixel > 29 comparison")
    _validate_training_method(config["tc4_codebook"]["training_method"])
    if mode in ("full", "release")
        get(dataset, "expected_images", 0) == 70_000 || error("Full mode must expect 70,000 images")
        get(dataset, "use_all_images", false) || error("Full mode must use all images")
    else
        get(dataset, "smoke_per_class", 0) > 0 || error("Smoke mode needs smoke_per_class > 0")
    end

    data_dir = isnothing(data_dir) ? _repo_path(repo_root, dataset["data_dir"]) : abspath(data_dir)
    output_root = _repo_path(repo_root, run["output_root"])
    if mode == "release"
        isnothing(dataset_manifest_path) && error("Release mode requires dataset_manifest_path from Notebook 01")
        manifest_path = normpath(abspath(dataset_manifest_path))
        manifest = read_dataset_manifest(manifest_path; verify_archives=true, repo_root)
        manifest["dataset"] == "Fashion-MNIST" || error("Release manifest is for a different dataset")
        manifest["train_count"] == 60_000 && manifest["test_count"] == 10_000 ||
            error("Release manifest split counts differ from Fashion-MNIST")
        run["run_id"] = manifest["run_id"]
        run["dataset_manifest_path"] = relpath(manifest_path, repo_root)
        output_root = _repo_path(repo_root, manifest["run_root"])
        expected_root = normpath(joinpath(_repo_path(repo_root, run["output_root"]), manifest["run_id"]))
        output_root == expected_root || error("Dataset manifest run_root does not match this release profile")
        codebook = config["tc4_codebook"]
        codebook["training_method"] == "raw_full_batch_kmeans" ||
            error("Release profile requires B0 raw full-batch K-means")
        codebook["k_candidates"] == [32] && codebook["random_seeds"] == [123] ||
            error("Release profile is fixed to K=32 and seed=123")
        config["tc6_transaction_encoding"]["variant"] == "S0" ||
            error("Release profile requires S0")
    end
    isdir(data_dir) || error("Fashion-MNIST archive directory not found: $data_dir")
    mkpath(output_root)

    # Loading both original splits gives every image a stable, global ID before
    # any optional smoke selection. No train/validation subset is created.
    train = load_fashion_mnist(data_dir; split=:train)
    test = load_fashion_mnist(data_dir; split=:test)
    images = cat(train.images, test.images; dims=3)
    labels = vcat(train.labels, test.labels)
    ids = collect(1:70_000)
    splits = vcat(fill("train", 60_000), fill("test", 10_000))
    original_indices = vcat(collect(1:60_000), collect(1:10_000))
    if mode == "smoke"
        selected = balanced_smoke_indices(labels, dataset["smoke_per_class"], dataset["sample_seed"])
        images = Array(@view images[:, :, selected])
        labels = labels[selected]
        ids = ids[selected]
        splits = splits[selected]
        original_indices = original_indices[selected]
        length(ids) == dataset["expected_images"] || error("Smoke selection count differs from config")
    else
        length(ids) == dataset["expected_images"] || error("Full image count differs from config")
    end
    hashes = Dict(file.name => _sha256(joinpath(data_dir, file.name)) for file in FASHION_FILES)
    size(images) == (28, 28, length(ids)) || error("Fashion-MNIST image shape is invalid")
    all(x -> 0 <= x <= 255, images) || error("Pixel value outside UInt8 range")

    return TCv2State(config_path, repo_root, data_dir, output_root, config, 0,
        images, labels, ids, splits, original_indices, Matrix{Float32}(undef, 16, 0),
        NamedTuple[], zeros(Int, length(ids)), hashes, String[], Dict{String,String}(),
        Dict{String,String}(), time())
end

function _require_previous(state::TCState, expected::Int)
    get(state.data, :completed_tc, -1) == expected - 1 ||
        error("TC$(expected) phải chạy sau TC$(expected - 1)")
end

function _finish_stage!(state::TCState, number::Int, label::String, summary)
    state.data[:completed_tc] = number
    return (; tc="TC$number", label, summary)
end

function _require_stage(state, expected)
    state.stage == expected - 1 || error("TC$expected expected after TC$(expected - 1); current stage=$(state.stage)")
end

function _set_stage!(state, stage, key, passed=true)
    state.checks[key] = passed ? "PASS" : "FAIL"
    passed || error("$key failed")
    state.stage = stage
end

"""
    prepare_run(config_path; data_dir, repo_root, output_root, work_root, dataset_manifest_path)

Prepare transaction construction from either supported TOML profile. Split
profiles use separate train/validation outputs. Combined profiles use the S0
JSONL contract and accept a dataset manifest in release mode.
"""
function prepare_run(config_path; data_dir=nothing, repo_root=nothing,
    output_root=nothing, work_root=nothing, dataset_manifest_path=nothing)
    config_path = abspath(config_path)
    config = read_config(config_path)
    combined = _is_combined_profile(config)
    root = _profile_repo_root(config_path, repo_root, combined)
    if combined
        isnothing(output_root) && isnothing(work_root) ||
            throw(ArgumentError("Combined profiles specify output_root in their config"))
        return _prepare_combined_run(config_path, config; repo_root=root, data_dir, dataset_manifest_path)
    end

    isnothing(data_dir) && throw(UndefKeywordError(:data_dir))
    isnothing(dataset_manifest_path) ||
        throw(ArgumentError("dataset_manifest_path requires a combined release profile"))
    return _prepare_split_run(config_path, config; data_dir, repo_root=root, output_root, work_root)
end

"""Run the configured profile and return its final export summary."""
function run_tc(config_path; notebook_fresh_kernel::Bool=false, kwargs...)
    state = prepare_run(config_path; kwargs...)
    state isa TCState && run_tc0!(state)
    for stage in (run_tc1!, run_tc2!, run_tc3!, run_tc4!, run_tc5!, run_tc6!)
        stage(state)
    end
    return _finish_pipeline!(state, notebook_fresh_kernel)
end

_finish_pipeline!(state::TCState, fresh) = run_tc7!(state; notebook_fresh_kernel=fresh).summary
_finish_pipeline!(state::TCv2State, _) = run_tc7!(state)

"""Run a transaction construction profile configured for smoke execution."""
function run_smoke(config_path; kwargs...)
    read_config(config_path)["run"]["mode"] == "smoke" ||
        throw(ArgumentError("run_smoke yêu cầu mode=smoke"))
    return run_tc(config_path; kwargs...)
end

"""Run a transaction construction profile configured for full execution."""
function run_full(config_path; kwargs...)
    read_config(config_path)["run"]["mode"] == "full" ||
        throw(ArgumentError("run_full yêu cầu mode=full"))
    return run_tc(config_path; kwargs...)
end
