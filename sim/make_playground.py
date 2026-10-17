#!/usr/bin/env python3
"""Bundle src/*.v into one file for https://vga-playground.com.

The playground compiles everything in the project together and always ships
its own hvsync_generator.v, so the submodules get unique names here.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ["tt_um_falling_leaves.v", "leaves.v", "tree_scene.v", "hvsync_generator.v"]
RENAMES = [
    ("module hvsync_generator (", "module falling_leaves_vga_timing ("),
    ("hvsync_generator vga (", "falling_leaves_vga_timing vga ("),
    ("module leaves #(", "module falling_leaves_leaves #("),
    ("leaves #(.N(8)) u_leaves (", "falling_leaves_leaves #(.N(8)) u_leaves ("),
    ("module tree_scene (", "module falling_leaves_scene ("),
    ("tree_scene scene (", "falling_leaves_scene scene ("),
]

HEADER = """\
// Falling Leaves: a VGA tree that drops autumn leaves at random.
// https://github.com/PvpGrief/chip-design
//
// Single-file bundle for https://vga-playground.com: paste this over
// project.v. Generated from src/ by sim/make_playground.py; don't edit by hand.
//
//   ui_in[0]  storm:  wind, grey sky and lots of leaves
//   ui_in[1]  freeze: pause the animation

`default_nettype none
"""

body = []
for name in FILES:
    text = (ROOT / "src" / name).read_text()
    text = text.replace("`default_nettype none\n", "").strip("\n")
    body.append(f"// ---- {name} " + "-" * (70 - len(name)) + "\n\n" + text + "\n")
out = HEADER + "\n" + "\n".join(body)
for old, new in RENAMES:
    if out.count(old) != 1:
        sys.exit(f"expected exactly one '{old}' in the sources")
    out = out.replace(old, new)

dest = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "playground" / "project.v"
dest.write_text(out)
print(f"wrote {dest.relative_to(ROOT) if dest.is_relative_to(ROOT) else dest}")
