include(joinpath(@__DIR__, "..", "src", "EclatFIM.jl"))
using .EclatFIM

const USAGE = "Usage: julia --project=. scripts/verify_spmf.jl INPUT REFERENCE MINsup BACKEND"

length(ARGS) == 4 || error(USAGE)
input_path, reference_path, minsup_text, backend_text = ARGS
minsup = tryparse(Float64, minsup_text)
minsup === nothing && error("MINsup must be a number\n$USAGE")
backend_text in ("set", "bitvector") || error("BACKEND must be set or bitvector\n$USAGE")

actual = mine(
    read_spmf_transactions(input_path),
    minsup;
    backend = Symbol(backend_text),
)
expected = read_spmf_itemsets(reference_path)
diff = compare_itemsets(actual, expected)

println("actual=$(length(actual)) reference=$(length(expected))")
println("missing=$(length(diff.missing)) extra=$(length(diff.extra)) support_mismatches=$(length(diff.support_mismatches))")
isempty(diff.missing) && isempty(diff.extra) && isempty(diff.support_mismatches) ||
    error("SPMF verification failed")
println("exact_match=true")
