module FashionFIMWorkflow

using SHA
using ..FashionTransactionIO: parse_mining_record

export FIMInput, load_transactions

include("TransactionInput.jl")

end # module
