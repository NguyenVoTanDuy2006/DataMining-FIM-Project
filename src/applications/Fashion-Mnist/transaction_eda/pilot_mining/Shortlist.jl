function prepare_shortlist!(ctx::EDA2Context)
    source=output_path(ctx,"pilot_eclat","pilot_common_45.csv")
    isfile(source) || error("Run the common C1 pilot first")
    _,pilot_rows=_read_csv(source)
    length(pilot_rows)==EXPECTED_DATABASES && length(unique([r["database_id"] for r in pilot_rows]))==EXPECTED_DATABASES ||
        error("C1 must contain one explicit status row for each of $EXPECTED_DATABASES databases before C2")
    _,manifest_rows=_read_csv(output_path(ctx,"input_manifest.csv"))
    _,codebook_rows=_read_csv(output_path(ctx,"codebook","codebook_metrics_15.csv"))
    _,transaction_rows=_read_csv(output_path(ctx,"transactions","transaction_metrics_45.csv"))
    _,diversity_rows=_read_csv(output_path(ctx,"transactions","transaction_diversity_45.csv"))
    prior_path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    prior=Dict{Tuple{Int,Int},Dict{String,String}}()
    if isfile(prior_path)
        _,prior_rows=_read_csv(prior_path)
        for row in prior_rows
            prior[(parse(Int,row["K"]),parse(Int,row["seed"]))]=row
        end
    end
    validation=Dict(r["database_id"]=>r["status"] for r in manifest_rows)
    c1_status=Dict(r["database_id"]=>r["status"] for r in pilot_rows)
    out=Vector{Vector{Any}}()
    for k in EXPECTED_K, seed in EXPECTED_SEEDS
        dbs=[r for r in pilot_rows if parse(Int,r["K"])==k && parse(Int,r["seed"])==seed]
        statuses=join(sort!(unique(getindex.(dbs,"status"))),"|")
        invalid=any(get(validation,"B0_K$(k)_seed$(seed)_$(variant)","NOT_RUN")!="PASS" ||
            get(c1_status,"B0_K$(k)_seed$(seed)_$(variant)","NOT_RUN")=="SKIPPED_BLOCKED" for variant in VARIANTS)
        previous=get(prior,(k,seed),Dict{String,String}())
        selected=!invalid && lowercase(get(previous,"selected","false"))=="true"
        reason=invalid ? "INVALID_INPUT_BLOCKED" : selected ? get(previous,"decision_reason","REVIEW_REQUIRED") : "REVIEW_REQUIRED"
        codebook=first(filter(r->parse(Int,r["K"])==k && parse(Int,r["seed"])==seed,codebook_rows))
        evidence=String["distortion=$(codebook["distortion"])";"convergence=$(codebook["convergence_status"])";
            "saved_ari=$(codebook["seed_stability_ari_mean_saved"])";"c1_status=$(statuses)"]
        for variant in VARIANTS
            database_id="B0_K$(k)_seed$(seed)_$(variant)"
            pilot=first(filter(r->r["database_id"]==database_id,pilot_rows))
            transaction=first(filter(r->r["database_id"]==database_id,transaction_rows))
            diversity=first(filter(r->r["database_id"]==database_id,diversity_rows))
            append!(evidence,["$(variant)_C1_f1=$(pilot["frequent_1_count"])_f2=$(pilot["frequent_2_count"])_runtime_s=$(pilot["runtime_s"])";
                "$(variant)_length_mean=$(transaction["mean_length"])_p5=$(transaction["p5_length"])_p95=$(transaction["p95_length"])";
                "$(variant)_unique_ratio=$(diversity["unique_ratio"])_jaccard=$(diversity["jaccard_mean"])" ])
        end
        push!(out,[k,seed,_canonical_run(k,seed),selected,reason,statuses,join(evidence,";"),string(invalid),"eda2-v1.1"])
    end
    path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    _write_csv(path,["K","seed","codebook_id","selected","decision_reason","pilot_statuses","metrics_used","rejected_for_invalidity","selection_protocol_version","label_informed_selection"],
        [[r... ,"false"] for r in out])
    _record_phase!(ctx,"pilot_c2","AWAITING_HUMAN_REVIEW",Dict("decision_rows"=>length(out),"selected"=>0))
    return path
end

function _read_decisions(ctx)
    path=output_path(ctx,"pilot_eclat","shortlist_decision.csv")
    _,rows=_read_csv(path)
    length(rows)==EXPECTED_CODEBOOKS && length(unique([(parse(Int,r["K"]),parse(Int,r["seed"])) for r in rows]))==EXPECTED_CODEBOOKS ||
        error("Shortlist must contain one decision row for each of the 15 codebooks")
    selected=[(parse(Int,r["K"]),parse(Int,r["seed"])) for r in rows if lowercase(r["selected"])=="true"]
    all(!isempty(r["decision_reason"]) && r["decision_reason"]!="REVIEW_REQUIRED" for r in rows if lowercase(r["selected"])=="true") ||
        error("Every selected (K,seed) needs a written decision_reason")
    manifest_path=output_path(ctx,"input_manifest.csv")
    c1_path=output_path(ctx,"pilot_eclat","pilot_common_45.csv")
    isfile(manifest_path) && isfile(c1_path) || error("Structural analysis and the common C1 pilot must finish before selecting codebooks")
    _,manifest=_read_csv(manifest_path); _,c1=_read_csv(c1_path)
    manifest_by_id=Dict(r["database_id"]=>r for r in manifest)
    c1_by_id=Dict(r["database_id"]=>r for r in c1)
    for (k,seed) in selected,variant in VARIANTS
        database_id="B0_K$(k)_seed$(seed)_$(variant)"
        haskey(manifest_by_id,database_id) && manifest_by_id[database_id]["status"]=="PASS" ||
            error("Cannot select invalid or blocked database: $database_id")
        haskey(c1_by_id,database_id) || error("Selected codebook is missing the common C1 status for $database_id")
        c1_by_id[database_id]["status"]!="SKIPPED_BLOCKED" || error("C1 marked selected database blocked: $database_id")
        txpath=_absolute(ctx.repo_root,manifest_by_id[database_id]["transactions_path"])
        _sha256(txpath)==manifest_by_id[database_id]["source_sha256"] || error("Selected transaction source changed after structural validation: $database_id")
    end
    return selected
end
