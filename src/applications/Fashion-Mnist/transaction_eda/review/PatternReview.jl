function _decode_item(variant,item,k)
    if variant=="S0"
        return "word_$item"
    elseif variant=="S1"
        region=(item-1)÷k+1; word=(item-1)%k+1
        return "region$(region)_word$(word)"
    elseif variant=="S3"
        stripe=(item-1)÷k+1; word=(item-1)%k+1
        label=("TOP","MIDDLE","BOTTOM")[stripe]
        return "$(label)_word$(word)"
    elseif variant=="S6-B"
        zero_based=item-1
        relation=zero_based÷k^2+1
        pair=zero_based%k^2
        word_a,word_b=pair÷k+1,pair%k+1
        label=relation==1 ? "ABOVE" : relation==2 ? "LEFT_OF" : "INVALID_RELATION"
        return "$(label)_word$(word_a)_word$(word_b)"
    else
        throw(ArgumentError("Unsupported EDA2 variant: $variant"))
    end
end

function prepare_pattern_review!(ctx::EDA2Context)
    deep_path=output_path(ctx,"pilot_eclat","pilot_deep_runs.csv")
    isfile(deep_path) || error("Run C3 before preparing pattern review")
    _,deep_rows=_read_csv(deep_path)
    selected=_read_decisions(ctx)
    selection_rows,interpretation_rows=Vector{Vector{Any}}(),Vector{Vector{Any}}()
    for (k,seed) in selected, variant in VARIANTS
        database_id="B0_K$(k)_seed$(seed)_$(variant)"
        run=first(filter(r->r["database_id"]==database_id && parse(Float64,r["minsup_fraction"])==0.03,deep_rows))
        run["completion_status"]=="COMPLETED_LENGTH_CAPPED" || continue
        isempty(run["output_ref"]) && continue
        itemset_path=output_path(ctx,split(run["output_ref"],'/')...)
        _,item_rows=_read_csv(itemset_path)
        by_length=Dict{Int,Vector{Tuple{Vector{Int},Int}}}()
        for row in item_rows
            items=parse.(Int,split(row["itemset"],' ')); support=parse(Int,row["support_count"])
            push!(get!(by_length,length(items),Tuple{Vector{Int},Int}[]),(items,support))
        end
        representatives=Vector{Tuple{String,Vector{Int},Int}}()
        for length_value in sort!(collect(keys(by_length)))
            candidates=sort!(by_length[length_value];by=x->(x[2],x[1]))
            for (band,q) in (("LOW",0.25),("MID",0.50),("HIGH",0.75))
                index=clamp(round(Int,q*(length(candidates)-1))+1,1,length(candidates))
                itemset,support=candidates[index]
                any(x->x[2]==itemset,representatives) || push!(representatives,(band,itemset,support))
            end
        end
        spec=first(filter(s->s.database_id==database_id,ctx.specs))
        example_tids=[Int[] for _ in representatives]
        txpath=joinpath(spec.run_dir,"transactions.jsonl")
        open(txpath,"r") do io
            for (tid,line) in enumerate(eachline(io))
                _,_,tx=_parse_transaction(line,txpath,tid)
                for (i,(_,itemset,_)) in enumerate(representatives)
                    length(example_tids[i])>=5 && continue
                    all(item->item in tx,itemset) && push!(example_tids[i],tid)
                end
                all(t->length(t)>=5,example_tids) && break
            end
        end
        for (i,(band,itemset,support)) in enumerate(representatives)
            pattern_id="$(database_id)_m003_l$(length(itemset))_$(band)"
            decoded=join([_decode_item(variant,item,k) for item in itemset],";")
            tids=join(example_tids[i],";")
            push!(selection_rows,[pattern_id,database_id,k,seed,variant,0.03,join(itemset," "),length(itemset),support,support/EXPECTED_IMAGES,band,
                "nearest p25/p50/p75 support quantile per itemset length"])
            push!(interpretation_rows,[pattern_id,database_id,k,seed,variant,join(itemset," "),decoded,support,support/EXPECTED_IMAGES,tids,"",
                "true",
                "pending","pending","pending","pending"])
        end
    end
    _write_csv(output_path(ctx,"interpretability","pattern_selection_manifest.csv"),
        ["pattern_id","database_id","K","seed","variant","minsup_fraction","itemset","length","support_count","support_fraction","support_band","selection_rule"],selection_rows)
    _write_csv(output_path(ctx,"interpretability","pattern_interpretability.csv"),
        ["pattern_id","database_id","K","seed","variant","itemset","decoded_items","support_count","support_fraction","example_tids","patch_coordinates","decodable","visual_coherence","nontriviality","redundancy","annotator_notes"],interpretation_rows)
    _record_phase!(ctx,"interpretability_review","PENDING_HUMAN_ANNOTATION",Dict("patterns"=>length(selection_rows)))
    return (patterns=length(selection_rows),)
end
