"""Mỗi ảnh thành transaction binary đã sort; giữ cả ảnh có transaction rỗng."""
function encode_transactions(assignments, descriptor_index, image_ids)
    length(assignments) == length(descriptor_index) ||
        throw(ArgumentError("Assignments không khớp số patch"))
    all(>(0), assignments) || throw(ArgumentError("Word IDs phải dương"))
    allunique(image_ids) || throw(ArgumentError("Image IDs phải duy nhất"))
    byimage = Dict(id => Int[] for id in image_ids)
    for (word, row) in zip(assignments, descriptor_index)
        haskey(byimage, row.image_id) || throw(ArgumentError("Patch có image ID không xác định"))
        push!(byimage[row.image_id], word)
    end
    return [sort!(unique!(byimage[id])) for id in image_ids]
end

"""TC6: mã hóa visual words thành một transaction cho mỗi ảnh."""
function run_tc6!(state::TCState)
    _require_previous(state, 6)
    config = state.config
    summaries = NamedTuple[]
    for run_id in state.data[:run_ids]
        run_dir = _run_output_dir(state, run_id)
        assignments = open(deserialize, joinpath(run_dir, "assignments.bin"))
        model = state.data[:models][run_id]
        train_tx = encode_transactions(assignments.train_words, state.data[:train_map], state.data[:train_ids])
        validation_tx = encode_transactions(assignments.valid_words, state.data[:validation_map],
            state.data[:validation_ids])
        k = size(model.centroids, 2)
        valid = length(train_tx) == length(state.data[:train_ids]) &&
            length(validation_tx) == length(state.data[:validation_ids]) &&
            all(issorted ∘ unique, vcat(train_tx, validation_tx)) &&
            all(length(tx) <= min(state.data[:train_keep_per_image][i], k)
                for (i, tx) in enumerate(train_tx)) &&
            all(length(tx) <= min(state.data[:validation_keep_per_image][i], k)
                for (i, tx) in enumerate(validation_tx)) &&
            all(tx -> all(item -> 1 <= item <= k, tx), vcat(train_tx, validation_tx))
        valid || error("Transaction invariant failed for $run_id")
        _write_transactions(joinpath(run_dir, "train_transactions.txt"), train_tx)
        _write_transactions(joinpath(run_dir, "validation_transactions.txt"), validation_tx)
        tid_rows = vcat([(tid, "train", image_id) for (tid, image_id) in enumerate(state.data[:train_ids])],
            [(length(state.data[:train_ids]) + tid, "validation", image_id)
                for (tid, image_id) in enumerate(state.data[:validation_ids])])
        _write_csv(joinpath(run_dir, "tid_mapping.csv"), ["tid", "split", "image_id"], tid_rows)
        if state.data[:mode] == "smoke"
            state.data[:train_tx] = train_tx
            state.data[:validation_tx] = validation_tx
        end
        push!(summaries, (; run_id, train_transactions=length(train_tx),
            validation_transactions=length(validation_tx),
            empty_train=count(isempty, train_tx), empty_validation=count(isempty, validation_tx)))
    end
    state.checks["tc6_transaction_invariants"] = "PASS"
    return _finish_stage!(state, 6, "Tạo transaction BoVW", summaries)
end

function run_tc6!(state::TCv2State)
    _require_stage(state, 6)
    summaries = NamedTuple[]
    for run_id in state.run_ids
        run_dir = state.run_dirs[run_id]
        checkpoint = TOML.parsefile(joinpath(run_dir, "checkpoint.toml"))
        transaction_path = joinpath(run_dir, "transactions.jsonl")
        already_completed = get(checkpoint, "status", "") == "COMPLETED" &&
            isfile(transaction_path) && isfile(joinpath(run_dir, "tid_image_mapping.csv")) &&
            isfile(joinpath(run_dir, "image_metadata.csv"))
        if already_completed
            transactions = [_parse_transaction_line(line).items for line in eachline(transaction_path)]
        else
            words = open(deserialize, joinpath(run_dir, "assignments.bin"))
            transactions = encode_transactions(words, state.descriptor_index, state.image_ids)
        end
        k = _load_codebook(joinpath(run_dir, "codebook.bin")).k
        valid = length(transactions) == length(state.image_ids) &&
            all(issorted, transactions) && all(tx -> length(tx) == length(unique(tx)), transactions) &&
            all(tx -> length(tx) <= min(k, 49), transactions) &&
            all(tx -> all(item -> 1 <= item <= k, tx), transactions)
        valid || error("TC6 transaction contract failed for $run_id")
        if !already_completed
            image_id_map = _release_image_id_map(state)
            output_ids = isnothing(image_id_map) ? state.image_ids :
                [image_id_map[id] for id in state.image_ids]
            _write_transaction_jsonl(transaction_path, transactions, output_ids)
            _write_run_mappings(state, joinpath(run_dir, "tid_image_mapping.csv"))
            _write_image_metadata(state, joinpath(run_dir, "image_metadata.csv"))
        end
        push!(summaries, (; run_id, transactions=length(transactions), empty=count(isempty, transactions)))
    end
    _set_stage!(state, 6, "tc6_s0_transactions", all(s -> s.transactions == length(state.image_ids), summaries))
    return summaries
end
