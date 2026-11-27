function common_pilot_scope_status(rows, expected_ids)
    expected = Set(String(id) for id in expected_ids)
    isempty(rows) && return "FAILED"
    observed = Set(String(get(row, "database_id", "")) for row in rows)
    length(rows) == length(expected) && observed == expected && length(observed) == length(expected) ||
        return "PARTIAL"
    successful = Set(String(row["database_id"]) for row in rows
        if get(row, "status", "") == "COMPLETED_LENGTH_CAPPED" &&
            lowercase(strip(get(row, "censored", ""))) == "false")
    return successful == expected ? "COMPLETED" : "PARTIAL"
end

function run_common_pilot!(ctx::EDA2Context)
    manifest=output_path(ctx,"input_manifest.csv")
    isfile(manifest) || error("Run the structural phase first; input_manifest.csv is missing")
    rows=Vector{Vector{Any}}()
    outpath=output_path(ctx,"pilot_eclat","pilot_common_60.csv")
    support_headers=["frequent_1_support_min","frequent_1_support_p5","frequent_1_support_median","frequent_1_support_p95","frequent_1_support_max",
        "frequent_2_support_min","frequent_2_support_p5","frequent_2_support_median","frequent_2_support_p95","frequent_2_support_max"]
    checkpoint_header=["database_id","K","seed","variant","engine_name","engine_version","source_sha256","config_sha256","engine_source_sha256","adapter_source_sha256","minsup_fraction","minsup_count","max_length","completed_length","frequent_1_count","frequent_2_count",
        support_headers...,"runtime_s","peak_rss_bytes","status","censored","resumed","limit_reason"]
    prior=Dict{String,Dict{String,String}}()
    if isfile(outpath)
        _,old_rows=_read_csv(outpath)
        prior=Dict(r["database_id"]=>r for r in old_rows)
    end
    minsup=Float64(get(get(ctx.config,"pilot",Dict{String,Any}()),"common_minsup_fraction",0.03))
    expected_runs=ctx.scope == "S0_ONLY" ? EXPECTED_CODEBOOKS : EXPECTED_DATABASES
    max_len=Int(get(get(ctx.config,"pilot",Dict{String,Any}()),"common_max_itemset_length",2))
    timeout=Float64(get(get(ctx.config,"resources",Dict{String,Any}()),"per_database_timeout_seconds",600))
    max_pairs=Int(get(get(ctx.config,"resources",Dict{String,Any}()),"max_pair_candidates",20_000_000))
    config_hash=_sha256(ctx.config_path)
    engine_hash=_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl"))
    adapter_hash=source_sha256()
    _,manifest_rows=_read_csv(manifest)
    for (row_index,row) in enumerate(manifest_rows)
        dbid=row["database_id"]; path=_absolute(ctx.repo_root,row["transactions_path"])
        println("C1 Eclat $(row_index)/$(length(manifest_rows)): $dbid")
        flush(stdout)
        actual_source_hash=isfile(path) ? _sha256(path) : ""
        if actual_source_hash!=row["source_sha256"]
            blocked_row=[dbid,row["K"],row["seed"],row["variant"],"EclatFIM.mine(:set)","max-length-v1",row["source_sha256"],config_hash,
                engine_hash,adapter_hash,minsup,ceil(Int,minsup*EXPECTED_IMAGES),max_len,"","",""]
            append!(blocked_row,fill("",length(support_headers)))
            append!(blocked_row,["","","SKIPPED_BLOCKED",true,false,"transaction source missing or changed after structural validation"])
            push!(rows,blocked_row)
            _write_csv(outpath,checkpoint_header,rows)
            continue
        end
        if row["status"]=="PASS" && Bool(get(get(ctx.config,"run",Dict{String,Any}()),"resume",true)) && haskey(prior,dbid)
            old=prior[dbid]
            if old["status"]=="COMPLETED_LENGTH_CAPPED" && old["source_sha256"]==row["source_sha256"] &&
                old["config_sha256"]==config_hash && old["engine_source_sha256"]==engine_hash && old["adapter_source_sha256"]==adapter_hash && parse(Float64,old["minsup_fraction"])==minsup &&
                parse(Int,old["minsup_count"])==ceil(Int,minsup*EXPECTED_IMAGES) && parse(Int,old["max_length"])==max_len
                resumed_row=[dbid,row["K"],row["seed"],row["variant"],old["engine_name"],old["engine_version"],old["source_sha256"],old["config_sha256"],
                    old["engine_source_sha256"],old["adapter_source_sha256"],old["minsup_fraction"],old["minsup_count"],old["max_length"],old["completed_length"],old["frequent_1_count"],old["frequent_2_count"]]
                append!(resumed_row,[old[h] for h in support_headers])
                append!(resumed_row,[old["runtime_s"],old["peak_rss_bytes"],old["status"],old["censored"],true,"reused matching completed checkpoint"])
                push!(rows,resumed_row)
                _write_csv(outpath,checkpoint_header,rows)
                continue
            end
        end
        if row["status"]!="PASS"
            blocked_row=[dbid,row["K"],row["seed"],row["variant"],"EclatFIM.mine(:set)","max-length-v1",row["source_sha256"],config_hash,engine_hash,adapter_hash,
                minsup,ceil(Int,minsup*EXPECTED_IMAGES),max_len,"","",""]
            append!(blocked_row,fill("",length(support_headers)))
            append!(blocked_row,["","","SKIPPED_BLOCKED",true,false,row["issue"]])
            push!(rows,blocked_row)
            _write_csv(outpath,checkpoint_header,rows)
            continue
        end
        result=try _bounded_eclat(path,ceil(Int,minsup*EXPECTED_IMAGES),max_len,timeout,max_pairs)
        catch err; (status="FAILED",count1="",count2="",singleton_support=fill("",5),pair_support=fill("",5),elapsed=0.0,active=0,reason=sprint(showerror,err)); end
        censored=result.status in ("TIMEOUT","MEMORY_LIMIT","ITEMSET_LIMIT","FAILED")
        result_row=[dbid,row["K"],row["seed"],row["variant"],"EclatFIM.mine(:set)","max-length-v1",row["source_sha256"],config_hash,engine_hash,adapter_hash,
            minsup,ceil(Int,minsup*EXPECTED_IMAGES),max_len,censored ? "" : max_len,censored ? "" : result.count1,censored ? "" : result.count2]
        append!(result_row,censored ? fill("",length(support_headers)) : vcat(result.singleton_support,result.pair_support))
        append!(result_row,[result.elapsed,"",result.status,censored,false,result.reason])
        push!(rows,result_row)
        _write_csv(outpath,checkpoint_header,rows)
        GC.gc(false)
    end
    open(output_path(ctx,"pilot_eclat","pilot_validation_report.toml"),"w") do io
        TOML.print(io,Dict("scope"=>ctx.scope,"expected_runs"=>expected_runs,"completed_or_censored_rows"=>length(rows),
            "engine_name"=>"EclatFIM.mine(:set)","engine_version"=>"max-length-v1","max_length"=>max_len,
            "minsup_fraction"=>minsup,"minsup_count"=>ceil(Int,minsup*EXPECTED_IMAGES),
            "timeout_seconds_per_database"=>timeout,"max_pair_candidates"=>max_pairs,
            "memory_cap_bytes_configured"=>get(get(ctx.config,"resources",Dict{String,Any}()),"memory_cap_bytes",0),
            "memory_cap_enforced"=>false,"peak_rss_measured"=>false,
            "eda2_module_sha256"=>source_sha256(),
            "eclat_baseline_sha256"=>_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl"))))
    end
    completed=count(r->lowercase(string(r[30]))=="false" && r[29]=="COMPLETED_LENGTH_CAPPED",rows)
    _record_phase!(ctx,"pilot_c1",length(rows)==expected_runs ? (completed==expected_runs ? "COMPLETED" : "COMPLETED_WITH_CENSORING") : "PARTIAL",
        Dict("scope"=>ctx.scope,"expected_runs"=>expected_runs,"rows"=>length(rows),
            "completed"=>completed,"censored_or_blocked"=>length(rows)-completed))
    return (rows=length(rows),completed=completed,output=outpath)
end
