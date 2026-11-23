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

function minimum_cost_assignment(cost)
    row_count, column_count = size(cost)
    row_count == column_count || throw(ArgumentError("Hungarian yêu cầu ma trận vuông"))
    n = row_count
    row_potential = zeros(Float64, n)
    column_potential = zeros(Float64, n + 1)
    matched_row = zeros(Int, n + 1)
    previous_column = zeros(Int, n + 1)

    for row in 1:n
        matched_row[1] = row
        current_column = 1
        minimum_reduced_cost = fill(Inf, n + 1)
        visited = falses(n + 1)
        while true
            visited[current_column] = true
            current_row = matched_row[current_column]
            delta = Inf
            next_column = 0
            for column in 2:n+1
                visited[column] && continue
                reduced_cost = cost[current_row, column - 1] -
                    row_potential[current_row] - column_potential[column]
                if reduced_cost < minimum_reduced_cost[column]
                    minimum_reduced_cost[column] = reduced_cost
                    previous_column[column] = current_column
                end
                if minimum_reduced_cost[column] < delta
                    delta = minimum_reduced_cost[column]
                    next_column = column
                end
            end
            for column in 1:n+1
                if visited[column]
                    row_potential[matched_row[column]] += delta
                    column_potential[column] -= delta
                else
                    minimum_reduced_cost[column] -= delta
                end
            end
            current_column = next_column
            matched_row[current_column] == 0 && break
        end
        while true
            prior_column = previous_column[current_column]
            matched_row[current_column] = matched_row[prior_column]
            current_column = prior_column
            current_column == 1 && break
        end
    end

    assignment = zeros(Int, n)
    for column in 2:n+1
        assignment[matched_row[column]] = column - 1
    end
    return assignment
end

function centroid_mse(reference, candidate)
    size(reference) == size(candidate) ||
        throw(ArgumentError("Số chiều hoặc số centroid không khớp sau khi đưa về Raw 16D"))
    dimension, cluster_count = size(reference)
    cost = Matrix{Float64}(undef, cluster_count, cluster_count)
    for reference_cluster in 1:cluster_count, candidate_cluster in 1:cluster_count
        cost[reference_cluster, candidate_cluster] = sum(abs2,
            reference[:, reference_cluster] .- candidate[:, candidate_cluster])
    end
    candidate_for_reference = minimum_cost_assignment(cost)
    total_squared_error = sum(cost[reference_cluster,
        candidate_for_reference[reference_cluster]] for reference_cluster in 1:cluster_count)
    return total_squared_error / (dimension * cluster_count)
end

function centroids_to_raw_space(config_id, centroids, pca)
    (; mu, pca_basis) = pca
    if config_id == "B0" || startswith(config_id, "Q")
        size(centroids, 1) == 16 || error("$config_id cần centroid 16D")
        return Float64.(centroids)
    end
    if startswith(config_id, "PQ")
        parts = split(config_id, "_")
        dimensions = parse(Int, parts[1][3:end])
    elseif startswith(config_id, "P")
        dimensions = parse(Int, config_id[2:end])
    else
        error("Không thể đưa centroid của $config_id về Raw 16D")
    end
    basis = pca_basis[:, 1:dimensions]
    return mu .+ basis * Float64.(centroids)
end

function raw_space_validation_distortion(validation_descriptors, raw_centroids)
    size(validation_descriptors, 1) == size(raw_centroids, 1) ||
        throw(ArgumentError("Validation descriptors và centroid phải cùng chiều Raw 16D"))
    total_squared_distance = 0.0
    @inbounds for descriptor_id in axes(validation_descriptors, 2)
        nearest_squared_distance = Inf
        for cluster_id in axes(raw_centroids, 2)
            squared_distance = 0.0
            for dimension in axes(validation_descriptors, 1)
                difference = Float64(validation_descriptors[dimension, descriptor_id]) -
                    raw_centroids[dimension, cluster_id]
                squared_distance += difference * difference
            end
            if squared_distance < nearest_squared_distance
                nearest_squared_distance = squared_distance
            end
        end
        total_squared_distance += nearest_squared_distance
    end
    return total_squared_distance / (size(validation_descriptors, 1) * size(validation_descriptors, 2))
end

function centroid_fingerprint(centroids)
    return bytes2hex(sha256(reinterpret(UInt8, vec(centroids))))
end
