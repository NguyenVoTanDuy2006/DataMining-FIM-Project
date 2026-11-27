using Printf

const WIDTH = 480
const HEIGHT = 350
const LEFT = 52.0
const RIGHT = 464.0
const TOP = 36.0
const BOTTOM = 260.0
const MAX_SECONDS = 25.0
const SET_COLOR = "#1f77b4"
const BITVECTOR_COLOR = "#ff7f0e"

const THRESHOLDS = ("80%", "60%", "40%", "20%", "10%", "5%")
const SET_SECONDS = (4.580, 4.755, 5.260, 7.629, 11.862, 20.937)
const BITVECTOR_SECONDS = (4.161, 4.493, 5.380, 6.097, 7.467, 8.727)

plot_width() = RIGHT - LEFT
plot_height() = BOTTOM - TOP
map_y(value) = BOTTOM - value / MAX_SECONDS * plot_height()
format_decimal(value) = replace(@sprintf("%.2f", value), "." => ",")

function write_text(io, x, y, content; size=10, anchor="middle", weight="normal", color="#222222")
    println(io, "<text x=\"$x\" y=\"$y\" text-anchor=\"$anchor\" font-family=\"Arial,sans-serif\" font-size=\"$size\" font-weight=\"$weight\" fill=\"$color\">$content</text>")
end

function write_chart(path)
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$WIDTH\" height=\"$HEIGHT\" viewBox=\"0 0 $WIDTH $HEIGHT\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        write_text(io, WIDTH / 2, 20, "Thời gian chạy Eclat theo ngưỡng hỗ trợ"; size=14, weight="bold")

        for tick in 0:5:25
            y = map_y(tick)
            println(io, "<line x1=\"$LEFT\" y1=\"$y\" x2=\"$RIGHT\" y2=\"$y\" stroke=\"#dddddd\" stroke-width=\"1\"/>")
            write_text(io, LEFT - 9, y + 3.5, string(tick); size=9, anchor="end")
        end

        println(io, "<line x1=\"$LEFT\" y1=\"$TOP\" x2=\"$LEFT\" y2=\"$BOTTOM\" stroke=\"#333333\"/>")
        println(io, "<line x1=\"$LEFT\" y1=\"$BOTTOM\" x2=\"$RIGHT\" y2=\"$BOTTOM\" stroke=\"#333333\"/>")
        println(io, "<text x=\"15\" y=\"$(TOP + plot_height() / 2)\" text-anchor=\"middle\" font-family=\"Arial,sans-serif\" font-size=\"10\" fill=\"#222222\" transform=\"rotate(-90 15 $(TOP + plot_height() / 2))\">Thời gian (giây)</text>")

        group_step = plot_width() / length(THRESHOLDS)
        bar_width = 16.0
        bar_gap = 3.0
        for index in eachindex(THRESHOLDS)
            center = LEFT + (index - 0.5) * group_step
            for (value, x, color, label) in (
                (SET_SECONDS[index], center - bar_width - bar_gap / 2, SET_COLOR, "Set"),
                (BITVECTOR_SECONDS[index], center + bar_gap / 2, BITVECTOR_COLOR, "BitVector"),
            )
                y = map_y(value)
                height = BOTTOM - y
                println(io, "<rect x=\"$x\" y=\"$y\" width=\"$bar_width\" height=\"$height\" fill=\"$color\"><title>$(THRESHOLDS[index]) $label: $(format_decimal(value)) giây</title></rect>")
                write_text(io, x + bar_width / 2, max(TOP + 11, y - 4), format_decimal(value); size=9)
            end
            write_text(io, center, BOTTOM + 16, THRESHOLDS[index]; size=9)
        end

        write_text(io, WIDTH / 2, 299, "Ngưỡng hỗ trợ tối thiểu"; size=10)
        println(io, "<rect x=\"155\" y=\"318\" width=\"11\" height=\"11\" fill=\"$SET_COLOR\"/>")
        write_text(io, 171, 327, "Set"; size=9, anchor="start")
        println(io, "<rect x=\"255\" y=\"318\" width=\"11\" height=\"11\" fill=\"$BITVECTOR_COLOR\"/>")
        write_text(io, 271, 327, "BitVector"; size=9, anchor="start")
        println(io, "</svg>")
    end
    return path
end

output_path = isempty(ARGS) ? joinpath(@__DIR__, "eclat_performance.svg") : ARGS[1]
mkpath(dirname(output_path))
println("Wrote ", write_chart(output_path))
