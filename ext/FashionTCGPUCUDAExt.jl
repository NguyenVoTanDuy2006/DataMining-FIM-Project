module FashionTCGPUCUDAExt

using CUDA
using LinearAlgebra: mul!
using Random

export DeviceDescriptors, available, check_available!, device_info, to_device,
    to_device_centroids, warmup!, fit_kmeans, assign_words, synchronize

const DEFAULT_BATCH_SIZE = 65_536
const KERNEL_THREADS = 256

struct DeviceDescriptors{A,B}
    values::A
    squared_norms::B
end

"""Kiểm tra CUDA có thể dùng được trong phiên Julia hiện tại."""
available() = CUDA.functional()

"""Báo lỗi sớm nếu cấu hình yêu cầu CUDA nhưng GPU chưa sẵn sàng."""
function check_available!()
    available() || throw(ArgumentError(
        "backend=\"cuda\" được chọn nhưng CUDA.functional() trả về false. " *
        "Hãy bật GPU T4 trong Colab, khởi động lại runtime và chạy lại cell kiểm tra CUDA."
    ))
    return CUDA.device()
end

"""Trả tên GPU, dung lượng VRAM và phiên bản CUDA.jl của thiết bị hiện hành."""
function device_info()
    check_available!()
    device = CUDA.device()
    return (; name=CUDA.name(device), total_memory_bytes=CUDA.totalmem(device),
        cuda_package_version=string(Base.pkgversion(CUDA)))
end

"""Chép ma trận descriptor lên GPU một lần và tính trước bình phương chuẩn từng cột."""
function to_device(X::AbstractMatrix{<:Real})
    check_available!()
    values = CUDA.CuArray(Float32.(X))
    squared_norms = vec(sum(abs2, values; dims=1))
    CUDA.synchronize()
    return DeviceDescriptors(values, squared_norms)
end

"""Chép codebook Float32 lên GPU."""
to_device_centroids(centroids::AbstractMatrix{<:Real}) = CUDA.CuArray(Float32.(centroids))

"""Đồng bộ công việc đã gửi tới GPU trước khi đo thời gian hoặc dùng kết quả."""
synchronize() = CUDA.synchronize()

function _squared_distances_to_center!(distances, values, center, n, d)
    i = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
    if i <= n
        distance = 0.0f0
        @inbounds for feature in 1:d
            delta = values[feature, i] - center[feature]
            distance += delta * delta
        end
        @inbounds distances[i] = distance
    end
    return
end

function _update_min_distance!(minimums, distances, n)
    i = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
    if i <= n
        @inbounds minimums[i] = min(minimums[i], distances[i])
    end
    return
end

function _select_weighted_index!(cdf, selected, threshold, n)
    i = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
    if i <= n
        current = @inbounds cdf[i]
        previous = 0.0f0
        if i > 1
            @inbounds previous = cdf[i - 1]
        end
        if current >= threshold && previous < threshold
            @inbounds selected[1] = Int32(i)
        end
    end
    return
end

function _assign_min_distance!(distances, labels, residuals, k, n)
    column = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
    if column <= n
        first_offset = (column - 1) * k
        best_cluster = 1
        best_distance = @inbounds distances[first_offset + 1]
        @inbounds for cluster in 2:k
            distance = distances[first_offset + cluster]
            if distance < best_distance
                best_cluster = cluster
                best_distance = distance
            end
        end
        @inbounds labels[column] = Int32(best_cluster)
        @inbounds residuals[column] = best_distance
    end
    return
end

function _accumulate_cluster_sums!(values, labels, sums, counts, n, d)
    column = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
    if column <= n
        @inbounds cluster = Int(labels[column])
        CUDA.@atomic counts[cluster] += Int32(1)
        @inbounds for feature in 1:d
            CUDA.@atomic sums[feature, cluster] += values[feature, column]
        end
    end
    return
end

function _update_centroids!(centroids, sums, counts, k, d)
    index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
    total = k * d
    if index <= total
        feature = mod(index - 1, d) + 1
        cluster = div(index - 1, d) + 1
        @inbounds count = counts[cluster]
        if count > 0
            @inbounds centroids[feature, cluster] = sums[feature, cluster] / Float32(count)
        end
    end
    return
end

function _distance_batch!(distances, data::DeviceDescriptors, centroids,
    center_norms, first_column, last_column)
    batch = view(data.values, :, first_column:last_column)
    mul!(distances, transpose(centroids), batch)
    batch_norms = view(data.squared_norms, first_column:last_column)
    distances .= max.(
        -2.0f0 .* distances .+ reshape(center_norms, :, 1) .+ reshape(batch_norms, 1, :),
        0.0f0,
    )
    return
end

function _assign_batch!(distances, labels, residuals, data, centroids,
    center_norms, first_column, last_column)
    count = last_column - first_column + 1
    _distance_batch!(distances, data, centroids, center_norms, first_column, last_column)
    CUDA.@cuda threads=KERNEL_THREADS blocks=cld(count, KERNEL_THREADS) _assign_min_distance!(
        distances, labels, residuals, size(centroids, 2), count,
    )
    return
