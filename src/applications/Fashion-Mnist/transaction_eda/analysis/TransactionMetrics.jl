function _transaction_metrics(spec, txs, pair_manifest, class_manifest, ctx)
    n = length(txs)
    lengths = length.(txs)
    supports = Dict{Int,Int}()
    unique_counts = Dict{Tuple{Vararg{Int}},Int}()
    for tx in txs
        key = Tuple(tx)
        unique_counts[key] = get(unique_counts, key, 0) + 1
        for item in tx
            supports[item] = get(supports, item, 0) + 1
        end
    end
    observed = sort!(collect(keys(supports)))
    counts = [supports[item] for item in observed]
    support_frac = counts ./ n
    support_cfg=get(ctx.config,"support",Dict{String,Any}())
    rare_max=Float64(get(support_cfg,"rare_support_max",0.01))
    ubiquitous_min=Float64(get(support_cfg,"ubiquitous_support_min",0.90))
    universe = _theoretical_size(spec.variant, spec.k)
    capacity=_transaction_length_capacity(spec.variant,spec.k)
    metrics = Dict{String,Any}(
        "database_id"=>spec.database_id, "K"=>spec.k, "seed"=>spec.seed, "variant"=>spec.variant, "N"=>n,
        "empty_count"=>count(isempty, txs), "nonempty_count"=>count(tx -> !isempty(tx), txs),
        "empty_rate"=>count(isempty,txs)/n,"length1_count"=>count(==(1),lengths),"length1_fraction"=>count(==(1),lengths)/n,
        "mean_length"=>mean(lengths), "median_length"=>median(lengths), "std_length"=>std(lengths),
        "min_length"=>minimum(lengths), "max_length"=>maximum(lengths),
        "p5_length"=>quantile(lengths, 0.05), "p25_length"=>quantile(lengths, 0.25),
        "p75_length"=>quantile(lengths, 0.75), "p95_length"=>quantile(lengths, 0.95), "p99_length"=>quantile(lengths, 0.99),
        "observed_universe"=>length(observed), "theoretical_universe"=>universe,
        "length_capacity"=>capacity,"length_capacity_ratio"=>maximum(lengths)/capacity,
        "density_theoretical"=>sum(lengths)/(n*universe), "density_observed"=>(isempty(observed) ? 0.0 : sum(lengths)/(n*length(observed))),
        "unique_transaction_count"=>length(unique_counts), "unique_ratio"=>length(unique_counts)/n,
        "duplicate_ratio"=>1-length(unique_counts)/n, "support_min"=>isempty(observed) ? NaN : minimum(support_frac),
        "support_median"=>isempty(observed) ? NaN : median(support_frac), "support_mean"=>isempty(observed) ? NaN : mean(support_frac),
        "support_p5"=>isempty(observed) ? NaN : quantile(support_frac, 0.05), "support_p95"=>isempty(observed) ? NaN : quantile(support_frac, 0.95),
        "support_max"=>isempty(observed) ? NaN : maximum(support_frac), "integrity_status"=>"PASS")
    support_rows = [[spec.database_id, spec.k, spec.seed, spec.variant, item, supports[item], supports[item]/n] for item in observed]
    support_path = output_path(ctx, "transactions", "item_support_by_database", "$(spec.database_id).csv")
    _write_csv(support_path, ["database_id", "K", "seed", "variant", "item_id", "support_count", "support_fraction"], support_rows)
    repeated=sort!([entry for entry in collect(unique_counts) if last(entry)>1];by=entry->(-last(entry),first(entry)))
    duplicate_rows=[[spec.database_id,spec.variant,join(first(entry)," "),join([_decode_item(spec.variant,item,spec.k) for item in first(entry)],";"),last(entry),length(first(entry))]
        for entry in repeated[1:min(100,length(repeated))]]
    _write_csv(output_path(ctx,"transactions","repeated_transactions", "$(spec.database_id).csv"),
        ["database_id","variant","item_ids_raw_namespace","decoded_items","multiplicity","length"],duplicate_rows)
    threshold_rows = Vector{Vector{Any}}()
    thresholds = Float64.(get(get(ctx.config, "pilot", Dict{String,Any}()), "minsup_fractions", [0.01, 0.03, 0.05, 0.10]))
    for fraction in thresholds
        cutoff = ceil(Int, fraction*n)
        frequent = count(>=(cutoff), counts)
        push!(threshold_rows, [spec.database_id, spec.k, spec.seed, spec.variant, fraction, cutoff, frequent,
            length(observed), universe, isempty(observed) ? 0.0 : frequent/length(observed), frequent/universe,
            metrics["support_min"],metrics["support_median"],metrics["support_mean"],metrics["support_p5"],metrics["support_p95"],metrics["support_max"],
            count(<=(rare_max),support_frac),count(>=(ubiquitous_min),support_frac)])
    end
    _pair_similarity!(metrics, txs, pair_manifest)
    class_rows, between_rows = _class_similarity!(metrics, spec, txs, class_manifest)
    return metrics, support_rows, threshold_rows, class_rows, between_rows
