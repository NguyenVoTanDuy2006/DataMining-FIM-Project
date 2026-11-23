function csv_fields(line::AbstractString; identify_line::Bool=false)
    fields, buffer, quoted = String[], IOBuffer(), false
    i = firstindex(line)
    while i <= lastindex(line)
        ch = line[i]
        if ch == '"'
            ni = nextind(line, i)
            if quoted && ni <= lastindex(line) && line[ni] == '"'
                print(buffer, '"'); i = ni
            else
                quoted = !quoted
            end
        elseif ch == ',' && !quoted
            push!(fields, String(take!(buffer)))
        else
            print(buffer, ch)
        end
        i = nextind(line, i)
    end
    quoted && error(identify_line ? "Unterminated quoted CSV field: $line" : "Unterminated quoted CSV field")
    push!(fields, String(take!(buffer)))
    return fields
end
