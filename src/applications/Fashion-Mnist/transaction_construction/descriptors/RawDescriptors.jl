"""Tạo descriptor Float32/255 cho patch được giữ; không đưa label/vị trí vào vector."""
function make_descriptors(patches, index, tau; alpha=0.0)
    kept = Int[]
    for i in eachindex(patches)
        _keep_foreground(patches[i], tau, alpha) && push!(kept, i)
    end
    d = length(patches[1])
    x = Matrix{Float32}(undef, d, length(kept))
    for (j, i) in enumerate(kept)
        x[:, j] .= Float32.(vec(patches[i])) ./ 255f0
    end
    return x, index[kept], kept
end

"""Extract/filter descriptors directly from images without materializing patch matrices."""
function _image_descriptors(images, image_ids, tau; patch_size=4, alpha=0.0)
    n = size(images, 3)
    grid = 28 ÷ patch_size
    retained = 0
    for i in 1:n, row in 1:grid, col in 1:grid
        patch = _patch_view(images, i, row, col, patch_size)
        _keep_foreground(patch, tau, alpha) && (retained += 1)
    end
    descriptors = Matrix{Float32}(undef, patch_size^2, retained)
    index = NamedTuple[]
    sizehint!(index, retained)
    column = 0
    for i in 1:n, row in 1:grid, col in 1:grid
        patch = _patch_view(images, i, row, col, patch_size)
        _keep_foreground(patch, tau, alpha) || continue
        column += 1
        descriptors[:, column] .= Float32.(vec(patch)) ./ 255f0
        push!(index, (; image_id=image_ids[i], patch_id=(row-1)*grid+col,
            patch_row=row, patch_col=col))
    end
    return descriptors, index
end

"""TC3: tạo descriptor raw 16D, kiểm tra miền giá trị và lưu cache theo split."""
function run_tc3!(state::TCState)
    _require_previous(state, 3)
    tau = state.data[:tau]
    features = state.config["tc3_feature_extraction"]
    patch_size = state.config["tc1_patch_extraction"]["patch_size"][1]
    alpha = state.config["tc2_patch_filtering"]["alpha"]
    if state.data[:mode] == "smoke"
        train_desc, train_map, train_keep = make_descriptors(state.data[:train_patches],
            state.data[:train_patch_index], tau; alpha)
        validation_desc, validation_map, validation_keep = make_descriptors(state.data[:validation_patches],
            state.data[:validation_patch_index], tau; alpha)
        train_keep == state.data[:train_keep] && validation_keep == state.data[:validation_keep] ||
            error("Mask TC2 và descriptor TC3 không khớp")
    else
        train_desc, train_map = _image_descriptors(state.data[:train_images], state.data[:train_ids], tau;
            patch_size, alpha)
        validation_desc, validation_map = _image_descriptors(state.data[:validation_images],
            state.data[:validation_ids], tau; patch_size, alpha)
    end
    valid = size(train_desc, 1) == features["dimension"] &&
        size(validation_desc, 1) == features["dimension"] &&
        size(train_desc, 2) == length(train_map) && size(validation_desc, 2) == length(validation_map) &&
        all(isfinite, train_desc) && all(isfinite, validation_desc) &&
        all(x -> 0 <= x <= 1, train_desc) && all(x -> 0 <= x <= 1, validation_desc)
    valid || error("Descriptor invariant failed")
    train_path = joinpath(state.work_root, "train_descriptors.bin")
    validation_path = joinpath(state.work_root, "validation_descriptors.bin")
    open(train_path, "w") do io
        serialize(io, (; descriptors=train_desc, index=train_map))
    end
    open(validation_path, "w") do io
        serialize(io, (; descriptors=validation_desc, index=validation_map))
    end
    state.data[:train_desc] = train_desc
    state.data[:validation_desc] = validation_desc
    state.data[:train_map] = train_map
    state.data[:validation_map] = validation_map
    state.data[:descriptor_checksums] = Dict(
        "train" => bytes2hex(sha256(read(train_path))),
        "validation" => bytes2hex(sha256(read(validation_path))))
    state.checks["tc3_descriptor_mapping"] = "PASS"
    return _finish_stage!(state, 3, "Tạo raw-pixel descriptor",
        (; dimension=size(train_desc, 1), train_descriptors=size(train_desc, 2),
            validation_descriptors=size(validation_desc, 2), values="Float32 trong [0,1]"))
end

function run_tc3!(state::TCv2State)
    _require_stage(state, 3)
    descriptors, index = _image_descriptors(state.images, state.image_ids, 29; patch_size=4, alpha=0.0)
    dimension = state.config["tc3_feature_extraction"]["dimension"]
    valid = size(descriptors) == (dimension, length(index)) && all(isfinite, descriptors) &&
        all(x -> 0f0 <= x <= 1f0, descriptors) && length(index) == sum(state.retained_per_image)
    for i in eachindex(index)
        image_id = index[i].image_id
        valid &= index[i].patch_id in 1:49 && image_id in state.image_ids
    end
    state.descriptor_matrix = descriptors
    state.descriptor_index = index
    _set_stage!(state, 3, "tc3_raw_descriptor_contract", valid)
    return (; descriptor_shape=size(descriptors), retained_descriptors=size(descriptors, 2),
        dtype=string(eltype(descriptors)), flatten_order="column_major")
end