end

function _spatial_descriptive_rows(spec, txs)
    region_rows = Vector{Vector{Any}}()
    key = [spec.database_id, spec.k, spec.seed, spec.variant]
    spec.variant in ("S1", "S3") || return region_rows, nothing
    _, mapping = _read_csv(joinpath(spec.run_dir, "item_mapping.csv"))
    by_id = Dict(parse(Int, row["item_id"]) => row for row in mapping)
    labels=spec.variant=="S1" ? ["top_left","top_right","bottom_left","bottom_right"] : ["top","middle","bottom"]
    capacities=spec.variant=="S1" ? [9,12,12,16] : [14,21,14]
    counts=zeros(Int,length(labels))
    for tx in txs
        present=Set{Int}()
        for item in tx
            row=get(by_id,item,nothing)
            isnothing(row) && error("No spatial mapping for observed item $item")
            group=parse(Int,spec.variant=="S1" ? row["region_id"] : row["stripe_id"])
            push!(present,group)
        end
        for group in present; counts[group]+=1; end
    end
    for group in eachindex(labels)
        push!(region_rows,[spec.database_id,spec.k,spec.seed,spec.variant,group,labels[group],capacities[group],counts[group],counts[group]/EXPECTED_IMAGES])
    end
    return region_rows, [key..., "PROJECTION_AND_EMPTY_STATUS_PASS"]
end

function _s6b_neighbor_edge_row(spec, txs)
    spec.variant == "S6-B" || return nothing
    _, mapping = _read_csv(joinpath(spec.run_dir, "item_mapping.csv"))
    integrity = TOML.parsefile(joinpath(spec.run_dir, "integrity_report.toml"))
    stats = TOML.parsefile(joinpath(spec.run_dir, "encoding_stats.toml"))

    above_items = count(row -> row["relation_type"] == "ABOVE", mapping)
    left_items = count(row -> row["relation_type"] == "LEFT_OF", mapping)
    same_word_items = count(row -> row["word_a"] == row["word_b"], mapping)
    observed_items = Set(parse(Int, row["item_id"]) for row in mapping)
    mapping_complete = all(item -> item in observed_items, (item for tx in txs for item in tx))
    max_length = maximum(length.(txs); init=0)
    length_bound = max_length <= _transaction_length_capacity("S6-B", spec.k)
    applicable = String.(get(integrity, "applicable_checks", String[]))
    checks = get(integrity, "checks", Dict{String,Any}())
    witness_geometry = "S6-B witness geometry for every observed item" in applicable &&
        get(checks, "variant_specific_invariant_valid", false) == true
    rule_snapshot = TOML.parsefile(joinpath(spec.run_dir, "config_snapshot.toml"))
    rules = get(rule_snapshot, "spatial_rules", Dict{String,Any}())
    s6b_rules = get(rules, "s6b", Dict{String,Any}())
    edge_rules = get(s6b_rules, "relation_types", String[]) == ["ABOVE", "LEFT_OF"] &&
        get(s6b_rules, "min_manhattan_distance", 0) == 1 &&
        get(s6b_rules, "max_manhattan_distance", 0) == 2
    geometry = _s6b_neighbor_geometry_counts()
    geometry.candidate_pairs == 226 && geometry.diagonal_pairs == 72 &&
        geometry.boundary_pairs == 124 && geometry.corner_pairs == 20 &&
        geometry.wraparound_only_pairs == 68 && geometry.valid_candidates ||
        error("S6-B 7×7 neighbor geometry differs from the expected edge layout")
    pair_capacity = geometry.candidate_pairs * length(txs)
    eligible_pairs = Int(get(stats, "eligible_neighbor_pairs_processed", -1))
    0 <= eligible_pairs <= pair_capacity || error("S6-B eligible neighbor-pair count is outside geometric capacity")
    eligible_boundary_pairs = Int(get(stats, "eligible_boundary_neighbor_pairs_processed", -1))
    eligible_corner_pairs = Int(get(stats, "eligible_corner_neighbor_pairs_processed", -1))
    0 <= eligible_boundary_pairs <= geometry.boundary_pairs * length(txs) ||
        error("S6-B eligible boundary-pair count is outside geometric capacity")
    0 <= eligible_corner_pairs <= geometry.corner_pairs * length(txs) ||
        error("S6-B eligible corner-pair count is outside geometric capacity")
    boundary_counts = eligible_corner_pairs <= eligible_boundary_pairs <= eligible_pairs &&
        eligible_boundary_pairs <= geometry.boundary_pairs * length(txs) &&
        eligible_corner_pairs <= geometry.corner_pairs * length(txs)
    no_wrap = geometry.no_wrap &&
        get(checks, "s6b_in_bounds_no_wrap_valid", false) == true
    boundary_geometry = geometry.boundary_pairs == 124 && geometry.corner_pairs == 20 &&
        geometry.wraparound_only_pairs == 68 &&
        get(checks, "s6b_boundary_counts_within_capacity", false) == true
    edge_status = mapping_complete && length_bound && witness_geometry && edge_rules &&
        no_wrap && boundary_geometry && boundary_counts ? "PASS" : "FAIL"

    return [spec.database_id, spec.k, spec.seed, length(txs), geometry.candidate_pairs,
        geometry.diagonal_pairs, geometry.boundary_pairs, geometry.corner_pairs,
        geometry.wraparound_only_pairs, eligible_pairs, eligible_boundary_pairs,
        eligible_corner_pairs,
        pair_capacity == 0 ? 0.0 : eligible_pairs / pair_capacity,
        Int(get(stats, "relation_occurrences_before_dedup", -1)), length(observed_items),
        above_items, left_items, same_word_items, count(!isempty, txs), count(isempty, txs),
        max_length, mapping_complete, length_bound, witness_geometry, edge_rules,
        no_wrap, boundary_geometry && boundary_counts, edge_status]
