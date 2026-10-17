`default_nettype none

// Background renderer: sky, sun, a drifting cloud, grassy mound, the tree
// and the pile of fallen leaves under it. Purely combinational on the beam
// position; the top level registers the result.
module tree_scene (
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
