function _archive_run!(state::TCState, run_id, stage)
    run_dir = _run_output_dir(state, run_id)
    fingerprint = state.data[:fit_fingerprints][run_id]
    archive_root = joinpath(state.output_root, "archives", _backend(state))
    mkpath(archive_root)
    archive_name = "$(run_id)_$(stage)_$(fingerprint[1:12]).tar"
    destination = joinpath(archive_root, archive_name)
    temporary_root = mktempdir()
    local_archive = joinpath(temporary_root, archive_name)
    pack_started = time()
    try
        Tar.create(run_dir, local_archive; portable=true)
        pack_seconds = time() - pack_started
        archive_hash = bytes2hex(open(sha256, local_archive))
        transfer_started = time()
        cp(local_archive, destination; force=true)
        copied_hash = bytes2hex(open(sha256, destination))
        copied_hash == archive_hash || error("TAR Drive không khớp SHA-256: $destination")
        open(destination * ".sha256", "w") do io
            println(io, "$archive_hash  $archive_name")
        end
        transfer_seconds = time() - transfer_started
        state.checks["archive_$(stage)_$(run_id)"] = "PASS"
        return (; run_id, stage, path=destination, sha256=archive_hash,
            pack_seconds, drive_copy_seconds=transfer_seconds)
    finally
        rm(temporary_root; recursive=true, force=true)
    end
end
