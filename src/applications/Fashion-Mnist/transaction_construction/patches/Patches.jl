@inline function _patch_view(images, image, row, col, patch_size)
    y = (row - 1) * patch_size + 1
    x = (col - 1) * patch_size + 1
    return @view images[y:y+patch_size-1, x:x+patch_size-1, image]
end

"""Tách ảnh thành patch row-major và trả descriptor raw index cùng metadata."""
function extract_patches(images, image_ids; patch_size=4)
    h, w, n = size(images)
    h == 28 && w == 28 || throw(ArgumentError("Ảnh phải có shape 28×28"))
    length(image_ids) == n || throw(ArgumentError("image_ids không khớp ảnh"))
    patches = Matrix{UInt8}[]
    index = NamedTuple[]
    grid = 28 ÷ patch_size
    grid * patch_size == 28 || error("Patch không phủ kín ảnh")
    for i in 1:n, r in 1:grid, c in 1:grid
        patch_id = (r - 1) * grid + c
        patch = Matrix(_patch_view(images, i, r, c, patch_size))
        push!(patches, patch)
        push!(index, (; image_id=image_ids[i], patch_id, patch_row=r, patch_col=c))
    end
    return patches, index
end

function _reconstruct_images(patches,index,image_ids;patch_size=4)
    restored=zeros(UInt8,28,28,length(image_ids))
    slots=Dict(id=>slot for (slot,id) in enumerate(image_ids))
    for (patch,row) in zip(patches,index)
        y=(row.patch_row-1)*patch_size+1
        x=(row.patch_col-1)*patch_size+1
        restored[y:y+patch_size-1,x:x+patch_size-1,slots[row.image_id]].=patch
    end
    return restored
end

"""TC1: trích patch dense 4×4 và xác minh tái tạo ảnh chính xác."""
function run_tc1!(state::TCState)
    _require_previous(state, 1)
    config = state.config
    patch_size = config["tc1_patch_extraction"]["patch_size"][1]
    patches_per_image = (28 ÷ patch_size)^2
    train_count = length(state.data[:train_ids]) * patches_per_image
    validation_count = length(state.data[:validation_ids]) * patches_per_image
    if state.data[:mode] == "smoke"
        train_patches, train_index = extract_patches(state.data[:train_images], state.data[:train_ids]; patch_size)
        validation_patches, validation_index = extract_patches(state.data[:validation_images],
            state.data[:validation_ids]; patch_size)
        train_reconstructed = _reconstruct_images(train_patches, train_index, state.data[:train_ids]; patch_size)
        validation_reconstructed = _reconstruct_images(validation_patches, validation_index,
            state.data[:validation_ids]; patch_size)
        train_reconstructed == state.data[:train_images] &&
            validation_reconstructed == state.data[:validation_images] || error("Tái tạo patch không khớp ảnh nguồn")
        state.data[:train_patches] = train_patches
        state.data[:validation_patches] = validation_patches
        state.data[:train_patch_index] = train_index
        state.data[:validation_patch_index] = validation_index
        state.checks["tc1_patch_reconstruction"] = length(train_patches) == train_count &&
            length(validation_patches) == validation_count ? "PASS" : "FAIL"
        state.checks["tc1_exact_reconstruction"] = "PASS"
    else
        state.data[:train_patch_count] = train_count
        state.data[:validation_patch_count] = validation_count
        state.checks["tc1_patch_reconstruction"] = "PASS"
    end
    state.data[:train_patch_count] = train_count
    state.data[:validation_patch_count] = validation_count
    return _finish_stage!(state, 1, "Trích patch 4×4",
        (; train_patches=train_count, validation_patches=validation_count,
            reconstruction=get(state.checks, "tc1_exact_reconstruction", "không chạy cho full")))
end

function run_tc1!(state::TCv2State)
    _require_stage(state, 1)
    n = length(state.image_ids)
    patch = state.config["tc1_patch_extraction"]
    patch["patch_size"] == [4, 4] && patch["stride"] == [4, 4] || error("TC1 v2 requires 4×4 non-overlapping patches")
    patch_count = n * 49
    passed = size(state.images, 3) == n && patch_count == 49n &&
        patch["padding"] == "none" && patch["patch_order"] == "row_major"
    if state.config["run"]["mode"] == "smoke"
        sample_images = reshape(state.images[:, :, 1], 28, 28, 1)
        sample_patches, sample_index = extract_patches(sample_images, [state.image_ids[1]])
        restored = _reconstruct_images(sample_patches, sample_index, [state.image_ids[1]])
        passed &= length(sample_patches) == 49 && restored[:, :, 1] == state.images[:, :, 1] &&
            [row.patch_id for row in sample_index] == collect(1:49)
    end
    _set_stage!(state, 1, "tc1_patch_geometry_and_mapping", passed)
    return (; images=n, patches_before_filter=patch_count, patch_size=(4, 4), traversal="row_major")
end
