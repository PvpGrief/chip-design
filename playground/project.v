// Falling Leaves: a VGA tree that drops autumn leaves at random.
// https://github.com/PvpGrief/chip-design
//
// Single-file bundle for https://vga-playground.com: paste this over
// project.v. Generated from src/ by sim/make_playground.py; don't edit by hand.
//
//   ui_in[0]  storm:  wind, grey sky and lots of leaves
//   ui_in[1]  freeze: pause the animation

`default_nettype none

// ---- tt_um_falling_leaves.v ------------------------------------------------

// Falling Leaves: a VGA tree that drops autumn leaves at random.
//
// Output is 640x480 @ 60 Hz on the TinyVGA Pmod pinout. A free-running LFSR
// decides when the next leaf lets go (every ~0.5-2.6 s), where on the tree
// it starts, its colour and how long it lies on the grass afterwards.
//
//   ui_in[0]  storm:  wind, grey sky and lots of leaves
//   ui_in[1]  freeze: pause the animation
module tt_um_falling_leaves (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
  localparam N = 8;  // leaves that can be in the air / on the ground at once

  wire storm  = ui_in[0];
  wire freeze = ui_in[1];

  wire       hsync, vsync, display_on;
  wire [9:0] hpos, vpos;

  falling_leaves_vga_timing vga (
      .clk(clk),
      .rst_n(rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(display_on),
      .hpos(hpos),
      .vpos(vpos)
  );

  // Animation state advances once per frame, at the start of vertical blank
  wire frame_tick = (hpos == 10'd0) && (vpos == 10'd480);
  wire step       = frame_tick && !freeze;

  // ---- randomness: 32-bit maximal-length Galois LFSR, stepped every clock --
  reg [31:0] lfsr;
  always @(posedge clk) begin
    if (!rst_n) lfsr <= 32'hACE1_2468;
    else        lfsr <= {1'b0, lfsr[31:1]} ^ (lfsr[0] ? 32'h8020_0003 : 32'h0);
  end
  wire [63:0] lfsr2 = {lfsr, lfsr};

  // ---- leaf spawner ---------------------------------------------------------
  wire [N-1:0] busy, rotted, hit;
  wire [6*N-1:0] leaf_rgb;

  reg  [7:0] spawn_timer;  // frames until the next leaf lets go
  wire [N-1:0] free        = ~busy;
  wire [N-1:0] lowest_free = free & (~free + 1'b1);
  wire [N-1:0] spawn       = (step && spawn_timer == 8'd0) ? lowest_free : {N{1'b0}};

  // Start somewhere near the middle of one of four leafy blobs
  reg [9:0] blob_x;
  reg [8:0] blob_y;
  always @* begin
    case (lfsr[9:8])
      2'd0: begin blob_x = 10'd320; blob_y = 9'd150; end
      2'd1: begin blob_x = 10'd235; blob_y = 9'd200; end
      2'd2: begin blob_x = 10'd405; blob_y = 9'd200; end
      default: begin blob_x = 10'd320; blob_y = 9'd228; end
    endcase
  end
  wire [9:0] spawn_x = blob_x + {4'd0, lfsr[15:10]} - 10'd40;
  wire [8:0] spawn_y = blob_y + {4'd0, lfsr[20:16]} - 9'd24;

  genvar g;
  generate
    for (g = 0; g < N; g = g + 1) begin : leaves
      falling_leaves_leaf u_leaf (
          .clk(clk),
          .rst_n(rst_n),
          .frame_tick(frame_tick),
          .freeze(freeze),
          .wind(storm),
          .spawn(spawn[g]),
          .spawn_x(spawn_x),
          .spawn_y(spawn_y),
          .rnd(lfsr2[16 + 3*g +: 13]),
          .hpos(hpos),
          .vpos(vpos),
          .busy(busy[g]),
          .rotted(rotted[g]),
          .hit(hit[g]),
          .rgb(leaf_rgb[6*g +: 6])
      );
    end
  endgenerate

  // ---- scenery state --------------------------------------------------------
  reg [9:0] cloud_x;
  reg [1:0] cloud_div;
  reg [3:0] litter;  // grows as leaves rot on the grass, slowly blows away
  reg [7:0] decay;

  always @(posedge clk) begin
    if (!rst_n) begin
      spawn_timer <= 8'd20;
      cloud_x     <= 10'd40;
      cloud_div   <= 2'd0;
      decay       <= 8'd0;
    end else if (step) begin
      if (spawn_timer == 8'd0)
        spawn_timer <= storm ? 8'd3 + {4'd0, lfsr[24:21]}
                             : 8'd30 + {1'b0, lfsr[27:21]};
      else
        spawn_timer <= spawn_timer - 8'd1;
      cloud_div <= cloud_div + 2'd1;
      if (storm || cloud_div == 2'd0) cloud_x <= cloud_x + 10'd1;
      decay <= decay + 8'd1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n)
      litter <= 4'd0;
    else if (|rotted) begin
      if (litter != 4'd15) litter <= litter + 4'd1;
    end else if (step && litter != 4'd0 && (decay == 8'd0 || (storm && decay[3:0] == 4'd0)))
      litter <= litter - 4'd1;
  end

  // ---- pixel output ---------------------------------------------------------
  wire [5:0] scene_rgb;
  falling_leaves_scene scene (
      .hpos(hpos),
      .vpos(vpos),
      .cloud_x(cloud_x),
      .litter(litter),
      .storm(storm),
      .rgb(scene_rgb)
  );

  // Leaves are drawn over the scenery; lower slots win when they overlap
  reg [5:0] pix;
  integer i;
  always @* begin
    pix = scene_rgb;
    for (i = N - 1; i >= 0; i = i - 1)
      if (hit[i]) pix = leaf_rgb[6*i +: 6];
  end

  reg       hsync_r, vsync_r;
  reg [5:0] rgb_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      hsync_r <= 1'b1;
      vsync_r <= 1'b1;
      rgb_r   <= 6'd0;
    end else begin
      hsync_r <= hsync;
      vsync_r <= vsync;
      rgb_r   <= display_on ? pix : 6'd0;
    end
  end

  // TinyVGA Pmod: {hsync, B0, G0, R0, vsync, B1, G1, R1}
  assign uo_out  = {hsync_r, rgb_r[0], rgb_r[2], rgb_r[4], vsync_r, rgb_r[1], rgb_r[3], rgb_r[5]};
  assign uio_out = 8'd0;
  assign uio_oe  = 8'd0;

  wire _unused = &{ena, uio_in, ui_in[7:2], lfsr2, 1'b0};
endmodule

// ---- leaf.v ----------------------------------------------------------------

// One falling leaf sprite (8x8 bitmap drawn at 2x = 16x16 pixels).
//
// Idle until `spawn` pulses, then it flutters down from (spawn_x, spawn_y),
// swinging side to side like a pendulum, lies on the grass for a random
// while, fades out and frees itself for reuse. In a storm it falls faster,
// drifts right and gets blown off the ground.
module falling_leaves_leaf (
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

// ---- tree_scene.v ----------------------------------------------------------

// Background renderer: sky, sun, a drifting cloud, grassy mound, the tree
// and the pile of fallen leaves under it. Purely combinational on the beam
// position; the top level registers the result.
module falling_leaves_scene (
    input  wire [9:0] hpos,
    input  wire [9:0] vpos,
    input  wire [9:0] cloud_x,
    input  wire [3:0] litter,  // how many leaves are lying around (0..15)
    input  wire       storm,
    output reg  [5:0] rgb      // {R[1:0], G[1:0], B[1:0]}
);
  // 6-bit square as a lookup table (smaller than a multiplier once optimised)
  function [11:0] sq6;
    input [5:0] a;
    begin
      case (a)
        6'd0: sq6 = 12'd0;
        6'd1: sq6 = 12'd1;
        6'd2: sq6 = 12'd4;
        6'd3: sq6 = 12'd9;
        6'd4: sq6 = 12'd16;
        6'd5: sq6 = 12'd25;
        6'd6: sq6 = 12'd36;
        6'd7: sq6 = 12'd49;
        6'd8: sq6 = 12'd64;
        6'd9: sq6 = 12'd81;
        6'd10: sq6 = 12'd100;
        6'd11: sq6 = 12'd121;
        6'd12: sq6 = 12'd144;
        6'd13: sq6 = 12'd169;
        6'd14: sq6 = 12'd196;
        6'd15: sq6 = 12'd225;
        6'd16: sq6 = 12'd256;
        6'd17: sq6 = 12'd289;
        6'd18: sq6 = 12'd324;
        6'd19: sq6 = 12'd361;
        6'd20: sq6 = 12'd400;
        6'd21: sq6 = 12'd441;
        6'd22: sq6 = 12'd484;
        6'd23: sq6 = 12'd529;
        6'd24: sq6 = 12'd576;
        6'd25: sq6 = 12'd625;
        6'd26: sq6 = 12'd676;
        6'd27: sq6 = 12'd729;
        6'd28: sq6 = 12'd784;
        6'd29: sq6 = 12'd841;
        6'd30: sq6 = 12'd900;
        6'd31: sq6 = 12'd961;
        6'd32: sq6 = 12'd1024;
        6'd33: sq6 = 12'd1089;
        6'd34: sq6 = 12'd1156;
        6'd35: sq6 = 12'd1225;
        6'd36: sq6 = 12'd1296;
        6'd37: sq6 = 12'd1369;
        6'd38: sq6 = 12'd1444;
        6'd39: sq6 = 12'd1521;
        6'd40: sq6 = 12'd1600;
        6'd41: sq6 = 12'd1681;
        6'd42: sq6 = 12'd1764;
        6'd43: sq6 = 12'd1849;
        6'd44: sq6 = 12'd1936;
        6'd45: sq6 = 12'd2025;
        6'd46: sq6 = 12'd2116;
        6'd47: sq6 = 12'd2209;
        6'd48: sq6 = 12'd2304;
        6'd49: sq6 = 12'd2401;
        6'd50: sq6 = 12'd2500;
        6'd51: sq6 = 12'd2601;
        6'd52: sq6 = 12'd2704;
        6'd53: sq6 = 12'd2809;
        6'd54: sq6 = 12'd2916;
        6'd55: sq6 = 12'd3025;
        6'd56: sq6 = 12'd3136;
        6'd57: sq6 = 12'd3249;
        6'd58: sq6 = 12'd3364;
        6'd59: sq6 = 12'd3481;
        6'd60: sq6 = 12'd3600;
        6'd61: sq6 = 12'd3721;
        6'd62: sq6 = 12'd3844;
        6'd63: sq6 = 12'd3969;
        default: sq6 = 12'd0;
      endcase
    end
  endfunction

  // Is (px,py) inside the circle at (cx,cy)? Distances are halved before
  // squaring so the multipliers stay 6x6 bits: r is in 2-pixel units
  // (radius up to 126 pixels). Coordinates wrap at 1024, so cx can scroll
  // smoothly off one edge and back in at the other.
  function in_circle;
    input [9:0] px, py, cx, cy;
    input [5:0] r;
    /* verilator lint_off UNUSED */
    reg [9:0]  dx, dy, ax, ay;  // bit 0 is dropped by the halving
    /* verilator lint_on UNUSED */
    reg [11:0] sx, sy, rr;
    begin
      dx = px - cx;
      dy = py - cy;
      ax = dx[9] ? 10'd0 - dx : dx;
      ay = dy[9] ? 10'd0 - dy : dy;
      sx = sq6(ax[6:1]);
      sy = sq6(ay[6:1]);
      rr = sq6(r);
      in_circle = (ax[9:7] == 3'd0) && (ay[9:7] == 3'd0) &&
                  ({1'b0, sx} + {1'b0, sy} < {1'b0, rr});
    end
  endfunction

  // Two multiply-xorshift rounds: enough mixing to avoid visible stripes
  function [7:0] mix;
    input [7:0] x, y, kx, ky, salt;
    reg [7:0] t, u;
    begin
      t   = (x * kx) ^ (y * ky) ^ salt;
      u   = t * 8'd229;
      u   = (u ^ {u[3:0], u[7:4]}) * 8'd181;
      mix = u ^ {u[4:0], u[7:5]};
    end
  endfunction

  // Cheap spatial hashes for texture, on 4x4 and 2x2 pixel blocks
  wire [7:0] bx4 = hpos[9:2];
  wire [7:0] by4 = vpos[9:2];
  wire [7:0] bx2 = hpos[8:1];
  wire [7:0] by2 = vpos[8:1];
  wire [7:0] h4  = mix(bx4, by4, 8'd167, 8'd97,  8'h5A);  // canopy clumps
  wire [7:0] h2  = mix(bx2, by2, 8'd59,  8'd211, 8'hC3);  // fine canopy/grass detail
  wire [7:0] h4b = mix(bx4, by4, 8'd29,  8'd139, 8'h37);  // leaf litter

  // 4x4 ordered-dither threshold
  wire [3:0] bayer = {hpos[0] ^ vpos[0], vpos[0], hpos[1] ^ vpos[1], vpos[1]};

  // ---- sky ----------------------------------------------------------------
  wire [2:0] sky_idx = {1'b0, vpos[8:7]} + ((vpos[6:3] > bayer) ? 3'd1 : 3'd0);
  reg  [5:0] sky;
  always @* begin
    if (storm) begin
      case (sky_idx)
        3'd0: sky = 6'b00_00_01;
        3'd1: sky = 6'b00_01_01;
        3'd2: sky = 6'b01_01_01;
        3'd3: sky = 6'b01_10_10;
        default: sky = 6'b10_10_10;
      endcase
    end else begin
      case (sky_idx)
        3'd0: sky = 6'b00_01_10;
        3'd1: sky = 6'b00_01_11;
        3'd2: sky = 6'b00_10_11;
        3'd3: sky = 6'b01_10_11;
        default: sky = 6'b10_11_11;
      endcase
    end
  end

  wire sun      = in_circle(hpos, vpos, 10'd548, 10'd70, 6'd16);
  wire sun_glow = in_circle(hpos, vpos, 10'd548, 10'd70, 6'd21);

  wire cloud = vpos < 10'd112 && (
      in_circle(hpos, vpos, cloud_x,           10'd98, 6'd14) ||
      in_circle(hpos, vpos, cloud_x + 10'd34,  10'd84, 6'd19) ||
      in_circle(hpos, vpos, cloud_x + 10'd72,  10'd96, 6'd15) ||
      in_circle(hpos, vpos, cloud_x + 10'd100, 10'd104, 6'd9));

  // ---- ground ---------------------------------------------------------------
  wire ground = (vpos >= 10'd400) ||
                in_circle(hpos, vpos, 10'd320, 10'd500, 6'd62);

  // Fallen leaves pile up around the trunk, thinning out to the sides
  wire [9:0] tdx  = hpos - 10'd320;
  wire [9:0] atdx = tdx[9] ? 10'd0 - tdx : tdx;
  wire [3:0] thin = atdx[8:5];
  wire [3:0] pile = (litter > thin) ? litter - thin : 4'd0;
  wire litter_here = (atdx < 10'd176) && (vpos >= 10'd408) && (vpos < 10'd472) &&
                     (h4b < {1'b0, pile, 3'b000});

  // ---- tree -----------------------------------------------------------------
  wire [9:0] flare    = (vpos > 10'd350) ? {2'd0, vpos[9:2]} - 10'd87 : 10'd0;
  wire [9:0] trunk_hw = 10'd16 + flare;
  wire trunk = (vpos >= 10'd200) && (vpos < 10'd410) && (atdx < trunk_hw);
  wire bark_groove = (hpos[2:0] + {1'b0, h4[1:0]}) == 3'd0 && vpos[0];

  // Two branches at 45 degrees, peeking through gaps in the leaves
  wire [9:0] bl = vpos - hpos + 10'd20;   // y - x = const line, up-left
  wire [9:0] br = vpos + hpos - 10'd610;  // y + x = const line, up-right
  wire branch = (vpos >= 10'd170) && (vpos < 10'd302) &&
                (((bl + 10'd5 < 10'd10) && hpos < 10'd322 && hpos > 10'd190) ||
                 ((br + 10'd5 < 10'd10) && hpos > 10'd318 && hpos < 10'd450));

  wire canopy =
      in_circle(hpos, vpos, 10'd320, 10'd150, 6'd45) ||
      in_circle(hpos, vpos, 10'd225, 10'd205, 6'd33) ||
      in_circle(hpos, vpos, 10'd415, 10'd205, 6'd33) ||
      in_circle(hpos, vpos, 10'd262, 10'd112, 6'd30) ||
      in_circle(hpos, vpos, 10'd383, 10'd116, 6'd30) ||
      in_circle(hpos, vpos, 10'd320, 10'd236, 6'd32);
  wire canopy_hole = h4 < 8'd10;
  wire lit_side    = (hpos + vpos) < 10'd440;   // light comes from upper left
  wire shade_side  = (hpos + vpos) > 10'd600 || vpos > 10'd250;

  // ---- compose (back to front) ----------------------------------------------
  always @* begin
    rgb = sky;
    if (!storm && sun_glow) rgb = (bayer[0] || sun) ? 6'b11_11_01 : 6'b11_11_10;
    if (cloud) rgb = storm ? ((vpos > 10'd100) ? 6'b01_01_01 : 6'b10_10_10)
                           : ((vpos > 10'd100) ? 6'b10_10_11 : 6'b11_11_11);

    if (ground) begin
      if (h2 < 8'd40)       rgb = 6'b00_01_00;
      else if (h2 > 8'd225) rgb = 6'b01_11_00;
      else                  rgb = 6'b00_10_00;
      if (litter_here) begin
        case (h4b[1:0])
          2'd0: rgb = 6'b11_01_00;
          2'd1: rgb = 6'b10_01_00;
          2'd2: rgb = 6'b10_10_00;
          default: rgb = 6'b10_00_00;
        endcase
      end
    end

    if (trunk || branch) begin
      if (bark_groove)                                rgb = 6'b01_00_00;
      else if (trunk && tdx[9] && atdx + 10'd6 > trunk_hw) rgb = 6'b11_10_01;
      else if (trunk && !tdx[9] && atdx + 10'd7 > trunk_hw) rgb = 6'b01_00_00;
      else                                            rgb = 6'b10_01_00;
    end

    if (canopy && !(canopy_hole && !shade_side)) begin
      if (canopy_hole)                     rgb = branch ? 6'b01_00_00 : 6'b00_01_00;
      else if (h4 > 8'd238)                rgb = 6'b11_01_00;  // turning orange
      else if (h4 > 8'd222)                rgb = 6'b10_10_00;  // turning yellow
      else if (shade_side && h2 < 8'd120)  rgb = 6'b00_01_00;
      else if (h4 < 8'd60)                 rgb = 6'b00_01_00;
      else if (lit_side && h2 > 8'd130)    rgb = 6'b01_11_00;
      else if (h2 > 8'd215)                rgb = 6'b01_11_00;
      else                                 rgb = 6'b00_10_00;
    end
  end
endmodule

// ---- hvsync_generator.v ----------------------------------------------------

// 640x480 @ 60 Hz VGA timing (25.175 MHz pixel clock, 25 MHz works too).
// hsync/vsync are active-low, as this mode requires.
module falling_leaves_vga_timing (
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
