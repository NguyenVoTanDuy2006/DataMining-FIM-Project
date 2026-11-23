_csv_escape(value) = begin
    s = string(value)
    (occursin(',', s) || occursin('"', s) || occursin('\n', s)) ? "\"$(replace(s, "\""=>"\"\""))\"" : s
end

function _write_csv(path, header, rows)
    mkpath(dirname(path))
    tmp = path * ".partial"
    open(tmp, "w") do io
        println(io, join(_csv_escape.(header), ','))
        for row in rows
            length(row) == length(header) || error("CSV row width mismatch for $path")
            println(io, join(_csv_escape.(row), ','))
        end
    end
    mv(tmp, path; force=true)
    open(path,"r") do io
        eof(io) && error("CSV read-back found an empty artifact: $path")
        _csv_fields(readline(io))==String.(header) || error("CSV schema read-back mismatch: $path")
    end
    return path
end

function _record_phase!(ctx,phase,status,details=Dict{String,Any}())
    path=output_path(ctx,"execution","run_summary.toml")
    summary=isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
    summary[phase]=merge(Dict{String,Any}("status"=>status,"updated_unix_seconds"=>time()),Dict{String,Any}(details))
    mkpath(dirname(path)); tmp=path*".partial"
    open(tmp,"w") do io; TOML.print(io,summary); end
    mv(tmp,path;force=true)
    return path
end

function _write_input_manifest(ctx, status_rows)
    header = ["database_id","method","K","seed","variant","source_root","run_path","transactions_path","codebook_path_or_ref","item_mapping_path_or_ref","tid_mapping_path","integrity_path","config_path","source_sha256","record_count","status","issue"]
    rows = Vector{Vector{Any}}()
    statuses = Dict(String(r[1]) => r for r in status_rows)
    for spec in ctx.specs
        source = spec.variant == "S0" ? spec.run_dir : spec.source_dir
        txpath = joinpath(spec.run_dir,"transactions.jsonl")
        sha = _input_transaction_hash(txpath)
        row = get(statuses,spec.database_id,nothing)
        status = isnothing(row) ? "NOT_RUN" : row[2]
        issue = isnothing(row) ? "" : row[3]
        push!(rows,[spec.database_id,"B0",spec.k,spec.seed,spec.variant,relpath(source,ctx.repo_root),relpath(spec.run_dir,ctx.repo_root),
            relpath(txpath,ctx.repo_root),relpath(joinpath(source,"codebook.bin"),ctx.repo_root),
            spec.variant=="S0" ? "" : relpath(joinpath(spec.run_dir,"item_mapping.csv"),ctx.repo_root),
            relpath(joinpath(spec.run_dir,"tid_image_mapping.csv"),ctx.repo_root),relpath(joinpath(spec.run_dir,"integrity_report.toml"),ctx.repo_root),
            relpath(joinpath(spec.run_dir,"config_snapshot.toml"),ctx.repo_root),sha,EXPECTED_IMAGES,status,issue])
    end
    _write_csv(output_path(ctx,"input_manifest.csv"),header,rows)
end

function _record_validation!(ctx,validation,row)
    push!(validation,row)
    _write_input_manifest(ctx,validation)
    _write_csv(output_path(ctx,"validation_report.csv"),["database_id","status","issue","record_count","empty_count"],validation)
    spec=first(filter(s->s.database_id==row[1],ctx.specs))
    checkpoint=Dict("database_id"=>row[1],"status"=>row[2],"issue"=>row[3],"record_count"=>row[4],
        "source_sha256"=>_input_transaction_hash(joinpath(spec.run_dir,"transactions.jsonl")),
        "config_sha256"=>_sha256(ctx.config_path),"updated_unix_seconds"=>time())
    path=output_path(ctx,"execution","checkpoints","analysis_a_$(row[1]).toml")
    mkpath(dirname(path)); tmp=path*".partial"
    open(tmp,"w") do io; TOML.print(io,checkpoint); end
    mv(tmp,path;force=true)
end
