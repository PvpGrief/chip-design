// Virtual VGA monitor + robot players for tt_um_pvpgrief_pong.
//
// Drives the chip through its pins only: decodes hsync/vsync and the TinyVGA
// colour bits from uo_out into frames, finds the ball, paddles and scores in
// the picture, and presses the chip's buttons (directly on ui_in[0..3] or via
// an emulated Gamepad Pmod, the same way vga-playground.com sends keys).
//
//   ./sim_pong --mode test [--out DIR --every K]   scripted checks, exit 1 on failure
//   ./sim_pong --mode demo --frames N --every K --out DIR   robots play, for the GIF
//   ./sim_pong --mode idle --frames N --every K --out DIR   nobody touches anything

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "Vtt_um_pvpgrief_pong.h"
#include "verilated.h"

static const int W = 640, H = 480;
static const int H_TOTAL = 800, H_SYNC = 96, H_BACK = 48;
static const int V_TOTAL = 525, V_SYNC = 2, V_BACK = 33;

// Gamepad Pmod key bits, as the playground numbers them
enum { GP_B = 0, GP_Y, GP_SELECT, GP_START, GP_UP, GP_DOWN, GP_LEFT, GP_RIGHT, GP_A, GP_X, GP_L, GP_R };

struct Frame {
  std::vector<unsigned char> rgb = std::vector<unsigned char>(W * H * 3, 0);
  int r(int x, int y) const { return rgb[(y * W + x) * 3] / 85; }
  int g(int x, int y) const { return rgb[(y * W + x) * 3 + 1] / 85; }
  int b(int x, int y) const { return rgb[(y * W + x) * 3 + 2] / 85; }
  bool is(int x, int y, int R, int G, int B) const {
    return x >= 0 && x < W && y >= 0 && y < H && r(x, y) == R && g(x, y) == G && b(x, y) == B;
  }
  bool yellow(int x, int y) const { return is(x, y, 3, 3, 0); }
};

struct Seen {
  int ball_x = -1, ball_y = -1;  // top-left of the 10x10 ball, -1 if not visible
  int pl_y = -1, pr_y = -1;      // paddle tops
  int score_l = -1, score_r = -1;
  int trail_px = 0;              // yellow pixels that aren't the ball
};

static int read_digit(const Frame& f, int x0, int R, int G, int B) {
  static const int font[10] = {0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9,
                               0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF};
  int bits = 0;
  for (int r = 0; r < 5; r++)
    for (int c = 0; c < 3; c++)
      bits = bits << 1 | (f.is(x0 + 4 + 8 * c, 36 + 8 * r, R, G, B) ? 1 : 0);
  for (int d = 0; d < 10; d++)
    if (font[d] == bits) return d;
  return -1;
}

static Seen analyse(const Frame& f) {
  Seen s;
  int yellow_total = 0;
  for (int y = 0; y < H; y++)
    for (int x = 0; x < W; x++) {
      if (!f.yellow(x, y)) continue;
      yellow_total++;
      // the ball is the only fully yellow 10x10 square (trail copies are at most 8x8)
      if (s.ball_x < 0) {
        bool full = true;
        for (int dy = 0; dy < 10 && full; dy++)
          for (int dx = 0; dx < 10 && full; dx++) full = f.yellow(x + dx, y + dy);
        if (full) { s.ball_x = x; s.ball_y = y; }
      }
    }
  s.trail_px = yellow_total - (s.ball_x >= 0 ? 100 : 0);
  for (int y = 8; y < 472; y++) {
    if (s.pl_y < 0 && f.is(28, y, 0, 3, 3)) s.pl_y = y;
    if (s.pr_y < 0 && f.is(610, y, 3, 0, 3)) s.pr_y = y;
  }
  s.score_l = read_digit(f, 256, 0, 3, 3);
  s.score_r = read_digit(f, 360, 3, 0, 3);
  return s;
}

// Robot player: keep the paddle's centre on the ball. Returns {up, down}.
// `lazy` makes it move away from the ball instead (to lose points on purpose).
static void robot(const Seen& s, int paddle_y, bool lazy, int reach, bool& up, bool& down) {
  up = down = false;
  if (paddle_y < 0) return;
  int target = 240;
  if (s.ball_y >= 0) target = s.ball_y + 5;
  int centre = paddle_y + 32;
  if (lazy) { up = target > 240; down = !up; return; }
  if (centre > target + reach) up = true;
  if (centre < target - reach) down = true;
}