end

function _initialize_kmeanspp(data::DeviceDescriptors, k, seed; initial_indices=nothing)
    d, n = size(data.values)
    rng = MersenneTwister(seed)
    centroids = CUDA.CuArray{Float32}(undef, d, k)
    if !isnothing(initial_indices)
        length(initial_indices) == k || throw(ArgumentError("initial_indices phải có đúng K phần tử"))
        all(index -> 1 <= index <= n, initial_indices) ||
            throw(ArgumentError("initial_indices nằm ngoài descriptor range"))
        for cluster in 1:k
            copyto!(view(centroids, :, cluster), view(data.values, :, initial_indices[cluster]))
        end
        CUDA.synchronize()
        return centroids
    end

    distances = CUDA.CuVector{Float32}(undef, n)
    minimums = CUDA.fill(Inf32, n)
    cumulative = similar(minimums)
    selected = CUDA.zeros(Int32, 1)
    first_index = rand(rng, 1:n)
    copyto!(view(centroids, :, 1), view(data.values, :, first_index))

    for cluster in 1:k-1
        center = view(centroids, :, cluster)
        CUDA.@cuda threads=KERNEL_THREADS blocks=cld(n, KERNEL_THREADS) _squared_distances_to_center!(
            distances, data.values, center, n, d,
        )
        CUDA.@cuda threads=KERNEL_THREADS blocks=cld(n, KERNEL_THREADS) _update_min_distance!(
            minimums, distances, n,
        )

        total_weight = sum(Float64, minimums)
        if !isfinite(total_weight) || total_weight <= 0.0
            selected_index = rand(rng, 1:n)
        else
            cumsum!(cumulative, minimums)
            threshold = max(Float32(rand(rng) * total_weight), nextfloat(0.0f0))
            fill!(selected, 0)
            CUDA.@cuda threads=KERNEL_THREADS blocks=cld(n, KERNEL_THREADS) _select_weighted_index!(
                cumulative, selected, threshold, n,
            )
            selected_index = Int(Array(selected)[1])
            selected_index == 0 && (selected_index = n)
        end
        copyto!(view(centroids, :, cluster + 1), view(data.values, :, selected_index))
    end
    CUDA.synchronize()
    return centroids
end

function _assign_all!(data::DeviceDescriptors, centroids; batch_size,
    distances=nothing, labels=nothing, residuals=nothing)
    d, n = size(data.values)
    k = size(centroids, 2)
    isnothing(distances) && (distances = CUDA.CuMatrix{Float32}(undef, k, min(batch_size, n)))
    isnothing(labels) && (labels = CUDA.CuVector{Int32}(undef, n))
    isnothing(residuals) && (residuals = CUDA.CuVector{Float32}(undef, n))
    center_norms = vec(sum(abs2, centroids; dims=1))

    for first_column in 1:batch_size:n
        last_column = min(first_column + batch_size - 1, n)
        count = last_column - first_column + 1
        batch_distances = view(distances, :, 1:count)
        batch_labels = view(labels, first_column:last_column)
        batch_residuals = view(residuals, first_column:last_column)
        _assign_batch!(batch_distances, batch_labels, batch_residuals, data,
            centroids, center_norms, first_column, last_column)
    end
    CUDA.synchronize()
    return labels, residuals
end

