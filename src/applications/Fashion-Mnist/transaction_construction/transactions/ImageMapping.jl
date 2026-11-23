function _release_image_id_map(state)
    state.config["run"]["mode"] == "release" || return nothing
    return Dict(state.image_ids[i] => format_image_id(Symbol(state.original_splits[i]),
        state.original_indices[i] - 1) for i in eachindex(state.image_ids))
end

function _write_run_mappings(state, path)
    image_id_map = _release_image_id_map(state)
    open(path, "w") do io
        release = state.config["run"]["mode"] == "release"
        println(io, release ? "tid,image_id,split,source_index" : "tid,image_id,original_split,original_index")
        for tid in eachindex(state.image_ids)
            image_id = isnothing(image_id_map) ? state.image_ids[tid] : image_id_map[state.image_ids[tid]]
            source_index = release ? state.original_indices[tid] - 1 : state.original_indices[tid]
            println(io, tid, ',', image_id, ',', state.original_splits[tid], ',', source_index)
        end
    end
end

function _write_image_metadata(state, path)
    image_id_map = _release_image_id_map(state)
    open(path, "w") do io
        release = state.config["run"]["mode"] == "release"
        println(io, release ? "image_id,split,source_index,class_label" : "image_id,original_split,original_index,class_label")
        for i in eachindex(state.image_ids)
            image_id = isnothing(image_id_map) ? state.image_ids[i] : image_id_map[state.image_ids[i]]
            source_index = release ? state.original_indices[i] - 1 : state.original_indices[i]
            println(io, image_id, ',', state.original_splits[i], ',', source_index, ',', state.labels[i])
        end
    end
end

function _expected_output_image_ids(state)
    image_id_map = _release_image_id_map(state)
    return isnothing(image_id_map) ? state.image_ids :
        [image_id_map[id] for id in state.image_ids]
end
