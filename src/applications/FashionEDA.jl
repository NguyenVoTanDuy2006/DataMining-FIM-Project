using Random: MersenneTwister, shuffle!
using TOML

export fashion_class_counts, select_fashion_samples, save_fashion_eda

struct FashionSVG
    source::String
end

Base.show(io::IO, ::MIME"image/svg+xml", image::FashionSVG) = print(io, image.source)
Base.show(io::IO, ::MIME"text/plain", ::FashionSVG) = print(io, "Fashion-MNIST sample grid (SVG)")

"Return per-class image counts and fraction of black pixels for a loaded split."
function fashion_class_counts(dataset)
    counts = NamedTuple{(:label, :class_name, :images, :black_pixel_fraction),
        Tuple{Int,String,Int,Float64}}[]

    for label in 0:9
        indices = findall(==(label), dataset.labels)
        isempty(indices) && throw(ArgumentError("Dataset split has no images for class $label"))
        black_pixels = sum(index -> count(iszero, @view(dataset.images[:, :, index])), indices)
        total_pixels = length(indices) * 28 * 28
        push!(counts, (label, FASHION_CLASSES[label + 1], length(indices), black_pixels / total_pixels))
    end
    return counts
end

"Choose a fixed number of distinct image indices per class with a reproducible seed."
function select_fashion_samples(labels::AbstractVector{<:Integer}; samples_per_class::Int=1,
    seed::Int=42)
    samples_per_class > 0 || throw(ArgumentError("samples_per_class must be positive"))
    seed >= 0 || throw(ArgumentError("seed must be nonnegative"))

    rng = MersenneTwister(seed)
    selected = Int[]
    for label in 0:9
        candidates = findall(==(label), labels)
        length(candidates) >= samples_per_class ||
            throw(ArgumentError("Class $label has fewer than $samples_per_class images"))
        shuffle!(rng, candidates)
        append!(selected, candidates[1:samples_per_class])
    end
    return selected
end

function _fashion_svg_escape(text)
    return replace(string(text), '&' => "&amp;", '<' => "&lt;", '>' => "&gt;", '"' => "&quot;")
end

function _fashion_svg_text(io, x, y, text; size=16, anchor="start", color="#172338")
    escaped = _fashion_svg_escape(text)
    println(io, "<text x=\"$x\" y=\"$y\" font-family=\"sans-serif\" font-size=\"$size\" text-anchor=\"$anchor\" fill=\"$color\">$escaped</text>")
end

function _fashion_svg_image(io, image, x, y; scale=6)
    println(io, "<g shape-rendering=\"crispEdges\">")
    for row in axes(image, 1), column in axes(image, 2)
        value = Int(image[row, column])
        println(io, "<rect x=\"$(x + (column - 1) * scale)\" y=\"$(y + (row - 1) * scale)\" width=\"$scale\" height=\"$scale\" fill=\"rgb($value,$value,$value)\"/>")
    end
    println(io, "</g>")
end

function _fashion_sample_svg(dataset, indices)
    length(indices) == 10 || throw(ArgumentError("Expected one representative index per class"))
    width, height = 1120, 600
    return sprint() do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"#f5f7fb\"/>")
        _fashion_svg_text(io, 30, 36, "Fashion-MNIST — 10 training classes"; size=24)
        _fashion_svg_text(io, 30, 63, "Original 28×28 grayscale pixels; one seeded sample per class"; size=15)

        for label in 0:9
            index = indices[label + 1]
            dataset.labels[index] == label || throw(ArgumentError("Sample index $index is not class $label"))
            x = 30 + (label % 5) * 220
            y = 90 + (label ÷ 5) * 245
            _fashion_svg_text(io, x, y, "$label · $(FASHION_CLASSES[label + 1])"; size=17)
            _fashion_svg_image(io, @view(dataset.images[:, :, index]), x, y + 14)
            _fashion_svg_text(io, x, y + 204, "train index $index"; size=14)
        end
        println(io, "</svg>")
    end
end

"Write the class-count CSV, seeded sample indices, SVG and a short EDA summary."
function save_fashion_eda(output_dir::AbstractString, train, test; seed::Int=42)
    mkpath(output_dir)
    train_counts = fashion_class_counts(train)
    test_counts = fashion_class_counts(test)
    sample_indices = select_fashion_samples(train.labels; seed)

    open(joinpath(output_dir, "class_counts.csv"), "w") do io
        println(io, "split,label,class_name,count,black_pixel_fraction")
        for (split, counts) in (("train", train_counts), ("test", test_counts)), row in counts
            println(io, "$split,$(row.label),$(row.class_name),$(row.images),$(row.black_pixel_fraction)")
        end
    end
    open(joinpath(output_dir, "eda_sample_indices.csv"), "w") do io
        println(io, "label,class_name,train_index_1based")
        for label in 0:9
            println(io, "$label,$(FASHION_CLASSES[label + 1]),$(sample_indices[label + 1])")
        end
    end
    image_svg = _fashion_sample_svg(train, sample_indices)
    write(joinpath(output_dir, "class_samples.svg"), image_svg)

    train_black_fraction = count(iszero, train.images) / length(train.images)
    summary = """
    # Fashion-MNIST EDA

    - Train: $(size(train.images, 3)) images; $(first(train_counts).images) images/class.
    - Test: $(size(test.images, 3)) images; $(first(test_counts).images) images/class.
    - Shape: 28×28, grayscale `UInt8`, labels 0–9.
    - Zero-valued train pixels: $(round(100 * train_black_fraction; digits=2))%.
    - One sample/class selected with seed `$seed`; indices are 1-based.

    A large fraction of pixels is black background. The current EDA preserves all
    pixels and does not filter patches or make a mining decision.
    """
    write(joinpath(output_dir, "eda_summary.md"), summary)

    metadata = Dict(
        "dataset" => "Fashion-MNIST",
        "source" => FASHION_SOURCE,
        "seed" => seed,
        "julia_version" => string(VERSION),
        "train_images" => size(train.images, 3),
        "test_images" => size(test.images, 3),
        "train_black_pixel_fraction" => train_black_fraction,
    )
    open(joinpath(output_dir, "eda_metadata.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    return (; train_counts, test_counts, sample_indices, image_svg,
        image_path=joinpath(output_dir, "class_samples.svg"))
end
