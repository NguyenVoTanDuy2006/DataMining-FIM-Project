# Fashion-MNIST EDA

- Train: 60000 images; 6000 images/class.
- Test: 10000 images; 1000 images/class.
- Shape: 28×28, grayscale `UInt8`, labels 0–9.
- Zero-valued train pixels: 50.21%.
- One sample/class selected with seed `42`; indices are 1-based.

A large fraction of pixels is black background. The current EDA preserves all
pixels and does not filter patches or make a mining decision.
