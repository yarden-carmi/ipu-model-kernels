"""Removed: the temporary chain-failure debugger (its finding lives on in
row_softmax.asm's pass-2 comment and kernelgen.toml's notes -- pass 2's two
multiplies per chunk must read the chunk's own R_CYCLIC slot, which the
alternating slot 0 / slot 128 stream provides; run the chain checks with

    bazel test //kernels/zoo/row_softmax
"""
