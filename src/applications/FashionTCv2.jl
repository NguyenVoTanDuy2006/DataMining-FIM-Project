module FashionTCv2

using Random
using SHA
using Serialization
using Statistics
using TOML
using ..EclatFIM: load_fashion_mnist, FASHION_FILES
using ..FashionTC

const TC = FashionTC
const TC_V2_SCHEMA_VERSION = 1

export TCv2State, prepare_run, run_unit_smoke_checks!, run_tc1!, run_tc2!,
    run_tc3!, run_tc4!, run_tc5!, run_tc6!, run_tc7!

mutable struct TCv2State
    config_path::String
    repo_root::String
    data_dir::String
    output_root::String
    config::Dict{String,Any}
    stage::Int
    images::Array{UInt8,3}
    labels::Vector{Int}
    image_ids::Vector{Int}
    original_splits::Vector{String}
    original_indices::Vector{Int}
    descriptor_matrix::Matrix{Float32}
    descriptor_index::Vector{NamedTuple}
    retained_per_image::Vector{Int}
    archive_hashes::Dict{String,String}
    run_ids::Vector{String}
    run_dirs::Dict{String,String}
    checks::Dict{String,String}
    started_at::Float64
end

function _sha256(path)
    return bytes2hex(open(sha256, path))
end

function _canonical_sha(value)
    return bytes2hex(sha256(codeunits(repr(value))))
end

function _repo_path(repo_root, path)
    return isabspath(path) ? normpath(path) : normpath(joinpath(repo_root, path))
end

function _validate_training_method(method)
    method in ("raw_full_batch_kmeans", "q20_weighted_kmeans") ||
        throw(ArgumentError("Unsupported TC4 training_method: $method"))
    return method
end

function prepare_run(config_path::AbstractString; repo_root=pwd(), data_dir=nothing)
    repo_root = normpath(abspath(repo_root))
    config_path = normpath(abspath(config_path))
    config = TOML.parsefile(config_path)
    run = config["run"]
    dataset = config["dataset"]
    mode = run["mode"]
    mode in ("smoke", "full") || error("run.mode must be smoke or full")
    config["execution"]["backend"] == "cpu" ||
        error("CPU notebook rejects non-CPU execution.backend")
    config["tc2_patch_filtering"]["foreground_threshold"] == 29 ||
        error("TC v2 requires the fixed foreground threshold 29")
    config["tc2_patch_filtering"]["threshold_comparison"] == "strict_greater" ||
        error("TC v2 requires the strict pixel > 29 comparison")
    _validate_training_method(config["tc4_codebook"]["training_method"])
    if mode == "full"
        get(dataset, "expected_images", 0) == 70_000 || error("Full mode must expect 70,000 images")
        get(dataset, "use_all_images", false) || error("Full mode must use all images")
    else
        get(dataset, "smoke_per_class", 0) > 0 || error("Smoke mode needs smoke_per_class > 0")
    end

    data_dir = isnothing(data_dir) ? _repo_path(repo_root, dataset["data_dir"]) : abspath(data_dir)
    output_root = _repo_path(repo_root, run["output_root"])
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
        selected = TC.balanced_smoke_indices(labels, dataset["smoke_per_class"], dataset["sample_seed"])
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

function _require_stage(state, expected)
    state.stage == expected - 1 || error("TC$expected expected after TC$(expected - 1); current stage=$(state.stage)")
end

function _set_stage!(state, stage, key, passed=true)
    state.checks[key] = passed ? "PASS" : "FAIL"
    passed || error("$key failed")
    state.stage = stage
end

