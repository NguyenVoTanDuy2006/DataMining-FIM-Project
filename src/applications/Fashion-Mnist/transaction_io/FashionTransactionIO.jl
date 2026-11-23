module FashionTransactionIO

using ..FashionMNIST: parse_image_id

include("CSVFields.jl")
include("CompactJSONL.jl")
include("MiningJSONL.jl")

end # module
