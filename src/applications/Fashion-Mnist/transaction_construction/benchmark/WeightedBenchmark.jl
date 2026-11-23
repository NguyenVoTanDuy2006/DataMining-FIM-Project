function build_selected_representation(features, config_id)
    (; X, N, PCA_FIT_SECONDS) = features
    if config_id == "B0"
        return X, ones(Int, N), 0.0
    elseif startswith(config_id, "P") && !startswith(config_id, "PQ")
        dimensions = parse(Int, config_id[2:end])
        Z, weights = build_pca_representation(features, dimensions)
        return Z, weights, PCA_FIT_SECONDS
    elseif startswith(config_id, "Q")
        q = parse(Int, config_id[2:end])
        Z, weights = build_pixel_quant_representation(features, q)
        return Z, weights, 0.0
    elseif startswith(config_id, "PQ")
        parts = split(config_id, "_")
        dimensions = parse(Int, parts[1][3:end])
        alpha = parse(Int, parts[2][2:end]) / 100
        Z, weights = build_pca_quant_representation(features, dimensions, alpha)
        return Z, weights, PCA_FIT_SECONDS
    end
    error("Không hỗ trợ config_id: $config_id")
end

function validate_weighted_input(config_id, Z, weights, expected_row, N, K)
    size(Z, 2) == length(weights) || error("Số vector và weights không khớp: $config_id")
    size(Z, 2) == expected_row["n_unique"] || error("U không khớp TC4: $config_id")
    size(Z, 1) == expected_row["d_eff"] || error("D_eff không khớp TC4: $config_id")
    sum(weights) == N || error("sum(weights) phải bằng N=$N: $config_id")
    all(>(0), weights) || error("Weights phải dương: $config_id")
    all(isfinite, Z) || error("Z chứa giá trị không hữu hạn: $config_id")
    size(Z, 2) >= K || error("Không đủ vector để tạo K cụm: $config_id")
    return true
end

function benchmark_one_config(config_id, source_row, features, fit_config)
    (; K, SEED, MAX_ITER, TOL, N_REPEATS) = fit_config
    N = features.N
    preparation_started = time_ns()
    Z, weights, shared_pca_seconds = build_selected_representation(features, config_id)
    preparation_elapsed = (time_ns() - preparation_started) / 1e9 + shared_pca_seconds
    validate_weighted_input(config_id, Z, weights, source_row, N, K)
    println(config_id, ": Z=", size(Z), ", sum(weights)=", sum(weights),
        ", prep=", round(preparation_elapsed; digits = 3), " s")

    runs = NamedTuple[]
    for repeat_id in 1:N_REPEATS
        GC.gc()
        started = time_ns()
        fitted = weighted_kmeans(Z, weights; k = K, seed = SEED,
            max_iter = MAX_ITER, tolerance = TOL)
        fit_seconds = (time_ns() - started) / 1e9
        push!(runs, (; config_id, repeat = repeat_id, fit_time_s = fit_seconds,
            n_iter = fitted.n_iter, converged = fitted.converged,
            weighted_inertia = fitted.weighted_inertia,
            empty_cluster_count = fitted.empty_cluster_count,
            stop_reason = fitted.stop_reason,
            centroids = fitted.centroids))
        println("  repeat ", repeat_id, ": ", round(fit_seconds; digits = 3),
            " s, iter=", fitted.n_iter, ", converged=", fitted.converged,
            ", empty clusters=", fitted.empty_cluster_count)
    end

    fit_times = [run.fit_time_s for run in runs]
    median_position = argmin(abs.(fit_times .- median(fit_times)))
    representative = runs[median_position]
    result = (; config_id, method = source_row["method"], k = K, seed = SEED,
        n_input = N, n_unique = size(Z, 2), d_eff = size(Z, 1), sum_weights = sum(weights),
        prep_time_s = preparation_elapsed, fit_time_min_s = minimum(fit_times),
        fit_time_median_s = median(fit_times), fit_time_mean_s = mean(fit_times),
        fit_time_std_s = std(fit_times; corrected = false),
        total_time_median_s = preparation_elapsed + median(fit_times),
        representative_repeat = representative.repeat,
        n_iter = representative.n_iter, converged = representative.converged,
        weighted_inertia = representative.weighted_inertia,
        empty_cluster_count = representative.empty_cluster_count,
        passes_sanity_checks = true, runs)
    Z = nothing
    weights = nothing
    GC.gc()
    return result
end

function representative_run(config_result)
    return only(filter(run -> run.repeat == config_result.representative_repeat,
        config_result.runs))
end
