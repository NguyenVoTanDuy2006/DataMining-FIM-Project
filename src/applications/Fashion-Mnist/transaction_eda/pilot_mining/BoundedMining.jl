function _read_transactions_bounded(path,deadline)
    transactions=Vector{Vector{Int}}()
    expired=false
    open(path,"r") do io
        for (line_number,line) in enumerate(eachline(io))
            if time()>deadline
                expired=true
                break
            end
            tid,_,items=_parse_transaction(line,path,line_number)
            tid==line_number || error("Non-contiguous TID in $path:$line_number")
            push!(transactions,items)
        end
    end
    expired && return nothing
    return transactions
end

function _support_distribution(values)
    isempty(values) && return ["","","","",""]
    q=quantile(Float64.(values),[0.05,0.50,0.95])
    return [minimum(values),q[1],q[2],q[3],maximum(values)]
end

function _bounded_eclat(path, min_count, max_length, timeout_s, max_pairs)
    started=time(); deadline=started+timeout_s
    transactions=_read_transactions_bounded(path,deadline)
    blank=["","","","",""]
    isnothing(transactions) && return (status="TIMEOUT", count1="", count2="", singleton_support=blank, pair_support=blank, elapsed=time()-started, active=0, reason="timeout while reading transactions")
    length(transactions)==EXPECTED_IMAGES || return (status="FAILED",count1="",count2="",singleton_support=blank,pair_support=blank,elapsed=time()-started,active=0,reason="transaction denominator is not 70,000")
    singleton_counts=Dict{Int,Int}()
    for tx in transactions
        time()>deadline && return (status="TIMEOUT",count1="",count2="",singleton_support=blank,pair_support=blank,elapsed=time()-started,active=0,reason="timeout while counting singleton supports")
        for item in unique(tx); singleton_counts[item]=get(singleton_counts,item,0)+1; end
    end
    active=count(>=(min_count),values(singleton_counts))
    pair_estimate=active*(active-1)÷2
    pair_estimate>max_pairs && return (status="ITEMSET_LIMIT", count1="", count2="", singleton_support=blank, pair_support=blank, elapsed=time()-started, active=active, reason="pair candidate estimate exceeds configured cap")
    result=try
        mine(transactions,min_count;backend=:set,max_length=max_length,deadline=deadline,max_itemsets=max_pairs)
    catch err
        return (status=err isa InterruptException ? "TIMEOUT" : err isa OverflowError ? "ITEMSET_LIMIT" : "FAILED",
            count1="",count2="",singleton_support=blank,pair_support=blank,elapsed=time()-started,active=active,reason=sprint(showerror,err))
    end
    pairs=count(key->length(key)==2,keys(result))
    singleton_values=[support for support in values(singleton_counts) if support>=min_count]
    pair_values=[support for (key,support) in result if length(key)==2]
    return (status="COMPLETED_LENGTH_CAPPED",count1=active,count2=max_length>=2 ? pairs : 0,
        singleton_support=_support_distribution(singleton_values),pair_support=_support_distribution(pair_values),
        elapsed=time()-started,active=active,reason="exact through itemset length $max_length")
end

function _mine_lengths(path,min_count,max_len,timeout,max_pairs)
    # C3 calls the repository Eclat engine; the length/resource limits are explicit.
    started=time(); deadline=started+timeout
    transactions=try
        _read_transactions_bounded(path,deadline)
    catch
        return nothing,"FAILED",time()-started
    end
    isnothing(transactions) && return nothing,"TIMEOUT",time()-started
    length(transactions)==EXPECTED_IMAGES || return nothing,"FAILED",time()-started
    try
        result=mine(transactions,min_count;backend=:set,max_length=max_len,deadline=deadline,max_itemsets=max_pairs)
        return result,"COMPLETED_LENGTH_CAPPED",time()-started
    catch err
        status=err isa InterruptException ? "TIMEOUT" : err isa OverflowError ? "ITEMSET_LIMIT" : "FAILED"
        return nothing,status,time()-started
    end
end
