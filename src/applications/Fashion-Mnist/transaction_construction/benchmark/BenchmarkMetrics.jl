function process_high_water_mib()
    status_path = "/proc/self/status"
    isfile(status_path) || return missing
    for line in eachline(status_path)
        startswith(line, "VmHWM:") || continue
        kib = parse(Float64, split(strip(line))[2])
        return kib / 1024
    end
    return missing
end

function average_ranks(values)
    order = sortperm(values)
    ranks = Vector{Float64}(undef, length(values))
    first = 1
    while first <= length(order)
        last = first
        while last < length(order) && values[order[last + 1]] == values[order[first]]
            last += 1
        end
        average_rank = (first + last) / 2
        for position in first:last
            ranks[order[position]] = average_rank
        end
        first = last + 1
    end
    return ranks
end

function spearman_correlation(a, b)
    rank_a = average_ranks(a)
    rank_b = average_ranks(b)
    return cor(rank_a, rank_b)
end

function distance_for_pair(X, first, second)
    total = 0.0
    @inbounds for d in axes(X, 1)
        delta = Float64(X[d, first]) - Float64(X[d, second])
        total += delta * delta
    end
    return sqrt(total)
end

function unique_weight_summary(weights)
    weight_values = collect(Base.values(weights))
    isempty(weight_values) && return (; max_weight = 0, mean_weight = 0.0,
        median_weight = 0.0, weight_p95 = 0.0, fraction_singleton_keys = 0.0,
        sum_weights = 0)
    return (; max_weight = maximum(weight_values), mean_weight = mean(weight_values),
        median_weight = median(weight_values), weight_p95 = quantile(weight_values, 0.95),
        fraction_singleton_keys = count(==(1), weight_values) / length(weight_values),
        sum_weights = sum(weight_values))
end

function weight_summary_or_singletons(counts, n)
    isnothing(counts) && return (; max_weight = 1, mean_weight = 1.0,
        median_weight = 1.0, weight_p95 = 1.0, fraction_singleton_keys = 1.0,
        sum_weights = n)
    return unique_weight_summary(counts)
end

function add_result!(results, fields)
    push!(results, Dict{String,Any}(string(key) => value for (key, value) in pairs(fields)))
end

function append_vector_metrics!(results, id, method, d_eff, counts, mse, rmse_values,
    rank_value, pca_evr, prep_seconds, high_water, features)
    (; N, raw_mean_feature_variance) = features
    unique_count = isnothing(counts) ? N : length(counts)
    unique_ratio = unique_count / N
    compute_proxy = (unique_count * d_eff) / (N * 16)
    weights = weight_summary_or_singletons(counts, N)
    sanity = isfinite(mse) && isfinite(rank_value) && weights.sum_weights == N &&
        unique_count > 0 && compute_proxy > 0
    add_result!(results, (; config_id = id, method, n_input = N, n_unique = unique_count,
        unique_ratio, duplicate_rate = 1 - unique_ratio, d_eff, compute_proxy,
        theoretical_speedup_proxy = 1 / compute_proxy,
        raw_vector_mse = mse, normalized_distortion = mse / raw_mean_feature_variance,
        patch_rmse_p95 = quantile(rmse_values, 0.95),
        distance_rank_spearman = rank_value, pca_evr,
        prep_time_s = prep_seconds, peak_ram_mib = high_water,
        max_weight = weights.max_weight, mean_weight = weights.mean_weight,
        median_weight = weights.median_weight, weight_p95 = weights.weight_p95,
        fraction_singleton_keys = weights.fraction_singleton_keys,
        sum_weights = weights.sum_weights, passes_sanity_checks = sanity))
end

function is_dominated(candidate, all_rows, x_key, y_key)
    return any(other -> other !== candidate &&
        other[x_key] <= candidate[x_key] && other[y_key] <= candidate[y_key] &&
        (other[x_key] < candidate[x_key] || other[y_key] < candidate[y_key]), all_rows)
end

function pareto_rows(rows, x_key, y_key)
    return [row for row in rows if !is_dominated(row, rows, x_key, y_key)]
end
