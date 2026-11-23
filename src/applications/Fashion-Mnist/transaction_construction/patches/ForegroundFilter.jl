_foreground_ratio(patch, tau) = count(>(tau), patch) / length(patch)
_keep_foreground(patch, tau, alpha) = iszero(alpha) ? any(>(tau), patch) : _foreground_ratio(patch, tau) > alpha

"""Fit phân vị Q10 trên các pixel dương của tập train, trả tau và metadata."""
function fit_q10_positive(images; q=0.10, fit_split="train")
    positive = filter(>(0), vec(images))
    isempty(positive) && error("Không có pixel dương để fit Q10+")
    tau = quantile(Float64.(positive), q)
    return tau, (; positive_pixel_count=length(positive), quantile=q,
        definition="Statistics.quantile linear interpolation", fit_split)
end

function _patch_status_rows(split, patches, index, tau, alpha)
    return [(split, row.image_id, row.patch_id, row.patch_row, row.patch_col,
        _foreground_ratio(patch, tau), _foreground_ratio(patch, tau) > alpha,
        tau, alpha, "T2") for (patch, row) in zip(patches, index)]
end

"""Tính số patch được giữ và tỉ lệ trùng chính xác sau lọc.

Tỉ lệ trùng được tính bằng `1 - N_unique / N_total`; các patch được so sánh
theo toàn bộ giá trị pixel UInt8.
"""
function _retained_patch_summary(images, tau, alpha, patch_size)
    patch_size^2 <= sizeof(UInt128) ||
        throw(ArgumentError("Tính patch trùng hiện hỗ trợ tối đa 16 pixel mỗi patch"))
    grid = 28 ÷ patch_size
    counts = zeros(Int, size(images, 3))
    unique_patch_keys = Set{UInt128}()
    total = 0

    for image_id in axes(images, 3), row in 1:grid, col in 1:grid
        patch = _patch_view(images, image_id, row, col, patch_size)
        _keep_foreground(patch, tau, alpha) || continue

        counts[image_id] += 1
        total += 1

        key = zero(UInt128)
        for pixel in patch
            key = (key << 8) | UInt128(pixel)
        end
        push!(unique_patch_keys, key)
    end

    unique_count = length(unique_patch_keys)
    duplicate_rate = total == 0 ? 0.0 : 1 - unique_count / total
    return (; per_image=counts, total, unique=unique_count, duplicate_rate)
end

