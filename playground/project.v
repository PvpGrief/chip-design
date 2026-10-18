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

// ---- tt_um_pvpgrief_pong.v -------------------------------------------------

// Two-player Pong on VGA (640x480 @ 60 Hz, TinyVGA Pmod), with a fading
// trail behind the ball.
//
// Controls (1 = pressed):
//   ui_in[0] / ui_in[1]  left paddle up / down
//   ui_in[2] / ui_in[3]  right paddle up / down
//   ui_in[4..6]          Gamepad Pmod (latch, clock, data):
//                          controller 1 D-pad up/down  -> right paddle
//                          controller 1 Select / X     -> left paddle up / down
//                          controller 2 D-pad up/down  -> left paddle
//                          Start (either controller)   -> new game
//   ui_in[7]             new game
module tt_um_pvpgrief_pong (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
  wire       hsync, vsync, display_on;
  wire [9:0] hpos, vpos;

  pong_vga_timing vga (
      .clk(clk),
      .rst_n(rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(display_on),
      .hpos(hpos),
      .vpos(vpos)
  );

  // ---- controls -------------------------------------------------------------
  wire [11:0] pad1, pad2;  // {b, y, select, start, up, down, left, right, a, x, l, r}

  pong_gamepad gamepad (
      .clk(clk),
      .rst_n(rst_n),
      .pmod_latch(ui_in[4]),
      .pmod_clk(ui_in[5]),
      .pmod_data(ui_in[6]),
      .pad1(pad1),
      .pad2(pad2)
  );

  wire l_up     = ui_in[0] | pad1[9] | pad2[7];  // button, Select, pad 2 up
  wire l_down   = ui_in[1] | pad1[2] | pad2[6];  // button, X, pad 2 down
  wire r_up     = ui_in[2] | pad1[7];            // button, pad 1 up
  wire r_down   = ui_in[3] | pad1[6];            // button, pad 1 down
  wire new_game = ui_in[7] | pad1[8] | pad2[8];  // button, Start

  // ---- randomness for serves: 16-bit LFSR, stepped every line ---------------
  reg [15:0] lfsr;
  always @(posedge clk) begin
    if (!rst_n)              lfsr <= 16'hACE1;
    else if (hpos == 10'd0)  lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end

  // ---- game -----------------------------------------------------------------
  wire        frame_tick = (hpos == 10'd0) && (vpos == 10'd480);
  wire        pre_tick1  = (hpos == 10'd0) && (vpos == 10'd478);
  wire        pre_tick2  = (hpos == 10'd0) && (vpos == 10'd479);
  wire [8:0]  pl_y, pr_y, ball_y;
  wire [9:0]  ball_x;
  wire [49:0] trail_x;
  wire [44:0] trail_y;
  wire [3:0]  score_l, score_r;
  wire        serving, game_over, winner_r, blink;

  pong_game game (
      .clk(clk),
      .rst_n(rst_n),
      .pre_tick1(pre_tick1),
      .pre_tick2(pre_tick2),
      .frame_tick(frame_tick),
      .new_game(new_game),
      .l_up(l_up),
      .l_down(l_down),
      .r_up(r_up),
      .r_down(r_down),
      .rnd(lfsr[2:0]),
      .pl_y(pl_y),
      .pr_y(pr_y),
      .ball_x(ball_x),
      .ball_y(ball_y),
      .trail_x(trail_x),
      .trail_y(trail_y),
      .score_l(score_l),
      .score_r(score_r),
      .serving(serving),
      .game_over(game_over),
      .winner_r(winner_r),
      .blink(blink)
  );

  // ---- picture --------------------------------------------------------------
  // Per-line data for the next line is prepared during horizontal blank
  wire       row_load  = (hpos == 10'd700);
  wire [9:0] row_y     = (vpos == 10'd524) ? 10'd0 : vpos + 10'd1;
  wire [5:0] rgb;

  pong_render render (
      .clk(clk),
      .row_load(row_load),
      .row_y(row_y),
      .en(display_on),
      .x(hpos),
      .pl_y(pl_y),
      .pr_y(pr_y),
      .ball_x(ball_x),
      .ball_y(ball_y),
      .trail_x(trail_x),
      .trail_y(trail_y),
      .ball_visible(!(serving && blink)),
      .trail_visible(!serving && !game_over),
      .score_l(score_l),
      .score_r(score_r),
      .hide_l(game_over && !winner_r && blink),
      .hide_r(game_over && winner_r && blink),
      .rgb(rgb)
  );

  // The pixel colour is registered, so delay the syncs by one clock to match
  reg hsync_r, vsync_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      hsync_r <= 1'b1;
      vsync_r <= 1'b1;
    end else begin
      hsync_r <= hsync;
      vsync_r <= vsync;
    end
  end

  // TinyVGA Pmod: {hsync, B0, G0, R0, vsync, B1, G1, R1}
  assign uo_out  = {hsync_r, rgb[0], rgb[2], rgb[4], vsync_r, rgb[1], rgb[3], rgb[5]};
  assign uio_out = 8'd0;
  assign uio_oe  = 8'd0;

  wire _unused = &{ena, uio_in, pad1[11:10], pad1[5:3], pad1[1:0],
                   pad2[11:9], pad2[5:0], lfsr[15:3], 1'b0};
endmodule

// ---- pong_game.v -----------------------------------------------------------

// Pong game logic, updated once per frame.
//
// Field: walls above y=8 and below y=472. Paddles are 10x64 at x=24 (left)
// and x=606 (right). The ball is 10x10; where it hits a paddle sets how
// steeply it bounces off. First to 9 wins.
//
// Speeds are in 1/16 px per frame. The ball starts at 4 px/frame across and
// gets 1/4 px/frame faster on every return, up to 10 px/frame. The paddles
// always move 3 px/frame faster than the ball does across (7 at the start,
// up to 13), so they keep up as a rally heats up. Both reset after a point.
//
// The last five ball positions (sampled every other frame) are kept for the
// trail drawn behind the ball.
module pong_game (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pre_tick1,   // two lines before frame_tick
    input  wire        pre_tick2,   // one line before frame_tick
    input  wire        frame_tick,
    input  wire        new_game,
    input  wire        l_up,
    input  wire        l_down,
    input  wire        r_up,
    input  wire        r_down,
    input  wire [2:0]  rnd,
    output reg  [8:0]  pl_y,       // left paddle top
    output reg  [8:0]  pr_y,       // right paddle top
    output reg  [9:0]  ball_x,     // ball top-left
    output reg  [8:0]  ball_y,
    output reg  [49:0] trail_x,    // trail position k is trail_x[10*k +: 10], newest first
    output reg  [44:0] trail_y,    // ... and trail_y[9*k +: 9]
    output reg  [3:0]  score_l,
    output reg  [3:0]  score_r,
    output wire        serving,    // ball waiting in the middle
    output wire        game_over,
    output reg         winner_r,   // who won (valid when game_over)
    output wire        blink       // ~2 Hz, for blinking things
);
  localparam [8:0] TOP      = 9'd8;
  localparam [8:0] BOTTOM   = 9'd472;
  localparam [8:0] PADDLE_H = 9'd64;
  localparam [9:0] LEFT_FACE  = 10'd34;   // right edge of the left paddle
  localparam [9:0] RIGHT_FACE = 10'd606;  // left edge of the right paddle
  localparam [9:0] BALL     = 10'd10;
  localparam [9:0] CENTER_X = 10'd315;
  localparam [8:0] CENTER_Y = 9'd235;
  localparam [8:0] PADDLE_MID = 9'd208;
  localparam [3:0] WIN      = 4'd9;

  localparam [7:0] VX_START = 8'h40;  // 4.0 px/frame (4.4 fixed point)
  localparam [7:0] VX_STEP  = 8'h04;  // +0.25 px/frame per return
  localparam [7:0] VX_MAX   = 8'hA0;  // 10.0 px/frame
  localparam [7:0] PADDLE_EXTRA = 8'h30;  // paddles: ball speed + 3.0
  localparam [12:0] PADDLE_MIN = {TOP, 4'd0};                  // 9.4 fixed point
  localparam [12:0] PADDLE_MAX = {BOTTOM - PADDLE_H, 4'd0};

  localparam [1:0] SERVE = 2'd0, PLAY = 2'd1, OVER = 2'd2;

  reg [1:0] state;
  reg [7:0] timer;
  reg [7:0] vx;          // ball speed across, 1/16 px per frame
  reg [3:0] ball_xf;     // fractional parts of the ball and paddle positions
  reg [3:0] pl_f, pr_f;
  reg       vx_left;
  reg [2:0] vy;
  reg       vy_up;
  reg       serve_left;  // direction of the next serve
  reg       trail_tick;
  reg [4:0] frames;

  assign serving   = (state == SERVE);
  assign game_over = (state == OVER);
  assign blink     = frames[4];

  // Bounce angle from where the ball meets the paddle: distance between the
  // ball's centre and the paddle's centre, /8, at least 1 and at most 6.
  /* verilator lint_off BLKSEQ */
  function [3:0] bounce;  // {up, speed}
    input [8:0] by, py;
    reg [9:0] d;
    /* verilator lint_off UNUSED */
    reg [9:0] ad;  // only ad/8 is used
    /* verilator lint_on UNUSED */
    begin
      d  = {1'b0, by} + 10'd5 - {1'b0, py} - 10'd32;
      ad = d[9] ? 10'd0 - d : d;
      if (ad[9:3] == 7'd0)      bounce = {d[9], 3'd1};
      else if (ad[9:3] > 7'd6)  bounce = {d[9], 3'd6};
      else                      bounce = {d[9], ad[5:3]};
    end
  endfunction
  /* verilator lint_on BLKSEQ */

  // The frame update is prepared on the two lines before it, in registers,
  // so this logic only runs a few times per frame (instead of being
  // continuous logic, which a cycle-based simulator evaluates every clock).
  reg [13:0] next_x;     // ball x after this frame, 10.4 fixed point
  reg [8:0] next_y;
  reg [3:0] bounce_l, bounce_r;
  reg       hits_left, hits_right, out_left, out_right;

  always @(posedge clk) begin
    if (pre_tick1) begin
      next_x   <= vx_left ? {ball_x, ball_xf} - {6'd0, vx} : {ball_x, ball_xf} + {6'd0, vx};
      next_y   <= vy_up   ? ball_y - {6'd0, vy} : ball_y + {6'd0, vy};
      bounce_l <= bounce(ball_y, pl_y);
      bounce_r <= bounce(ball_y, pr_y);
    end
    if (pre_tick2) begin
      hits_left  <= vx_left && ball_x >= LEFT_FACE && next_x[13:4] < LEFT_FACE &&
                    ball_y + 9'd10 > pl_y && ball_y < pl_y + PADDLE_H;
      hits_right <= !vx_left && ball_x + BALL <= RIGHT_FACE && next_x[13:4] + BALL > RIGHT_FACE &&
                    ball_y + 9'd10 > pr_y && ball_y < pr_y + PADDLE_H;
      out_left   <= vx_left && {ball_x, ball_xf} <= {6'd0, vx};
      out_right  <= !vx_left && {ball_x, ball_xf} + {6'd0, vx} >= {10'd630, 4'd0};
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state      <= SERVE;
      timer      <= 8'd90;
      pl_y       <= PADDLE_MID;
      pr_y       <= PADDLE_MID;
      ball_x     <= CENTER_X;
      ball_y     <= CENTER_Y;
      trail_x    <= {5{CENTER_X}};
      trail_y    <= {5{CENTER_Y}};
      vx         <= VX_START;
      ball_xf    <= 4'd0;
      pl_f       <= 4'd0;
      pr_f       <= 4'd0;
      vx_left    <= 1'b0;
      vy         <= 3'd1;
      vy_up      <= 1'b0;
      serve_left <= 1'b0;
      score_l    <= 4'd0;
      score_r    <= 4'd0;
      winner_r   <= 1'b0;
      trail_tick <= 1'b0;
      frames     <= 5'd0;
    end else if (frame_tick) begin
      frames <= frames + 5'd1;

      // Paddles move in every state
      if (l_up && !l_down)
        {pl_y, pl_f} <= ({pl_y, pl_f} > PADDLE_MIN + {5'd0, vx + PADDLE_EXTRA})
                        ? {pl_y, pl_f} - {5'd0, vx + PADDLE_EXTRA} : PADDLE_MIN;
      else if (l_down && !l_up)
        {pl_y, pl_f} <= ({pl_y, pl_f} + {5'd0, vx + PADDLE_EXTRA} < PADDLE_MAX)
                        ? {pl_y, pl_f} + {5'd0, vx + PADDLE_EXTRA} : PADDLE_MAX;
      if (r_up && !r_down)
        {pr_y, pr_f} <= ({pr_y, pr_f} > PADDLE_MIN + {5'd0, vx + PADDLE_EXTRA})
                        ? {pr_y, pr_f} - {5'd0, vx + PADDLE_EXTRA} : PADDLE_MIN;
      else if (r_down && !r_up)
        {pr_y, pr_f} <= ({pr_y, pr_f} + {5'd0, vx + PADDLE_EXTRA} < PADDLE_MAX)
                        ? {pr_y, pr_f} + {5'd0, vx + PADDLE_EXTRA} : PADDLE_MAX;

      if (new_game) begin
        state   <= SERVE;
        timer   <= 8'd60;
        score_l <= 4'd0;
        score_r <= 4'd0;
        vx      <= VX_START;
        ball_x  <= CENTER_X;
        ball_xf <= 4'd0;
        ball_y  <= CENTER_Y;
        trail_x <= {5{CENTER_X}};
        trail_y <= {5{CENTER_Y}};
      end else begin
        case (state)
          SERVE: begin
            if (timer == 8'd0) begin
              state   <= PLAY;
              vx      <= VX_START;
              vx_left <= serve_left;
              vy      <= 3'd1 + {1'b0, rnd[1:0] == 2'd3 ? 2'd2 : rnd[1:0]};
              vy_up   <= rnd[2];
            end else begin
              timer <= timer - 8'd1;
            end
          end

          PLAY: begin
            // trail: remember where the ball was, every other frame
            trail_tick <= ~trail_tick;
            if (trail_tick) begin
              trail_x <= {trail_x[39:0], ball_x};
              trail_y <= {trail_y[35:0], ball_y};
            end

            if (hits_left) begin
              ball_x  <= LEFT_FACE;
              ball_xf <= 4'd0;
              vx_left <= 1'b0;
              if (vx != VX_MAX) vx <= vx + VX_STEP;
              {vy_up, vy} <= bounce_l;
            end else if (hits_right) begin
              ball_x  <= RIGHT_FACE - BALL;
              ball_xf <= 4'd0;
              vx_left <= 1'b1;
              if (vx != VX_MAX) vx <= vx + VX_STEP;
              {vy_up, vy} <= bounce_r;
            end else if (out_left || out_right) begin
              // point to the other player; the loser receives the next serve
              if (out_left) score_r <= score_r + 4'd1;
              else          score_l <= score_l + 4'd1;
              serve_left <= out_left;
              vx         <= VX_START;
              ball_x     <= CENTER_X;
              ball_xf    <= 4'd0;
              ball_y     <= CENTER_Y;
              trail_x    <= {5{CENTER_X}};
              trail_y    <= {5{CENTER_Y}};
              if ((out_left ? score_r : score_l) == WIN - 4'd1) begin
                state    <= OVER;
                timer    <= 8'd240;
                winner_r <= out_left;
              end else begin
                state <= SERVE;
                timer <= 8'd60;
              end
            end else begin
              {ball_x, ball_xf} <= next_x;
            end

            // top and bottom walls
            if (!(out_left || out_right)) begin
              if (vy_up && next_y <= TOP) begin
                ball_y <= TOP;
                vy_up  <= 1'b0;
              end else if (!vy_up && next_y + 9'd10 >= BOTTOM) begin
                ball_y <= BOTTOM - 9'd10;
                vy_up  <= 1'b1;
              end else if (!(hits_left || hits_right)) begin
                ball_y <= next_y;
              end
            end
          end

          default: begin  // OVER: show the result for a few seconds, then start again
            if (timer == 8'd0) begin
              state   <= SERVE;
              timer   <= 8'd60;
              score_l <= 4'd0;
              score_r <= 4'd0;
            end else begin
              timer <= timer - 8'd1;
            end
          end
        endcase
      end
    end
  end
endmodule

// ---- pong_render.v ---------------------------------------------------------

// Draws the Pong screen. Everything that depends only on the line (which
// objects cross it, which row of the score digits it shows) is worked out
// once per line during horizontal blank (row_load), so each pixel only needs
// a few x comparisons.
module pong_render (
    input  wire        clk,
    input  wire        row_load,     // prepare the line row_y (during hblank)
    input  wire [9:0]  row_y,
    input  wire        en,           // draw pixel x this clock
    input  wire [9:0]  x,
    input  wire [8:0]  pl_y,
    input  wire [8:0]  pr_y,
    input  wire [9:0]  ball_x,
    input  wire [8:0]  ball_y,
    input  wire [49:0] trail_x,
    input  wire [44:0] trail_y,
    input  wire        ball_visible,
    input  wire        trail_visible,
    input  wire [3:0]  score_l,
    input  wire [3:0]  score_r,
    input  wire        hide_l,       // blink a score off
    input  wire        hide_r,
    output reg  [5:0]  rgb           // {R[1:0], G[1:0], B[1:0]}
);
  localparam [5:0] BACKGROUND = 6'b00_00_01;
  localparam [5:0] WALL       = 6'b10_10_10;
  localparam [5:0] BALL       = 6'b11_11_00;
  localparam [5:0] LEFT       = 6'b00_11_11;
  localparam [5:0] RIGHT      = 6'b11_00_11;

  // 3x5 digit font, one 3-bit row at a time (bit 2 = left column)
  function [2:0] font_row;
    input [3:0] digit;
    input [2:0] row;
    reg [14:0] g;
    begin
      case (digit)
        4'd0: g = 15'b111_101_101_101_111;
        4'd1: g = 15'b010_110_010_010_111;
        4'd2: g = 15'b111_001_111_100_111;
        4'd3: g = 15'b111_001_111_001_111;
        4'd4: g = 15'b101_101_111_001_001;
        4'd5: g = 15'b111_100_111_001_111;
        4'd6: g = 15'b111_100_111_101_111;
        4'd7: g = 15'b111_001_001_001_001;
        4'd8: g = 15'b111_101_111_101_111;
        default: g = 15'b111_101_111_001_111;
      endcase
      case (row)
        3'd0: font_row = g[14:12];
        3'd1: font_row = g[11:9];
        3'd2: font_row = g[8:6];
        3'd3: font_row = g[5:3];
        default: font_row = g[2:0];
      endcase
    end
  endfunction

  // Trail: five copies of the ball, newest first, getting smaller (8, 8, 6,
  // 6, 4 px) so they form a tapering tail in the ball's colour. Each copy is
  // inset from the ball's top-left corner so that it stays centred.

  // ---- per-line flags ---------------------------------------------------
  // Does trail copy (cy, size, inset) cross line ry?
  function copy_row;
    input [9:0] ry;
    input [8:0] cy;
    input [9:0] size, inset;
    copy_row = (ry - {1'b0, cy} - inset) < size;
  endfunction

  // Which trail copies cross line ry
  function [4:0] trail_rows;
    input [9:0] ry;
    trail_rows = {copy_row(ry, trail_y[44:36], 10'd4, 10'd3),
                  copy_row(ry, trail_y[35:27], 10'd6, 10'd2),
                  copy_row(ry, trail_y[26:18], 10'd6, 10'd2),
                  copy_row(ry, trail_y[17:9],  10'd8, 10'd1),
                  copy_row(ry, trail_y[8:0],   10'd8, 10'd1)};
  endfunction

  function trail_hits;
    input [9:0] ry;
    trail_hits = |trail_rows(ry);
  endfunction

  reg       wall_row, dash_row, pl_row, pr_row, ball_row;
  reg [4:0] trail_row;
  reg [2:0] digits_l, digits_r;
  reg       ball_line;   // the ball or any trail copy crosses this line
  reg       digit_line;  // a score digit has pixels on this line

  wire [9:0] dy_l    = row_y - {1'b0, pl_y};
  wire [9:0] dy_r    = row_y - {1'b0, pr_y};
  wire [9:0] dy_ball = row_y - {1'b0, ball_y};
  wire [9:0] dy_font = row_y - 10'd32;

  always @(posedge clk) begin
    if (row_load) begin
      wall_row <= (row_y < 10'd8) || (row_y >= 10'd472 && row_y < 10'd480);
      dash_row <= row_y[4] && row_y >= 10'd8 && row_y < 10'd472;
      pl_row   <= dy_l < 10'd64;
      pr_row   <= dy_r < 10'd64;
      ball_row <= ball_visible && dy_ball < 10'd10;
      trail_row <= trail_visible ? trail_rows(row_y) : 5'b00000;
      digits_l <= (dy_font < 10'd40 && !hide_l) ? font_row(score_l, dy_font[5:3]) : 3'b000;
      digits_r <= (dy_font < 10'd40 && !hide_r) ? font_row(score_r, dy_font[5:3]) : 3'b000;
      ball_line  <= (ball_visible && dy_ball < 10'd10) || (trail_visible && trail_hits(row_y));
      digit_line <= dy_font < 10'd40;
    end
  end

  // ---- per-pixel ----------------------------------------------------------
  /* verilator lint_off BLKSEQ */
  // Nested so that the common case (background) takes only a few tests;
  // the ball/trail and score tests only run on lines that contain them.
  // (Separate nested ifs and plain expressions, rather than one big
  // condition or function calls, so a simulator can really skip them.)
  function [5:0] pixel;
    input [9:0] px;
    begin
      pixel = BACKGROUND;
      if (wall_row) begin
        pixel = WALL;
      end else begin
        if (px < 10'd34) begin
          if (pl_row && px >= 10'd24) pixel = LEFT;
        end else if (px >= 10'd606) begin
          if (pr_row && px < 10'd616) pixel = RIGHT;
        end else begin
          if (digit_line) begin
            case (px[9:3])
              7'd32: if (digits_l[2]) pixel = LEFT;
              7'd33: if (digits_l[1]) pixel = LEFT;
              7'd34: if (digits_l[0]) pixel = LEFT;
              7'd45: if (digits_r[2]) pixel = RIGHT;
              7'd46: if (digits_r[1]) pixel = RIGHT;
              7'd47: if (digits_r[0]) pixel = RIGHT;
              default: ;
            endcase
          end
          if (dash_row && px >= 10'd318 && px < 10'd322) pixel = WALL;
        end
        // the ball and its trail go on top of everything
        if (ball_line) begin
          if ((ball_row     && px - ball_x                  < 10'd10) ||
              (trail_row[0] && px - trail_x[9:0]   - 10'd1 < 10'd8)  ||
              (trail_row[1] && px - trail_x[19:10] - 10'd1 < 10'd8)  ||
              (trail_row[2] && px - trail_x[29:20] - 10'd2 < 10'd6)  ||
              (trail_row[3] && px - trail_x[39:30] - 10'd2 < 10'd6)  ||
              (trail_row[4] && px - trail_x[49:40] - 10'd3 < 10'd4))
            pixel = BALL;
        end
      end
    end
  endfunction
  /* verilator lint_on BLKSEQ */

  always @(posedge clk) begin
    if (en) rgb <= pixel(x);
    else    rgb <= 6'd0;
  end
endmodule

// ---- pong_gamepad.v --------------------------------------------------------

// Reads the Tiny Tapeout Gamepad Pmod: two SNES-style controllers sent as a
// serial stream on latch/clock/data. 24 bits are shifted in on rising pmod_clk
// edges and taken over on a rising pmod_latch edge; controller 1 is the last
// 12 bits. A controller that isn't plugged in reads as all ones.
//
// Each pad output is {b, y, select, start, up, down, left, right, a, x, l, r}
// with 1 = pressed (all zero when the controller is missing).
module pong_gamepad (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pmod_latch,
    input  wire        pmod_clk,
    input  wire        pmod_data,
    output wire [11:0] pad1,
    output wire [11:0] pad2
);
  reg [1:0]  latch_s, clk_s, data_s;  // synchronisers
  reg        latch_prev, clk_prev;
  reg [23:0] shift, data;

  always @(posedge clk) begin
    if (!rst_n) begin
      latch_s    <= 2'b00;
      clk_s      <= 2'b00;
      data_s     <= 2'b00;
      latch_prev <= 1'b0;
      clk_prev   <= 1'b0;
      shift      <= {24{1'b1}};
      data       <= {24{1'b1}};
    end else begin
      latch_s    <= {latch_s[0], pmod_latch};
      clk_s      <= {clk_s[0], pmod_clk};
      data_s     <= {data_s[0], pmod_data};
      latch_prev <= latch_s[1];
      clk_prev   <= clk_s[1];
      if (clk_s[1] && !clk_prev) shift <= {shift[22:0], data_s[1]};
      if (latch_s[1] && !latch_prev) data <= shift;
    end
  end

  assign pad1 = (data[11:0]  == 12'hFFF) ? 12'd0 : data[11:0];
  assign pad2 = (data[23:12] == 12'hFFF) ? 12'd0 : data[23:12];
endmodule

// ---- hvsync_generator.v ----------------------------------------------------

// 640x480 @ 60 Hz VGA timing (25.175 MHz pixel clock, 25 MHz works too).
// hsync/vsync are active-low, as this mode requires.
module pong_vga_timing (
    input  wire       clk,
    input  wire       rst_n,
    output wire       hsync,
    output wire       vsync,
    output wire       display_on,
    output reg  [9:0] hpos,
    output reg  [9:0] vpos
);
  localparam [9:0] H_DISPLAY    = 10'd640;
  localparam [9:0] H_SYNC_START = 10'd656;  // + 16 front porch
  localparam [9:0] H_SYNC_END   = 10'd752;  // + 96 sync pulse
  localparam [9:0] H_MAX        = 10'd799;  // + 48 back porch - 1
  localparam [9:0] V_DISPLAY    = 10'd480;
  localparam [9:0] V_SYNC_START = 10'd490;  // + 10 front porch
  localparam [9:0] V_SYNC_END   = 10'd492;  // + 2 sync pulse
  localparam [9:0] V_MAX        = 10'd524;  // + 33 back porch - 1

  always @(posedge clk) begin
    if (!rst_n) begin
      hpos <= 10'd0;
      vpos <= 10'd0;
    end else if (hpos == H_MAX) begin
      hpos <= 10'd0;
      vpos <= (vpos == V_MAX) ? 10'd0 : vpos + 10'd1;
    end else begin
      hpos <= hpos + 10'd1;
    end
  end

  assign hsync      = ~((hpos >= H_SYNC_START) && (hpos < H_SYNC_END));
  assign vsync      = ~((vpos >= V_SYNC_START) && (vpos < V_SYNC_END));
  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);
endmodule
