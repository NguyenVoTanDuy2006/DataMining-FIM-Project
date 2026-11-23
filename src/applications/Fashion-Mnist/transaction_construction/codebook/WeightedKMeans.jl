function squared_distance_column(Z, column, center)
    distance = 0.0
    @inbounds @simd for dimension in axes(Z, 1)
        delta = Float64(Z[dimension, column]) - center[dimension]
        distance += delta * delta
    end
    return distance
end

function weighted_sample_index(mass, rng, selected = nothing)
    total = sum(mass)
    if !(total > 0)
        for index in eachindex(mass)
            isnothing(selected) || !selected[index] || continue
            return index
        end
        error("Không còn vector phù hợp để chọn tâm")
    end
    target = rand(rng) * total
    cumulative = 0.0
    fallback = firstindex(mass)
    for index in eachindex(mass)
        mass[index] > 0 || continue
        fallback = index
        cumulative += mass[index]
        target < cumulative && return index
    end
    return fallback
end

function weighted_kmeanspp(Z, weights, k, rng)
    dimension, n = size(Z)
    centers = Matrix{Float64}(undef, dimension, k)
    selected = falses(n)
    first_center = weighted_sample_index(weights, rng)
    centers[:, 1] .= Float64.(Z[:, first_center])
    selected[first_center] = true
    nearest_distance = Vector{Float64}(undef, n)
    @inbounds for index in 1:n
        nearest_distance[index] = squared_distance_column(Z, index, @view centers[:, 1])
    end
    probability_mass = Vector{Float64}(undef, n)

    for cluster in 2:k
        @inbounds for index in 1:n
            probability_mass[index] = selected[index] ? 0.0 : weights[index] * nearest_distance[index]
        end
        chosen = weighted_sample_index(probability_mass, rng, selected)
        centers[:, cluster] .= Float64.(Z[:, chosen])
        selected[chosen] = true
        @inbounds for index in 1:n
            distance = squared_distance_column(Z, index, @view centers[:, cluster])
            nearest_distance[index] = min(nearest_distance[index], distance)
        end
    end
    return centers
end

function weighted_assign(Z, centers, weights)
    n = size(Z, 2)
    labels = Vector{Int}(undef, n)
    nearest_distance = Vector{Float64}(undef, n)
    objective = 0.0
    @inbounds for index in 1:n
        best_cluster = 1
        best_distance = squared_distance_column(Z, index, @view centers[:, 1])
        for cluster in 2:size(centers, 2)
            distance = squared_distance_column(Z, index, @view centers[:, cluster])
            if distance < best_distance
                best_cluster = cluster
                best_distance = distance
            end
        end
        labels[index] = best_cluster
        nearest_distance[index] = best_distance
        objective += weights[index] * best_distance
    end
    return labels, nearest_distance, objective
end

function weighted_kmeans(Z, weights; k, seed = 42, max_iter = 1000,
    tolerance = 1e-4, initial_centers = nothing)
    dimension, n = size(Z)
    n >= k || throw(ArgumentError("Cần ít nhất K vector duy nhất"))
    length(weights) == n || throw(ArgumentError("weights không khớp số vector"))
    all(>(0), weights) || throw(ArgumentError("Mọi weight phải dương"))
    rng = MersenneTwister(seed)
    centers = isnothing(initial_centers) ? weighted_kmeanspp(Z, weights, k, rng) :
        Matrix{Float64}(initial_centers)
    size(centers) == (dimension, k) || throw(ArgumentError("Shape initial_centers sai"))
    cluster_sums = zeros(Float64, dimension, k)
    cluster_weights = zeros(Int64, k)
    weighted_errors = Vector{Float64}(undef, n)
    empty_cluster_count = 0
    previous_objective = Inf
    converged = false
    n_iter = 0

    for iteration in 1:max_iter
        labels, nearest_distance, objective = weighted_assign(Z, centers, weights)
        fill!(cluster_sums, 0.0)
        fill!(cluster_weights, 0)
        @inbounds for index in 1:n
            cluster = labels[index]
            weight = weights[index]
            cluster_weights[cluster] += weight
            weighted_errors[index] = weight * nearest_distance[index]
            for coordinate in 1:dimension
                cluster_sums[coordinate, cluster] += weight * Float64(Z[coordinate, index])
            end
        end

        @inbounds for cluster in 1:k
            if cluster_weights[cluster] > 0
                centers[:, cluster] .= cluster_sums[:, cluster] ./ cluster_weights[cluster]
            end
        end
        used_rescue_points = falses(n)
        for cluster in 1:k
            cluster_weights[cluster] == 0 || continue
            best_index = 0
            best_error = -Inf
            @inbounds for index in 1:n
                if !used_rescue_points[index] && weighted_errors[index] > best_error
                    best_index = index
                    best_error = weighted_errors[index]
                end
            end
            best_index > 0 || error("Không thể tái khởi tạo cụm rỗng")
            centers[:, cluster] .= Float64.(Z[:, best_index])
            used_rescue_points[best_index] = true
            empty_cluster_count += 1
        end

        n_iter = iteration
        if isfinite(previous_objective)
            relative_change = abs(previous_objective - objective) / max(abs(previous_objective), eps(Float64))
            if relative_change <= tolerance
                converged = true
                break
            end
        end
        previous_objective = objective
    end

    final_labels, _, final_objective = weighted_assign(Z, centers, weights)
    return (; centroids = centers, labels = final_labels, weighted_inertia = final_objective,
        n_iter, converged, empty_cluster_count,
        stop_reason = converged ? "relative_objective_change" : "max_iter")
end