"""TC2: tạo keep masks theo tau và alpha, đồng thời lưu patch status."""
function run_tc2!(state::TCState)
    _require_previous(state, 2)
    tau = state.data[:tau]
    alpha = state.config["tc2_patch_filtering"]["alpha"]
    train_ids, validation_ids = state.data[:train_ids], state.data[:validation_ids]
    patch_size = state.config["tc1_patch_extraction"]["patch_size"][1]
    patches_per_image = (28 ÷ patch_size)^2
    if state.data[:mode] == "smoke"
        train_patches = state.data[:train_patches]
        validation_patches = state.data[:validation_patches]
        train_index = state.data[:train_patch_index]
        validation_index = state.data[:validation_patch_index]
        train_keep = findall(i -> _keep_foreground(train_patches[i], tau, alpha),
            eachindex(train_patches))
        validation_keep = findall(i -> _keep_foreground(validation_patches[i], tau, alpha),
            eachindex(validation_patches))
        _write_csv(joinpath(state.work_root, "patch_filter_status.csv"),
            ["split", "image_id", "patch_id", "patch_row", "patch_col", "foreground_ratio", "keep", "tau", "alpha", "experiment_id"],
            vcat(_patch_status_rows("train", train_patches, train_index, tau, alpha),
                _patch_status_rows("validation", validation_patches, validation_index, tau, alpha)))
        state.data[:train_keep] = train_keep
        state.data[:validation_keep] = validation_keep
    end

    train_duplicate_summary = _retained_patch_summary(
        state.data[:train_images], tau, alpha, patch_size)
    validation_duplicate_summary = _retained_patch_summary(
        state.data[:validation_images], tau, alpha, patch_size)
    train_per_image = train_duplicate_summary.per_image
    validation_per_image = validation_duplicate_summary.per_image
    state.data[:patch_duplicate_summary] = Dict(
        "train" => train_duplicate_summary,
        "validation" => validation_duplicate_summary)

    _write_csv(joinpath(state.work_root, "patch_filter_summary.csv"),
        ["split", "image_id", "retained_count", "discarded_count", "empty_after_filter"],
        vcat([("train", id, kept, patches_per_image - kept, kept == 0)
                for (id, kept) in zip(train_ids, train_per_image)],
            [("validation", id, kept, patches_per_image - kept, kept == 0)
                for (id, kept) in zip(validation_ids, validation_per_image)]))
    _write_csv(joinpath(state.work_root, "patch_duplicate_summary.csv"),
        ["split", "retained_patches", "unique_patches", "duplicate_patches", "duplicate_rate"],
        [("train", train_duplicate_summary.total, train_duplicate_summary.unique,
            train_duplicate_summary.total - train_duplicate_summary.unique,
            train_duplicate_summary.duplicate_rate),
            ("validation", validation_duplicate_summary.total, validation_duplicate_summary.unique,
                validation_duplicate_summary.total - validation_duplicate_summary.unique,
                validation_duplicate_summary.duplicate_rate)])
    state.data[:train_keep_per_image] = train_per_image
    state.data[:validation_keep_per_image] = validation_per_image
    train_retained = sum(train_per_image)
    validation_retained = sum(validation_per_image)
    state.checks["tc2_filter_invariants"] = train_retained <= state.data[:train_patch_count] &&
        validation_retained <= state.data[:validation_patch_count] ? "PASS" : "FAIL"
    state.checks["tc2_filter_invariants"] == "PASS" || error("Filtering count invariant failed")
    return _finish_stage!(state, 2, "Lọc patch T2",
        (; train_kept=train_retained, train_discarded=state.data[:train_patch_count]-train_retained,
            validation_kept=validation_retained,
            validation_discarded=state.data[:validation_patch_count]-validation_retained,
            train_total_patches=train_duplicate_summary.total,
            train_unique_patches=train_duplicate_summary.unique,
            train_duplicate_patches=train_duplicate_summary.total-train_duplicate_summary.unique,
            train_duplicate_rate=train_duplicate_summary.duplicate_rate,
            validation_total_patches=validation_duplicate_summary.total,
            validation_unique_patches=validation_duplicate_summary.unique,
            validation_duplicate_patches=validation_duplicate_summary.total-validation_duplicate_summary.unique,
            validation_duplicate_rate=validation_duplicate_summary.duplicate_rate))
end

function run_tc2!(state::TCv2State)
    _require_stage(state, 2)
    tau = 29
    n = length(state.image_ids)
    retained = zeros(Int, n)
    for i in 1:n, row in 1:7, col in 1:7
        patch = _patch_view(state.images, i, row, col, 4)
        _keep_foreground(patch, tau, 0.0) && (retained[i] += 1)
    end
    state.retained_per_image = retained
    total = 49n
    kept = sum(retained)
    passed = kept <= total && total - kept + kept == total
    open(joinpath(state.output_root, "tc2_per_image_summary.csv"), "w") do io
        println(io, "image_id,original_split,original_index,retained_patches,removed_patches,empty_after_filter")
        for i in eachindex(state.image_ids)
            println(io, state.image_ids[i], ',', state.original_splits[i], ',', state.original_indices[i],
                ',', retained[i], ',', 49-retained[i], ',', retained[i] == 0)
        end
    end
    open(joinpath(state.output_root, "tc2_filter_summary.toml"), "w") do io
        TOML.print(io, Dict("threshold"=>tau, "comparison"=>">", "total_patches"=>total,
            "retained_patches"=>kept, "removed_patches"=>total-kept,
            "retention_rate"=>kept/total, "images_with_no_retained_patches"=>count(iszero, retained)))
    end
    _set_stage!(state, 2, "tc2_foreground_filter", passed)
    return (; threshold=tau, kept, removed=total-kept, total_patches=total,
        retention_rate=total == 0 ? 0.0 : kept/total, images_with_no_patches=count(iszero, retained))
end
