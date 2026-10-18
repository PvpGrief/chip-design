`default_nettype none

// Two-player Pong on VGA (640x480 @ 60 Hz, TinyVGA Pmod), with a trail
// behind the ball. The ball gets a little faster on every return and the
// paddles speed up with it. First to 9 wins.
//
// The whole design is this one module (no submodules), so tools that look
// for the Tiny Tapeout ports on "the" module always find them. It is kept
// small enough for 1x2 Tiny Tapeout tiles.
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

  // ===========================================================================
  // VGA timing: 640x480 @ 60 Hz, active-low syncs
  // ===========================================================================
  localparam [9:0] H_DISPLAY    = 10'd640;
  localparam [9:0] H_SYNC_START = 10'd656;  // + 16 front porch
  localparam [9:0] H_SYNC_END   = 10'd752;  // + 96 sync pulse
  localparam [9:0] H_MAX        = 10'd799;  // + 48 back porch - 1
  localparam [9:0] V_DISPLAY    = 10'd480;
  localparam [9:0] V_SYNC_START = 10'd490;  // + 10 front porch
  localparam [9:0] V_SYNC_END   = 10'd492;  // + 2 sync pulse
  localparam [9:0] V_MAX        = 10'd524;  // + 33 back porch - 1

  reg [9:0] hpos, vpos;

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

  wire hsync      = ~((hpos >= H_SYNC_START) && (hpos < H_SYNC_END));
  wire vsync      = ~((vpos >= V_SYNC_START) && (vpos < V_SYNC_END));
  wire display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

  // Once per frame the game advances (at the start of vertical blank).
  // Per-line drawing data is prepared during horizontal blank for the next
  // line.
  wire       frame_tick = (hpos == 10'd0) && (vpos == 10'd480);
  wire       row_load   = (hpos == 10'd700);
  wire [9:0] row_y      = (vpos == V_MAX) ? 10'd0 : vpos + 10'd1;

  // ===========================================================================
  // Controls: buttons and the Gamepad Pmod
  // ===========================================================================
  // The Gamepad Pmod sends two SNES-style controllers as a serial stream on
  // latch/clock/data: 24 bits shifted in on rising clock edges, taken over
  // on a rising latch edge; controller 1 is the last 12 bits. A controller
  // that isn't plugged in reads as all ones. Pad bits:
  // {b, y, select, start, up, down, left, right, a, x, l, r}, 1 = pressed.
  // Only the buttons the game uses are kept (and zeroed for a missing pad).
  reg [1:0]  gp_latch_s, gp_clk_s, gp_data_s;  // synchronisers
  reg        gp_latch_prev, gp_clk_prev;
  reg [23:0] gp_shift;
  reg [4:0]  pad1;  // {select, start, up, down, x}
  reg [2:0]  pad2;  // {start, up, down}

  wire pad1_present = (gp_shift[11:0]  != 12'hFFF);
  wire pad2_present = (gp_shift[23:12] != 12'hFFF);

  always @(posedge clk) begin
    if (!rst_n) begin
      gp_latch_s    <= 2'b00;
      gp_clk_s      <= 2'b00;
      gp_data_s     <= 2'b00;
      gp_latch_prev <= 1'b0;
      gp_clk_prev   <= 1'b0;
      gp_shift      <= {24{1'b1}};
      pad1          <= 5'd0;
      pad2          <= 3'd0;
    end else begin
      gp_latch_s    <= {gp_latch_s[0], ui_in[4]};
      gp_clk_s      <= {gp_clk_s[0], ui_in[5]};
      gp_data_s     <= {gp_data_s[0], ui_in[6]};
      gp_latch_prev <= gp_latch_s[1];
      gp_clk_prev   <= gp_clk_s[1];
      if (gp_clk_s[1] && !gp_clk_prev) gp_shift <= {gp_shift[22:0], gp_data_s[1]};
      if (gp_latch_s[1] && !gp_latch_prev) begin
        pad1 <= pad1_present ? {gp_shift[9:6], gp_shift[2]} : 5'd0;
        pad2 <= pad2_present ? gp_shift[20:18] : 3'd0;
      end
    end
  end

  wire l_up     = ui_in[0] | pad1[4] | pad2[1];  // button, Select, pad 2 up
  wire l_down   = ui_in[1] | pad1[0] | pad2[0];  // button, X, pad 2 down
  wire r_up     = ui_in[2] | pad1[2];            // button, pad 1 up
  wire r_down   = ui_in[3] | pad1[1];            // button, pad 1 down
  wire new_game = ui_in[7] | pad1[3] | pad2[2];  // button, Start

  // Randomness for serves: 8-bit LFSR, stepped every line
  reg [7:0] lfsr;
  always @(posedge clk) begin
    if (!rst_n)              lfsr <= 8'hA5;
    else if (hpos == 10'd0)  lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
  end

  // ===========================================================================
  // Game, updated once per frame
  // ===========================================================================
  // Field: walls above y=8 and below y=472. Paddles are 10x64 at x=24 (left)
  // and x=606 (right). The ball is 10x10; where it hits a paddle sets how
  // steeply it bounces off.
  //
  // Speeds are in 1/4 px per frame. The ball starts at 4 px/frame across and
  // gets 1/4 px/frame faster on every return, up to 10 px/frame. The paddles
  // always move 3 px/frame faster than the ball does across (7 at the start,
  // up to 13), so they keep up as a rally heats up. Both reset after a point.
  localparam [8:0] TOP        = 9'd8;
  localparam [8:0] BOTTOM     = 9'd472;
  localparam [8:0] PADDLE_H   = 9'd64;
  localparam [9:0] LEFT_FACE  = 10'd34;   // right edge of the left paddle
  localparam [9:0] RIGHT_FACE = 10'd606;  // left edge of the right paddle
  localparam [9:0] BALL_SIZE  = 10'd10;
  localparam [9:0] CENTER_X   = 10'd315;
  localparam [8:0] CENTER_Y   = 9'd235;
  localparam [8:0] PADDLE_MID = 9'd208;
  localparam [3:0] WIN        = 4'd9;

  localparam [5:0]  VX_START     = 6'd16;  // 4.0 px/frame (4.2 fixed point)
  localparam [5:0]  VX_STEP      = 6'd1;   // +0.25 px/frame per return
  localparam [5:0]  VX_MAX       = 6'd40;  // 10.0 px/frame
  localparam [5:0]  PADDLE_EXTRA = 6'd12;  // paddles: ball speed + 3.0
  localparam [10:0] PADDLE_MIN   = {TOP, 2'd0};             // 9.2 fixed point
  localparam [10:0] PADDLE_MAX   = {BOTTOM - PADDLE_H, 2'd0};

  localparam [1:0] SERVE = 2'd0, PLAY = 2'd1, OVER = 2'd2;

  reg [1:0]  state;
  reg [7:0]  timer;
  reg [8:0]  pl_y, pr_y;    // paddle tops
  reg [1:0]  pl_f, pr_f;    // ... and their fractional parts
  reg [9:0]  ball_x;        // ball top-left
  reg [1:0]  ball_xf;
  reg [8:0]  ball_y;
  reg [5:0]  vx;            // ball speed across, 1/4 px per frame
  reg        vx_left;
  reg [2:0]  vy;            // ball speed up/down, px per frame
  reg        vy_up;
  reg        serve_left;    // direction of the next serve
  reg [3:0]  score_l, score_r;
  reg        winner_r;      // who won (valid in OVER)
  reg [4:0]  frames;
  reg        trail_tick;
  // The trail shows where the ball was 2, 4, ... 10 frames ago. Between
  // bounces the ball moves in a straight line, so those positions are
  // worked out from its speed instead of being stored; after a bounce the
  // trail starts again and grows back one copy every other frame.
  reg [2:0]  trail_len;     // how many trail copies are valid (0..5)

  wire serving   = (state == SERVE);
  wire game_over = (state == OVER);
  wire blink     = frames[4];  // ~2 Hz

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

  // Ball position after this frame (10.2 fixed point), and what happens on
  // the way. Only used at frame_tick.
  wire [11:0] next_x = vx_left ? {ball_x, ball_xf} - {6'd0, vx} : {ball_x, ball_xf} + {6'd0, vx};
  wire [8:0]  next_y = vy_up   ? ball_y - {6'd0, vy} : ball_y + {6'd0, vy};
  // only the paddle the ball is heading for matters
  wire [8:0] facing_y   = vx_left ? pl_y : pr_y;
  wire       facing_hit = ball_y + 9'd10 > facing_y && ball_y < facing_y + PADDLE_H;
  wire hits_left  = vx_left && ball_x >= LEFT_FACE && next_x[11:2] < LEFT_FACE && facing_hit;
  wire hits_right = !vx_left && ball_x + BALL_SIZE <= RIGHT_FACE && next_x[11:2] + BALL_SIZE > RIGHT_FACE &&
                    facing_hit;
  wire out_left   = vx_left && {ball_x, ball_xf} <= {6'd0, vx};
  wire out_right  = !vx_left && {ball_x, ball_xf} + {6'd0, vx} >= {10'd630, 2'd0};
  wire hits_top    = vy_up && next_y <= TOP;
  wire [3:0] bounce_dir = bounce(ball_y, facing_y);
  wire hits_bottom = !vy_up && next_y + 9'd10 >= BOTTOM;

  // A paddle (9.2 fixed point) after one frame of up/down at speed s
  function [10:0] move_paddle;
    input [10:0] p;
    input        up, down;
    input [5:0]  s;
    begin
      if (up && !down)      move_paddle = (p > PADDLE_MIN + {5'd0, s}) ? p - {5'd0, s} : PADDLE_MIN;
      else if (down && !up) move_paddle = (p + {5'd0, s} < PADDLE_MAX) ? p + {5'd0, s} : PADDLE_MAX;
      else                  move_paddle = p;
    end
  endfunction

  wire [5:0] paddle_speed = vx + PADDLE_EXTRA;

  always @(posedge clk) begin
    if (!rst_n) begin
      state      <= SERVE;
      timer      <= 8'd90;
      pl_y       <= PADDLE_MID;
      pr_y       <= PADDLE_MID;
      pl_f       <= 2'd0;
      pr_f       <= 2'd0;
      ball_x     <= CENTER_X;
      ball_xf    <= 2'd0;
      ball_y     <= CENTER_Y;
      trail_len  <= 3'd0;
      vx         <= VX_START;
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
      {pl_y, pl_f} <= move_paddle({pl_y, pl_f}, l_up, l_down, paddle_speed);
      {pr_y, pr_f} <= move_paddle({pr_y, pr_f}, r_up, r_down, paddle_speed);

      if (new_game) begin
        state   <= SERVE;
        timer   <= 8'd60;
        score_l <= 4'd0;
        score_r <= 4'd0;
        vx        <= VX_START;
        ball_x    <= CENTER_X;
        ball_xf   <= 2'd0;
        ball_y    <= CENTER_Y;
        trail_len <= 3'd0;
      end else begin
        case (state)
          SERVE: begin
            if (timer == 8'd0) begin
              state     <= PLAY;
              trail_len <= 3'd0;
              vx        <= VX_START;
              vx_left <= serve_left;
              vy      <= 3'd1 + {1'b0, lfsr[1:0] == 2'd3 ? 2'd2 : lfsr[1:0]};
              vy_up   <= lfsr[2];
            end else begin
              timer <= timer - 8'd1;
            end
          end

          PLAY: begin
            // trail: one more copy every other frame, starting again on a bounce
            trail_tick <= ~trail_tick;
            if (hits_left || hits_right || hits_top || hits_bottom)
              trail_len <= 3'd0;
            else if (trail_tick && trail_len != 3'd5)
              trail_len <= trail_len + 3'd1;

            if (hits_left) begin
              ball_x  <= LEFT_FACE;
              ball_xf <= 2'd0;
              vx_left <= 1'b0;
              if (vx != VX_MAX) vx <= vx + VX_STEP;
              {vy_up, vy} <= bounce_dir;
            end else if (hits_right) begin
              ball_x  <= RIGHT_FACE - BALL_SIZE;
              ball_xf <= 2'd0;
              vx_left <= 1'b1;
              if (vx != VX_MAX) vx <= vx + VX_STEP;
              {vy_up, vy} <= bounce_dir;
            end else if (out_left || out_right) begin
              // point to the other player; the loser receives the next serve
              if (out_left) score_r <= score_r + 4'd1;
              else          score_l <= score_l + 4'd1;
              serve_left <= out_left;
              vx         <= VX_START;
              ball_x     <= CENTER_X;
              ball_xf    <= 2'd0;
              ball_y     <= CENTER_Y;
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
              if (hits_top) begin
                ball_y <= TOP;
                vy_up  <= 1'b0;
              end else if (hits_bottom) begin
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

  // ===========================================================================
  // Picture
  // ===========================================================================
  // Everything that depends only on the line (which objects cross it, which
  // row of the score digits it shows) is worked out once per line during
  // horizontal blank, so each pixel only needs a few x comparisons.
  localparam [5:0] BACKGROUND_RGB = 6'b00_00_01;  // {R[1:0], G[1:0], B[1:0]}
  localparam [5:0] WALL_RGB       = 6'b10_10_10;
  localparam [5:0] BALL_RGB       = 6'b11_11_00;
  localparam [5:0] LEFT_RGB       = 6'b00_11_11;
  localparam [5:0] RIGHT_RGB      = 6'b11_00_11;

  wire ball_visible  = !(serving && blink);      // blinks while waiting to serve
  wire trail_visible = !serving && !game_over;
  wire hide_l        = game_over && !winner_r && blink;  // winner's score blinks
  wire hide_r        = game_over && winner_r && blink;

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

  // Trail: five copies of the ball from 2, 4, ... 10 frames ago, getting
  // smaller (8, 8, 6, 6, 4 px) so they form a tapering tail in the ball's
  // colour. During horizontal blank the copies are stepped through one per
  // clock (each is one "2 frames of movement" further back), and the span
  // of the line covered by the ball and the copies crossing it is recorded.
  // Each pixel then only needs to check that one span.
  function [3:0] copy_size;
    input [2:0] k;
    copy_size = (k < 3'd2) ? 4'd8 : (k < 3'd4) ? 4'd6 : 4'd4;
  endfunction

  // ---- per-line data, for line row_y --------------------------------------
  reg       wall_row, dash_row, pl_row, pr_row;
  reg [2:0] digits_l, digits_r;
  reg       digit_line;  // a score digit has pixels on this line
  reg [9:0] span_lo, span_hi;  // ball + trail cover pixels span_lo .. span_hi-1

  // stepping through the trail copies
  reg        tr_on;     // still stepping
  reg [2:0]  tr_k;      // copy being looked at
  reg [11:0] tr_x;      // its position (x in 10.2 fixed point)
  reg [8:0]  tr_y;

  // The left and right paddle/score share one row test and one font lookup:
  // the left side is done at row_load, the right side one clock later.
  wire       right_side = (hpos == 10'd701);
  wire [9:0] dy_paddle  = row_y - {1'b0, right_side ? pr_y : pl_y};
  wire [9:0] dy_ball    = row_y - {1'b0, ball_y};
  wire [9:0] dy_font    = row_y - 10'd32;
  wire [2:0] font_bits  = (dy_font < 10'd40 && !(right_side ? hide_r : hide_l))
                          ? font_row(right_side ? score_r : score_l, dy_font[5:3]) : 3'b000;

  // one trail step: the copy 2 frames further back than (tr_x, tr_y)
  wire [11:0] step_x  = vx_left ? tr_x + {5'd0, vx, 1'b0} : tr_x - {5'd0, vx, 1'b0};
  wire [8:0]  step_y  = vy_up   ? tr_y + {5'd0, vy, 1'b0} : tr_y - {5'd0, vy, 1'b0};
  wire [3:0]  size_k  = copy_size(tr_k);
  wire [9:0]  inset_k = {7'd0, 3'd5 - size_k[3:1]};
  wire [9:0]  copy_lo = step_x[11:2] + inset_k;
  wire [9:0]  copy_hi = copy_lo + {6'd0, size_k};
  wire        copy_on = (row_y - {1'b0, step_y} - inset_k) < {6'd0, size_k};

  always @(posedge clk) begin
    if (row_load) begin
      wall_row   <= (row_y < 10'd8) || (row_y >= 10'd472 && row_y < 10'd480);
      dash_row   <= row_y[4] && row_y >= 10'd8 && row_y < 10'd472;
      pl_row     <= dy_paddle < 10'd64;
      digits_l   <= font_bits;
      digit_line <= dy_font < 10'd40;
      if (ball_visible && dy_ball < 10'd10) begin
        span_lo <= ball_x;
        span_hi <= ball_x + 10'd10;
      end else begin
        span_lo <= 10'h3FF;
        span_hi <= 10'h000;
      end
      tr_on <= trail_visible && trail_len != 3'd0;
      tr_k  <= 3'd0;
      tr_x  <= {ball_x, ball_xf};
      tr_y  <= ball_y;
    end else if (tr_on) begin
      tr_x <= step_x;
      tr_y <= step_y;
      if (copy_on) begin
        if (copy_lo < span_lo) span_lo <= copy_lo;
        if (copy_hi > span_hi) span_hi <= copy_hi;
      end
      tr_k  <= tr_k + 3'd1;
      tr_on <= tr_k + 3'd1 < trail_len;
    end
    if (right_side) begin
      pr_row   <= dy_paddle < 10'd64;
      digits_r <= font_bits;
    end
  end

  // ---- per pixel -------------------------------------------------------------
  // Nested so that the common case (background) takes only a few tests;
  // the score tests only run on lines that contain them.
  // (Separate nested ifs and plain expressions, rather than one big
  // condition or function calls, so a simulator can really skip them.)
  /* verilator lint_off BLKSEQ */
  function [5:0] pixel;
    input [9:0] px;
    begin
      pixel = BACKGROUND_RGB;
      if (wall_row) begin
        pixel = WALL_RGB;
      end else begin
        if (px < 10'd34) begin
          if (pl_row && px >= 10'd24) pixel = LEFT_RGB;
        end else if (px >= 10'd606) begin
          if (pr_row && px < 10'd616) pixel = RIGHT_RGB;
        end else begin
          if (digit_line) begin
            case (px[9:3])
              7'd32: if (digits_l[2]) pixel = LEFT_RGB;
              7'd33: if (digits_l[1]) pixel = LEFT_RGB;
              7'd34: if (digits_l[0]) pixel = LEFT_RGB;
              7'd45: if (digits_r[2]) pixel = RIGHT_RGB;
              7'd46: if (digits_r[1]) pixel = RIGHT_RGB;
              7'd47: if (digits_r[0]) pixel = RIGHT_RGB;
              default: ;
            endcase
          end
          if (dash_row && px >= 10'd318 && px < 10'd322) pixel = WALL_RGB;
        end
        // the ball and its trail go on top of everything
        if (px >= span_lo && px < span_hi) pixel = BALL_RGB;
      end
    end
  endfunction
  /* verilator lint_on BLKSEQ */

  // The pixel colour is registered, so the syncs are delayed by one clock
  reg [5:0] rgb;
  reg       hsync_r, vsync_r;
  always @(posedge clk) begin
    if (display_on) rgb <= pixel(hpos);
    else            rgb <= 6'd0;
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

  wire _unused = &{ena, uio_in, lfsr[7:3], 1'b0};
endmodule
