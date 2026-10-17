`default_nettype none

// Background: sky, sun, a drifting cloud, grassy mound, the tree and the
// pile of fallen leaves under it, drawn in 4x4-pixel blocks (160x120).
// Only evaluated when `en` is high (once per block); the result is held.
module tree_scene (
    input  wire       clk,
    input  wire       en,
    input  wire [7:0] bx,       // block column, 0..159
    input  wire [6:0] by,       // block row, 0..119
    input  wire [7:0] cloud_x,  // block column of the cloud's left edge
    input  wire [3:0] litter,   // how many leaves are lying around (0..15)
    input  wire       storm,
    output reg  [5:0] rgb       // {R[1:0], G[1:0], B[1:0]}
);
  /* verilator lint_off BLKSEQ */
  // Rounded blob ("octagon") of radius r around (cx, cy)
  function blob;
    input [7:0] px, cx;
    input [6:0] py, cy;
    input [6:0] r;
    reg [7:0] ax, ay;
    begin
      ax   = (px >= cx) ? px - cx : cx - px;
      ay   = (py >= cy) ? {1'b0, py - cy} : {1'b0, cy - py};
      blob = (ax < {1'b0, r}) && (ay < {1'b0, r}) &&
             (ax + ay < {1'b0, r} + {2'b0, r[6:1]});
    end
  endfunction

  function [5:0] shade;
    input [7:0] px;
    input [6:0] py;
    reg [7:0] ax;    // distance from the trunk's centre line
    reg [7:0] h;     // texture hash
    reg [6:0] d;
    reg [7:0] c;
    reg [3:0] pile;
    reg [6:0] yy;
    begin
      ax = (px >= 8'd80) ? px - 8'd80 : 8'd80 - px;
      h  = (px * 8'd37) ^ ({1'b0, py} * 8'd101);
      h  = (h ^ {h[4:0], h[7:5]}) * 8'd229;
      h  = h ^ {h[3:0], h[7:4]};
      d  = 7'd100 - py;

      if (py >= 7'd100 || (py >= 7'd94 && ax < 8'd40 - {1'b0, d} * 8'd5)) begin
        // grass, with fallen leaves piling up around the trunk
        pile = (litter > ax[6:3]) ? litter - ax[6:3] : 4'd0;
        if (py >= 7'd102 && py < 7'd118 && ax < 8'd44 && h < {1'b0, pile, 3'b000})
          case (h[1:0])
            2'd0: shade = 6'b11_01_00;
            2'd1: shade = 6'b10_01_00;
            2'd2: shade = 6'b10_10_00;
            default: shade = 6'b10_00_00;
          endcase
        else if (h < 8'd40)  shade = 6'b00_01_00;
        else if (h > 8'd225) shade = 6'b01_11_00;
        else                 shade = 6'b00_10_00;

      end else if (py < 7'd77 && ax < 8'd40 &&
                   (blob(px, 8'd80,  py, 7'd37, 7'd23) ||
                    blob(px, 8'd57,  py, 7'd52, 7'd16) ||
                    blob(px, 8'd103, py, 7'd52, 7'd16) ||
                    blob(px, 8'd66,  py, 7'd27, 7'd15) ||
                    blob(px, 8'd94,  py, 7'd28, 7'd15) ||
                    blob(px, 8'd80,  py, 7'd60, 7'd16))) begin
        // canopy: clumps of light and dark green, a few leaves turning
        if (h > 8'd238)                                             shade = 6'b11_01_00;
        else if (h > 8'd224)                                        shade = 6'b10_10_00;
        else if ((px + {1'b0, py} > 8'd150 || py > 7'd62) && h < 8'd120) shade = 6'b00_01_00;
        else if (h < 8'd60)                                         shade = 6'b00_01_00;
        else if (px + {1'b0, py} < 8'd105 && h > 8'd130)            shade = 6'b01_11_00;
        else if (h > 8'd215)                                        shade = 6'b01_11_00;
        else                                                        shade = 6'b00_10_00;

      end else if (py >= 7'd60 && ax < 8'd5 + ((py >= 7'd92) ? {2'd0, py[6:1]} - 8'd46 : 8'd0)) begin
        // trunk, flaring out at the base
        if (h[2:0] == 3'd0)                         shade = 6'b01_00_00;
        else if (px < 8'd80 && ax > 8'd1 && ax + 8'd2 >= 8'd5 + ((py >= 7'd92) ? {2'd0, py[6:1]} - 8'd46 : 8'd0))
                                                    shade = 6'b11_10_01;
        else if (px > 8'd81)                        shade = 6'b01_00_00;
        else                                        shade = 6'b10_01_00;

      end else begin
        // sky, dithered between bands
        yy = py + ((px[0] ^ py[0]) ? 7'd3 : 7'd0);
        if (storm) begin
          if (yy < 7'd24)      shade = 6'b00_00_01;
          else if (yy < 7'd48) shade = 6'b00_01_01;
          else if (yy < 7'd72) shade = 6'b01_01_01;
          else                 shade = 6'b01_10_10;
        end else begin
          if (yy < 7'd24)      shade = 6'b00_01_10;
          else if (yy < 7'd48) shade = 6'b00_01_11;
          else if (yy < 7'd72) shade = 6'b00_10_11;
          else                 shade = 6'b01_10_11;
        end

        // sun with a dithered glow
        if (!storm && px >= 8'd127 && py < 7'd28) begin
          if (blob(px, 8'd137, py, 7'd17, 7'd6))
            shade = 6'b11_11_01;
          else if (blob(px, 8'd137, py, 7'd17, 7'd8) && (px[0] ^ py[0]))
            shade = 6'b11_11_10;
        end

        // cloud
        if (py >= 7'd15 && py < 7'd25) begin
          c = px - cloud_x;
          if ((py >= 7'd19 && c < 8'd24 && !((c == 8'd0 || c == 8'd23) && (py == 7'd19 || py == 7'd24))) ||
              (py <  7'd19 && c >= 8'd5 && c < 8'd17 && !((c == 8'd5 || c == 8'd16) && py == 7'd15)) ||
              (py >= 7'd17 && c >= 8'd15 && c < 8'd21))
            shade = storm ? ((py >= 7'd23) ? 6'b01_01_01 : 6'b10_10_10)
                          : ((py >= 7'd23) ? 6'b10_10_11 : 6'b11_11_11);
        end
      end
    end
  endfunction
  /* verilator lint_on BLKSEQ */

  // Evaluated once per block, inside the clocked block, so a simulator only
  // runs this logic one clock in four.
  always @(posedge clk) begin
    if (en) rgb <= shade(bx, by);
  end
endmodule
