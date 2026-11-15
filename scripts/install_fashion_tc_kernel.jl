using Pkg

const ROOT = dirname(@__DIR__)
Pkg.activate(ROOT)
using IJulia

kernel_path = IJulia.installkernel(
    "Fashion-MNIST TC",
    "--project=$(ROOT)";
    specname="fashion-mnist-tc",
    displayname="Julia Fashion-MNIST TC",
)
println("Installed Julia kernel at: ", kernel_path)
