<!---
This file is used to generate the project datasheet.
-->

## How it works

Two-player Pong on a VGA monitor (640×480 at 60 Hz). Two paddles, a ball
with a tapering trail of copies of itself in the same colour, a dashed
centre line and a score for each player. The first player to 9 wins; the
winner's score blinks and a new game starts.

The ball starts at 4 px per frame across and gets 1/4 px per frame faster on
every return, up to 10 px per frame. The paddles always move 3 px per frame
faster than that (7 to 13), so they keep up as a rally heats up. Both reset
after each point. Where the ball meets a paddle sets how steeply it bounces
off.

There is no frame buffer: the picture is computed on the fly as the beam
scans the screen. Everything that depends only on the current line is
worked out during horizontal blanking, so each pixel needs only a few
comparisons; the game itself advances once per frame.

## How to test

Connect a TinyVGA Pmod to the outputs and a VGA monitor, and supply a
25.175 MHz clock (25 MHz works on most monitors). Then reset.

- Plain buttons: `ui[0]`/`ui[1]` move the left paddle up/down, `ui[2]`/`ui[3]`
  the right paddle, `ui[7]` starts a new game (1 = pressed).
- Gamepad Pmod on `ui[4..6]`: controller 1's D-pad moves the right paddle,
  controller 2's D-pad the left paddle (controller 1's Select/X also move the
  left paddle), Start starts a new game.

You can also play it in the browser at https://vga-playground.com: paste in
`playground/project.v` from the project repository, turn on gamepad mode,
and use S/X (left) and the arrow keys (right).

## External hardware

- [TinyVGA Pmod](https://github.com/mole99/tiny-vga) and a VGA monitor
- Optional: [Gamepad Pmod](https://github.com/psychogenic/gamepad-pmod) with one or two SNES-style controllers, or four push buttons on `ui[0..3]`
