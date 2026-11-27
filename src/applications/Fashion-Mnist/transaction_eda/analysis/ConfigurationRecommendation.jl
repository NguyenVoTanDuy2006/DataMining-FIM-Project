"""Build separate, scope-limited K and transaction-representation comparisons."""
function _recommendation_number(row, name)
    value = tryparse(Float64, get(row, name, ""))
    return isnothing(value) || !isfinite(value) ? missing : value
end

function _recommendation_mean(rows, column)
    values = collect(skipmissing([_recommendation_number(row, column) for row in rows]))
    return isempty(values) ? missing : mean(values)
end

function _recommendation_sd(rows, column)
    values = collect(skipmissing([_recommendation_number(row, column) for row in rows]))
    return length(values) < 2 ? missing : std(values)
end

function _recommendation_leader(rows, index; higher=false)
    candidates = filter(row -> !ismissing(row[index]), rows)
    isempty(candidates) && return (ks=String[], value=missing)
    values = [Float64(row[index]) for row in candidates]
    target = higher ? maximum(values) : minimum(values)
    ks = sort!(unique([string(row[1]) for row in candidates if Float64(row[index]) == target]))
    return (; ks, value=target)
end

function _recommendation_pareto_k(rows)
    candidates = filter(row -> row[2] == length(EXPECTED_SEEDS) &&
        !ismissing(row[4]) && !ismissing(row[9]), rows)
    return [row for row in candidates if !any(other -> other !== row &&
        other[4] <= row[4] && other[9] >= row[9] &&
        (other[4] < row[4] || other[9] > row[9]), candidates)]
end

_recommendation_display(value) = ismissing(value) ? "unavailable" : string(round(value; sigdigits=4))

function _recommendation_rows(path)
    isfile(path) || return Dict{String,String}[]
    _, rows = _read_csv(path)
    return rows
end

