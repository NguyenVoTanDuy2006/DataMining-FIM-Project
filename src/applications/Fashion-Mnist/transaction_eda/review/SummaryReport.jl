function write_inconclusive_report!(ctx::EDA2Context)
    mkpath(output_path(ctx,"final"))
    metrics_path=output_path(ctx,"transactions","transaction_metrics_45.csv")
    diversity_path=output_path(ctx,"transactions","transaction_diversity_45.csv")
    similarity_path=output_path(ctx,"transactions","class_similarity_summary_45.csv")
    pilot_path=output_path(ctx,"pilot_eclat","pilot_common_45.csv")
    deep_path=output_path(ctx,"pilot_eclat","pilot_deep_runs.csv")
    pattern_path=output_path(ctx,"interpretability","pattern_interpretability.csv")
    shortlist_path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    metric_rows=isfile(metrics_path) ? last(_read_csv(metrics_path)) : Dict{String,String}[]
    manifest_rows=isfile(output_path(ctx,"input_manifest.csv")) ? last(_read_csv(output_path(ctx,"input_manifest.csv"))) : Dict{String,String}[]
    diversity_rows=isfile(diversity_path) ? last(_read_csv(diversity_path)) : Dict{String,String}[]
    similarity_rows=isfile(similarity_path) ? last(_read_csv(similarity_path)) : Dict{String,String}[]
    pilot_rows=isfile(pilot_path) ? last(_read_csv(pilot_path)) : Dict{String,String}[]
    deep_rows=isfile(deep_path) ? last(_read_csv(deep_path)) : Dict{String,String}[]
    pattern_rows=isfile(pattern_path) ? last(_read_csv(pattern_path)) : Dict{String,String}[]
    shortlist_rows=isfile(shortlist_path) ? last(_read_csv(shortlist_path)) : Dict{String,String}[]
    metrics_by_db=Dict(r["database_id"]=>r for r in metric_rows)
    diversity=Dict(r["database_id"]=>r for r in diversity_rows)
    similarity=Dict(r["database_id"]=>r for r in similarity_rows)
    pilot=Dict(r["database_id"]=>r for r in pilot_rows)
    deep_by_db=Dict{String,Vector{Dict{String,String}}}(); for r in deep_rows; push!(get!(deep_by_db,r["database_id"],Dict{String,String}[]),r); end
    pattern_count=Dict{String,Int}(); for r in pattern_rows; pattern_count[r["database_id"]]=get(pattern_count,r["database_id"],0)+1; end
    selected_keys=Set("B0_K$(r["K"])_seed$(r["seed"])" for r in shortlist_rows if lowercase(r["selected"])=="true")
    shortlist_by_key=Dict("B0_K$(r["K"])_seed$(r["seed"])"=>r for r in shortlist_rows)
    comparison=Vector{Vector{Any}}()
    base_rows=isempty(manifest_rows) ? metric_rows : manifest_rows
    for base in base_rows
        dbid=base["database_id"]; m=get(metrics_by_db,dbid,Dict{String,String}())
        d=get(diversity,dbid,Dict{String,String}()); s=get(similarity,dbid,Dict{String,String}()); p=get(pilot,dbid,Dict{String,String}())
        deep=get(deep_by_db,dbid,Dict{String,String}[])
        deep_complete=isempty(deep) ? "" : count(r->r["completion_status"]=="COMPLETED_LENGTH_CAPPED",deep)
        deep_censored=isempty(deep) ? "" : count(r->r["completion_status"] in ("TIMEOUT","ITEMSET_LIMIT","FAILED","SKIPPED_WARMUP"),deep)
        deep_times=[parse(Float64,r["runtime_median_s"]) for r in deep if !isempty(r["runtime_median_s"])]
        k=get(m,"K",get(base,"K","")); seed=get(m,"seed",get(base,"seed","")); variant=get(m,"variant",get(base,"variant",""))
        shortlist_key="B0_K$(k)_seed$(seed)"
        decision=get(shortlist_by_key,shortlist_key,Dict{String,String}())
        source_status=get(base,"status",get(m,"integrity_status","NOT_RUN"))
        pattern_rows_value=isfile(pattern_path) ? get(pattern_count,dbid,0) : ""
        shortlist_selected=isfile(shortlist_path) ? shortlist_key in selected_keys : ""
        label_informed=isempty(decision) ? "" : get(decision,"label_informed_selection","false")
        closed_status=isempty(deep) ? "NOT_RUN" : "NOT_EXACT"
        interpretability_status=!isfile(pattern_path) ? "NOT_RUN" : get(pattern_count,dbid,0)>0 ? "PENDING_HUMAN_REVIEW" : "NO_COMPLETED_PATTERN_FAMILY"
        push!(comparison,[dbid,get(base,"run_path",""),get(base,"transactions_path",""),get(base,"source_sha256",""),
            k,seed,variant,source_status,get(m,"empty_rate",""),get(m,"mean_length",""),get(m,"density_theoretical",""),
            get(d,"jaccard_mean",""),get(s,"within_mean_jaccard",""),get(s,"between_mean_jaccard",""),get(s,"separation_gap",""),
            get(s,"pair_discrimination_auc",""),get(p,"status","NOT_RUN"),get(p,"frequent_1_count",""),get(p,"frequent_2_count",""),
            deep_complete,deep_censored,isempty(deep_times) ? "" : median(deep_times),pattern_rows_value,
            shortlist_selected,closed_status,interpretability_status,label_informed,"INCONCLUSIVE"])
    end
    _write_csv(output_path(ctx,"final","comparative_summary.csv"),
        ["database_id","run_path","transactions_path","source_sha256","K","seed","variant","integrity_status","empty_rate","mean_length","density_theoretical","jaccard_mean","within_mean_jaccard_posthoc","between_mean_jaccard_posthoc","class_similarity_gap_posthoc","class_similarity_auc_posthoc","c1_status","c1_frequent_1_count","c1_frequent_2_count","c3_completed_runs","c3_censored_runs","c3_median_runtime_s","interpretability_patterns","shortlist_selected","closed_maximal_status","interpretability_status","label_informed_selection","decision_status"],comparison)
    _write_csv(output_path(ctx,"final","tradeoff_candidates.csv"),
        ["database_id","run_path","transactions_path","source_sha256","K","seed","variant","integrity_status","empty_rate","mean_length","density_theoretical","jaccard_mean","within_mean_jaccard_posthoc","between_mean_jaccard_posthoc","class_similarity_gap_posthoc","class_similarity_auc_posthoc","c1_status","c1_frequent_1_count","c1_frequent_2_count","c3_completed_runs","c3_censored_runs","c3_median_runtime_s","interpretability_patterns","shortlist_selected","closed_maximal_status","interpretability_status","label_informed_selection","decision_status"],comparison)
    open(output_path(ctx,"final","final_selection.md"),"w") do io
        println(io,"# EDA2 final selection\n")
        println(io,"**Status: INCONCLUSIVE.** This status remains until the required EDA2 evidence and human review are complete.\n")
        println(io,"The notebook does not select a configuration from distortion, raw itemset count, or class-label similarity alone. Review `pilot_eclat/shortlist_decision.csv`, C3 results and interpretability evidence before recording a final choice.\n")
        println(io,"Source transaction databases and codebooks remain read-only.")
    end
    open(output_path(ctx,"final","EDA2_summary_report.md"),"w") do io
        println(io,"# EDA2 summary\n\nDecision status: **INCONCLUSIVE**.\n")
        println(io,"Generated from the checked input manifest and completed analysis phases. Missing, censored, or unreviewed phases are not interpreted as zero-quality results. See `validation_report.toml` and pilot status tables.")
    end
    _record_phase!(ctx,"final_decision","INCONCLUSIVE",Dict("comparative_rows"=>length(comparison),"automated_winner_selected"=>false))
    return output_path(ctx,"final","final_selection.md")
end
