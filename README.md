# Falling Leaves

A small digital chip, written in Verilog, that draws a tree on a VGA monitor
and lets it drop autumn leaves at random moments. Each leaf breaks off
somewhere in the canopy, swings side to side like a pendulum on the way down,
lands on the grass, lies there for a while and dissolves into the leaf pile
under the tree.

![simulated VGA output](docs/preview.gif)

*Simulated output, decoded from the chip's pins. The storm switch is turned on partway through.*

## Try it in your browser

1. Open [vga-playground.com](https://vga-playground.com).
2. Open the `project.v` tab, select all and paste in
   [`playground/project.v`](playground/project.v) (use the *Raw* button on
   GitHub to copy it). Leave the playground's `hvsync_generator.v` tab alone.
3. The tree appears once it compiles. Click the **0** button next to
   `ui_in` above the picture to toggle the storm, and **1** to freeze (the
   number keys 0 and 1 do the same when the editor isn't focused).

The playground simulates every gate in software, and this design is much
bigger than the playground's examples, so it runs at only a few frames per
second instead of 60: the leaves fall in slow motion. It shows exactly the
same pixels as the real chip would.

`playground/project.v` is generated from `src/` by `make playground`. The
submodules are renamed there so they don't clash with the playground's own
`hvsync_generator`.

There is no frame buffer: every pixel is computed on the fly as the beam
scans the screen, so the design is pure logic plus about 450 flip-flops.

## Pins

The design uses the [Tiny Tapeout](https://tinytapeout.com) interface
(`tt_um_falling_leaves`), with video on the
[TinyVGA Pmod](https://github.com/mole99/tiny-vga) pinout.

| Pin     | Function |
|---------|----------|
| `clk`   | 25.175 MHz pixel clock (25 MHz works on most monitors) |
| `rst_n` | Active-low synchronous reset |
| `ui[0]` | **storm**: wind, grey sky, lots of leaves that blow away to the right |
| `ui[1]` | **freeze**: pause the animation |
| `uo[7:0]` | `{HSync, B0, G0, R0, VSync, B1, G1, R1}`: 640×480 @ 60 Hz, 2 bits per colour |

## How it works

```
              hpos/vpos ┌──────────────┐ scene rgb
  ┌─────────────┐  ┌───►│  tree_scene  ├──────────┐
  │ hvsync_gen  ├──┤    └──────────────┘          ▼
  │ 640x480@60  │  │    ┌──────────────┐ hit/rgb ┌─────┐   ┌──────┐
  └─────────────┘  ├───►│  leaf × 8    ├────────►│ mux ├──►│ regs ├──► uo_out
                   │    └──────▲───────┘         └─────┘   └──────┘
         frame_tick│           │ spawn, position, random bits
                   │    ┌──────┴───────┐
                   └───►│ spawner +    │◄── 32-bit LFSR (runs every clock)
                        │ LFSR         │
                        └──────────────┘
```

| File | What it does |
|------|--------------|
| [`src/tt_um_falling_leaves.v`](src/tt_um_falling_leaves.v) | Top level: LFSR, leaf spawner, cloud and leaf-pile state, pixel mux, output registers |
| [`src/hvsync_generator.v`](src/hvsync_generator.v) | VGA timing counters and sync pulses |
| [`src/leaf.v`](src/leaf.v) | One leaf: falling and swinging physics, landing, fade-out, 8×8 sprite drawn at 2× |
| [`src/tree_scene.v`](src/tree_scene.v) | Background: dithered sky, sun, drifting cloud, grassy mound, trunk, textured canopy, leaf pile |

- **Randomness.** A 32-bit maximal-length Galois LFSR steps every clock. Once
  per frame (at the start of vertical blanking) it decides how long to wait
  before the next leaf falls (30 to 157 frames, so about 0.5 to 2.6 s, or
  much faster in a storm). It also picks which part of the canopy the leaf
  starts from, the leaf's colour (orange, red, gold or russet), its starting
  swing, where it lands and how long it stays on the ground.
- **Leaves.** Eight leaf slots. Each one is a small state machine (idle,
  falling, landed) with its own position. The spawner gives a new leaf to the
  lowest free slot (`free & -free`). A falling leaf moves 2 px per frame
  through the middle of each swing and 1 px at the ends, and its sprite
  flips with each swing so it looks like it is fluttering.
- **Leaf pile.** Every leaf that finishes rotting on the grass adds to a
  4-bit `litter` counter, which sets how dense the pile of leaves around the
  trunk is drawn. The pile slowly shrinks again, and much faster in a storm.
- **Drawing.** Shapes are unions of circles. Each circle test halves the
  distance and uses a 64-entry square lookup table, so no real multipliers
  are needed. Texture comes from cheap multiply-xorshift hashes of the pixel
  position, and the sky gradient uses 4×4 ordered dithering.

## Running it

You need [Verilator](https://verilator.org), [Icarus Verilog](https://steveicarus.github.io/iverilog/),
[Yosys](https://yosyshq.net/yosys/) and Python 3 with Pillow (the last only for the GIF).

```sh
make lint    # verilator -Wall lint (clean)
make test    # Icarus testbench: 2 frames, sync timing, known pixels (~1 min)
make sim     # Verilator virtual monitor: 600 frames incl. storm + freeze checks
make gif     # re-render docs/preview.gif
make synth   # Yosys generic synthesis + cell count
make playground  # regenerate playground/project.v
```

`make sim` and `make gif` drive the chip through its pins only. The simulator
([`sim/sim_main.cpp`](sim/sim_main.cpp)) recovers the picture from the sync
pulses the way a monitor would. It checks every hsync and vsync period and
pulse width, checks that nothing is driven during blanking, checks that
leaves really appear in the air below the canopy, and checks that the
picture stays exactly still while `freeze` is held.

## Size

Generic Yosys synthesis gives about 10.8k gates and 452 flip-flops. Most of
the logic is the 13 circle tests in the scene. The `tiles: "8x2"` in
`info.yaml` is an estimate that has not been through the Tiny Tapeout
hardening flow yet. The design also fits easily on any small FPGA with a VGA
output (for example an iCE40 board with a VGA Pmod).
