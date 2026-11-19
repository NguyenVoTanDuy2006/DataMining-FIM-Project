using Pkg

const ROOT = dirname(@__DIR__)
const NOTEBOOK_ENV = joinpath(ROOT, "environments", "fashion_notebooks")
Pkg.activate(NOTEBOOK_ENV)
# IJulia chỉ phục vụ kernel; TC dùng môi trường project gốc và chạy trên CPU.
cd(NOTEBOOK_ENV) do
    Pkg.develop(path="../..")
end
Pkg.instantiate()
using IJulia

kernel_path = IJulia.installkernel(
    "Fashion-MNIST TC",
    "--project=$(NOTEBOOK_ENV)";
    specname="fashion-mnist-tc",
    displayname="Julia Fashion-MNIST TC",
)
println("Installed Julia kernel at: ", kernel_path)
