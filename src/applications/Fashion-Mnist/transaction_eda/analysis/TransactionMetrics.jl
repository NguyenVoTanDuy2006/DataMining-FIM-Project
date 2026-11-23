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
    capacity=min(universe,49)
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
    spec.variant == "S0" && return region_rows, [key..., "PASS"]
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

function _length_histogram_rows(spec,txs)
    bins=[("0",0,0),("1",1,1),("2",2,2),("3-5",3,5),("6-10",6,10),
        ("11-20",11,20),("21-40",21,40),("41-80",41,80),("81-160",81,160),("161+",161,typemax(Int))]
    lengths=length.(txs)
    return [[spec.database_id,spec.k,spec.seed,spec.variant,label,count(x->lo<=x<=hi,lengths),
        count(x->lo<=x<=hi,lengths)/length(lengths)] for (label,lo,hi) in bins]
end
