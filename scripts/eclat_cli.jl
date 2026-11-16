include(joinpath(@__DIR__, "..", "src", "EclatFIM.jl"))
using .EclatFIM

const USAGE = """
Usage:
  julia --project=. scripts/eclat_cli.jl --input FILE --minsup VALUE \\
      --backend set|bitvector --output FILE
"""

function parse_arguments(args)
    values = Dict{String, String}()
    supported = ("--input", "--minsup", "--backend", "--output")
    index = 1

    while index <= length(args)
        option = args[index]
        option == "--help" && (println(USAGE); exit(0))
        option in supported || throw(ArgumentError("Unknown option: $option"))
        index < length(args) || throw(ArgumentError("Missing value for $option"))
        value = args[index + 1]
        startswith(value, "--") && throw(ArgumentError("Missing value for $option"))
        values[option] = value
        index += 2
    end

    for option in supported
        haskey(values, option) || throw(ArgumentError("Missing required option: $option"))
    end

    return values
end

function main(args)
    values = parse_arguments(args)
    minsup = tryparse(Float64, values["--minsup"])
    minsup === nothing && throw(ArgumentError("--minsup must be a number"))

    backend_name = values["--backend"]
    backend_name in ("set", "bitvector") ||
        throw(ArgumentError("--backend must be set or bitvector"))

    transactions = read_spmf_transactions(values["--input"])
    result = mine(
        transactions,
        minsup;
        backend = Symbol(backend_name),
    )
    write_spmf_itemsets(values["--output"], result)
    output_path = values["--output"]
    println("Wrote $(length(result)) frequent itemsets to $output_path.")
end

try
    main(ARGS)
catch error
    println(stderr, "Error: ", sprint(showerror, error))
    println(stderr, USAGE)
    exit(1)
end
