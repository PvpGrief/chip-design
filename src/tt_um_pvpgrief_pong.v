`default_nettype none

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

  hvsync_generator vga (
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
