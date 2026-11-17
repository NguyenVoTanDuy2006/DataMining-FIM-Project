module FashionTC

using Clustering
using Random
using SHA
using Serialization
using Statistics
using Tar
using TOML

const DEFAULT_GPU_BATCH_SIZE = 65_536

export read_config, balanced_smoke_indices, fit_q10_positive, extract_patches,
    make_descriptors, fit_kmeans, assign_words, encode_transactions, run_smoke,
    prepare_run, run_tc0!, run_tc1!, run_tc2!, run_tc3!, run_tc4!, run_tc5!,
    run_tc6!, run_tc7!, run_full, run_tc, gpu_available, gpu_device_info,
    gpu_warmup!

mutable struct TCState
    config_path::String
    data_dir::String
    output_root::String
    work_root::String
    config::Dict{String,Any}
    checks::Dict{String,String}
    data::Dict{Symbol,Any}
    started_at::Float64
end

function _cuda_backend()
    extension = Base.get_extension(parentmodule(@__MODULE__), :FashionTCGPUCUDAExt)
    isnothing(extension) && throw(ArgumentError(
        "CUDA backend chưa được nạp. Chạy using CUDA trong project trước khi chọn backend=\"cuda\"."
    ))
    return extension
end

"""Báo CUDA có extension và thiết bị hoạt động trong phiên hiện tại hay không."""
function gpu_available()
    extension = Base.get_extension(parentmodule(@__MODULE__), :FashionTCGPUCUDAExt)
    return !isnothing(extension) && extension.available()
end

"""Trả thông tin thiết bị hiện hành; yêu cầu extension CUDA đã được nạp."""
gpu_device_info() = _cuda_backend().device_info()

"""Làm nóng GPU bằng dữ liệu nhỏ trước khi đo thời gian TC4/TC5."""
gpu_warmup!(; kwargs...) = _cuda_backend().warmup!(; kwargs...)

"""Đọc TOML, chấp nhận smoke/full và kiểm tra output path tách biệt."""
function read_config(path::AbstractString)
    config = TOML.parsefile(path)
    run_config = get(config, "run", Dict())
    mode = get(run_config, "mode", "")
    mode in ("smoke", "full") || throw(ArgumentError("run.mode phải là smoke hoặc full"))
    output_root = get(run_config, "output_root", "")
    isempty(output_root) && throw(ArgumentError("Thiếu run.output_root"))
    backend = get(get(config, "execution", Dict()), "backend", "cpu")
    backend in ("cpu", "cuda") || throw(ArgumentError("execution.backend phải là cpu hoặc cuda"))
    if mode == "smoke"
        occursin(joinpath("tc", "smoke"), output_root) ||
            throw(ArgumentError("Smoke output phải nằm trong thư mục riêng tc/smoke"))
    else
        occursin(joinpath("tc", "smoke"), output_root) &&
            throw(ArgumentError("Full output không được ghi vào vùng smoke"))
    end
    return config
end

"""Chạy cùng TC0–TC7 theo cấu hình smoke hoặc full đã chọn."""
function run_tc(config_path; data_dir, output_root=nothing)
    return _run_pipeline(config_path; data_dir, output_root, notebook_fresh_kernel=false)
end

"""Chọn mẫu cân bằng xác định; trả chỉ số Julia (bắt đầu từ 1)."""
function balanced_smoke_indices(labels, per_class::Int, seed::Int)
    rng = MersenneTwister(seed)
    ids = Int[]
    for label in 0:9
        candidates = findall(==(label), labels)
        length(candidates) >= per_class || error("Không đủ ảnh cho lớp $label")
        append!(ids, sort(shuffle(rng, candidates)[1:per_class]))
    end
    return ids
end

"""Fit phân vị Q10 trên các pixel dương của tập train, trả tau và metadata."""
function fit_q10_positive(images; q=0.10, fit_split="train")
    positive = filter(>(0), vec(images))
    isempty(positive) && error("Không có pixel dương để fit Q10+")
    tau = quantile(Float64.(positive), q)
    return tau, (; positive_pixel_count=length(positive), quantile=q,
        definition="Statistics.quantile linear interpolation", fit_split)
end

"""Tách ảnh thành patch row-major và trả descriptor raw index cùng metadata."""
function extract_patches(images, image_ids; patch_size=4)
    h, w, n = size(images)
    h == 28 && w == 28 || throw(ArgumentError("Ảnh phải có shape 28×28"))
    length(image_ids) == n || throw(ArgumentError("image_ids không khớp ảnh"))
    patches = Matrix{UInt8}[]
    index = NamedTuple[]
    grid = 28 ÷ patch_size
    grid * patch_size == 28 || error("Patch không phủ kín ảnh")
    for i in 1:n, r in 1:grid, c in 1:grid
        patch_id = (r - 1) * grid + c
        y = (r - 1) * patch_size + 1
        x = (c - 1) * patch_size + 1
        patch = Matrix(@view images[y:y+patch_size-1, x:x+patch_size-1, i])
        push!(patches, patch)
        push!(index, (; image_id=image_ids[i], patch_id, patch_row=r, patch_col=c))
    end
    return patches, index
end

function _reconstruct_images(patches,index,image_ids;patch_size=4)
    restored=zeros(UInt8,28,28,length(image_ids))
    slots=Dict(id=>slot for (slot,id) in enumerate(image_ids))
    for (patch,row) in zip(patches,index)
        y=(row.patch_row-1)*patch_size+1
        x=(row.patch_col-1)*patch_size+1
        restored[y:y+patch_size-1,x:x+patch_size-1,slots[row.image_id]].=patch
    end
    return restored