function _write_recommendation_report!(ctx::EDA2Context)
    codebook_rows = _recommendation_rows(output_path(ctx, "codebook", "codebook_metrics_15.csv"))
    transaction_rows = _recommendation_rows(output_path(ctx, "transactions", "transaction_metrics_60.csv"))
    paired_rows = _recommendation_rows(output_path(ctx, "transactions", "paired_encoding_comparison.csv"))
    pilot_rows = _recommendation_rows(output_path(ctx, "pilot_eclat", "pilot_common_60.csv"))

    k_rows = Vector{Vector{Any}}()
    for k in EXPECTED_K
        fits = filter(row -> get(row, "K", "") == string(k), codebook_rows)
        valid_fits = filter(row -> !ismissing(_recommendation_number(row, "distortion")), fits)
        k_transactions = filter(row -> get(row, "K", "") == string(k), transaction_rows)
        k_pilots = filter(row -> get(row, "K", "") == string(k), pilot_rows)
        converged = count(row -> get(row, "convergence_status", "") == "CONVERGED", fits)
        pilot_completed = count(row -> get(row, "status", "") == "COMPLETED_LENGTH_CAPPED" &&
            lowercase(get(row, "censored", "true")) == "false", k_pilots)
        row = Any[k, length(valid_fits), converged,
            _recommendation_mean(valid_fits, "distortion"),
            _recommendation_sd(valid_fits, "distortion"),
            _recommendation_mean(valid_fits, "occupancy"),
            _recommendation_mean(valid_fits, "cluster_entropy_norm"),
            _recommendation_mean(valid_fits, "top1_cluster_share"),
            _recommendation_mean(valid_fits, "seed_stability_ari_mean_saved"),
            _recommendation_sd(valid_fits, "seed_stability_ari_mean_saved"),
            _recommendation_mean(filter(r -> get(r, "variant", "") == "S0", k_transactions), "mean_length"),
            _recommendation_mean(filter(r -> get(r, "variant", "") == "S0", k_transactions), "unique_ratio"),
            _recommendation_mean(filter(r -> get(r, "variant", "") == "S0", k_pilots), "frequent_2_count")]
        for variant in VARIANTS[2:end]
            variant_tx = filter(r -> get(r, "variant", "") == variant, k_transactions)
            variant_pilot = filter(r -> get(r, "variant", "") == variant, k_pilots)
            append!(row, [_recommendation_mean(variant_tx, "mean_length"),
                _recommendation_mean(variant_tx, "unique_ratio"),
                _recommendation_mean(variant_pilot, "frequent_2_count")])
        end
        append!(row, [pilot_completed, length(k_pilots)])
        push!(k_rows, row)
    end
    _write_csv(output_path(ctx, "recommendations", "k_comparison.csv"),
        ["K", "valid_fits", "converged_fits", "distortion_mean", "distortion_std",
            "occupancy_mean", "normalized_entropy_mean", "top_cluster_share_mean",
            "saved_ari_mean", "saved_ari_std", "S0_mean_transaction_length", "S0_unique_transaction_ratio",
            "S0_frequent_2_itemsets_mean",
            "S1_mean_transaction_length", "S1_unique_transaction_ratio", "S1_frequent_2_itemsets_mean",
            "S3_mean_transaction_length", "S3_unique_transaction_ratio", "S3_frequent_2_itemsets_mean",
            "S6-B_mean_transaction_length", "S6-B_unique_transaction_ratio", "S6-B_frequent_2_itemsets_mean",
            "C1_completed_runs", "C1_expected_runs"], k_rows)

    representation_rows = Vector{Vector{Any}}()
    for k in EXPECTED_K, variant in VARIANTS
        tx = filter(row -> get(row, "K", "") == string(k) &&
            get(row, "variant", "") == variant, transaction_rows)
        paired = filter(row -> get(row, "K", "") == string(k) &&
            get(row, "variant", "") == variant, paired_rows)
        mined = filter(row -> get(row, "K", "") == string(k) &&
            get(row, "variant", "") == variant, pilot_rows)
        completed = count(row -> get(row, "status", "") == "COMPLETED_LENGTH_CAPPED" &&
            lowercase(get(row, "censored", "true")) == "false", mined)
        completed_mining = filter(row -> get(row, "status", "") == "COMPLETED_LENGTH_CAPPED" &&
            lowercase(get(row, "censored", "true")) == "false", mined)
        push!(representation_rows, Any[k, variant, length(tx), length(paired),
            _recommendation_mean(tx, "mean_length"), _recommendation_mean(tx, "empty_rate"),
            _recommendation_mean(tx, "unique_ratio"),
            _recommendation_mean(paired, "length_delta_mean_vs_s0"),
            _recommendation_mean(completed_mining, "frequent_1_count"),
            _recommendation_mean(completed_mining, "frequent_2_count"),
            _recommendation_mean(completed_mining, "runtime_s"), completed, length(mined)])
    end
    _write_csv(output_path(ctx, "recommendations", "representation_comparison.csv"),
        ["K", "variant", "transaction_runs", "matched_S0_pairs", "mean_length",
            "empty_rate", "unique_transaction_ratio", "mean_length_delta_vs_S0",
            "frequent_1_itemsets_mean", "frequent_2_itemsets_mean", "C1_mean_runtime_s",
            "C1_completed_runs", "C1_expected_runs"], representation_rows)

    representation_summary = Vector{Vector{Any}}()
    for variant in VARIANTS
        tx = filter(row -> get(row, "variant", "") == variant, transaction_rows)
        paired = filter(row -> get(row, "variant", "") == variant, paired_rows)
        mined = filter(row -> get(row, "variant", "") == variant &&
            get(row, "status", "") == "COMPLETED_LENGTH_CAPPED" &&
            lowercase(get(row, "censored", "true")) == "false", pilot_rows)
        push!(representation_summary, Any[variant, length(tx), length(paired),
            _recommendation_mean(tx, "mean_length"), _recommendation_mean(tx, "empty_rate"),
            _recommendation_mean(tx, "unique_ratio"),
            _recommendation_mean(paired, "length_delta_mean_vs_s0"),
            _recommendation_mean(mined, "frequent_1_count"),
            _recommendation_mean(mined, "frequent_2_count"),
            _recommendation_mean(mined, "runtime_s"), length(mined)])
    end
    _write_csv(output_path(ctx, "recommendations", "representation_summary.csv"),
        ["variant", "transaction_runs", "matched_S0_pairs", "mean_length", "empty_rate",
            "unique_transaction_ratio", "mean_length_delta_vs_S0", "frequent_1_itemsets_mean",
            "frequent_2_itemsets_mean", "C1_mean_runtime_s", "C1_completed_runs"], representation_summary)

    valid_k = filter(row -> row[2] == length(EXPECTED_SEEDS), k_rows)
    k_status = isempty(valid_k) ? "UNAVAILABLE" : "PROVISIONAL"
    complete_pairs = count(row -> row[4] == length(EXPECTED_SEEDS), representation_rows)
    representation_status = complete_pairs == 0 ? "UNAVAILABLE" : "PROVISIONAL"
    pareto_k = _recommendation_pareto_k(k_rows)
    lowest_distortion = _recommendation_leader(valid_k, 4)
    highest_saved_ari = _recommendation_leader(valid_k, 9; higher=true)
    representation_by_length = _recommendation_leader(representation_summary, 4)
    representation_by_diversity = _recommendation_leader(representation_summary, 6; higher=true)
    representation_by_pairs = _recommendation_leader(representation_summary, 9; higher=true)
    pareto_k_labels = isempty(pareto_k) ? "unavailable" : join(string.(first.(pareto_k)), ", ")
    limitations = [
        "The K comparison uses the configured five K values and three seeds; it does not establish a universal optimum.",
        "The common Eclat comparison is limited to 3% minimum support and itemsets of length at most two.",
        "A larger frequent-itemset count is not treated as a stand-alone quality objective.",
        "The results describe unsupervised structure and do not establish predictive classification value.",
    ]
    report = Dict{String,Any}(
        "schema_version" => 1,
        "scope" => ctx.scope,
        "common_minsup_fraction" => Float64(get(ctx.config["pilot"], "common_minsup_fraction", 0.03)),
        "common_max_itemset_length" => Int(get(ctx.config["pilot"], "common_max_itemset_length", 2)),
        "expected_k_seed_fits" => length(EXPECTED_K) * length(EXPECTED_SEEDS),
        "observed_valid_k_seed_fits" => sum(row[2] for row in k_rows),
        "expected_transaction_sets" => EXPECTED_DATABASES,
        "observed_transaction_sets" => length(transaction_rows),
        "expected_common_pilot_runs" => EXPECTED_DATABASES,
        "observed_common_pilot_runs" => length(pilot_rows),
        "k_recommendation_status" => k_status,
        "representation_recommendation_status" => representation_status,
        "k_pareto_candidates_distortion_vs_saved_ari" => String[string(row[1]) for row in pareto_k],
        "lowest_mean_distortion_k" => join(lowest_distortion.ks, ","),
        "lowest_mean_distortion" => ismissing(lowest_distortion.value) ? "" : lowest_distortion.value,
        "highest_saved_ari_k" => join(highest_saved_ari.ks, ","),
        "highest_saved_ari_mean" => ismissing(highest_saved_ari.value) ? "" : highest_saved_ari.value,
        "shortest_mean_transaction_variant" => join(representation_by_length.ks, ","),
        "highest_unique_ratio_variant" => join(representation_by_diversity.ks, ","),
        "highest_mean_frequent_2_count_variant" => join(representation_by_pairs.ks, ","),
        "limitations" => limitations,
    )
    open(output_path(ctx, "recommendations", "recommendation_summary.toml"), "w") do io
        TOML.print(io, report; sorted=true)
    end
    open(output_path(ctx, "recommendations", "recommendation_summary.md"), "w") do io
        println(io, "# Fashion-MNIST configuration comparison")
        println(io)
        println(io, "## K-means codebook size")
        println(io)
        println(io, "`k_comparison.csv` reports codebook distortion, occupancy, entropy and saved ARI, alongside transaction length, diversity and common Eclat counts for S0, S1, S3 and S6-B at each K. These transaction measures show how a shared codebook changes each encoding; they are not K-means fit metrics. Among K values with all three fits, the lowest mean distortion is K=$(join(lowest_distortion.ks, ",")) ($( _recommendation_display(lowest_distortion.value) )); the highest saved ARI is K=$(join(highest_saved_ari.ks, ",")) ($( _recommendation_display(highest_saved_ari.value) )). The two criteria can favor different K values.")
        println(io)
        println(io, "The nondominated K candidates on mean distortion and saved ARI are $pareto_k_labels. This is a shortlist for review, not a universal optimum; the saved ARI sample provenance remains a limitation.")
        println(io)
        println(io, "## Transaction representation")
        println(io)
        println(io, "`representation_summary.csv` and `representation_comparison.csv` compare BoVW binary (S0), region-aware (S1), stripe-aware (S3), and neighbor-relation (S6-B) over matched K–seed inputs. The shortest mean transaction is $(join(representation_by_length.ks, ",")); the highest unique-transaction ratio is $(join(representation_by_diversity.ks, ",")); the most frequent 2-itemsets at the common scope is $(join(representation_by_pairs.ks, ",")). These are separate tradeoff leaders: pattern count alone does not determine the preferred representation. The common mining scope is 3% minimum support with a maximum itemset length of two.")
        println(io)
        println(io, "## Evidence limits")
        println(io)
        for limitation in limitations
            println(io, "- ", limitation)
        end
    end
    return (; k_comparison=output_path(ctx, "recommendations", "k_comparison.csv"),
        representation_comparison=output_path(ctx, "recommendations", "representation_comparison.csv"),
        representation_summary=output_path(ctx, "recommendations", "representation_summary.csv"),
        summary=output_path(ctx, "recommendations", "recommendation_summary.toml"),
        status=(k=k_status, representation=representation_status))
end

write_configuration_recommendations!(ctx::EDA2Context) = _write_recommendation_report!(ctx)