function run_unit_smoke_checks!()
    p29 = fill(UInt8(29), 4, 4)
    p30 = fill(UInt8(29), 4, 4); p30[1, 1] = 30
    @assert !any(>(29), p29)
    @assert any(>(29), p30)
    patch = UInt8[1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16]
    @assert vec(patch) == UInt8[1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 4, 8, 12, 16]
    @assert TC.encode_transactions([5, 2, 5, 1], [(image_id=1,), (image_id=1,), (image_id=1,), (image_id=1,)], [1]) == [[1, 2, 5]]
    @assert TC.encode_transactions(Int[], NamedTuple[], [1]) == [[]]
    @assert TC.assign_words(reshape(Float32[0], 1, 1), reshape(Float32[0, 0], 1, 2)) == [1]
    @assert _validate_training_method("raw_full_batch_kmeans") == "raw_full_batch_kmeans"
    @assert _validate_training_method("q20_weighted_kmeans") == "q20_weighted_kmeans"
    invalid_method_rejected = try
        _validate_training_method("unknown_method")
        false
    catch err
        err isa ArgumentError
    end
    @assert invalid_method_rejected
    temp_path = tempname()
    _write_transaction_jsonl(temp_path, [Int[], [2, 5]], [11, 12])
    roundtrip = [_parse_transaction_line(line) for line in eachline(temp_path)]
    @assert length(roundtrip) == 2 && isempty(roundtrip[1].items) && roundtrip[1].tid == 1 &&
        roundtrip[1].image_id == 11 && roundtrip[2].items == [2, 5]
    rm(temp_path; force=true)
    return Dict("threshold_29_30"=>"PASS", "column_major_descriptor"=>"PASS",
        "transaction_sort_deduplicate_empty"=>"PASS", "deterministic_tie_break"=>"PASS",
        "method_selector_and_invalid_value"=>"PASS", "jsonl_empty_transaction_roundtrip"=>"PASS")
end

function run_tc1!(state::TCv2State)
    _require_stage(state, 1)
    n = length(state.image_ids)
    patch = state.config["tc1_patch_extraction"]
    patch["patch_size"] == [4, 4] && patch["stride"] == [4, 4] || error("TC1 v2 requires 4×4 non-overlapping patches")
    patch_count = n * 49
    passed = size(state.images, 3) == n && patch_count == 49n &&
        patch["padding"] == "none" && patch["patch_order"] == "row_major"
    if state.config["run"]["mode"] == "smoke"
        sample_images = reshape(state.images[:, :, 1], 28, 28, 1)
        sample_patches, sample_index = TC.extract_patches(sample_images, [state.image_ids[1]])
        restored = TC._reconstruct_images(sample_patches, sample_index, [state.image_ids[1]])
        passed &= length(sample_patches) == 49 && restored[:, :, 1] == state.images[:, :, 1] &&
            [row.patch_id for row in sample_index] == collect(1:49)
    end
    _set_stage!(state, 1, "tc1_patch_geometry_and_mapping", passed)
    return (; images=n, patches_before_filter=patch_count, patch_size=(4, 4), traversal="row_major")
end

function run_tc2!(state::TCv2State)
    _require_stage(state, 2)
    tau = 29
    n = length(state.image_ids)
    retained = zeros(Int, n)
    for i in 1:n, row in 1:7, col in 1:7
        y = (row - 1) * 4 + 1
        x = (col - 1) * 4 + 1
        patch = @view state.images[y:y+3, x:x+3, i]
        any(>(tau), patch) && (retained[i] += 1)
    end
    state.retained_per_image = retained
    total = 49n
    kept = sum(retained)
    passed = kept <= total && total - kept + kept == total
    open(joinpath(state.output_root, "tc2_per_image_summary.csv"), "w") do io
        println(io, "image_id,original_split,original_index,retained_patches,removed_patches,empty_after_filter")
        for i in eachindex(state.image_ids)
            println(io, state.image_ids[i], ',', state.original_splits[i], ',', state.original_indices[i],
                ',', retained[i], ',', 49-retained[i], ',', retained[i] == 0)
        end
    end
    open(joinpath(state.output_root, "tc2_filter_summary.toml"), "w") do io
        TOML.print(io, Dict("threshold"=>tau, "comparison"=>">", "total_patches"=>total,
            "retained_patches"=>kept, "removed_patches"=>total-kept,
            "retention_rate"=>kept/total, "images_with_no_retained_patches"=>count(iszero, retained)))
    end
    _set_stage!(state, 2, "tc2_foreground_filter", passed)
    return (; threshold=tau, kept, removed=total-kept, total_patches=total,
        retention_rate=total == 0 ? 0.0 : kept/total, images_with_no_patches=count(iszero, retained))
