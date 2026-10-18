`default_nettype none

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
