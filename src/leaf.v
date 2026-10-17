`default_nettype none

// One falling leaf sprite (8x8 bitmap drawn at 2x = 16x16 pixels).
//
// Idle until `spawn` pulses, then it flutters down from (spawn_x, spawn_y),
// swinging side to side like a pendulum, lies on the grass for a random
// while, fades out and frees itself for reuse. In a storm it falls faster,
// drifts right and gets blown off the ground.
module leaf (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,  // one pulse per frame, during vblank
    input  wire        freeze,
    input  wire        wind,
    input  wire        spawn,
    input  wire [9:0]  spawn_x,     // top-left corner of the sprite
    input  wire [8:0]  spawn_y,
    input  wire [12:0] rnd,
    input  wire [9:0]  hpos,
    input  wire [9:0]  vpos,
    output wire        busy,
    output reg         rotted,      // pulse: finished lying on the ground
    output wire        hit,         // current pixel is covered by this leaf
    output wire [5:0]  rgb          // {R[1:0], G[1:0], B[1:0]}
);
  reg       active;
  reg       landed;
  reg [9:0] x;
  reg [8:0] y;
  reg [8:0] ground_y;
  reg [5:0] phase;   // pendulum: [5] = swing direction, [4:0] = progress
  reg [1:0] hue;
  reg [7:0] timer;   // frames left on the ground

  assign busy = active;

  wire       swing_right = phase[5];
  wire       mid_swing   = phase[4] ^ phase[3];
  // 2 px/frame through the middle of a swing, 1 px/frame at the ends
  wire [8:0] fall  = {7'd0, mid_swing, ~mid_swing} + {8'd0, wind};
  wire [9:0] drift = (swing_right ? 10'd1 : 10'h3FF) + {9'd0, wind};
  wire       off_screen = (x >= 10'd640) && (x < 10'd960);

  always @(posedge clk) begin
    rotted <= 1'b0;
    if (!rst_n) begin
      active   <= 1'b0;
      landed   <= 1'b0;
      x        <= 10'd0;
      y        <= 9'd0;
      ground_y <= 9'd0;
      phase    <= 6'd0;
      hue      <= 2'd0;
      timer    <= 8'd0;
    end else if (spawn) begin
      active   <= 1'b1;
      landed   <= 1'b0;
      x        <= spawn_x;
      y        <= spawn_y;
      ground_y <= 9'd404 + {4'd0, rnd[12:8]};
      phase    <= rnd[5:0];
      hue      <= rnd[7:6];
    end else if (frame_tick && active && !freeze) begin
      if (!landed) begin
        phase <= phase + 6'd1;
        x     <= x + drift;
        y     <= y + fall;
        if (y >= ground_y) begin
          landed <= 1'b1;
          timer  <= {1'b1, rnd[6:0]};
        end
      end else if (wind) begin
        x <= x + 10'd3;
      end else begin
        timer <= timer - 8'd1;
        if (timer == 8'd0) begin
          active <= 1'b0;
          rotted <= 1'b1;
        end
      end
      if (off_screen) active <= 1'b0;
    end
  end

  // ---- sprite -------------------------------------------------------------
  wire [9:0] dx = hpos - x;
  wire [9:0] dy = vpos - {1'b0, y};
  wire       in_box = (dx < 10'd16) && (dy < 10'd16);
  wire [2:0] col = swing_right ? dx[3:1] : ~dx[3:1];  // mirror on each swing
  wire [2:0] row = dy[3:1];

  // Leaf pointing up-right with its stem at the bottom-left. Bit n = column n.
  reg [7:0] mask;
  always @* begin
    case (row)
      3'd0: mask = 8'b1110_0000;
      3'd1: mask = 8'b1111_1000;
      3'd2: mask = 8'b1111_1100;
      3'd3: mask = 8'b1111_1110;
      3'd4: mask = 8'b0111_1110;
      3'd5: mask = 8'b0011_1110;
      3'd6: mask = 8'b0001_1100;
      default: mask = 8'b0000_0011;
    endcase
  end

  wire vein   = ({1'b0, row} + {1'b0, col} == 4'd8) || (row == 3'd7);
  wire fading = landed && (timer[7:4] == 4'd0);  // dissolve in the last frames

  assign hit = active && in_box && mask[col] && !(fading && (dx[1] ^ dy[1]));

  reg [5:0] body;
  always @* begin
    case (hue)
      2'd0: body = 6'b11_01_00;  // orange
      2'd1: body = 6'b11_00_00;  // red
      2'd2: body = 6'b11_10_00;  // gold
      default: body = 6'b10_01_00;  // russet
    endcase
  end

  assign rgb = vein ? {body[5:4] - 2'd1, 1'b0, body[3], 2'b00} : body;
endmodule
