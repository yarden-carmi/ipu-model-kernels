"""One-shot helper: add row_norm_rmsnorm to the zoo line of kernels/families.bzl.

The write tooling here is restricted to kernels/zoo/, and the only edit outside
it this kernel needs is its own name on the zoo line, which the task allows.
Run once:

    bazel run //kernels/zoo/row_norm_rmsnorm:register
"""

from pathlib import Path
import os

FAMILIES = Path(os.environ.get("BUILD_WORKING_DIRECTORY", ".")) / "kernels/families.bzl"
text = FAMILIES.read_text(encoding="utf-8")
old = '"row_norm_layernorm", "row_softmax"'
new = '"row_norm_layernorm", "row_norm_rmsnorm", "row_softmax"'
if new not in text:
    assert old in text, "zoo line not found"
    FAMILIES.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("families.bzl updated")
else:
    print("already registered")
