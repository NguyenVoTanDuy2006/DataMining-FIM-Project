"""TC0: kiểm tra archive, lấy mẫu cân bằng và fit Q10+ chỉ trên smoke train."""
function run_tc0!(state::TCState)
    _require_previous(state, 0)
    dataset = state.config["dataset"]
    preprocessing = state.config["tc0_preprocessing"]
    hashes = Dict(file.name => bytes2hex(sha256(read(joinpath(state.data_dir, file.name))))
        for file in FASHION_FILES)
    foreach(file -> _verify_fashion_checksum(joinpath(state.data_dir, file.name), file.sha256),
        FASHION_FILES)
    train = load_fashion_mnist(state.data_dir; split=:train)
    validation = load_fashion_mnist(state.data_dir; split=:test)
    if state.data[:mode] == "smoke"
        train_ids = balanced_smoke_indices(train.labels, dataset["train_per_class"], dataset["sample_seed"])
        validation_ids = balanced_smoke_indices(validation.labels,
            dataset["validation_per_class"], dataset["sample_seed"])
    else
        length(train.labels) == dataset["train_images"] || error("Số ảnh train full không đúng")
        length(validation.labels) == dataset["validation_images"] || error("Số ảnh validation full không đúng")
        train_ids = collect(eachindex(train.labels))
        validation_ids = collect(eachindex(validation.labels))
    end
    train_images = Array(@view train.images[:, :, train_ids])
    validation_images = Array(@view validation.images[:, :, validation_ids])
    train_labels = train.labels[train_ids]
    validation_labels = validation.labels[validation_ids]
    _write_csv(joinpath(state.work_root, "selected_image_ids.csv"), ["split", "image_id", "label"],
        vcat([("train", id, label) for (id, label) in zip(train_ids, train_labels)],
            [("validation", id, label) for (id, label) in zip(validation_ids, validation_labels)]))
    fit_split = state.data[:mode] == "smoke" ? "smoke_train_only" : "train"
    tau, tau_meta = fit_q10_positive(train_images; q=preprocessing["quantile"], fit_split)
    isfinite(tau) || error("Q10+ không hữu hạn")
    state.checks["tc0_archive_checksums"] = "PASS"
    state.checks["tc0_train_only"] = "PASS"
    state.data[:archive_checksums] = hashes
    state.data[:train] = train
    state.data[:validation] = validation
    state.data[:train_ids] = train_ids
    state.data[:validation_ids] = validation_ids
    state.data[:train_images] = train_images
    state.data[:validation_images] = validation_images
    state.data[:train_labels] = train_labels
    state.data[:validation_labels] = validation_labels
    state.data[:tau] = tau
    state.data[:tau_meta] = tau_meta
    open(joinpath(state.work_root, "threshold_fit.toml"), "w") do io
        TOML.print(io, Dict("tau_train" => tau, "train_only" => true,
            "positive_pixel_count" => tau_meta.positive_pixel_count,
            "quantile" => preprocessing["quantile"], "definition" => tau_meta.definition,
            "source_archive_sha256" => hashes))
    end
    state.checks["tc0_archive_checksums"] = "PASS"
    state.checks["tc0_train_only"] = "PASS"
    return _finish_stage!(state, 0, "Fit ngưỡng train-only",
        (; train_images=length(train_ids), validation_images=length(validation_ids), tau))
end
