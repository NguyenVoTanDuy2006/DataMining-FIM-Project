function csv_escape(value)
    text = ismissing(value) ? "" : string(value)
    needs_quotes = occursin(',', text) || occursin('"', text) ||
        occursin('\n', text) || occursin('\r', text)
    escaped = replace(text, "\"" => "\"\"")
    return needs_quotes ? "\"" * escaped * "\"" : escaped
end

function write_results_csv(path, rows)
    columns = ["config_id", "method", "n_input", "n_unique", "unique_ratio", "duplicate_rate", "d_eff",
        "compute_proxy", "theoretical_speedup_proxy", "raw_vector_mse",
        "normalized_distortion", "patch_rmse_p95", "distance_rank_spearman", "pca_evr",
        "prep_time_s", "peak_ram_mib", "max_weight", "mean_weight", "median_weight",
        "weight_p95", "fraction_singleton_keys", "sum_weights", "passes_sanity_checks"]
    open(path, "w") do io
        println(io, join(columns, ','))
        for row in rows
            escaped_values = [csv_escape(row[column]) for column in columns]
            println(io, join(escaped_values, ','))
        end
    end
    return path
end

function write_summary(path, chosen, n, tau, raw_duplicate_rate, pca_fit_seconds, frontier_count)
    open(path, "w") do io
        println(io, "# TC4 pre-K-means vector tradeoff — kết quả")
        println(io)
        println(io, "- Julia: `", VERSION, "`")
        println(io, "- Train descriptors N: `", n, "` (D=16)")
        println(io, "- Tau Q10+ train: `", tau, "`")
        println(io, "- Duplicate rate raw TC2: `", raw_duplicate_rate, "`")
        println(io, "- PCA fit seconds: `", round(pca_fit_seconds; digits = 3), "`")
        println(io, "- K-means fits: `0` (không chạy trong notebook này)")
        println(io, "- Pareto candidates: `", frontier_count, "`")
        println(io)
        println(io, "## Shortlist sơ bộ")
        println(io)
        println(io, "| Cấu hình | Compute proxy | Normalized distortion | P95 RMSE | Spearman | Prep (s) | U/N |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|")
        for row in chosen
            println(io, "| ", row["config_id"], " | ", round(row["compute_proxy"]; digits = 4),
                " | ", round(row["normalized_distortion"]; digits = 6), " | ",
                round(row["patch_rmse_p95"]; digits = 6), " | ",
                round(row["distance_rank_spearman"]; digits = 4), " | ",
                round(row["prep_time_s"]; digits = 2), " | ", row["n_unique"], "/", n, " |")
        end
        println(io)
        println(io, "`compute_proxy` và nghịch đảo của nó là proxy lý thuyết, không phải speedup đo được. MSE thấp không chứng minh codebook K-means tốt. Chỉ dùng bảng này để chọn tối đa 2–3 ứng viên cho thí nghiệm K=64, seed=42 ở giai đoạn sau; TC5 vẫn dùng descriptor raw 16D.")
    end
    return path
end

function encode_centroids(centroids)
    encoded_clusters = [join(repr.(centroids[:, cluster]), ";")
        for cluster in axes(centroids, 2)]
    return join(encoded_clusters, "|")
end

function benchmark_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ','))
        for row in rows
            values = [csv_escape(getproperty(row, Symbol(column))) for column in header]
            println(io, join(values, ','))
        end
    end
    return path
end

function optional_git_commit(repo_root)
    try
        return strip(read(`git -C $repo_root rev-parse HEAD`, String))
    catch
        return "unavailable"
    end
end
