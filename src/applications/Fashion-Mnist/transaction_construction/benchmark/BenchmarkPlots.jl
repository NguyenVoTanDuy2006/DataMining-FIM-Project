const SVG_COLORS = ["#2563eb", "#dc2626", "#059669", "#7c3aed", "#d97706"]

struct TradeoffSVG
    content::String
end

Base.show(io::IO, ::MIME"image/svg+xml", figure::TradeoffSVG) = print(io, figure.content)
Base.show(io::IO, ::MIME"text/plain", ::TradeoffSVG) = print(io, "Biểu đồ SVG đã lưu.")

function tradeoff_svg(rows, x_key, x_label, title, path; frontier=false)
    width, height = 920, 610
    left, top, plot_width, plot_height = 90, 45, 760, 450

    xs = Float64[row[x_key] for row in rows if !ismissing(row[x_key])]
    ys = Float64[row["normalized_distortion"] for row in rows]

    xmin, xmax = minimum(xs), maximum(xs)
    ymin, ymax = minimum(ys), maximum(ys)

    xmax = xmax == xmin ? xmin + 1 : xmax
    ymax = ymax == ymin ? ymin + 1 : ymax
    ymin = min(0.0, ymin)

    sx(x) = left + plot_width * (x - xmin) / (xmax - xmin)
    sy(y) = top + plot_height * (1 - (y - ymin) / (ymax - ymin))

    io = IOBuffer()

    println(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">""")
    println(io, """<rect width="100%" height="100%" fill="white"/>""")

    println(io, """<text x="$left" y="25" font-size="18" font-family="sans-serif" font-weight="bold">$title</text>""")

    println(io, """<line x1="$left" y1="$(top + plot_height)" x2="$(left + plot_width)" y2="$(top + plot_height)" stroke="#334155"/>""")

    println(io, """<line x1="$left" y1="$top" x2="$left" y2="$(top + plot_height)" stroke="#334155"/>""")

    println(io, """<text x="$(left + plot_width / 2)" y="$(height - 25)" text-anchor="middle" font-size="14" font-family="sans-serif">$x_label</text>""")

    println(io, """<text transform="translate(22 $(top + plot_height / 2)) rotate(-90)" text-anchor="middle" font-size="14" font-family="sans-serif">Normalized distortion</text>""")

    frontier_rows = frontier ?
        pareto_rows(rows, x_key, "normalized_distortion") :
        Dict{String,Any}[]

    if frontier && !isempty(frontier_rows)
        sort!(frontier_rows; by = row -> row[x_key])

        points = join(
            (string(sx(row[x_key]), ",", sy(row["normalized_distortion"]))
             for row in frontier_rows),
            " "
        )

        println(io, """<polyline points="$points" fill="none" stroke="#111827" stroke-width="2" stroke-dasharray="6,4"/>""")
    end

    for (index, row) in enumerate(rows)
        x = sx(row[x_key])
        y = sy(row["normalized_distortion"])

        color = SVG_COLORS[mod1(index, length(SVG_COLORS))]
        config_id = row["config_id"]

        println(io, """<circle cx="$x" cy="$y" r="5" fill="$color"/>""")

        println(io, """<text x="$(x + 7)" y="$(y - 5)" font-size="10" font-family="sans-serif">$config_id</text>""")
    end

    println(io, "</svg>")

    svg = String(take!(io))

    write(path, svg)
    display(TradeoffSVG(svg))

    return path
end

function timing_bar_svg(rows, metric, title, path)
    width = 900
    row_height = 46
    top = 58
    left = 180
    plot_width = 630
    height = top + row_height * length(rows) + 38
    maximum_value = maximum(row -> getproperty(row, metric), rows)
    io = IOBuffer()
    println(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">""")
    println(io, """<rect width="100%" height="100%" fill="white"/>""")
    println(io, """<text x="$left" y="30" font-family="sans-serif" font-size="18" font-weight="bold">$title</text>""")
    for (index, row) in enumerate(rows)
        y = top + (index - 1) * row_height
        value = getproperty(row, metric)
        bar_width = maximum_value == 0 ? 0 : plot_width * value / maximum_value
        println(io, """<text x="$(left - 10)" y="$(y + 20)" text-anchor="end" font-family="sans-serif" font-size="13">$(row.config_id)</text>""")
        println(io, """<rect x="$left" y="$y" width="$bar_width" height="25" fill="#2563eb" rx="3"/>""")
        println(io, """<text x="$(left + bar_width + 7)" y="$(y + 18)" font-family="sans-serif" font-size="12">$(round(value; digits = 3)) s</text>""")
    end
    println(io, """</svg>""")
    svg = String(take!(io))
    write(path, svg)
    display(TradeoffSVG(svg))
    return path
