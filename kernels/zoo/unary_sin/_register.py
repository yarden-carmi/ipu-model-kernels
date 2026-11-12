"""One-shot registration chore: name this kernel in ``kernels/families.bzl``.

The write tools only touch ``kernels/zoo/``, so this runs under Bazel and edits
the zoo line of ``KERNELS`` (the only line of that file this kernel may touch).

    bazel run //kernels/zoo/unary_sin:register
"""

import os
from pathlib import Path

FAMILIES = Path(os.environ.get("BUILD_WORKING_DIRECTORY", ".")) / "kernels/families.bzl"
text = FAMILIES.read_text()
line = '    "zoo": ['
head, rest = text.split(line, 1)
names, tail = rest.split("],", 1)
entries = [n.strip().strip('"') for n in names.split(",") if n.strip()]
if "unary_sin" not in entries:
    entries.append("unary_sin")
entries = sorted(set(entries), key=entries.index)
FAMILIES.write_text(head + line + ", ".join(f'"{e}"' for e in entries) + "]," + tail)
print("families.bzl updated")