end

"""Tạo descriptor Float32/255 cho patch được giữ; không đưa label/vị trí vào vector."""
function make_descriptors(patches, index, tau; alpha=0.0)
    kept = Int[]
    for i in eachindex(patches)
        fr = count(>(tau), patches[i]) / length(patches[i])
        fr > alpha && push!(kept, i)
    end
    d = length(patches[1])
    x = Matrix{Float32}(undef, d, length(kept))
    for (j, i) in enumerate(kept)
        x[:, j] .= Float32.(vec(patches[i])) ./ 255f0
    end
    return x, index[kept], kept
end

function _patch_status_rows(split, patches, index, tau, alpha)
    return [(split, row.image_id, row.patch_id, row.patch_row, row.patch_col,
        count(>(tau), patch) / length(patch), count(>(tau), patch) / length(patch) > alpha,
        tau, alpha, "T2") for (patch, row) in zip(patches, index)]
end

"""Fit full-batch K-means bằng backend CPU hoặc CUDA; K-means++ dùng seed đã chỉ định."""
function fit_kmeans(X; k=8, seed=42, maxiter=20, tolerance=1e-4,
    backend="cpu", batch_size=DEFAULT_GPU_BATCH_SIZE, device_data=nothing,
    initial_indices=nothing)
    _, n = size(X)
    n >= k || throw(ArgumentError("Cần tối thiểu K descriptors train; nhận $n, K=$k"))
    backend in ("cpu", "cuda") || throw(ArgumentError("backend phải là cpu hoặc cuda"))
    if backend == "cuda"
        return _cuda_backend().fit_kmeans(X; k, seed, maxiter, tolerance,
            batch_size, device_data, initial_indices)
    end
    fit_started = time()
    initialization = isnothing(initial_indices) ? :kmpp : initial_indices
    result = Clustering.kmeans(X, k; init=initialization, maxiter, tol=tolerance,
        display=:none, rng=MersenneTwister(seed))
    return (; centroids=result.centers, labels=result.assignments,
        objective=result.totalcost, iterations=result.iterations,
        converged=result.converged,
        stop_reason=result.converged ? "library_tolerance" : "max_iterations",
        history=NamedTuple[], initialization_seconds=NaN,
        fit_seconds=time() - fit_started, backend="cpu", batch_size,
        library="Clustering.jl",
        library_version=string(Base.pkgversion(Clustering)),
        initialization=isnothing(initial_indices) ? ":kmpp" : "provided descriptor indices",
        maxiter, tolerance)
end

"""Gán nearest centroid theo chunk; tie-break chọn word ID nhỏ nhất."""
function assign_words(X, centroids; backend="cpu", chunk_size=128,
    batch_size=DEFAULT_GPU_BATCH_SIZE, device_data=nothing,
    device_centroids=nothing)
    d, n = size(X)
    size(centroids, 1) == d || throw(ArgumentError("Số chiều centroid không khớp"))
    backend in ("cpu", "cuda") || throw(ArgumentError("backend phải là cpu hoặc cuda"))
    if backend == "cuda"
        return _cuda_backend().assign_words(X, centroids; batch_size,
            device_data, device_centroids)
    end
    words = Vector{Int}(undef, n)
    for lo in 1:chunk_size:n
        for j in lo:min(lo + chunk_size - 1, n)
            best, bestdist = 1, Inf
            for c in axes(centroids, 2)
                dist = sum(abs2, X[:, j] .- centroids[:, c])
                if dist < bestdist
                    best, bestdist = c, dist
                end
            end
            words[j] = best
        end
    end
    return words
end

"""Mỗi ảnh thành transaction binary đã sort; giữ cả ảnh có transaction rỗng."""
function encode_transactions(assignments, descriptor_index, image_ids)
    byimage = Dict(id => Int[] for id in image_ids)
    for (word, row) in zip(assignments, descriptor_index)
        push!(byimage[row.image_id], word)
    end
    return [sort!(unique!(byimage[id])) for id in image_ids]
end

"""Extract/filter descriptors directly from images without materializing patch matrices."""
function _image_descriptors(images, image_ids, tau; patch_size=4, alpha=0.0)
    n = size(images, 3)
    grid = 28 ÷ patch_size
    retained = 0
    for i in 1:n, row in 1:grid, col in 1:grid
        y = (row - 1) * patch_size + 1
        x = (col - 1) * patch_size + 1
        patch = @view images[y:y+patch_size-1, x:x+patch_size-1, i]
        count(>(tau), patch) / length(patch) > alpha && (retained += 1)
    end
    descriptors = Matrix{Float32}(undef, patch_size^2, retained)
    index = NamedTuple[]
    sizehint!(index, retained)
    column = 0
    for i in 1:n, row in 1:grid, col in 1:grid
        y = (row - 1) * patch_size + 1
        x = (col - 1) * patch_size + 1
        patch = @view images[y:y+patch_size-1, x:x+patch_size-1, i]
        count(>(tau), patch) / length(patch) > alpha || continue
        column += 1
        descriptors[:, column] .= Float32.(vec(patch)) ./ 255f0
        push!(index, (; image_id=image_ids[i], patch_id=(row-1)*grid+col,
            patch_row=row, patch_col=col))
    end
    return descriptors, index
end

function _write_transactions(path, transactions)
    open(path, "w") do io
        for tx in transactions
            println(io, join(tx, ' '))
        end
    end
