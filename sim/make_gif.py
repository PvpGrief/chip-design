#!/usr/bin/env python3
"""Turn the simulator's PPM frames into an animated GIF (and a still PNG)."""
import argparse
import glob
import os

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("frames_dir")
ap.add_argument("gif")
ap.add_argument("--every", type=int, default=3, help="frame stride used by the simulator")
ap.add_argument("--scale", type=float, default=1.0)
ap.add_argument("--still", help="also save the last frame at full size as PNG")
args = ap.parse_args()

paths = sorted(glob.glob(os.path.join(args.frames_dir, "frame_*.ppm")))
if not paths:
    raise SystemExit(f"no frames in {args.frames_dir}")
frames = []
for p in paths:
    im = Image.open(p).convert("RGB")
    if args.scale != 1:
        im = im.resize((int(im.width * args.scale), int(im.height * args.scale)), Image.NEAREST)
    frames.append(im.quantize(colors=64, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE))
frames[0].save(args.gif, save_all=True, append_images=frames[1:],
               duration=round(1000 * args.every / 60), loop=0, optimize=True)
if args.still:
    Image.open(paths[-1]).save(args.still)
print(f"wrote {args.gif} ({len(frames)} frames)")