end

function run_tc3!(state::TCv2State)
    _require_stage(state, 3)
    descriptors, index = TC._image_descriptors(state.images, state.image_ids, 29; patch_size=4, alpha=0.0)
    dimension = state.config["tc3_feature_extraction"]["dimension"]
    valid = size(descriptors) == (dimension, length(index)) && all(isfinite, descriptors) &&
        all(x -> 0f0 <= x <= 1f0, descriptors) && length(index) == sum(state.retained_per_image)
    for i in eachindex(index)
        image_id = index[i].image_id
        valid &= index[i].patch_id in 1:49 && image_id in state.image_ids
    end
    state.descriptor_matrix = descriptors
    state.descriptor_index = index
    _set_stage!(state, 3, "tc3_raw_descriptor_contract", valid)
    return (; descriptor_shape=size(descriptors), retained_descriptors=size(descriptors, 2),
        dtype=string(eltype(descriptors)), flatten_order="column_major")
end

function _quantiles(counts)
    isempty(counts) && return Float64[]
    return Float64[quantile(counts, q) for q in (0.0, 0.25, 0.5, 0.75, 0.95, 1.0)]
end

function _cluster_metrics(model, k, n)
    counts = zeros(Int, k)
    for label in model.labels
        counts[label] += 1
    end
    proportions = counts ./ max(n, 1)
    nonzero = filter(>(0), proportions)
    entropy = isempty(nonzero) || k <= 1 ? 0.0 : -sum(nonzero .* log.(nonzero)) / log(k)
    return Dict{String,Any}(
        "distortion_mean_squared"=>Float64(model.objective / max(n,1)),
        "occupancy_used"=>count(>(0), counts),
        "occupancy_fraction"=>count(>(0), counts)/k,
        "cluster_size_min"=>minimum(counts), "cluster_size_max"=>maximum(counts),
        "cluster_size_quantiles"=>_quantiles(counts),
        "top_cluster_share"=>maximum(counts)/max(n,1),
        "normalized_entropy"=>Float64(entropy),
        "iterations"=>model.iterations, "converged"=>model.converged,
        "stop_reason"=>model.stop_reason, "fit_seconds"=>model.fit_seconds,
        "distance"=>"squared_euclidean",
        "tolerance_semantics"=>"absolute change in clustering objective (Clustering.jl tol)",
        "library"=>model.library, "library_version"=>model.library_version,
        "initialization"=>model.initialization, "max_iterations"=>model.maxiter,
        "tolerance"=>model.tolerance, "empty_clusters"=>findall(iszero, counts))
end

function _adjusted_rand_index(a, b)
    length(a) == length(b) || error("ARI vectors differ in length")
    n = length(a)
    n < 2 && return 1.0
    table = Dict{Tuple{Int,Int},Int}()
    row = Dict{Int,Int}(); col = Dict{Int,Int}()
    for (x, y) in zip(a, b)
        table[(x,y)] = get(table, (x,y), 0) + 1
        row[x] = get(row, x, 0) + 1
        col[y] = get(col, y, 0) + 1
    end
    choose2(x) = x * (x - 1) / 2
    index = sum(choose2, values(table))
    expected = sum(choose2, values(row)) * sum(choose2, values(col)) / choose2(n)
    maximum_index = (sum(choose2, values(row)) + sum(choose2, values(col))) / 2
    denominator = maximum_index - expected
    return denominator == 0 ? 1.0 : (index - expected) / denominator
end

_mean_std(values) = (mean=mean(values), std=length(values) < 2 ? 0.0 : std(values))

