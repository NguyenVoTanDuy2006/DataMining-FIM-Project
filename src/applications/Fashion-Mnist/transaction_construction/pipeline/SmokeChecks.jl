function run_unit_smoke_checks!()
    p29 = fill(UInt8(29), 4, 4)
    p30 = fill(UInt8(29), 4, 4); p30[1, 1] = 30
    @assert !any(>(29), p29)
    @assert any(>(29), p30)
    patch = UInt8[1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16]
    @assert vec(patch) == UInt8[1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 4, 8, 12, 16]
    @assert encode_transactions([5, 2, 5, 1], [(image_id=1,), (image_id=1,), (image_id=1,), (image_id=1,)], [1]) == [[1, 2, 5]]
    @assert encode_transactions(Int[], NamedTuple[], [1]) == [[]]
    @assert assign_words(reshape(Float32[0], 1, 1), reshape(Float32[0, 0], 1, 2)) == [1]
    @assert _validate_training_method("raw_full_batch_kmeans") == "raw_full_batch_kmeans"
    @assert _validate_training_method("q20_weighted_kmeans") == "q20_weighted_kmeans"
    invalid_method_rejected = try
        _validate_training_method("unknown_method")
        false
    catch err
        err isa ArgumentError
    end
    @assert invalid_method_rejected
    temp_path = tempname()
    _write_transaction_jsonl(temp_path, [Int[], [2, 5]], [11, 12])
    roundtrip = [_parse_transaction_line(line) for line in eachline(temp_path)]
    @assert length(roundtrip) == 2 && isempty(roundtrip[1].items) && roundtrip[1].tid == 1 &&
        roundtrip[1].image_id == 11 && roundtrip[2].items == [2, 5]
    rm(temp_path; force=true)
    return Dict("threshold_29_30"=>"PASS", "column_major_descriptor"=>"PASS",
        "transaction_sort_deduplicate_empty"=>"PASS", "deterministic_tie_break"=>"PASS",
        "method_selector_and_invalid_value"=>"PASS", "jsonl_empty_transaction_roundtrip"=>"PASS")
end
