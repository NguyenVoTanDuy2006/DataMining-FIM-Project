function run_deep_pilot!(ctx::EDA2Context)
    selected=_read_decisions(ctx)
    isempty(selected) && error("No codebooks are selected. Review shortlist_decision.csv, set selected=true and document the reason.")
    minsups=Float64.(get(get(ctx.config,"pilot",Dict{String,Any}()),"minsup_fractions",[0.01,0.03,0.05,0.10]))
    max_len=Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"deep_max_itemset_length",4))
    timeout=Float64(get(get(ctx.config,"resources",Dict{String,Any}()),"deep_timeout_seconds",1800))
    max_sets=Int(get(get(ctx.config,"resources",Dict{String,Any}()),"max_itemsets_per_run",2_000_000))
    run_rows, count_rows, performance_rows=Vector{Vector{Any}}(),Vector{Vector{Any}}(),Vector{Vector{Any}}()
    run_header=["database_id","source_sha256","config_sha256","K","seed","variant","minsup_fraction","minsup_count","max_length","completion_status","warmup_status","warmup_runtime_s","runtime_median_s","runtime_max_s","peak_rss_bytes","output_ref","output_sha256","closed_maximal_status","repetitions","engine_source_sha256","adapter_source_sha256"]
    count_header=["database_id","K","seed","variant","minsup_fraction","minsup_count","itemset_count","status"]
    perf_header=["database_id","K","seed","variant","minsup_fraction","run_kind","repetition","status","runtime_s","peak_rss_bytes","memory_cap_enforced"]
    run_out=output_path(ctx,"pilot_eclat","pilot_deep_runs.csv")
    count_out=output_path(ctx,"pilot_eclat","pilot_itemset_counts.csv")
    perf_out=output_path(ctx,"pilot_eclat","performance_repetitions.csv")
    old_runs,old_counts,old_perf=Dict{Tuple{String,Float64},Dict{String,String}}(),Dict{Tuple{String,Float64},Vector{Dict{String,String}}}(),Dict{Tuple{String,Float64},Vector{Dict{String,String}}}()
    if isfile(run_out)
        _,previous=_read_csv(run_out)
        for row in previous; old_runs[(row["database_id"],parse(Float64,row["minsup_fraction"]))]=row; end
    end
    if isfile(count_out)
        _,previous=_read_csv(count_out)
        for row in previous; push!(get!(old_counts,(row["database_id"],parse(Float64,row["minsup_fraction"])),Dict{String,String}[]),row); end
    end
    if isfile(perf_out)
        _,previous=_read_csv(perf_out)
        for row in previous; push!(get!(old_perf,(row["database_id"],parse(Float64,row["minsup_fraction"])),Dict{String,String}[]),row); end
    end
    resume=Bool(get(get(ctx.config,"run",Dict{String,Any}()),"resume",true))
    config_hash=_sha256(ctx.config_path)
    engine_hash=_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl"))
    adapter_hash=source_sha256()
    for (k,seed) in selected, variant in VARIANTS, minsup in minsups
        println("C3 Eclat: K=$k seed=$seed variant=$variant minsup=$minsup")
        flush(stdout)
        spec=first(filter(s->s.k==k && s.seed==seed && s.variant==variant,ctx.specs))
        txpath=joinpath(spec.run_dir,"transactions.jsonl")
        source_hash=_input_transaction_hash(txpath)
        count=ceil(Int,minsup*EXPECTED_IMAGES)
        key=(spec.database_id,minsup)
        if resume && haskey(old_runs,key)
            old=old_runs[key]
            output_file=isempty(old["output_ref"]) ? "" : output_path(ctx,split(old["output_ref"],'/')...)
            if old["source_sha256"]==source_hash && old["config_sha256"]==config_hash && old["engine_source_sha256"]==engine_hash && old["adapter_source_sha256"]==adapter_hash && old["completion_status"]=="COMPLETED_LENGTH_CAPPED" &&
                isfile(output_file) && _sha256(output_file)==old["output_sha256"]
                push!(run_rows,[old[h] for h in run_header])
                for row in get(old_counts,key,Dict{String,String}[]); push!(count_rows,[row[h] for h in count_header]); end
                for row in get(old_perf,key,Dict{String,String}[]); push!(performance_rows,[row[h] for h in perf_header]); end
                _write_csv(run_out,run_header,run_rows)
                _write_csv(count_out,count_header,count_rows)
                _write_csv(perf_out,perf_header,performance_rows)
                continue
            end
        end
        _,warmup_status,warmup_runtime=_mine_lengths(txpath,count,max_len,timeout,max_sets)
        push!(performance_rows,[spec.database_id,k,seed,variant,minsup,"warmup",0,warmup_status,warmup_runtime,"",false])
        if warmup_status!="COMPLETED_LENGTH_CAPPED"
            push!(run_rows,[spec.database_id,source_hash,config_hash,k,seed,variant,minsup,count,max_len,"SKIPPED_WARMUP",warmup_status,warmup_runtime,"","","","","",
                "NOT_EXACT",0,engine_hash,adapter_hash])
            _write_csv(run_out,run_header,run_rows); _write_csv(count_out,count_header,count_rows); _write_csv(perf_out,perf_header,performance_rows)
            continue
        end
        repetitions=Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"deep_repetitions",3))
        outputs=Dict{Tuple{Vararg{Int}},Int}[]; statuses=String[]; runtimes=Float64[]
        for rep in 1:repetitions
            sets,status,elapsed=_mine_lengths(txpath,count,max_len,timeout,max_sets)
            push!(statuses,status); push!(runtimes,elapsed)
            push!(performance_rows,[spec.database_id,k,seed,variant,minsup,"measured",rep,status,elapsed,"",false])
            !isnothing(sets) && push!(outputs,sets)
            status in ("TIMEOUT","ITEMSET_LIMIT","FAILED") && break
        end
        status=all(==("COMPLETED_LENGTH_CAPPED"),statuses) ? "COMPLETED_LENGTH_CAPPED" : last(statuses)
        exact=length(outputs)==repetitions && all(==(first(outputs)),outputs)
        outref=""
        if exact
            outref=joinpath("pilot_eclat","itemsets","$(spec.database_id)","minsup_$(replace(string(minsup),"."=>"p")).csv")
            rows=[[join(key," "),length(key),support] for (key,support) in sort!(collect(first(outputs));by=x->(length(first(x)),first(x)))]
            _write_csv(output_path(ctx,split(outref,'/')...),["itemset","length","support_count"],rows)
            counts=Dict{Int,Int}(); for key in keys(first(outputs)); counts[length(key)]=get(counts,length(key),0)+1; end
            for len in 1:max_len; push!(count_rows,[spec.database_id,k,seed,variant,minsup,count,get(counts,len,0),status]); end
        end
        output_hash=isempty(outref) ? "" : _sha256(output_path(ctx,split(outref,'/')...))
        push!(run_rows,[spec.database_id,source_hash,config_hash,k,seed,variant,minsup,count,max_len,status,warmup_status,warmup_runtime,median(runtimes),maximum(runtimes),"",outref,output_hash,
            "NOT_EXACT",repetitions,engine_hash,adapter_hash])
        _write_csv(run_out,run_header,run_rows); _write_csv(count_out,count_header,count_rows); _write_csv(perf_out,perf_header,performance_rows)
    end
    _write_csv(output_path(ctx,"pilot_eclat","performance_summary.csv"),
        run_header,run_rows)
    completed_runs=count(r->r[10]=="COMPLETED_LENGTH_CAPPED",run_rows)
    open(output_path(ctx,"pilot_eclat","pilot_deep_validation_report.toml"),"w") do io
        TOML.print(io,Dict("expected_runs"=>length(selected)*length(VARIANTS)*length(minsups),"rows_written"=>length(run_rows),
            "completed_length_capped_runs"=>completed_runs,"selected_codebooks"=>length(selected),"variants_per_codebook"=>length(VARIANTS),
            "minsup_fractions"=>minsups,"max_itemset_length"=>max_len,"repetitions_configured"=>Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"deep_repetitions",3)),
            "memory_cap_enforced"=>false,"peak_rss_measured"=>false,"closed_maximal_status"=>"NOT_EXACT",
            "config_sha256"=>config_hash,"engine_source_sha256"=>engine_hash,"adapter_source_sha256"=>adapter_hash))
    end
    _record_phase!(ctx,"pilot_c3",completed_runs==length(run_rows) ? "COMPLETED_LENGTH_CAPPED" : "COMPLETED_WITH_CENSORING",
        Dict("runs"=>length(run_rows),"completed_length_capped"=>completed_runs,"selected_codebooks"=>length(selected)))
    return (runs=length(run_rows),selected=length(selected))
end