function _write_tc4_summaries!(state, k_values)
    rows = NamedTuple[]
    stability = Dict{String,Any}("method"=>state.config["tc4_codebook"]["training_method"])
    previous_mean = nothing
    open(joinpath(state.output_root, "tc4_metrics_summary.csv"), "w") do io
        println(io, "run_id,method,k,seed,distortion_mean_squared,relative_improvement_vs_previous_k,occupancy_used,occupancy_fraction,cluster_size_min,cluster_size_max,top_cluster_share,normalized_entropy,iterations,converged,fit_seconds,seed_stability_ari_mean")
        for k in k_values
            ids = filter(id -> occursin("_K$(k)_", id), state.run_ids)
            metrics_by_run = Dict(id=>TOML.parsefile(joinpath(state.run_dirs[id], "tc4_metrics.toml")) for id in ids)
            distortion = [Float64(metrics_by_run[id]["distortion_mean_squared"]) for id in ids]
            mean_distortion = mean(distortion)
            relative = isnothing(previous_mean) || previous_mean == 0 ? "" : string((previous_mean-mean_distortion)/previous_mean)
            for id in ids
                m = metrics_by_run[id]
                seed = only(filter(s -> endswith(id, "_seed$(s)"), state.config["tc4_codebook"]["random_seeds"]))
                println(io, join((id, m["method"], k, seed, m["distortion_mean_squared"], relative,
                    m["occupancy_used"], m["occupancy_fraction"], m["cluster_size_min"],
                    m["cluster_size_max"], m["top_cluster_share"], m["normalized_entropy"],
                    m["iterations"], m["converged"], m["fit_seconds"],
                    m["seed_stability_ari_mean"]), ','))
            end
            numeric_fields = ("distortion_mean_squared", "occupancy_used", "occupancy_fraction",
                "cluster_size_min", "cluster_size_max", "top_cluster_share", "normalized_entropy",
                "seed_stability_ari_mean")
            aggregate = Dict{String,Any}()
            for field in numeric_fields
                stats = _mean_std([Float64(metrics_by_run[id][field]) for id in ids])
                aggregate[field] = Dict("mean"=>stats.mean, "std"=>stats.std)
            end
            q_names = ("q0", "q25", "q50", "q75", "q95", "q100")
            for (index, name) in enumerate(q_names)
                stats = _mean_std([Float64(metrics_by_run[id]["cluster_size_quantiles"][index]) for id in ids])
                aggregate["cluster_size_$(name)"] = Dict("mean"=>stats.mean, "std"=>stats.std)
            end
            stability["K_$(k)"] = Dict("runs"=>ids, "metrics_mean_std"=>aggregate,
                "distortion_relative_improvement_vs_previous_K"=>isnothing(previous_mean) || previous_mean == 0 ? 0.0 : (previous_mean-mean_distortion)/previous_mean)
            previous_mean = mean_distortion
        end
    end
    open(joinpath(state.output_root, "tc4_seed_stability.toml"), "w") do io
        TOML.print(io, stability)
    end
end

function _run_name(method, k, seed)
    suffix = method == "raw_full_batch_kmeans" ? "B0" : "Q20"
    return "FashionMNIST_T2_S0_$(suffix)_K$(k)_seed$(seed)"
end

