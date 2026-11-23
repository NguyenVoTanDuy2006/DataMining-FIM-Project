function run_analysis_a!(ctx::EDA2Context)
    isempty(ctx.specs) && discover_inputs(ctx)
    _record_phase!(ctx,"analysis_a_b","RUNNING",Dict("expected_codebooks"=>EXPECTED_CODEBOOKS,"expected_databases"=>EXPECTED_DATABASES))
    mkpath(ctx.output_root)
    cp(ctx.config_path, output_path(ctx,"config_snapshot.toml"); force=true)
    _read_labels!(ctx)
    pair_manifest, class_manifest, class_manifest_hash = _make_pair_manifests!(ctx)
    jaccard_manifest_hash=_sha256(output_path(ctx,"transactions","jaccard_pair_manifest.csv"))
    codebook_rows = _codebook_analysis!(ctx)
    transaction_rows, support_summary, threshold_rows = Vector{Vector{Any}}(), Vector{Vector{Any}}(), Vector{Vector{Any}}()
    diversity_rows = Vector{Vector{Any}}()
    length_histogram=Vector{Vector{Any}}()
    paired_encoding=Vector{Vector{Any}}()
    class_summary, classwise, classpairs = Vector{Vector{Any}}(), Vector{Vector{Any}}(), Vector{Vector{Any}}()
    region_support, spatial_invariants = Vector{Vector{Any}}(), Vector{Vector{Any}}()
    validation = Vector{Vector{Any}}()
    _write_input_manifest(ctx,validation)
    _write_csv(output_path(ctx,"validation_report.csv"),["database_id","status","issue","record_count","empty_count"],validation)
    for k in EXPECTED_K, seed in EXPECTED_SEEDS
        specs = [s for s in ctx.specs if s.k==k && s.seed==seed]
        s0 = first(filter(s -> s.variant=="S0",specs))
        canonical_images = Int[]
        try
            println("EDA2 A/B: loading S0 for K=$k seed=$seed")
            flush(stdout)
            _metadata!(s0)
            s0tx, canonical_images = _read_s0_transactions(s0)
            for spec in sort(specs; by=s -> findfirst(==(s.variant),VARIANTS))
                try
                    println("  analyzing $(spec.database_id)")
                    flush(stdout)
                    txs = spec.variant=="S0" ? s0tx : _read_transactions(spec,canonical_images; compare_s0=s0tx)
                    if spec.variant!="S0"
                        length_delta=[length(txs[i])-length(s0tx[i]) for i in eachindex(s0tx)]
                        empty_mismatch=count(i->isempty(txs[i])!=isempty(s0tx[i]),eachindex(s0tx))
                        push!(paired_encoding,[spec.database_id,k,seed,spec.variant,EXPECTED_IMAGES,
                            mean(length_delta),median(length_delta),quantile(length_delta,0.05),
                            quantile(length_delta,0.95),empty_mismatch,empty_mismatch/EXPECTED_IMAGES])
                    end
                    metrics,supports,thresholds,within_rows,between_rows = _transaction_metrics(spec,txs,pair_manifest,class_manifest,ctx)
                    region_rows,invariant_row=_spatial_descriptive_rows(spec,txs)
                    append!(region_support,region_rows); push!(spatial_invariants,invariant_row)
                    append!(length_histogram,_length_histogram_rows(spec,txs))
                    push!(transaction_rows,[metrics[k] for k in ["database_id","K","seed","variant","N","empty_count","nonempty_count","empty_rate","length1_count","length1_fraction","min_length","mean_length","median_length","std_length","p5_length","p25_length","p75_length","p95_length","p99_length","max_length","length_capacity","length_capacity_ratio","observed_universe","theoretical_universe","density_theoretical","density_observed","unique_transaction_count","unique_ratio","duplicate_ratio","integrity_status"]])
                    append!(support_summary,thresholds); append!(threshold_rows,thresholds)
                    append!(classwise,within_rows); append!(classpairs,between_rows)
                    push!(diversity_rows,[spec.database_id,k,seed,spec.variant,EXPECTED_IMAGES,metrics["empty_count"],
                        metrics["unique_transaction_count"],metrics["unique_ratio"],metrics["duplicate_ratio"],metrics["jaccard_pair_count"],
                        metrics["jaccard_mean"],metrics["jaccard_median"],metrics["jaccard_p5"],metrics["jaccard_p95"],
                        metrics["jaccard_both_empty_pairs"],metrics["jaccard_one_empty_pairs"],jaccard_manifest_hash])
                    push!(class_summary,[spec.database_id,k,seed,spec.variant,EXPECTED_IMAGES,
                        metrics["within_mean_jaccard"],metrics["within_median_jaccard"],metrics["within_p5_jaccard"],metrics["within_p25_jaccard"],metrics["within_p75_jaccard"],metrics["within_p95_jaccard"],
                        metrics["between_mean_jaccard"],metrics["between_median_jaccard"],metrics["between_p5_jaccard"],metrics["between_p25_jaccard"],metrics["between_p75_jaccard"],metrics["between_p95_jaccard"],
                        metrics["separation_gap"],metrics["pair_discrimination_auc"],
                        metrics["within_valid_pairs"],metrics["between_valid_pairs"],metrics["within_both_empty_pairs"],metrics["between_both_empty_pairs"],
                        metrics["within_one_empty_pairs"],metrics["between_one_empty_pairs"],2026,class_manifest_hash])
                    _record_validation!(ctx,validation,[spec.database_id,"PASS","",EXPECTED_IMAGES,metrics["empty_count"]])
                    GC.gc(false)
                catch err
                    _record_validation!(ctx,validation,[spec.database_id,"BLOCKED",sprint(showerror,err),0,""])
                    get(get(ctx.config,"run",Dict{String,Any}()),"fail_fast_on_invalid_input",false) && rethrow()
                end
            end
        catch err
            for spec in specs
                any(r -> r[1]==spec.database_id, validation) || _record_validation!(ctx,validation,[spec.database_id,"BLOCKED",sprint(showerror,err),0,""])
            end
            get(get(ctx.config,"run",Dict{String,Any}()),"fail_fast_on_invalid_input",false) && rethrow()
        end
    end
    _write_input_manifest(ctx,validation)
    _write_csv(output_path(ctx,"transactions","transaction_metrics_45.csv"),
        ["database_id","K","seed","variant","N","empty_count","nonempty_count","empty_rate","length1_count","length1_fraction","min_length","mean_length","median_length","std_length","p5_length","p25_length","p75_length","p95_length","p99_length","max_length","length_capacity","length_capacity_ratio","observed_universe","theoretical_universe","density_theoretical","density_observed","unique_transaction_count","unique_ratio","duplicate_ratio","integrity_status"],transaction_rows)
    _write_csv(output_path(ctx,"transactions","paired_encoding_comparison.csv"),
        ["database_id","K","seed","variant","paired_tids","length_delta_mean_vs_s0","length_delta_median_vs_s0","length_delta_p5_vs_s0","length_delta_p95_vs_s0","empty_status_mismatches","empty_status_mismatch_fraction"],paired_encoding)
    _write_csv(output_path(ctx,"transactions","transaction_length_histogram_45.csv"),
        ["database_id","K","seed","variant","length_bin","transaction_count","fraction"],length_histogram)
    _write_csv(output_path(ctx,"transactions","item_support_summary_45.csv"),
        ["database_id","K","seed","variant","minsup_fraction","minsup_count","frequent_singletons","observed_items","theoretical_items","observed_item_fraction","theoretical_item_fraction","item_support_min","item_support_median","item_support_mean","item_support_p5","item_support_p95","item_support_max","rare_item_count","ubiquitous_item_count"],support_summary)
    _write_csv(output_path(ctx,"transactions","singleton_threshold_counts.csv"),
        ["database_id","K","seed","variant","minsup_fraction","minsup_count","frequent_singletons","observed_items","theoretical_items","observed_item_fraction","theoretical_item_fraction","item_support_min","item_support_median","item_support_mean","item_support_p5","item_support_p95","item_support_max","rare_item_count","ubiquitous_item_count"],threshold_rows)
    _write_csv(output_path(ctx,"transactions","transaction_diversity_45.csv"),
        ["database_id","K","seed","variant","N","empty_count","unique_transaction_count","unique_ratio","duplicate_ratio","jaccard_pair_count","jaccard_mean","jaccard_median","jaccard_p5","jaccard_p95","jaccard_both_empty_pairs","jaccard_one_empty_pairs","pair_manifest_sha256"],
        diversity_rows)
    _write_csv(output_path(ctx,"transactions","class_similarity_summary_45.csv"),
        ["database_id","K","seed","variant","N_labeled","within_mean_jaccard","within_median_jaccard","within_p5_jaccard","within_p25_jaccard","within_p75_jaccard","within_p95_jaccard","between_mean_jaccard","between_median_jaccard","between_p5_jaccard","between_p25_jaccard","between_p75_jaccard","between_p95_jaccard","separation_gap","pair_discrimination_auc","within_valid_pairs","between_valid_pairs","within_both_empty_pairs","between_both_empty_pairs","within_one_empty_pairs","between_one_empty_pairs","sampling_seed","pair_manifest_hash","status"],
        [[r...,"COMPUTED"] for r in class_summary])
    _write_csv(output_path(ctx,"transactions","classwise_similarity.csv"),
        ["database_id","K","seed","variant","class_id","valid_pairs","both_empty_pairs","one_empty_pairs","within_mean","within_median","within_p5","within_p25","within_p75","within_p95"],classwise)
    _write_csv(output_path(ctx,"transactions","class_pair_similarity.csv"),
        ["database_id","K","seed","variant","class_a","class_b","valid_pairs","both_empty_pairs","one_empty_pairs","between_mean","between_median","between_p5","between_p25","between_p75","between_p95"],classpairs)
    _write_csv(output_path(ctx,"transactions","region_support_summary.csv"),
        ["database_id","K","seed","variant","region_id","region_label","patch_slot_capacity","image_support_count","image_support_fraction"],region_support)
    _write_csv(output_path(ctx,"transactions","spatial_invariants_45.csv"),
        ["database_id","K","seed","variant","invariant_status"],spatial_invariants)
    issues=[r for r in validation if r[2]!="PASS"]
    _write_csv(output_path(ctx,"input_issues.csv"),["database_id","status","issue","run_path"],
        [[r[1],r[2],r[3],relpath(first(filter(s->s.database_id==r[1],ctx.specs)).run_dir,ctx.repo_root)] for r in issues])
    env = Dict("generated_unix_seconds"=>time(),"julia_version"=>string(VERSION),"database_count_expected"=>EXPECTED_DATABASES,
        "record_count_per_database"=>EXPECTED_IMAGES,"source_roots_read_only"=>true,"memory_cap_enforced"=>false,
        "machine"=>Sys.MACHINE,"kernel"=>string(Sys.KERNEL),"julia_threads"=>Threads.nthreads(),"total_memory_bytes"=>Sys.total_memory(),
        "codebook_count_validated"=>length(codebook_rows),"validated_database_count"=>count(r->r[2]=="PASS",validation),
        "config_sha256"=>_sha256(ctx.config_path),"project_sha256"=>_sha256(joinpath(ctx.repo_root,"Project.toml")),
        "manifest_sha256"=>isfile(joinpath(ctx.repo_root,"Manifest.toml")) ? _sha256(joinpath(ctx.repo_root,"Manifest.toml")) : "",
        "eda2_module_sha256"=>source_sha256(),
        "eclat_baseline_sha256"=>_sha256(joinpath(ctx.repo_root,"src","algorithm","EclatBaseline.jl")),
        "notebook_sha256"=>_sha256(joinpath(ctx.repo_root,"notebook","UD2","experiments","EDA2_FashionMNIST_Transaction_Evaluation.ipynb")))
    open(output_path(ctx,"environment.toml"),"w") do io; TOML.print(io,env); end
    open(output_path(ctx,"validation_report.toml"),"w") do io
        TOML.print(io,Dict("expected_codebooks"=>EXPECTED_CODEBOOKS,"validated_codebooks"=>length(codebook_rows),
            "expected_databases"=>EXPECTED_DATABASES,"validated_databases"=>count(r->r[2]=="PASS",validation),
            "blocked_databases"=>count(r->r[2]!="PASS",validation),
            "blocked_database_ids"=>[String(r[1]) for r in validation if r[2]!="PASS"],
            "status"=>all(r->r[2]=="PASS",validation) ? "PASS" : "PARTIAL"))
    end
    _record_phase!(ctx,"analysis_a_b",count(r->r[2]=="PASS",validation)==EXPECTED_DATABASES ? "COMPLETED" : "PARTIAL",
        Dict("expected_databases"=>EXPECTED_DATABASES,"validated_databases"=>count(r->r[2]=="PASS",validation),"codebooks"=>length(codebook_rows)))
    return (codebooks=length(codebook_rows), databases=length(validation), passed=count(r->r[2]=="PASS",validation),
        output_root=ctx.output_root)
end