"""Fit K-means++ full-batch; batch chỉ giới hạn bộ nhớ, không cập nhật tâm giữa các batch."""
function fit_kmeans(X::AbstractMatrix{<:Real}; k=8, seed=42, maxiter=20,
    tolerance=1.0e-4, batch_size=DEFAULT_BATCH_SIZE, device_data=nothing,
    initial_indices=nothing)
    d, n = size(X)
    1 <= k <= n || throw(ArgumentError("K phải nằm trong 1:$n"))
    batch_size > 0 || throw(ArgumentError("batch_size phải dương"))
    maxiter > 0 || throw(ArgumentError("maxiter phải dương"))
    data = isnothing(device_data) ? to_device(X) : device_data
    size(data.values) == (d, n) || throw(ArgumentError("device_data không khớp X"))
    CUDA.synchronize()

    initialization_started = time()
    centroids = _initialize_kmeanspp(data, k, seed; initial_indices)
    CUDA.synchronize()
    initialization_seconds = time() - initialization_started

    distances = CUDA.CuMatrix{Float32}(undef, k, min(batch_size, n))
    labels = CUDA.CuVector{Int32}(undef, n)
    residuals = CUDA.CuVector{Float32}(undef, n)
    all_residuals = CUDA.CuVector{Float32}(undef, n)
    sums = CUDA.CuMatrix{Float32}(undef, d, k)
    counts = CUDA.CuVector{Int32}(undef, k)
    previous_centroids = similar(centroids)
    history = NamedTuple[]
    converged = false
    stop_reason = "max_iterations"
    fit_started = time()

    # Gán ban đầu để objective và membership khớp với tâm K-means++.
    _assign_all!(data, centroids; batch_size, distances, labels, residuals)
    previous_objective = sum(Float64, residuals)

    for iteration in 1:maxiter
        fill!(sums, 0.0f0)
        fill!(counts, 0)

        for first_column in 1:batch_size:n
            last_column = min(first_column + batch_size - 1, n)
            count = last_column - first_column + 1
            batch_labels = view(labels, first_column:last_column)
            batch_residuals = view(residuals, first_column:last_column)
            CUDA.@cuda threads=KERNEL_THREADS blocks=cld(count, KERNEL_THREADS) _accumulate_cluster_sums!(
                view(data.values, :, first_column:last_column), batch_labels,
                sums, counts, count, d,
            )
            copyto!(view(all_residuals, first_column:last_column), batch_residuals)
        end

        copyto!(previous_centroids, centroids)
        CUDA.@cuda threads=KERNEL_THREADS blocks=cld(k * d, KERNEL_THREADS) _update_centroids!(
            centroids, sums, counts, k, d,
        )
        host_counts = Array(counts)
        empty_clusters = findall(iszero, host_counts)
        if !isempty(empty_clusters)
            host_residuals = Array(all_residuals)
            candidate_order = sortperm(eachindex(host_residuals);
                by=index -> (-host_residuals[index], index))
            used = Set{Int}()
            for cluster in empty_clusters
                descriptor_index = findfirst(index -> !(index in used), candidate_order)
                isnothing(descriptor_index) && error("Không đủ descriptor để khởi tạo cụm rỗng")
                selected_index = candidate_order[descriptor_index]
                push!(used, selected_index)
                copyto!(view(centroids, :, cluster), view(data.values, :, selected_index))
            end
        end
        shift = maximum(abs.(centroids .- previous_centroids))

        # Tính objective sau khi cập nhật tâm, giống semantics tol của Clustering.jl.
        _assign_all!(data, centroids; batch_size, distances, labels, residuals)
        objective = sum(Float64, residuals)
        CUDA.synchronize()
        objective_delta = objective - previous_objective
        cost_increased = objective_delta > tolerance
        push!(history, (; iteration, objective, objective_delta,
            max_centroid_shift=Float64(shift), cost_increased))
        if cost_increased
            @warn "The CUDA K-means objective increased beyond tolerance" iteration objective previous_objective objective_delta tolerance
        end

        if !cost_increased && abs(objective_delta) < tolerance
            converged = true
            stop_reason = "absolute_objective_change_tolerance"
            break
        end
        previous_objective = objective
    end

    # Gán lại theo tâm cuối để objective, assignments và codebook nhất quán.
    final_labels_gpu, final_residuals = _assign_all!(data, centroids;
        batch_size, distances, labels, residuals)
    objective = sum(Float64, final_residuals)
    CUDA.synchronize()
    final_labels = Int.(Array(final_labels_gpu))
    fit_seconds = time() - fit_started
    return (; centroids=Matrix{Float32}(Array(centroids)), labels=final_labels,
        objective, iterations=length(history), converged, stop_reason, history,
        backend="cuda", library="CUDA.jl", library_version=string(Base.pkgversion(CUDA)),
        initialization=isnothing(initial_indices) ? "K-means++" : "provided descriptor indices",
        maxiter, tolerance, batch_size,
        initialization_seconds, fit_seconds)
end

"""Gán gần tâm nhất theo batch; khoảng cách bằng nhau chọn word ID nhỏ nhất."""
function assign_words(X::AbstractMatrix{<:Real}, centroids::AbstractMatrix{<:Real};
    batch_size=DEFAULT_BATCH_SIZE, device_data=nothing, device_centroids=nothing)
    d, n = size(X)
    size(centroids, 1) == d || throw(ArgumentError("Số chiều centroid không khớp"))
    batch_size > 0 || throw(ArgumentError("batch_size phải dương"))
    data = isnothing(device_data) ? to_device(X) : device_data
    size(data.values) == (d, n) || throw(ArgumentError("device_data không khớp X"))
    centers = isnothing(device_centroids) ? CUDA.CuArray(Float32.(centroids)) : device_centroids
    size(centers) == size(centroids) || throw(ArgumentError("device_centroids không khớp centroids"))
    labels, _ = _assign_all!(data, centers; batch_size)
    return Int.(Array(labels))
end

"""Biên dịch kernel và làm nóng thư viện CUDA trên một ma trận nhỏ trước khi benchmark."""
function warmup!(; seed=42, batch_size=1024)
    check_available!()
    rng = MersenneTwister(seed)
    sample = rand(rng, Float32, 16, 128)
    fit_kmeans(sample; k=4, seed, maxiter=2, tolerance=0.0, batch_size)
    synchronize()
    return (; warmed_up=true, sample_descriptors=size(sample, 2), batch_size)
end

end # module FashionTCGPUCUDAExt