end

function centroid_time_tradeoff_svg(rows, path)
    width, height = 920, 610
    left, top, plot_width, plot_height = 105, 55, 740, 450
    x_values = [row.fit_time_median_s for row in rows]
    y_values = [row.centroid_mse_to_b0_raw_median for row in rows]
    xmin, xmax = extrema(x_values)
    ymin, ymax = extrema(y_values)
    xmax = xmax == xmin ? xmin + 1.0 : xmax
    ymax = ymax == ymin ? ymin + max(abs(ymin), 1.0) * 0.05 : ymax
    ymin = min(0.0, ymin)
    sx(value) = left + plot_width * (value - xmin) / (xmax - xmin)
    sy(value) = top + plot_height * (1 - (value - ymin) / (ymax - ymin))
    io = IOBuffer()
    println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
    println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
    println(io, "<text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"18\" font-weight=\"bold\">Thời gian fit và Centroid MSE so với B0</text>")
    println(io, "<line x1=\"$left\" y1=\"$(top + plot_height)\" x2=\"$(left + plot_width)\" y2=\"$(top + plot_height)\" stroke=\"#334155\"/>")
    println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top + plot_height)\" stroke=\"#334155\"/>")
    println(io, "<text x=\"$(left + plot_width / 2)\" y=\"$(height - 24)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Median fit time (s), càng thấp càng nhanh</text>")
    println(io, "<text transform=\"translate(22 $(top + plot_height / 2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Centroid MSE Raw 16D, càng thấp càng gần B0</text>")
    for row in rows
        x = sx(row.fit_time_median_s)
        y = sy(row.centroid_mse_to_b0_raw_median)
        println(io, "<circle cx=\"$x\" cy=\"$y\" r=\"6\" fill=\"#7c3aed\"/>")
        println(io, "<text x=\"$(x + 8)\" y=\"$(y - 7)\" font-family=\"sans-serif\" font-size=\"12\">$(row.config_id)</text>")
    end
    println(io, "</svg>")
    svg = String(take!(io))
    write(path, svg)
    display(TradeoffSVG(svg))
    return path
end

function validation_distortion_tradeoff_svg(rows, path)
    width, height = 920, 610
    left, top, plot_width, plot_height = 110, 55, 730, 450
    x_values = [row.fit_time_median_s for row in rows]
    y_values = [row.raw_space_validation_distortion_median for row in rows]
    xmin, xmax = extrema(x_values)
    ymin, ymax = extrema(y_values)
    xmax = xmax == xmin ? xmin + 1.0 : xmax
    ymax = ymax == ymin ? ymin + max(abs(ymin), 1.0) * 0.05 : ymax
    ymin = min(0.0, ymin)
    sx(value) = left + plot_width * (value - xmin) / (xmax - xmin)
    sy(value) = top + plot_height * (1 - (value - ymin) / (ymax - ymin))
    io = IOBuffer()
    println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
    println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
    println(io, "<text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"18\" font-weight=\"bold\">Thời gian fit và Raw-space Validation Distortion</text>")
    println(io, "<line x1=\"$left\" y1=\"$(top + plot_height)\" x2=\"$(left + plot_width)\" y2=\"$(top + plot_height)\" stroke=\"#334155\"/>")
    println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top + plot_height)\" stroke=\"#334155\"/>")
    println(io, "<text x=\"$(left + plot_width / 2)\" y=\"$(height - 24)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Median fit time (s), thấp hơn là nhanh hơn</text>")
    println(io, "<text transform=\"translate(24 $(top + plot_height / 2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Validation distortion Raw 16D, thấp hơn là tốt hơn</text>")
    for row in rows
        x = sx(row.fit_time_median_s)
        y = sy(row.raw_space_validation_distortion_median)
        println(io, "<circle cx=\"$x\" cy=\"$y\" r=\"6\" fill=\"#059669\"/>")
        println(io, "<text x=\"$(x + 8)\" y=\"$(y - 7)\" font-family=\"sans-serif\" font-size=\"12\">$(row.config_id)</text>")
    end
    println(io, "</svg>")
    svg = String(take!(io))
    write(path, svg)
    display(TradeoffSVG(svg))
    return path
end
