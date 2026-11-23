"""Gán nearest centroid theo chunk CPU; tie-break chọn word ID nhỏ nhất."""
function assign_words(X, centroids; chunk_size=128)
    d, n = size(X)
    size(centroids, 1) == d || throw(ArgumentError("Số chiều centroid không khớp"))
    words = Vector{Int}(undef, n)
    for lo in 1:chunk_size:n
        for j in lo:min(lo + chunk_size - 1, n)
            best, bestdist = 1, Inf
            for c in axes(centroids, 2)
                dist = sum(abs2, X[:, j] .- centroids[:, c])
                if dist < bestdist
                    best, bestdist = c, dist
                end
            end
            words[j] = best
        end
    end
    return words
end

function _write_assignments_csv(path, words, index; image_id_map=nothing)
    open(path, "w") do io
        println(io, "image_id,patch_id,patch_row,patch_col,word_id")
        for (word, row) in zip(words, index)
            image_id = isnothing(image_id_map) ? row.image_id : image_id_map[row.image_id]
            println(io, image_id, ',', row.patch_id, ',', row.patch_row, ',', row.patch_col, ',', word)
        end
    end
end

function run_tc5!(state::TCv2State)
    _require_stage(state, 5)
    summaries = NamedTuple[]
    for run_id in state.run_ids
        run_dir = state.run_dirs[run_id]
        book = _load_codebook(joinpath(run_dir, "codebook.bin"))
        checkpoint = TOML.parsefile(joinpath(run_dir, "checkpoint.toml"))
        already_completed = get(checkpoint, "status", "") == "COMPLETED" &&
            isfile(joinpath(run_dir, "assignments.bin")) && isfile(joinpath(run_dir, "patch_assignments.csv"))
        words = already_completed ? open(deserialize, joinpath(run_dir, "assignments.bin")) :
            assign_words(state.descriptor_matrix, book.centroids; chunk_size=16_384)
        k = size(book.centroids, 2)
        valid = length(words) == length(state.descriptor_index) && all(w -> 1 <= w <= k, words)
        valid || error("TC5 assignment contract failed for $run_id")
        if !already_completed
            _write_assignments_csv(joinpath(run_dir, "patch_assignments.csv"), words,
                state.descriptor_index; image_id_map=_release_image_id_map(state))
            open(joinpath(run_dir, "assignments.bin"), "w") do io
                serialize(io, words)
            end
        end
        push!(summaries, (; run_id, assignments=length(words), k))
    end
    _set_stage!(state, 5, "tc5_hard_assignments", all(s -> s.assignments == length(state.descriptor_index), summaries))
    return summaries
end

"""TC5: gán train/validation theo từng codebook, dùng cùng cách cho smoke và full."""
function run_tc5!(state::TCState)
    _require_previous(state, 5)
    config = state.config["tc5_word_assignment"]
    backend = _backend(state)
    chunk_size = get(config, "chunk_size", 128)
    mapping = Dict("train" => state.data[:train_map], "validation" => state.data[:validation_map])
    summaries = NamedTuple[]

    for run_id in state.data[:run_ids]
        model = state.data[:models][run_id]
        assignment_started = time()
        train_words = assign_words(state.data[:train_desc], model.centroids;
            chunk_size)
        validation_words = assign_words(state.data[:validation_desc], model.centroids;
            chunk_size)
        assignment_seconds = time() - assignment_started
        k = size(model.centroids, 2)
        all(in(1:k), train_words) && all(in(1:k), validation_words) ||
            error("Word ID nằm ngoài 1:$k cho $run_id")
        if state.data[:mode] == "smoke"
            direct_words = assign_words(state.data[:train_desc], model.centroids;
                chunk_size=size(state.data[:train_desc], 2))
            train_words == direct_words || error("Chunked assignment không khớp direct assignment")
            state.data[:train_words] = train_words
            state.data[:validation_words] = validation_words
        end
        run_dir = _run_output_dir(state, run_id)
        for (split, words) in (("train", train_words), ("validation", validation_words))
            rows = [(row.image_id, row.patch_id, row.patch_row, row.patch_col, word, split, run_id)
                for (row, word) in zip(mapping[split], words)]
            _write_csv(joinpath(run_dir, "$(split)_assignments.csv"),
                ["image_id", "patch_id", "patch_row", "patch_col", "word_id", "split", "run_id"], rows)
        end
        open(joinpath(run_dir, "assignments.bin"), "w") do io
            serialize(io, (; train_words, valid_words=validation_words))
        end
        archive = _archive_run!(state, run_id, "tc5")
        state.data[:timings]["assignment_seconds"] =
            get(state.data[:timings], "assignment_seconds", 0.0) + assignment_seconds
        state.data[:timings]["archive_pack_seconds"] =
            get(state.data[:timings], "archive_pack_seconds", 0.0) + archive.pack_seconds
        state.data[:timings]["drive_archive_copy_seconds"] =
            get(state.data[:timings], "drive_archive_copy_seconds", 0.0) + archive.drive_copy_seconds
        push!(summaries, (; run_id, train_assignments=length(train_words),
            validation_assignments=length(validation_words), backend,
            assignment_seconds, archive_path=archive.path, archive_sha256=archive.sha256,
            archive_pack_seconds=archive.pack_seconds,
            archive_drive_copy_seconds=archive.drive_copy_seconds))
    end
    state.data[:assignment_summaries] = summaries
    state.checks["tc5_chunked_assignment"] = "PASS"
    return _finish_stage!(state, 5, "Gán visual words", summaries)
end