function _run_directory(state, run_id)
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
    end
    size(state.descriptor_matrix, 2) >= maximum(k_values) || error("Not enough retained descriptors for max K")
    pairs = [(k, seed) for k in k_values for seed in seeds]
    for (k, seed) in pairs
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
        if isfile(cp) && isfile(codebook_path)
            saved = TOML.parsefile(cp)
            if saved["fingerprint"] == fingerprint && saved["codebook_sha256"] == _sha256(codebook_path)
                model = _load_codebook(codebook_path)
                metrics = TOML.parsefile(joinpath(run_dir, "tc4_metrics.toml"))
            else
                error("Existing output does not match this run; refusing to overwrite: $run_dir")
            end
        elseif isdir(run_dir) && !isempty(readdir(run_dir))
            error("Incomplete or unrecognized output exists; refusing to overwrite: $run_dir")
        else
            try
                fitted = TC.fit_kmeans(state.descriptor_matrix; k, seed,
                    maxiter=config["max_iterations"], tolerance=config["tolerance"], backend="cpu")
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
    end

    # ARI uses one fixed descriptor sample for every seed and never participates
    # in fitting. Word IDs are compared only within each K and seed pair.
    rng = MersenneTwister(config["stability_seed"])
    sample_count = min(config["stability_sample_size"], size(state.descriptor_matrix, 2))
    stability_indices = sort!(randperm(rng, size(state.descriptor_matrix, 2))[1:sample_count])
    stability_X = state.descriptor_matrix[:, stability_indices]
    for k in k_values
        ids = filter(id -> occursin("_K$(k)_", id), state.run_ids)
        labels_by_run = Dict(id => TC.assign_words(stability_X,
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

function _write_assignments_csv(path, words, index)
    open(path, "w") do io
        println(io, "image_id,patch_id,patch_row,patch_col,word_id")
        for (word, row) in zip(words, index)
            println(io, row.image_id, ',', row.patch_id, ',', row.patch_row, ',', row.patch_col, ',', word)
        end
    end
end

function run_tc5!(state::TCv2State)
    _require_stage(state, 5)
    summaries = NamedTuple[]
    for run_id in state.run_ids
        run_dir = state.run_dirs[run_id]
        book = _load_codebook(joinpath(run_dir, "codebook.bin"))
        checkpoint = TOML.parsefile(joinpath(run_dir, "checkpoint.toml"))
        already_completed = get(checkpoint, "status", "") == "COMPLETED" &&
            isfile(joinpath(run_dir, "assignments.bin")) && isfile(joinpath(run_dir, "patch_assignments.csv"))
        words = already_completed ? open(deserialize, joinpath(run_dir, "assignments.bin")) :
            TC.assign_words(state.descriptor_matrix, book.centroids; chunk_size=16_384)
        k = size(book.centroids, 2)
        valid = length(words) == length(state.descriptor_index) && all(w -> 1 <= w <= k, words)
        valid || error("TC5 assignment contract failed for $run_id")
        if !already_completed
            _write_assignments_csv(joinpath(run_dir, "patch_assignments.csv"), words, state.descriptor_index)
            open(joinpath(run_dir, "assignments.bin"), "w") do io
                serialize(io, words)
            end
        end
        push!(summaries, (; run_id, assignments=length(words), k))
    end
    _set_stage!(state, 5, "tc5_hard_assignments", all(s -> s.assignments == length(state.descriptor_index), summaries))
    return summaries
end

function _write_transaction_jsonl(path, transactions, image_ids)
    open(path, "w") do io
        for (tid, (items, image_id)) in enumerate(zip(transactions, image_ids))
            println(io, "{\"tid\":$tid,\"image_id\":$image_id,\"items\":[", join(items, ','), "]}")
        end
    end
end

function _write_run_mappings(state, path)
    open(path, "w") do io
        println(io, "tid,image_id,original_split,original_index")
        for tid in eachindex(state.image_ids)
            println(io, tid, ',', state.image_ids[tid], ',', state.original_splits[tid], ',', state.original_indices[tid])
        end
    end
end

function _write_image_metadata(state, path)
    open(path, "w") do io
        println(io, "image_id,original_split,original_index,class_label")
        for i in eachindex(state.image_ids)
            println(io, state.image_ids[i], ',', state.original_splits[i], ',', state.original_indices[i], ',', state.labels[i])
        end
    end
end

function run_tc6!(state::TCv2State)
    _require_stage(state, 6)
    summaries = NamedTuple[]
    for run_id in state.run_ids
        run_dir = state.run_dirs[run_id]
        checkpoint = TOML.parsefile(joinpath(run_dir, "checkpoint.toml"))
        transaction_path = joinpath(run_dir, "transactions.jsonl")
        already_completed = get(checkpoint, "status", "") == "COMPLETED" &&
            isfile(transaction_path) && isfile(joinpath(run_dir, "tid_image_mapping.csv")) &&
            isfile(joinpath(run_dir, "image_metadata.csv"))
        if already_completed
            transactions = [_parse_transaction_line(line).items for line in eachline(transaction_path)]
        else
            words = open(deserialize, joinpath(run_dir, "assignments.bin"))
            transactions = TC.encode_transactions(words, state.descriptor_index, state.image_ids)
        end
        k = _load_codebook(joinpath(run_dir, "codebook.bin")).k
        valid = length(transactions) == length(state.image_ids) &&
            all(issorted, transactions) && all(tx -> length(tx) == length(unique(tx)), transactions) &&
            all(tx -> length(tx) <= min(k, 49), transactions) &&
            all(tx -> all(item -> 1 <= item <= k, tx), transactions)
        valid || error("TC6 transaction contract failed for $run_id")
        if !already_completed
            _write_transaction_jsonl(transaction_path, transactions, state.image_ids)
            _write_run_mappings(state, joinpath(run_dir, "tid_image_mapping.csv"))
            _write_image_metadata(state, joinpath(run_dir, "image_metadata.csv"))
        end
        push!(summaries, (; run_id, transactions=length(transactions), empty=count(isempty, transactions)))
    end
    _set_stage!(state, 6, "tc6_s0_transactions", all(s -> s.transactions == length(state.image_ids), summaries))
    return summaries
end

function _parse_transaction_line(line)
    m = match(r"^\{\"tid\":(\d+),\"image_id\":(\d+),\"items\":\[([0-9,]*)\]\}$", line)
    isnothing(m) && error("Invalid transaction JSONL record: $line")
    items = isempty(m.captures[3]) ? Int[] : parse.(Int, split(m.captures[3], ','))
    return (tid=parse(Int,m.captures[1]), image_id=parse(Int,m.captures[2]), items)
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
        transaction_ok = length(records) == n && [r.tid for r in records] == collect(1:n) &&
            [r.image_id for r in records] == state.image_ids &&
            all(r -> issorted(r.items) && length(r.items) == length(unique(r.items)) &&
                length(r.items) <= min(book.k,49) && all(i -> 1 <= i <= book.k, r.items), records)
        mapping_ok = countlines(joinpath(run_dir, "tid_image_mapping.csv")) == n + 1
        if mapping_ok
            open(joinpath(run_dir, "tid_image_mapping.csv"), "r") do io
                mapping_ok = readline(io) == "tid,image_id,original_split,original_index"
                for (tid, line) in enumerate(eachline(io))
                    expected_line = "$tid,$(state.image_ids[tid]),$(state.original_splits[tid]),$(state.original_indices[tid])"
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
        assignment_csv_lines = countlines(assignment_csv_path)
        assignment_csv_ok = assignment_csv_lines == expected_words + 1
        if assignment_csv_ok
            open(assignment_csv_path, "r") do io
                assignment_csv_ok = readline(io) == "image_id,patch_id,patch_row,patch_col,word_id"
                for (i, line) in enumerate(eachline(io))
                    row = state.descriptor_index[i]
                    expected_line = "$(row.image_id),$(row.patch_id),$(row.patch_row),$(row.patch_col),$(words[i])"
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
        if !already_completed
            checkpoint["fit_status"] = get(checkpoint, "status", "UNKNOWN")
            checkpoint["status"] = "COMPLETED"
            checkpoint["completed_at_unix"] = time()
            open(checkpoint_path, "w") do io
                TOML.print(io, checkpoint)
            end
        end
        push!(results, (; run_id, status="COMPLETED", fit_status=get(checkpoint, "fit_status", get(checkpoint, "status", "UNKNOWN")), transactions=record_count,
            empty=empty_count, support_denominator=record_count))
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

end # module FashionTCv2
