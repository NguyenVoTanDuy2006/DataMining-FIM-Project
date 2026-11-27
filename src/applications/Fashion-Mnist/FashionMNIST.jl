module FashionMNIST

using ..EclatFIM: mine

export FashionTC, FashionTCSpatial, FashionMNISTEDA2, FashionFIMWorkflow, ExperimentBundleIO

const FASHION_MNIST_ROOT = @__DIR__

include("dataset/FashionMNIST.jl")
include("transaction_io/FashionTransactionIO.jl")
include("FashionTC.jl")
include("spatial/FashionTCSpatial.jl")
include("transaction_eda/FashionMNISTEDA2.jl")
include("mining/FashionFIMWorkflow.jl")
include("notebook_tools/ExperimentBundleIO.jl")

end # module FashionMNIST

# Keep the existing EclatFIM entry points for notebooks, scripts, and callers.
using .FashionMNIST: FashionTC, FashionTCSpatial, FashionMNISTEDA2, FashionFIMWorkflow,
    FashionTransactionIO, FASHION_MNIST_ROOT, FASHION_CLASSES, FASHION_FILES,
    FASHION_SOURCE, FASHION_DOWNLOAD_BASE, FASHION_DATASET_MANIFEST_SCHEMA_VERSION,
    download_fashion_mnist, read_fashion_mnist, load_fashion_mnist, format_image_id,
    parse_image_id, build_dataset_manifest, write_dataset_manifest, read_dataset_manifest,
    create_dataset_manifest, validate_dataset_manifest, new_release_run_id,
    _download_fashion_file, _verify_fashion_checksum, _read_fashion_images, _read_fashion_labels

const FashionTCv2 = FashionMNIST.FashionTC

export FASHION_CLASSES, download_fashion_mnist, read_fashion_mnist, load_fashion_mnist,
    format_image_id, parse_image_id, build_dataset_manifest, write_dataset_manifest,
    read_dataset_manifest, create_dataset_manifest, validate_dataset_manifest,
    new_release_run_id
