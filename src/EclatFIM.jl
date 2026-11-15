module EclatFIM

export mine

# Source files are included in dependency order. Implementations will define
# their public API here as the project plan is completed.
include("utils/SPMFIO.jl")
include("algorithm/EclatBaseline.jl")
include("algorithm/EclatOptimized.jl")
include("applications/Groceries.jl")
include("applications/AssociationRules.jl")
include("applications/FashionMNIST.jl")
include("applications/VisualCodebook.jl")
include("applications/VisualMining.jl")
include("applications/FashionTC.jl")

end # module EclatFIM
