#!/usr/bin/env python3
"""Bundle src/*.v into one file for https://vga-playground.com.

The design is a single module, so this only adds a header with the
playground instructions.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ["tt_um_pvpgrief_pong.v"]
RENAMES = []

HEADER = """\
// Two-player Pong with a ball trail.
// https://github.com/PvpGrief/chip-design
//
// Single-file bundle for https://vga-playground.com: paste this over
// project.v. Generated from src/ by sim/make_playground.py; don't edit by hand.
//
// Turn on the playground's gamepad mode (gamepad button next to ui_in), then:
//   left player:  S = up, X = down
//   right player: arrow up / arrow down
//   T (Start):    new game

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
