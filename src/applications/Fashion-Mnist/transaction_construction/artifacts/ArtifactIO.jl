function _json_escape(s)
    replace(string(s), "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n")
end

function _json_number(value)
    return isfinite(value) ? string(value) : "null"
end

function _write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ','))
        for row in rows
            println(io, join(string.(row), ','))
        end
    end
end

function _sha256(path)
    return bytes2hex(open(sha256, path))
end
