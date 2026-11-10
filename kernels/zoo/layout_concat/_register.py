"""One-shot registration chore: name this kernel in ``kernels/families.bzl``.

``//kernels:test_families`` requires every ``kernels/<family>/<name>/kernel.toml``
folder to appear in that file's ``KERNELS``, and Bazel cannot glob into
subpackages. The kernel-writing tool only allows writes inside the kernel's own
folder, so this helper -- run, like ``:dbg``, with ``bazel run`` -- makes the
single permitted edit outside it::

    bazel run //kernels/zoo/layout_concat:register

It appends the folder's name to ``KERNELS["zoo"]`` and prints what it changed;
it is a no-op once the name is there.
"""

import re
from pathlib import Path

FAMILY = "zoo"
KERNEL = "layout_concat"

#: The source root, as ``bazel run`` lays it out (runfiles symlink the checkout).
ROOTS = (
    Path("kernels/families.bzl"),
    Path(__file__).resolve().parents[3] / "kernels" / "families.bzl",
)


def main() -> int:
    """Add ``KERNELS["<FAMILY>"]``'s entry for this kernel; report the file."""
    for path in ROOTS:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        line = re.compile(rf'^(?P<indent>[ \t]*)"{FAMILY}": \[(?P<items>[^\]]*)\],', re.M)
        match = line.search(text)
        if match is None:
            raise SystemExit(f"{path}: no KERNELS entry for {FAMILY!r} to extend")
        items = [*re.findall(r"[A-Za-z_][A-Za-z0-9_]*", match["items"])]
        if KERNEL not in items:
            items.append(KERNEL)
        names = ", ".join(f'"{name}"' for name in sorted(items))
        replacement = f'{match["indent"]}"{FAMILY}": [{names}],'
        if replacement == match.group(0):
            print(f"{path}: {FAMILY}/{KERNEL} is already registered")
            return 0
        path.write_text(text[: match.start()] + replacement + text[match.end() :], encoding="utf-8")
        print(f"{path}: KERNELS[{FAMILY!r}] = {items}")
        return 0
    raise SystemExit("kernels/families.bzl not found from the runfiles root")


if __name__ == "__main__":
    raise SystemExit(main())
