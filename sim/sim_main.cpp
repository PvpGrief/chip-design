// Virtual VGA monitor for tt_um_falling_leaves.
//
// Drives the chip through its pins only: decodes hsync/vsync and the TinyVGA
// colour bits from uo_out, checks the sync timing, dumps frames as PPM and
// verifies that leaves really do fall.
//
//   ./sim_falling_leaves [--frames N] [--every K] [--out DIR]
//                        [--storm FROM:TO] [--freeze FROM:TO]

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "Vtt_um_falling_leaves.h"
#include "verilated.h"

static const int W = 640, H = 480;
static const int H_TOTAL = 800, H_SYNC = 96, H_BACK = 48;
static const int V_TOTAL = 525, V_SYNC = 2, V_BACK = 33;

struct Range {
  int from = -1, to = -1;
  bool has(int f) const { return f >= from && f < to; }
};

static Range parse_range(const char* s) {
  Range r;
  if (sscanf(s, "%d:%d", &r.from, &r.to) != 2) {
    fprintf(stderr, "bad range '%s', expected FROM:TO\n", s);
    exit(2);
  }
  return r;
}

int main(int argc, char** argv) {
  int frames = 300, every = 0;
  std::string out = "frames";
  Range storm, freeze;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--every") && i + 1 < argc) every = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--out") && i + 1 < argc) out = argv[++i];
    else if (!strcmp(argv[i], "--storm") && i + 1 < argc) storm = parse_range(argv[++i]);
    else if (!strcmp(argv[i], "--freeze") && i + 1 < argc) freeze = parse_range(argv[++i]);
    else if (argv[i][0] == '+') continue;  // verilator plusargs
    else { fprintf(stderr, "unknown argument %s\n", argv[i]); return 2; }
  }

  Verilated::commandArgs(argc, argv);
  Vtt_um_falling_leaves* dut = new Vtt_um_falling_leaves;

  auto tick = [&]() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
  };

  dut->ena = 1;
  dut->ui_in = 0;
  dut->uio_in = 0;
  dut->rst_n = 0;
  for (int i = 0; i < 10; i++) tick();
  dut->rst_n = 1;

  std::vector<unsigned char> fb(W * H * 3, 0);
  int errors = 0;
  auto fail = [&](const char* what, long got, long want) {
    if (errors++ < 10) fprintf(stderr, "FAIL: %s = %ld, expected %ld\n", what, got, want);
  };

  // Sync decoding state
  bool prev_hs = true, prev_vs = true;
  long clk = 0, last_hfall = -1, last_vfall = -1;
  long hcnt = 0;     // clocks since the last hsync falling edge
  long line = -1;    // hsync edges since the last vsync falling edge
  int frame = -1;    // completed vsyncs

  // Leaf detection: autumn-coloured pixels in the open air between the
  // canopy and the grass can only be falling leaves.
  int frames_with_leaves = 0, first_leaf_frame = -1, max_leaf_px = 0;
  long leaf_px_this_frame = 0;
  int frozen_mismatch = 0;
  long frozen_sum = 0, frozen_ref_sum = -1;

  while (frame < frames) {
    int f = frame < 0 ? 0 : frame;
    dut->ui_in = (storm.has(f) ? 1 : 0) | (freeze.has(f) ? 2 : 0);
    tick();
    clk++;
    hcnt++;

    unsigned uo = dut->uo_out;
    bool hs = (uo >> 7) & 1, vs = (uo >> 3) & 1;
    int r = ((uo >> 0) & 1) << 1 | ((uo >> 4) & 1);
    int g = ((uo >> 1) & 1) << 1 | ((uo >> 5) & 1);
    int b = ((uo >> 2) & 1) << 1 | ((uo >> 6) & 1);

    if (prev_vs && !vs) {  // start of vsync pulse = end of a frame
      if (last_vfall >= 0 && clk - last_vfall != (long)H_TOTAL * V_TOTAL)
        fail("vsync period", clk - last_vfall, (long)H_TOTAL * V_TOTAL);
      last_vfall = clk;
      if (frame >= 0) {
        if (leaf_px_this_frame > 0) {
          frames_with_leaves++;
          if (first_leaf_frame < 0) first_leaf_frame = frame;
          if (leaf_px_this_frame > max_leaf_px) max_leaf_px = leaf_px_this_frame;
        }
        if (freeze.has(frame) && freeze.has(frame - 1)) {
          if (frozen_ref_sum < 0) frozen_ref_sum = frozen_sum;
          else if (frozen_sum != frozen_ref_sum) frozen_mismatch++;
        }
        if (every > 0 && frame % every == 0) {
          char name[512];
          snprintf(name, sizeof name, "%s/frame_%05d.ppm", out.c_str(), frame);
          FILE* fp = fopen(name, "wb");
          if (!fp) { perror(name); return 1; }
          fprintf(fp, "P6\n%d %d\n255\n", W, H);
          fwrite(fb.data(), 1, fb.size(), fp);
          fclose(fp);
        }
      }
      frame++;
      line = 0;
      leaf_px_this_frame = 0;
      frozen_sum = 0;
      std::fill(fb.begin(), fb.end(), 0);
    }
    if (!prev_vs && vs) {
      if (clk - last_vfall != (long)H_TOTAL * V_SYNC)
        fail("vsync pulse width", clk - last_vfall, (long)H_TOTAL * V_SYNC);
    }
    if (prev_hs && !hs) {
      if (last_hfall >= 0 && clk - last_hfall != H_TOTAL)
        fail("hsync period", clk - last_hfall, H_TOTAL);
      last_hfall = clk;
      hcnt = 0;
      if (line >= 0) line++;
    }
    if (!prev_hs && hs) {
      if (clk - last_hfall != H_SYNC) fail("hsync pulse width", clk - last_hfall, H_SYNC);
    }
    prev_hs = hs;
    prev_vs = vs;

    int x = (int)hcnt - (H_SYNC + H_BACK);
    int y = (int)line - (V_SYNC + V_BACK);
    bool visible = line >= 0 && x >= 0 && x < W && y >= 0 && y < H;
    if (visible) {
      unsigned char* p = &fb[(y * W + x) * 3];
      p[0] = r * 85; p[1] = g * 85; p[2] = b * 85;
      bool in_air = y >= 300 && y < 390 && (x < 280 || x >= 360);
      if (in_air && r >= 2 && b == 0) leaf_px_this_frame++;
      frozen_sum += (long)(r * 16 + g * 4 + b) * (x + 1) * (y + 1) % 1000003;
    } else if (line >= 0 && (r | g | b)) {
      if (errors < 10) fprintf(stderr, "FAIL: colour during blanking at x=%d y=%d\n", x, y);
      errors++;
    }
  }

  printf("simulated %d frames (%ld clocks)\n", frames, clk);
  printf("frames with a leaf in the air: %d (first at frame %d, max %d px)\n",
         frames_with_leaves, first_leaf_frame, max_leaf_px);
  if (frames_with_leaves == 0) {
    fprintf(stderr, "FAIL: no leaf ever fell\n");
    errors++;
  }
  if (freeze.from >= 0) {
    printf("freeze check: %d changed frames while frozen\n", frozen_mismatch);
    if (frozen_mismatch) errors++;
  }
  delete dut;
  if (errors) {
    printf("FAILED with %d error(s)\n", errors);
    return 1;
  }
  printf("PASS\n");
  return 0;
}
