# SPDX-License-Identifier: Apache-2.0
#
# cocotb test for the Pong chip. Reads the VGA picture straight off the
# output pins: waits for hsync pulses to find a line, then counts clocks to
# find a pixel, and checks a few known spots of the opening screen.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge
from cocotb.utils import get_sim_time

H_TOTAL = 800
PIXEL_OFFSET = 144  # clocks from the start of an hsync pulse to pixel 0 of the next line

BACKGROUND = (0, 0, 1)
WALL = (2, 2, 2)
BALL = (3, 3, 0)
LEFT = (0, 3, 3)
RIGHT = (3, 0, 3)


def rgb(dut):
    """Decode the TinyVGA Pmod colour bits: uo_out = {HS, B0, G0, R0, VS, B1, G1, R1}."""
    uo = int(dut.uo_out.value)
    r = (uo & 1) << 1 | (uo >> 4) & 1
    g = ((uo >> 1) & 1) << 1 | (uo >> 5) & 1
    b = ((uo >> 2) & 1) << 1 | (uo >> 6) & 1
    return (r, g, b)


async def reset(dut, ui_in=0):
    clock = Clock(dut.clk, 40, unit="ns")  # 25 MHz
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = ui_in
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1


async def read_pixels(dut, spots, lines_before=0):
    """Colours at (x, y) spots of the frame that starts next.

    Call right after reset (lines_before=0: the first hsync pulse belongs to
    line 0) or right after a vsync pulse starts (lines_before=35: 35 more
    blanking lines come before line 0).
    """
    found = {}
    line = -lines_before  # index of the next line to be drawn
    by_line = {}
    for x, y in spots:
        by_line.setdefault(y, []).append(x)
    for y in sorted(by_line):
        while line < y:
            await FallingEdge(dut.hsync)
            line += 1
        # now at the start of the hsync pulse just before line y
        clocks = PIXEL_OFFSET
        for x in sorted(by_line[y]):
            await ClockCycles(dut.clk, clocks + x)
            found[(x, y)] = rgb(dut)
            clocks = -x  # next wait is relative to this pixel
    return found


@cocotb.test()
async def test_sync_timing(dut):
    """hsync repeats every 800 clocks."""
    await reset(dut)
    await FallingEdge(dut.hsync)
    t0 = get_sim_time("ns")
    await FallingEdge(dut.hsync)
    t1 = get_sim_time("ns")
    assert round((t1 - t0) / 40) == H_TOTAL, f"hsync period {(t1 - t0) / 40} clocks"


@cocotb.test()
async def test_opening_screen(dut):
    """Walls, paddles, ball, centre line and scores of the opening screen."""
    await reset(dut)
    expected = {
        (100, 4): ("top wall", WALL),
        (100, 100): ("background", BACKGROUND),
        (260, 36): ("left score", LEFT),
        (268, 52): ("inside of the 0", BACKGROUND),
        (364, 36): ("right score", RIGHT),
        (320, 20): ("centre line", WALL),
        (28, 240): ("left paddle", LEFT),
        (320, 240): ("ball", BALL),
        (610, 240): ("right paddle", RIGHT),
        (100, 475): ("bottom wall", WALL),
    }
    seen = await read_pixels(dut, list(expected))
    for spot, (what, colour) in expected.items():
        dut._log.info(f"{what:16s} at {spot}: {seen[spot]}")
        assert seen[spot] == colour, f"{what} at {spot} is {seen[spot]}, expected {colour}"


@cocotb.test()
async def test_paddle_moves(dut):
    """Holding 'right paddle up' (ui_in[2]) for one frame moves the paddle up 7 px."""
    await reset(dut, ui_in=0b0000_0100)
    await FallingEdge(dut.vsync)  # the paddles move once per frame, just before vsync
    dut.ui_in.value = 0
    # The paddle started at y=208 (rows 208..271) and moves 7 px per frame,
    # so the next frame shows it at rows 201..264.
    seen = await read_pixels(dut, [(610, 203), (610, 268)], lines_before=35)
    assert seen[(610, 203)] == RIGHT, f"paddle not at row 203: {seen[(610, 203)]}"
    assert seen[(610, 268)] == BACKGROUND, f"paddle still at row 268: {seen[(610, 268)]}"