end

function _s6b_neighbor_geometry_counts()
    candidates = Set{Tuple{Int,Int}}()
    wraparound_only = Set{Tuple{Int,Int}}()
    diagonal = 0
    boundary = 0
    corners = 0
    valid = true
    for p in 1:49, q in p+1:49
        r1, c1 = (p - 1) ÷ 7 + 1, (p - 1) % 7 + 1
        r2, c2 = (q - 1) ÷ 7 + 1, (q - 1) % 7 + 1
        dr, dc = abs(r1-r2), abs(c1-c2)
        distance = dr + dc
        if 1 <= distance <= 2
            push!(candidates, (p, q))
            if r1 != r2 && c1 != c2
                diagonal += 1
            end
            touches_boundary = r1 in (1,7) || r2 in (1,7) || c1 in (1,7) || c2 in (1,7)
            if touches_boundary
                boundary += 1
            end
            corner1 = r1 in (1,7) && c1 in (1,7)
            corner2 = r2 in (1,7) && c2 in (1,7)
            if corner1 || corner2
                corners += 1
            end
            valid &= 1 <= r1 <= 7 && 1 <= c1 <= 7 && 1 <= r2 <= 7 && 1 <= c2 <= 7
            valid &= 1 <= distance <= 2
        end
        wrapped_distance = min(dr, 7-dr) + min(dc, 7-dc)
        if distance > 2 && 1 <= wrapped_distance <= 2
            push!(wraparound_only, (p,q))
        end
    end
    no_wrap = isempty(intersect(candidates, wraparound_only)) &&
        all(pair -> begin
            p,q=pair
            r1,c1=(p-1)÷7+1,(p-1)%7+1
            r2,c2=(q-1)÷7+1,(q-1)%7+1
            abs(r1-r2)+abs(c1-c2) in 1:2
        end, candidates)
    return (candidate_pairs=length(candidates), diagonal_pairs=diagonal,
        boundary_pairs=boundary, corner_pairs=corners,
        wraparound_only_pairs=length(wraparound_only), valid_candidates=valid,
        no_wrap=no_wrap)
end

function _length_histogram_rows(spec,txs)
    bins=[("0",0,0),("1",1,1),("2",2,2),("3-5",3,5),("6-10",6,10),
        ("11-20",11,20),("21-40",21,40),("41-80",41,80),("81-160",81,160),("161+",161,typemax(Int))]
    lengths=length.(txs)
    return [[spec.database_id,spec.k,spec.seed,spec.variant,label,count(x->lo<=x<=hi,lengths),
        count(x->lo<=x<=hi,lengths)/length(lengths)] for (label,lo,hi) in bins]
end

function transaction_metric_rows_for_variants(rows, k, seed, variants)
    required_numeric = ("max_length", "p5_length", "p25_length", "median_length", "p75_length", "p95_length")
    result = Pair{String,Dict{String,String}}[]
    for variant in variants
        matches = filter(row -> get(row, "K", "") == string(k) &&
            get(row, "seed", "") == string(seed) && get(row, "variant", "") == variant, rows)
        length(matches) == 1 || continue
        row = only(matches)
        all(name -> begin
            value = tryparse(Float64, get(row, name, ""))
            !isnothing(value) && isfinite(value)
        end, required_numeric) || continue
        push!(result, String(variant) => row)
    end
    return result
end

function _support_plot_series(rows, k, thresholds, variants)
    result = Pair{String,Vector{Union{Missing,Float64}}}[]
    for variant in variants
        series = Union{Missing,Float64}[]
        for threshold in thresholds
            matching = filter(row -> get(row, "K", "") == string(k) &&
                get(row, "variant", "") == variant &&
                tryparse(Float64, get(row, "minsup_fraction", "")) == threshold, rows)
            seeds = Set(tryparse(Int, get(row, "seed", "")) for row in matching)
            values = [tryparse(Float64, get(row, "frequent_singletons", "")) for row in matching]
            complete = length(matching) == length(EXPECTED_SEEDS) && seeds == Set(EXPECTED_SEEDS) &&
                all(value -> !isnothing(value) && isfinite(value), values)
            push!(series, complete ? mean(Float64.(values)) : missing)
        end
        push!(result, String(variant) => series)
    end
    return result
end