int main(int argc, char** argv) {
  std::string mode = "test", out = "frames";
  int frames = 2100, every = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--mode") && i + 1 < argc) mode = argv[++i];
    else if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--every") && i + 1 < argc) every = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--out") && i + 1 < argc) out = argv[++i];
    else if (argv[i][0] == '+') continue;
    else { fprintf(stderr, "unknown argument %s\n", argv[i]); return 2; }
  }
  const bool test = mode == "test";
  if (test) frames = 2100;

  Verilated::commandArgs(argc, argv);
  Vtt_um_pvpgrief_pong* dut = new Vtt_um_pvpgrief_pong;
  auto tick = [&]() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); };

  dut->ena = 1;
  dut->ui_in = 0;
  dut->uio_in = 0;
  dut->rst_n = 0;
  for (int i = 0; i < 10; i++) tick();
  dut->rst_n = 1;

  int errors = 0;
  auto fail = [&](const char* fmt, long a, long b) {
    if (errors++ < 20) { fprintf(stderr, "FAIL: "); fprintf(stderr, fmt, a, b); fprintf(stderr, "\n"); }
  };

  Frame fb;
  Seen seen;
  unsigned buttons = 0;  // ui_in[0..3], [7]
  unsigned gamepad = 0;  // emulated Gamepad Pmod keys
  long gp_counter = 0;
  unsigned gp_pins = 0;

  bool prev_hs = true, prev_vs = true;
  long clk = 0, last_hfall = -1, last_vfall = -1, hcnt = 0, line = -1;
  int frame = -1;

  // statistics
  int bounces = 0, last_dir = 0, prev_ball_x = -1, frames_with_trail = 0;
  int left_wins_seen = 0;
  int prev_pr_y = -1, first_paddle_step = -1;
  int ball_speed_early = 0, ball_speed_late = 0, paddle_step_late = 0, prev_pl_y = -1;

  while (frame < frames) {
    dut->ui_in = (buttons & 0x8F) | gp_pins;
    tick();
    clk++;
    hcnt++;

    unsigned uo = dut->uo_out;
    bool hs = (uo >> 7) & 1, vs = (uo >> 3) & 1;
    int r = ((uo >> 0) & 1) << 1 | ((uo >> 4) & 1);
    int g = ((uo >> 1) & 1) << 1 | ((uo >> 5) & 1);
    int b = ((uo >> 2) & 1) << 1 | ((uo >> 6) & 1);

    if (prev_vs && !vs) {  // a frame is complete
      if (last_vfall >= 0 && clk - last_vfall != (long)H_TOTAL * V_TOTAL)
        fail("vsync period %ld, expected %ld", clk - last_vfall, (long)H_TOTAL * V_TOTAL);
      last_vfall = clk;
      if (frame >= 0) {
        seen = analyse(fb);
        if (every > 0 && frame % every == 0) {
          char name[512];
          snprintf(name, sizeof name, "%s/frame_%05d.ppm", out.c_str(), frame);
          FILE* fp = fopen(name, "wb");
          if (!fp) { perror(name); return 1; }
          fprintf(fp, "P6\n%d %d\n255\n", W, H);
          fwrite(fb.rgb.data(), 1, fb.rgb.size(), fp);
          fclose(fp);
        }
        // count paddle bounces: the ball reverses horizontally near a paddle
        if (seen.ball_x >= 0 && prev_ball_x >= 0) {
          int dir = seen.ball_x > prev_ball_x ? 1 : seen.ball_x < prev_ball_x ? -1 : 0;
          if (dir && last_dir && dir != last_dir && (seen.ball_x < 80 || seen.ball_x > 540)) bounces++;
          if (dir) last_dir = dir;
        }
        // speeds, measured from the picture: ball pixels per frame across, paddle steps
        if (test && seen.ball_x >= 0 && prev_ball_x >= 0) {
          int d = abs(seen.ball_x - prev_ball_x);
          if (d < 40) {  // ignore re-serves
            if (frame >= 345 && frame < 600) ball_speed_early = std::max(ball_speed_early, d);
            if (frame >= 1200 && frame < 1500) ball_speed_late = std::max(ball_speed_late, d);
          }
        }
        if (test && frame == 101 && prev_pr_y >= 0) first_paddle_step = prev_pr_y - seen.pr_y;
        if (test && frame >= 1200 && frame < 1500 && prev_pl_y >= 0 && seen.pl_y >= 0)
          paddle_step_late = std::max(paddle_step_late, abs(seen.pl_y - prev_pl_y));
        prev_pr_y = seen.pr_y;
        prev_pl_y = seen.pl_y;
        prev_ball_x = seen.ball_x;
        if (seen.trail_px > 0) frames_with_trail++;

        // ---- choose inputs for the next frame ----
        int f = frame + 1;
        buttons = 0;
        gamepad = 0;
        bool lu, ld, ru, rd;
        if (mode == "idle") {
          // no inputs at all
        } else if (!test) {
          robot(seen, seen.pl_y, false, 4, lu, ld);
          // the right robot is slower (moves every other frame) and only reacts
          // once the ball is in its half, so it misses now and then
          robot(seen, seen.pr_y, false, 6, ru, rd);
          if ((seen.ball_x >= 0 && seen.ball_x < 330) || frame % 2) ru = rd = false;
          buttons = lu | ld << 1 | ru << 2 | rd << 3;
        } else {
          auto expect = [&](const char* what, int got, int want) {
            if (got != want) { fprintf(stderr, "FAIL (frame %d): %s = %d, expected %d\n", frame, what, got, want); errors++; }
            else printf("ok   (frame %d): %s = %d\n", frame, what, got);
          };
          if (frame == 99) {
            expect("left paddle at start", seen.pl_y, 208);
            expect("right paddle at start", seen.pr_y, 208);
            expect("left score", seen.score_l, 0);
            expect("right score", seen.score_r, 0);
          }
          if (frame == 159) {
            expect("right paddle after ui_in[2] (up)", seen.pr_y, 8);
            expect("left paddle after ui_in[1] (down)", seen.pl_y, 408);
          }
          if (frame == 244) {
            expect("right paddle after gamepad Down arrow", seen.pr_y, 408);
            expect("left paddle after gamepad S (Select)", seen.pl_y, 8);
          }
          if (frame == 329) {
            expect("right paddle after gamepad Up arrow", seen.pr_y, 8);
            expect("left paddle after gamepad X", seen.pl_y, 408);
          }
          if (frame == 345) {
            expect("left score after new game", seen.score_l, 0);
            expect("right score after new game", seen.score_r, 0);
            bounces = 0;
          }
          if (frame == 1499) {
            expect("left score after robot rally", seen.score_l, 0);
            expect("right score after robot rally", seen.score_r, 0);
            printf("     paddle bounces in the rally: %d, frames with a visible trail: %d\n", bounces, frames_with_trail);
            if (bounces < 8) { fprintf(stderr, "FAIL: only %d paddle bounces\n", bounces); errors++; }
            if (frames_with_trail < 500) { fprintf(stderr, "FAIL: trail rarely visible\n"); errors++; }
            expect("paddle speed at the start (px/frame)", first_paddle_step, 7);
            printf("     ball speed early in the rally: %d px/frame, late: %d px/frame\n", ball_speed_early, ball_speed_late);
            printf("     paddle speed late in the rally: up to %d px/frame\n", paddle_step_late);
            if (ball_speed_late <= ball_speed_early) { fprintf(stderr, "FAIL: ball did not speed up\n"); errors++; }
            if (paddle_step_late <= 7) { fprintf(stderr, "FAIL: paddles did not speed up\n"); errors++; }
          }
          if (frame >= 1500 && seen.score_l >= 1 && seen.score_r == 0) left_wins_seen++;

          if (f >= 100 && f < 160) buttons = 0x4 | 0x2;                       // right up, left down
          else if (f >= 160 && f < 245) gamepad = 1 << GP_DOWN | 1 << GP_SELECT;
          else if (f >= 245 && f < 330) gamepad = 1 << GP_UP | 1 << GP_X;
          else if (f >= 330 && f < 340) buttons = 0x80;                       // new game
          else if (f >= 340) {
            robot(seen, seen.pl_y, false, 4, lu, ld);
            robot(seen, seen.pr_y, f >= 1500, 4, ru, rd);                    // right robot gives up
            buttons = lu | ld << 1 | ru << 2 | rd << 3;
          }
        }
      }
      frame++;
      line = 0;
      std::fill(fb.rgb.begin(), fb.rgb.end(), 0);
    }
    if (!prev_vs && vs && clk - last_vfall != (long)H_TOTAL * V_SYNC)
      fail("vsync pulse width %ld, expected %ld", clk - last_vfall, (long)H_TOTAL * V_SYNC);
    if (prev_hs && !hs) {
      if (last_hfall >= 0 && clk - last_hfall != H_TOTAL)
        fail("hsync period %ld, expected %ld", clk - last_hfall, H_TOTAL);
      last_hfall = clk;
      hcnt = 0;
      if (line >= 0) line++;
      // Gamepad Pmod emulation, one step per line like vga-playground.com
      long cycle = gp_counter++ % 400;
      unsigned long data_reg = (unsigned long)gamepad << 12;
      int clock = cycle < 48 ? cycle % 2 : 0;
      int index = cycle < 49 ? (int)(cycle >> 1) : 0;
      int data = (data_reg >> index) & 1;
      int latch = cycle == 49;
      gp_pins = data << 6 | clock << 5 | latch << 4;
    }
    if (!prev_hs && hs && clk - last_hfall != H_SYNC)
      fail("hsync pulse width %ld, expected %ld", clk - last_hfall, H_SYNC);
    prev_hs = hs;
    prev_vs = vs;

    int x = (int)hcnt - (H_SYNC + H_BACK);
    int y = (int)line - (V_SYNC + V_BACK);
    if (line >= 0 && x >= 0 && x < W && y >= 0 && y < H) {
      unsigned char* p = &fb.rgb[(y * W + x) * 3];
      p[0] = r * 85; p[1] = g * 85; p[2] = b * 85;
    } else if (line >= 0 && (r | g | b)) {
      if (errors++ < 20) fprintf(stderr, "FAIL: colour during blanking at x=%d y=%d\n", x, y);
    }
  }

  if (test) {
    printf("     frames after 1500 where the left robot leads: %d\n", left_wins_seen);
    if (left_wins_seen == 0) { fprintf(stderr, "FAIL: left robot never scored against the lazy right robot\n"); errors++; }
  }
  printf("simulated %d frames (%ld clocks)\n", frames, clk);
  delete dut;
  if (errors) { printf("FAILED with %d error(s)\n", errors); return 1; }
  printf("PASS\n");
  return 0;
}
