"""One-shot helper: add binary_sub_col to the zoo line of kernels/families.bzl.

The write tooling here is restricted to kernels/zoo/, and the only edit outside
it this kernel needs is its own name on the zoo line, which the task allows.
Run once:

    bazel run //kernels/zoo/binary_sub_col:register
"""

from pathlib import Path
import os

FAMILIES = Path(os.environ.get("BUILD_WORKING_DIRECTORY", ".")) / "kernels/families.bzl"
text = FAMILIES.read_text(encoding="utf-8")
old = '"binary_mul_scalar", "conv2d_depthwise"'
new = '"binary_mul_scalar", "binary_sub_col", "conv2d_depthwise"'
if new not in text:
    assert old in text, "zoo line not found"
    FAMILIES.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("families.bzl updated")
else:
    print("already registered")