end

function _json_escape(s)
    replace(string(s), "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n")
end

function _json_number(value)
    return isfinite(value) ? string(value) : "null"
end

function _write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ','))
        for row in rows
            println(io, join(string.(row), ','))
        end
    end
end

function _backend(state::TCState)
    return get(state.data, :backend, get(get(state.config, "execution", Dict()), "backend", "cpu"))
end

function _fit_fingerprint(state::TCState, k, seed)
    config = state.config
    values = Dict(
        "backend" => _backend(state),
        "julia_version" => string(VERSION),
        "backend_library_version" => _backend(state) == "cuda" ?
            string(Base.pkgversion(_cuda_backend().CUDA)) :
            string(Base.pkgversion(Clustering)),
        "data_archive_sha256" => state.data[:archive_checksums],
        "train_descriptor_sha256" => state.data[:descriptor_checksums]["train"],
        "validation_descriptor_sha256" => state.data[:descriptor_checksums]["validation"],
        "k" => k,
        "seed" => seed,
        "max_iterations" => config["tc4_codebook"]["max_iterations"],
        "tolerance" => config["tc4_codebook"]["tolerance"],
        "batch_size" => get(config["tc4_codebook"], "batch_size",
            get(config["tc5_word_assignment"], "batch_size", 65_536)),
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
        tolerance=Float64(metadata["tolerance"]), batch_size=Int(metadata["batch_size"]),
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
        "cuda_package_version" => _backend(state) == "cuda" ?
            string(Base.pkgversion(_cuda_backend().CUDA)) : "not_used",
        "gpu_device_name" => get(state.data, :gpu_device_info,
            (; name="not_used")).name,
        "gpu_vram_bytes" => get(state.data, :gpu_device_info,
            (; total_memory_bytes=0)).total_memory_bytes,
        "library" => model.library,
        "library_version" => model.library_version,
        "initialization" => model.initialization,
        "max_iterations" => model.maxiter,
        "tolerance" => model.tolerance,
        "batch_size" => model.batch_size,
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

function _archive_run!(state::TCState, run_id, stage)
    run_dir = _run_output_dir(state, run_id)
    fingerprint = state.data[:fit_fingerprints][run_id]
    archive_root = joinpath(state.output_root, "archives", _backend(state))
    mkpath(archive_root)
    archive_name = "$(run_id)_$(stage)_$(fingerprint[1:12]).tar"
    destination = joinpath(archive_root, archive_name)
    temporary_root = mktempdir()
    local_archive = joinpath(temporary_root, archive_name)
    pack_started = time()
    try
        Tar.create(run_dir, local_archive; portable=true)
        pack_seconds = time() - pack_started
        archive_hash = bytes2hex(open(sha256, local_archive))
        transfer_started = time()
        cp(local_archive, destination; force=true)
        copied_hash = bytes2hex(open(sha256, destination))
        copied_hash == archive_hash || error("TAR Drive không khớp SHA-256: $destination")
        open(destination * ".sha256", "w") do io
            println(io, "$archive_hash  $archive_name")
        end
        transfer_seconds = time() - transfer_started
        state.checks["archive_$(stage)_$(run_id)"] = "PASS"
        return (; run_id, stage, path=destination, sha256=archive_hash,
            pack_seconds, drive_copy_seconds=transfer_seconds)
    finally
        rm(temporary_root; recursive=true, force=true)
    end
end

"""Chuẩn bị phiên TC, tách thư mục làm việc local khỏi đích lưu checkpoint/Drive."""
function prepare_run(config_path; data_dir, output_root=nothing, work_root=nothing)
    config = read_config(config_path)
    run = config["run"]
    mode = run["mode"]
    root = dirname(dirname(abspath(config_path)))
    configured_output = normpath(joinpath(root, run["output_root"]))
    output_root = isnothing(output_root) ? configured_output : normpath(abspath(output_root))
    work_root = isnothing(work_root) ? mktempdir(prefix="fashion-tc-work-") : normpath(abspath(work_root))
    backend = get(get(config, "execution", Dict()), "backend", "cpu")
    backend == "cuda" && _cuda_backend().check_available!()
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

function _require_previous(state::TCState, expected::Int)
    get(state.data, :completed_tc, -1) == expected - 1 ||
        error("TC$(expected) phải chạy sau TC$(expected - 1)")
end

function _finish_stage!(state::TCState, number::Int, label::String, summary)
    state.data[:completed_tc] = number
    return (; tc="TC$number", label, summary)
end

"""TC0: kiểm tra archive, lấy mẫu cân bằng và fit Q10+ chỉ trên smoke train."""
function run_tc0!(state::TCState)
    _require_previous(state, 0)
    dataset = state.config["dataset"]
    preprocessing = state.config["tc0_preprocessing"]
    hashes = Dict(file.name => bytes2hex(sha256(read(joinpath(state.data_dir, file.name))))
        for file in Main.EclatFIM.FASHION_FILES)
    foreach(file -> Main.EclatFIM._verify_fashion_checksum(joinpath(state.data_dir, file.name), file.sha256),
        Main.EclatFIM.FASHION_FILES)
    train = Main.EclatFIM.load_fashion_mnist(state.data_dir; split=:train)
    validation = Main.EclatFIM.load_fashion_mnist(state.data_dir; split=:test)
    if state.data[:mode] == "smoke"
        train_ids = balanced_smoke_indices(train.labels, dataset["train_per_class"], dataset["sample_seed"])
        validation_ids = balanced_smoke_indices(validation.labels,
            dataset["validation_per_class"], dataset["sample_seed"])
    else
        length(train.labels) == dataset["train_images"] || error("Số ảnh train full không đúng")
        length(validation.labels) == dataset["validation_images"] || error("Số ảnh validation full không đúng")
        train_ids = collect(eachindex(train.labels))
        validation_ids = collect(eachindex(validation.labels))
    end
    train_images = Array(@view train.images[:, :, train_ids])
    validation_images = Array(@view validation.images[:, :, validation_ids])
    train_labels = train.labels[train_ids]
    validation_labels = validation.labels[validation_ids]
    _write_csv(joinpath(state.work_root, "selected_image_ids.csv"), ["split", "image_id", "label"],
        vcat([("train", id, label) for (id, label) in zip(train_ids, train_labels)],
            [("validation", id, label) for (id, label) in zip(validation_ids, validation_labels)]))
    fit_split = state.data[:mode] == "smoke" ? "smoke_train_only" : "train"
    tau, tau_meta = fit_q10_positive(train_images; q=preprocessing["quantile"], fit_split)
    isfinite(tau) || error("Q10+ không hữu hạn")
    state.checks["tc0_archive_checksums"] = "PASS"
    state.checks["tc0_train_only"] = "PASS"
    state.data[:archive_checksums] = hashes
    state.data[:train] = train
    state.data[:validation] = validation
    state.data[:train_ids] = train_ids
    state.data[:validation_ids] = validation_ids
    state.data[:train_images] = train_images
    state.data[:validation_images] = validation_images
    state.data[:train_labels] = train_labels
    state.data[:validation_labels] = validation_labels
    state.data[:tau] = tau
    state.data[:tau_meta] = tau_meta
    open(joinpath(state.work_root, "threshold_fit.toml"), "w") do io
        TOML.print(io, Dict("tau_train" => tau, "train_only" => true,
            "positive_pixel_count" => tau_meta.positive_pixel_count,
            "quantile" => preprocessing["quantile"], "definition" => tau_meta.definition,
            "source_archive_sha256" => hashes))
    end
    state.checks["tc0_archive_checksums"] = "PASS"
    state.checks["tc0_train_only"] = "PASS"
    return _finish_stage!(state, 0, "Fit ngưỡng train-only",
        (; train_images=length(train_ids), validation_images=length(validation_ids), tau))
end

"""TC1: trích patch dense 4×4 và xác minh tái tạo ảnh chính xác."""
function run_tc1!(state::TCState)
    _require_previous(state, 1)
    config = state.config
    patch_size = config["tc1_patch_extraction"]["patch_size"][1]
    patches_per_image = (28 ÷ patch_size)^2
    train_count = length(state.data[:train_ids]) * patches_per_image
    validation_count = length(state.data[:validation_ids]) * patches_per_image
    if state.data[:mode] == "smoke"
        train_patches, train_index = extract_patches(state.data[:train_images], state.data[:train_ids]; patch_size)
        validation_patches, validation_index = extract_patches(state.data[:validation_images],
            state.data[:validation_ids]; patch_size)
        train_reconstructed = _reconstruct_images(train_patches, train_index, state.data[:train_ids]; patch_size)
        validation_reconstructed = _reconstruct_images(validation_patches, validation_index,
            state.data[:validation_ids]; patch_size)
        train_reconstructed == state.data[:train_images] &&
            validation_reconstructed == state.data[:validation_images] || error("Tái tạo patch không khớp ảnh nguồn")
        state.data[:train_patches] = train_patches
        state.data[:validation_patches] = validation_patches
        state.data[:train_patch_index] = train_index
        state.data[:validation_patch_index] = validation_index
        state.checks["tc1_patch_reconstruction"] = length(train_patches) == train_count &&
            length(validation_patches) == validation_count ? "PASS" : "FAIL"
        state.checks["tc1_exact_reconstruction"] = "PASS"
    else
        state.data[:train_patch_count] = train_count
        state.data[:validation_patch_count] = validation_count
        state.checks["tc1_patch_reconstruction"] = "PASS"
    end
    state.data[:train_patch_count] = train_count
    state.data[:validation_patch_count] = validation_count
    return _finish_stage!(state, 1, "Trích patch 4×4",
        (; train_patches=train_count, validation_patches=validation_count,
            reconstruction=get(state.checks, "tc1_exact_reconstruction", "không chạy cho full")))
end

"""TC2: tạo keep masks theo tau và alpha, đồng thời lưu patch status."""
function run_tc2!(state::TCState)
    _require_previous(state, 2)
    tau = state.data[:tau]
    alpha = state.config["tc2_patch_filtering"]["alpha"]
    train_ids, validation_ids = state.data[:train_ids], state.data[:validation_ids]
    patch_size = state.config["tc1_patch_extraction"]["patch_size"][1]
    patches_per_image = (28 ÷ patch_size)^2
    if state.data[:mode] == "smoke"
        train_patches = state.data[:train_patches]
        validation_patches = state.data[:validation_patches]
        train_index = state.data[:train_patch_index]
        validation_index = state.data[:validation_patch_index]
        train_keep = findall(i -> count(>(tau), train_patches[i]) / length(train_patches[i]) > alpha,
            eachindex(train_patches))
        validation_keep = findall(i -> count(>(tau), validation_patches[i]) / length(validation_patches[i]) > alpha,
            eachindex(validation_patches))
        _write_csv(joinpath(state.work_root, "patch_filter_status.csv"),
            ["split", "image_id", "patch_id", "patch_row", "patch_col", "foreground_ratio", "keep", "tau", "alpha", "experiment_id"],
            vcat(_patch_status_rows("train", train_patches, train_index, tau, alpha),
                _patch_status_rows("validation", validation_patches, validation_index, tau, alpha)))
        state.data[:train_keep] = train_keep
        state.data[:validation_keep] = validation_keep
    end

    train_duplicate_summary = _retained_patch_summary(
        state.data[:train_images], tau, alpha, patch_size)
    validation_duplicate_summary = _retained_patch_summary(
        state.data[:validation_images], tau, alpha, patch_size)
    train_per_image = train_duplicate_summary.per_image
    validation_per_image = validation_duplicate_summary.per_image
    state.data[:patch_duplicate_summary] = Dict(
        "train" => train_duplicate_summary,
        "validation" => validation_duplicate_summary)

    _write_csv(joinpath(state.work_root, "patch_filter_summary.csv"),
        ["split", "image_id", "retained_count", "discarded_count", "empty_after_filter"],
        vcat([("train", id, kept, patches_per_image - kept, kept == 0)
                for (id, kept) in zip(train_ids, train_per_image)],
            [("validation", id, kept, patches_per_image - kept, kept == 0)
                for (id, kept) in zip(validation_ids, validation_per_image)]))
    _write_csv(joinpath(state.work_root, "patch_duplicate_summary.csv"),
        ["split", "retained_patches", "unique_patches", "duplicate_patches", "duplicate_rate"],
        [("train", train_duplicate_summary.total, train_duplicate_summary.unique,
            train_duplicate_summary.total - train_duplicate_summary.unique,
            train_duplicate_summary.duplicate_rate),
            ("validation", validation_duplicate_summary.total, validation_duplicate_summary.unique,
                validation_duplicate_summary.total - validation_duplicate_summary.unique,
                validation_duplicate_summary.duplicate_rate)])
    state.data[:train_keep_per_image] = train_per_image
    state.data[:validation_keep_per_image] = validation_per_image
    train_retained = sum(train_per_image)
    validation_retained = sum(validation_per_image)
    state.checks["tc2_filter_invariants"] = train_retained <= state.data[:train_patch_count] &&
        validation_retained <= state.data[:validation_patch_count] ? "PASS" : "FAIL"
    state.checks["tc2_filter_invariants"] == "PASS" || error("Filtering count invariant failed")
    return _finish_stage!(state, 2, "Lọc patch T2",
        (; train_kept=train_retained, train_discarded=state.data[:train_patch_count]-train_retained,
            validation_kept=validation_retained,
            validation_discarded=state.data[:validation_patch_count]-validation_retained,
            train_total_patches=train_duplicate_summary.total,
            train_unique_patches=train_duplicate_summary.unique,
            train_duplicate_patches=train_duplicate_summary.total-train_duplicate_summary.unique,
            train_duplicate_rate=train_duplicate_summary.duplicate_rate,
            validation_total_patches=validation_duplicate_summary.total,
            validation_unique_patches=validation_duplicate_summary.unique,
            validation_duplicate_patches=validation_duplicate_summary.total-validation_duplicate_summary.unique,
            validation_duplicate_rate=validation_duplicate_summary.duplicate_rate))
end

"""Tính số patch được giữ và tỉ lệ trùng chính xác sau lọc.

Tỉ lệ trùng được tính bằng `1 - N_unique / N_total`; các patch được so sánh
theo toàn bộ giá trị pixel UInt8.
"""
function _retained_patch_summary(images, tau, alpha, patch_size)
    patch_size^2 <= sizeof(UInt128) ||
        throw(ArgumentError("Tính patch trùng hiện hỗ trợ tối đa 16 pixel mỗi patch"))
    grid = 28 ÷ patch_size
    counts = zeros(Int, size(images, 3))
    unique_patch_keys = Set{UInt128}()
    total = 0

    for image_id in axes(images, 3), row in 1:grid, col in 1:grid
        y = (row - 1) * patch_size + 1
        x = (col - 1) * patch_size + 1
        patch = @view images[y:y+patch_size-1, x:x+patch_size-1, image_id]
        count(>(tau), patch) / length(patch) > alpha || continue

        counts[image_id] += 1
        total += 1

        key = zero(UInt128)
        for pixel in patch
            key = (key << 8) | UInt128(pixel)
        end
        push!(unique_patch_keys, key)
    end

    unique_count = length(unique_patch_keys)
    duplicate_rate = total == 0 ? 0.0 : 1 - unique_count / total
    return (; per_image=counts, total, unique=unique_count, duplicate_rate)
end

"""TC3: tạo descriptor raw 16D, kiểm tra miền giá trị và lưu cache theo split."""
function run_tc3!(state::TCState)
    _require_previous(state, 3)
    tau = state.data[:tau]
    features = state.config["tc3_feature_extraction"]
    patch_size = state.config["tc1_patch_extraction"]["patch_size"][1]
    alpha = state.config["tc2_patch_filtering"]["alpha"]
    if state.data[:mode] == "smoke"
        train_desc, train_map, train_keep = make_descriptors(state.data[:train_patches],
            state.data[:train_patch_index], tau; alpha)
        validation_desc, validation_map, validation_keep = make_descriptors(state.data[:validation_patches],
            state.data[:validation_patch_index], tau; alpha)
        train_keep == state.data[:train_keep] && validation_keep == state.data[:validation_keep] ||
            error("Mask TC2 và descriptor TC3 không khớp")
    else
        train_desc, train_map = _image_descriptors(state.data[:train_images], state.data[:train_ids], tau;
            patch_size, alpha)
        validation_desc, validation_map = _image_descriptors(state.data[:validation_images],
            state.data[:validation_ids], tau; patch_size, alpha)
    end
    valid = size(train_desc, 1) == features["dimension"] &&
        size(validation_desc, 1) == features["dimension"] &&
        size(train_desc, 2) == length(train_map) && size(validation_desc, 2) == length(validation_map) &&
        all(isfinite, train_desc) && all(isfinite, validation_desc) &&
        all(x -> 0 <= x <= 1, train_desc) && all(x -> 0 <= x <= 1, validation_desc)
    valid || error("Descriptor invariant failed")
    train_path = joinpath(state.work_root, "train_descriptors.bin")
    validation_path = joinpath(state.work_root, "validation_descriptors.bin")
    open(train_path, "w") do io
        serialize(io, (; descriptors=train_desc, index=train_map))
    end
    open(validation_path, "w") do io
        serialize(io, (; descriptors=validation_desc, index=validation_map))
    end
    state.data[:train_desc] = train_desc
    state.data[:validation_desc] = validation_desc
    state.data[:train_map] = train_map
    state.data[:validation_map] = validation_map
    state.data[:descriptor_checksums] = Dict(
        "train" => bytes2hex(sha256(read(train_path))),
        "validation" => bytes2hex(sha256(read(validation_path))))
    state.checks["tc3_descriptor_mapping"] = "PASS"
    return _finish_stage!(state, 3, "Tạo raw-pixel descriptor",
        (; dimension=size(train_desc, 1), train_descriptors=size(train_desc, 2),
            validation_descriptors=size(validation_desc, 2), values="Float32 trong [0,1]"))
end

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
    batch_size = get(config, "batch_size",
        get(state.config["tc5_word_assignment"], "batch_size", 65_536))
    if backend == "cuda"
        state.data[:gpu_device_info] = _cuda_backend().device_info()
        upload_started = time()
        state.data[:cuda_train_data] = _cuda_backend().to_device(state.data[:train_desc])
        state.data[:timings]["descriptor_upload_seconds"] = time() - upload_started
    end

    for (run_id, k, seed) in runs
        fingerprint = _fit_fingerprint(state, k, seed)
        fingerprints[run_id] = fingerprint
        started = time()
        model = _load_fit_checkpoint(state, run_id, k, seed, fingerprint)
        resumed = !isnothing(model)
        if !resumed
            model = fit_kmeans(state.data[:train_desc]; k, seed,
                maxiter=config["max_iterations"], tolerance=config["tolerance"],
                backend, batch_size,
                device_data=backend == "cuda" ? state.data[:cuda_train_data] : nothing)
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
            stop_reason=model.stop_reason, history=model.history, backend,
            initialization_seconds=model.initialization_seconds,
            fit_seconds=model.fit_seconds, batch_size, library=model.library,
            library_version=model.library_version, initialization=model.initialization,
            maxiter=model.maxiter, tolerance=model.tolerance, resumed)
        push!(fit_summaries, (; run_id, k, seed, shape=size(model.centroids),
            iterations=model.iterations, converged=model.converged,
            stop_reason=model.stop_reason, objective=model.objective,
            initialization_seconds=model.initialization_seconds,
            fit_seconds=model.fit_seconds, elapsed_seconds=elapsed,
            descriptor_upload_seconds=get(state.data[:timings], "descriptor_upload_seconds", 0.0),
            checkpoint_drive_seconds=checkpoint_seconds, resumed,
            backend, batch_size, library=model.library,
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

function _run_output_dir(state::TCState, run_id)
    return state.data[:mode] == "smoke" ? state.work_root : joinpath(state.work_root, "runs", run_id)
end

"""TC5: gán train/validation theo từng codebook, dùng cùng cách cho smoke và full."""
function run_tc5!(state::TCState)
    _require_previous(state, 5)
    config = state.config["tc5_word_assignment"]
    backend = _backend(state)
    batch_size = get(config, "batch_size", get(config, "chunk_size", 65_536))
    chunk_size = get(config, "chunk_size", batch_size)
    mapping = Dict("train" => state.data[:train_map], "validation" => state.data[:validation_map])
    summaries = NamedTuple[]
    if backend == "cuda"
        upload_started = time()
        state.data[:cuda_validation_data] = _cuda_backend().to_device(state.data[:validation_desc])
        state.data[:timings]["validation_descriptor_upload_seconds"] = time() - upload_started
    end

    for run_id in state.data[:run_ids]
        model = state.data[:models][run_id]
        device_centroids = backend == "cuda" ?
            _cuda_backend().to_device_centroids(model.centroids) : nothing
        assignment_started = time()
        train_words = assign_words(state.data[:train_desc], model.centroids;
            backend, chunk_size, batch_size,
            device_data=backend == "cuda" ? state.data[:cuda_train_data] : nothing,
            device_centroids)
        validation_words = assign_words(state.data[:validation_desc], model.centroids;
            backend, chunk_size, batch_size,
            device_data=backend == "cuda" ? state.data[:cuda_validation_data] : nothing,
            device_centroids)
        backend == "cuda" && _cuda_backend().synchronize()
        assignment_seconds = time() - assignment_started
        k = size(model.centroids, 2)
        all(in(1:k), train_words) && all(in(1:k), validation_words) ||
            error("Word ID nằm ngoài 1:$k cho $run_id")
        if state.data[:mode] == "smoke"
            direct_words = assign_words(state.data[:train_desc], model.centroids;
                backend, chunk_size=size(state.data[:train_desc], 2),
                batch_size=size(state.data[:train_desc], 2),
                device_data=backend == "cuda" ? state.data[:cuda_train_data] : nothing,
                device_centroids)
            train_words == direct_words || error("Chunked assignment không khớp direct assignment")
            state.data[:train_words] = train_words
            state.data[:validation_words] = validation_words
        end
        run_dir = _run_output_dir(state, run_id)
        for (split, words) in (("train", train_words), ("validation", validation_words))
            rows = [(row.image_id, row.patch_id, row.patch_row, row.patch_col, word, split, run_id)
                for (row, word) in zip(mapping[split], words)]
            _write_csv(joinpath(run_dir, "$(split)_assignments.csv"),
                ["image_id", "patch_id", "patch_row", "patch_col", "word_id", "split", "run_id"], rows)
        end
        open(joinpath(run_dir, "assignments.bin"), "w") do io
            serialize(io, (; train_words, valid_words=validation_words))
        end
        archive = _archive_run!(state, run_id, "tc5")
        state.data[:timings]["assignment_seconds"] =
            get(state.data[:timings], "assignment_seconds", 0.0) + assignment_seconds
        state.data[:timings]["archive_pack_seconds"] =
            get(state.data[:timings], "archive_pack_seconds", 0.0) + archive.pack_seconds
        state.data[:timings]["drive_archive_copy_seconds"] =
            get(state.data[:timings], "drive_archive_copy_seconds", 0.0) + archive.drive_copy_seconds
        push!(summaries, (; run_id, train_assignments=length(train_words),
            validation_assignments=length(validation_words), backend, batch_size,
            assignment_seconds, archive_path=archive.path, archive_sha256=archive.sha256,
            archive_pack_seconds=archive.pack_seconds,
            archive_drive_copy_seconds=archive.drive_copy_seconds))
    end
    state.data[:assignment_summaries] = summaries
    state.checks["tc5_chunked_assignment"] = "PASS"
    return _finish_stage!(state, 5, "Gán visual words", summaries)
end

"""TC6: mã hóa visual words thành một transaction cho mỗi ảnh."""
function run_tc6!(state::TCState)
    _require_previous(state, 6)
    config = state.config
    summaries = NamedTuple[]
    for run_id in state.data[:run_ids]
        run_dir = _run_output_dir(state, run_id)
        assignments = open(deserialize, joinpath(run_dir, "assignments.bin"))
        model = state.data[:models][run_id]
        train_tx = encode_transactions(assignments.train_words, state.data[:train_map], state.data[:train_ids])
        validation_tx = encode_transactions(assignments.valid_words, state.data[:validation_map],
            state.data[:validation_ids])
        k = size(model.centroids, 2)
        valid = length(train_tx) == length(state.data[:train_ids]) &&
            length(validation_tx) == length(state.data[:validation_ids]) &&
            all(issorted ∘ unique, vcat(train_tx, validation_tx)) &&
            all(length(tx) <= min(state.data[:train_keep_per_image][i], k)
                for (i, tx) in enumerate(train_tx)) &&
            all(length(tx) <= min(state.data[:validation_keep_per_image][i], k)
                for (i, tx) in enumerate(validation_tx)) &&
            all(tx -> all(item -> 1 <= item <= k, tx), vcat(train_tx, validation_tx))
        valid || error("Transaction invariant failed for $run_id")
        _write_transactions(joinpath(run_dir, "train_transactions.txt"), train_tx)
        _write_transactions(joinpath(run_dir, "validation_transactions.txt"), validation_tx)
        tid_rows = vcat([(tid, "train", image_id) for (tid, image_id) in enumerate(state.data[:train_ids])],
            [(length(state.data[:train_ids]) + tid, "validation", image_id)
                for (tid, image_id) in enumerate(state.data[:validation_ids])])
        _write_csv(joinpath(run_dir, "tid_mapping.csv"), ["tid", "split", "image_id"], tid_rows)
        if state.data[:mode] == "smoke"
            state.data[:train_tx] = train_tx
            state.data[:validation_tx] = validation_tx
        end
        push!(summaries, (; run_id, train_transactions=length(train_tx),
            validation_transactions=length(validation_tx),
            empty_train=count(isempty, train_tx), empty_validation=count(isempty, validation_tx)))
    end
    state.checks["tc6_transaction_invariants"] = "PASS"
    return _finish_stage!(state, 6, "Tạo transaction BoVW", summaries)
end

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
    patterns = Main.EclatFIM.mine(fixture, eclat_config["minsup_count"])
    fixture_valid = length(fixture) == 4 && patterns[(1,)] == 3 && patterns[(2,)] == 2 &&
        patterns[(1, 2)] == 2 && count(tx -> all(item -> item in tx, (2, 3)), fixture) == 1 &&
        !haskey(patterns, (2, 3))
    all_transactions = vcat(train_tx, validation_tx)
    frequent = Main.EclatFIM.mine(all_transactions, eclat_config["minsup_count"])
    _write_csv(joinpath(output_root, "eclat_frequent_itemsets.csv"), ["itemset", "support_count"],
        [(join(key, ' '), count) for (key, count) in sort!(collect(frequent); by=first)])
    direct_support(items) = count(tx -> all(item -> item in tx, items), all_transactions)
    selected = [(1,), (2,), (1, 2), (1, 3)]
    support_valid = all(items -> get(frequent, items, 0) == direct_support(items), selected)
    state.checks["tc7_reload_and_eclat_support"] = fixture_valid && support_valid ? "PASS" : "FAIL"
    state.checks["tc7_pilot"] = "PASS"
    verifier = joinpath(@__DIR__, "..", "..", "scripts", "verify_fashion_tc_artifacts.jl")
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
            "kmeans_batch_size" => kmeans.batch_size,
            "kmeans_initialization_seconds" => kmeans.initialization_seconds,
            "kmeans_fit_seconds" => kmeans.fit_seconds,
            "kmeans_library" => kmeans.library, "kmeans_library_version" => kmeans.library_version,
            "kmeans_initialization" => kmeans.initialization, "kmeans_maxiter" => kmeans.maxiter,
            "kmeans_tolerance" => kmeans.tolerance,
            "cuda_package_version" => kmeans.backend == "cuda" ?
                string(Base.pkgversion(_cuda_backend().CUDA)) : "not_used",
            "gpu_device_name" => get(state.data, :gpu_device_info,
                (; name="not_used")).name,
            "gpu_vram_bytes" => get(state.data, :gpu_device_info,
                (; total_memory_bytes=0)).total_memory_bytes,
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
        "descriptor_upload_seconds" => get(state.data[:timings], "descriptor_upload_seconds", 0.0),
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
        print(io, "{\n  \"run_id\": \"$run_id_json\",\n  \"mode\": \"smoke\",\n  \"status\": \"$overall_status\",\n  \"pipeline_status\": \"$pipeline_status\",\n  \"notebook_fresh_kernel\": \"$notebook_status\",\n  \"config_path\": \"$config_path_json\",\n  \"effective_config_path\": \"$effective_config_path_json\",\n  \"elapsed_seconds\": $(report["elapsed_seconds"]),\n  \"tau_train\": $tau,\n  \"train_images\": $(report["train_images"]),\n  \"validation_images\": $(report["validation_images"]),\n  \"train_patches_before_filter\": $(report["train_patches_before_filter"]),\n  \"validation_patches_before_filter\": $(report["validation_patches_before_filter"]),\n  \"train_retained_descriptors\": $(report["train_retained_descriptors"]),\n  \"validation_retained_descriptors\": $(report["validation_retained_descriptors"]),\n  \"kmeans_fit_count\": 1,\n  \"kmeans_k\": $(report["kmeans_k"]),\n  \"kmeans_initialization_seconds\": $(_json_number(report["kmeans_initialization_seconds"])),\n  \"kmeans_fit_seconds\": $(report["kmeans_fit_seconds"]),\n  \"assignment_seconds\": $(report["assignment_seconds"]),\n  \"descriptor_upload_seconds\": $(report["descriptor_upload_seconds"]),\n  \"checkpoint_drive_seconds\": $(report["checkpoint_drive_seconds"]),\n  \"checkpoint_resumed\": $(report["checkpoint_resumed"]),\n  \"train_transactions\": $(report["train_transactions"]),\n  \"validation_transactions\": $(report["validation_transactions"]),\n  \"archive_path\": \"$(_json_escape(archive.path))\",\n  \"archive_sha256\": \"$(archive.sha256)\",\n  \"archive_pack_seconds\": $(archive.pack_seconds),\n  \"archive_drive_copy_seconds\": $(archive.drive_copy_seconds),\n  \"checks\": {")
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
            "cuda_package_version" => _backend(state) == "cuda" ?
                string(Base.pkgversion(_cuda_backend().CUDA)) : "not_used",
            "gpu_device_name" => get(state.data, :gpu_device_info,
                (; name="not_used")).name,
            "gpu_vram_bytes" => get(state.data, :gpu_device_info,
                (; total_memory_bytes=0)).total_memory_bytes,
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

"""Chạy tuần tự cùng các cell TC0–TC7 với config smoke hoặc full."""
function _run_pipeline(config_path; data_dir, output_root=nothing, work_root=nothing,
    notebook_fresh_kernel=false)
    state = prepare_run(config_path; data_dir, output_root, work_root)
    run_tc0!(state)
    run_tc1!(state)
    run_tc2!(state)
    run_tc3!(state)
    run_tc4!(state)
    run_tc5!(state)
    run_tc6!(state)
    result = run_tc7!(state; notebook_fresh_kernel)
    return result.summary
end

"""CLI tương thích cho smoke; logic dùng chung với các cell TC và full run."""
function run_smoke(config_path; data_dir, output_root=nothing, work_root=nothing,
    notebook_fresh_kernel::Bool=false)
    read_config(config_path)["run"]["mode"] == "smoke" ||
        throw(ArgumentError("run_smoke yêu cầu mode=smoke"))
    return _run_pipeline(config_path; data_dir, output_root, work_root, notebook_fresh_kernel)
end

"""CLI tương thích cho full; logic dùng chung với các cell TC và smoke run."""
function run_full(config_path; data_dir, output_root=nothing, work_root=nothing,
    notebook_fresh_kernel::Bool=false)
    read_config(config_path)["run"]["mode"] == "full" ||
        throw(ArgumentError("run_full yêu cầu mode=full"))
    return _run_pipeline(config_path; data_dir, output_root, work_root, notebook_fresh_kernel)
end

end # module FashionTC
