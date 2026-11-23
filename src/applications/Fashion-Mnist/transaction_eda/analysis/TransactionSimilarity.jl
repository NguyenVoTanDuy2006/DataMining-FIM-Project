_jaccard(a, b) = (isempty(a) && isempty(b)) ? 1.0 : (isempty(a) || isempty(b)) ? 0.0 : length(intersect(a, b)) / length(union(a, b))
function _quantile_summary(values)
    isempty(values) && return (NaN, NaN, NaN, NaN, NaN, NaN, NaN)
    q = quantile(Float64.(values), [0.0, 0.05, 0.25, 0.5, 0.75, 0.95, 1.0])
    return (mean(values), q[4], q[2], q[3], q[5], q[6], q[7])
end

function _pair_similarity!(metrics, txs, pair_manifest)
    pair_values = [_jaccard(txs[a], txs[b]) for (a,b) in pair_manifest]
    qj = _quantile_summary(pair_values)
    both_empty = count(pair -> isempty(txs[pair[1]]) && isempty(txs[pair[2]]), pair_manifest)
    one_empty = count(pair -> xor(isempty(txs[pair[1]]), isempty(txs[pair[2]])), pair_manifest)
    metrics["jaccard_pair_count"] = length(pair_values)
    metrics["jaccard_mean"] = mean(pair_values); metrics["jaccard_median"] = median(pair_values)
    metrics["jaccard_p5"] = quantile(pair_values, 0.05); metrics["jaccard_p95"] = quantile(pair_values, 0.95)
    metrics["jaccard_both_empty_pairs"] = both_empty; metrics["jaccard_one_empty_pairs"] = one_empty
    return nothing
end

function _class_similarity!(metrics, spec, txs, class_manifest)
    within_vals, between_vals = Float64[], Float64[]
    within_both, between_both, within_one, between_one = 0, 0, 0, 0
    class_rows, between_rows = Vector{Vector{Any}}(), Vector{Vector{Any}}()
    class_buckets = Dict{Int,Vector{Float64}}(c=>Float64[] for c in 0:9)
    between_buckets = Dict{Tuple{Int,Int},Vector{Float64}}()
    class_both = Dict{Int,Int}(c=>0 for c in 0:9)
    class_one = Dict{Int,Int}(c=>0 for c in 0:9)
    between_both_by_pair = Dict{Tuple{Int,Int},Int}()
    between_one_by_pair = Dict{Tuple{Int,Int},Int}()
    for row in class_manifest
        a, b = Int(row[1]), Int(row[2]); ca, cb = Int(row[3]), Int(row[4]); kind = String(row[5])
        score = _jaccard(txs[a], txs[b])
        both = isempty(txs[a]) && isempty(txs[b])
        if kind == "within"
            both && (within_both += 1)
            both && (class_both[ca]+=1)
            xor(isempty(txs[a]),isempty(txs[b])) && (within_one+=1; class_one[ca]+=1)
            !both && push!(within_vals, score)
            !both && push!(class_buckets[ca], score)
        else
            both && (between_both += 1)
            both && (between_both_by_pair[(ca,cb)]=get(between_both_by_pair,(ca,cb),0)+1)
            xor(isempty(txs[a]),isempty(txs[b])) && (between_one+=1; between_one_by_pair[(ca,cb)]=get(between_one_by_pair,(ca,cb),0)+1)
            !both && push!(between_vals, score)
            !both && push!(get!(between_buckets, (ca,cb), Float64[]), score)
        end
    end
    for c in 0:9
        vals = class_buckets[c]
        push!(class_rows, [spec.database_id, spec.k, spec.seed, spec.variant, c, length(vals), class_both[c], class_one[c], isempty(vals) ? "" : mean(vals), isempty(vals) ? "" : median(vals), isempty(vals) ? "" : quantile(vals,0.05), isempty(vals) ? "" : quantile(vals,0.25), isempty(vals) ? "" : quantile(vals,0.75), isempty(vals) ? "" : quantile(vals,0.95)])
    end
    for (ca,cb) in [(a,b) for a in 0:9 for b in a+1:9]
        vals = get(between_buckets, (ca,cb), Float64[])
        push!(between_rows, [spec.database_id, spec.k, spec.seed, spec.variant, ca, cb, length(vals), get(between_both_by_pair,(ca,cb),0), get(between_one_by_pair,(ca,cb),0), isempty(vals) ? "" : mean(vals), isempty(vals) ? "" : median(vals), isempty(vals) ? "" : quantile(vals,0.05), isempty(vals) ? "" : quantile(vals,0.25), isempty(vals) ? "" : quantile(vals,0.75), isempty(vals) ? "" : quantile(vals,0.95)])
    end
    metrics["within_valid_pairs"] = length(within_vals); metrics["between_valid_pairs"] = length(between_vals)
    metrics["within_mean_jaccard"] = isempty(within_vals) ? NaN : mean(within_vals)
    metrics["between_mean_jaccard"] = isempty(between_vals) ? NaN : mean(between_vals)
    for (prefix,values) in (("within",within_vals),("between",between_vals))
        for (name,q) in (("median",0.50),("p5",0.05),("p25",0.25),("p75",0.75),("p95",0.95))
            metrics["$(prefix)_$(name)_jaccard"]=isempty(values) ? NaN : quantile(values,q)
        end
    end
    metrics["separation_gap"] = isempty(within_vals) || isempty(between_vals) ? NaN : mean(within_vals)-mean(between_vals)
    metrics["within_both_empty_pairs"] = within_both; metrics["between_both_empty_pairs"] = between_both
    metrics["within_one_empty_pairs"] = within_one; metrics["between_one_empty_pairs"] = between_one
    metrics["pair_discrimination_auc"] = _auc(within_vals, between_vals)
    return class_rows, between_rows
end

function _auc(within, between)
    (isempty(within) || isempty(between)) && return NaN
    wins = 0.0
    sorted_between = sort!(copy(between))
    for value in within
        wins += searchsortedfirst(sorted_between, value) - 1
        wins += (searchsortedlast(sorted_between, value)-searchsortedfirst(sorted_between, value)+1)/2
    end
    return wins/(length(within)*length(between))
end
