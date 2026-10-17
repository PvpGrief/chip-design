`default_nettype none

// The falling leaves: N independent leaf slots.
//
// Physics run in pixel units once per frame. Drawing is in 4x4-pixel blocks:
// once per line each leaf's sprite row is looked up (row_load), and per block
// only a subtract and a bit test per leaf remain. A leaf is a 4x4-block
// sprite (16x16 pixels) that flutters down from (spawn_x, spawn_y), swinging
// side to side, lies on the grass for a random while, dissolves and frees
// its slot. In a storm it falls faster, drifts right and gets blown away.
module leaves #(
    parameter N = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,  // one pulse per frame, during vblank
    input  wire        freeze,
    input  wire        wind,
    input  wire        spawn_now,   // let a new leaf go (if a slot is free)
    input  wire [9:0]  spawn_x,     // top-left corner, in pixels
    input  wire [8:0]  spawn_y,
    input  wire [31:0] rnd,
    input  wire        row_load,    // during hblank: prepare the sprite rows for row_by
    input  wire [6:0]  row_by,
    input  wire        en,          // draw: evaluate block bx of the current row this clock
    input  wire [7:0]  bx,
    output reg         rotted,      // a leaf finished lying on the ground (held for a frame)
    output wire        hit,         // block bx shows a leaf (valid after en)
    output wire [5:0]  rgb          // {R[1:0], G[1:0], B[1:0]}
);
  // Per-leaf state, packed into vectors: field of leaf i is e.g. xs[10*i +: 10].
  // Packed vectors keep simulation fast: unpacked arrays of registers get
  // extra per-element bookkeeping on every clock in cycle-based simulators.
  reg [N-1:0]   active;
  reg [N-1:0]   landed;
  reg [10*N-1:0] xs;        // top-left corner, pixels
  reg [9*N-1:0]  ys;
  reg [9*N-1:0]  ground_ys; // where it will land
  reg [6*N-1:0]  phases;    // pendulum: [5] = swing direction, [4:0] = progress
  reg [2*N-1:0]  hues;
  reg [8*N-1:0]  timers;    // frames left on the ground

  wire [N-1:0] free        = ~active;
  wire [N-1:0] lowest_free = free & (~free + 1'b1);

  integer i;
  always @(posedge clk) begin
    if (!rst_n) begin
      active    <= {N{1'b0}};
      landed    <= {N{1'b0}};
      rotted    <= 1'b0;
      xs        <= {10*N{1'b0}};
      ys        <= {9*N{1'b0}};
      ground_ys <= {9*N{1'b0}};
      phases    <= {6*N{1'b0}};
      hues      <= {2*N{1'b0}};
      timers    <= {8*N{1'b0}};
    end else if (frame_tick) begin
      rotted <= 1'b0;
      for (i = 0; i < N; i = i + 1) begin
        if (spawn_now && lowest_free[i]) begin
          active[i]           <= 1'b1;
          landed[i]           <= 1'b0;
          xs[10*i +: 10]      <= spawn_x;
          ys[9*i +: 9]        <= spawn_y;
          ground_ys[9*i +: 9] <= 9'd404 + {4'd0, rnd[30:26]};
          phases[6*i +: 6]    <= rnd[5:0];
          hues[2*i +: 2]      <= rnd[7:6];
        end else if (active[i] && !freeze) begin
          if (!landed[i]) begin
            phases[6*i +: 6] <= phases[6*i +: 6] + 6'd1;
            // sideways 1 px/frame plus wind; down 2 px/frame through the
            // middle of a swing and 1 px/frame at the ends (+1 in wind)
            xs[10*i +: 10] <= xs[10*i +: 10] + (phases[6*i+5] ? 10'd1 : 10'h3FF) + {9'd0, wind};
            ys[9*i +: 9]   <= ys[9*i +: 9]
                              + {7'd0, phases[6*i+4] ^ phases[6*i+3], ~(phases[6*i+4] ^ phases[6*i+3])}
                              + {8'd0, wind};
            if (ys[9*i +: 9] >= ground_ys[9*i +: 9]) begin
              landed[i]        <= 1'b1;
              timers[8*i +: 8] <= {1'b1, rnd[6:0]};
            end
          end else if (wind) begin
            xs[10*i +: 10] <= xs[10*i +: 10] + 10'd3;
          end else begin
            timers[8*i +: 8] <= timers[8*i +: 8] - 8'd1;
            if (timers[8*i +: 8] == 8'd0) begin
              active[i] <= 1'b0;
              rotted    <= 1'b1;
            end
          end
          if (xs[10*i +: 10] >= 10'd640 && xs[10*i +: 10] < 10'd960)
            active[i] <= 1'b0;  // blown off screen
        end
      end
    end
  end

  // ---- drawing ----------------------------------------------------------
  // Sprite row of leaf k on block row py, indexed by block offset from the
  // leaf's left edge (already mirrored and dissolved), plus its colour.
  // Returns {mask[3:0], rgb[5:0]}.
  /* verilator lint_off BLKSEQ */
  function [9:0] sprite_row;
    input integer k;
    input [6:0]   py;
    reg [6:0] dy;
    reg [3:0] mask;
    reg [5:0] body;
    begin
      dy = py - ys[9*k+2 +: 7];
      // leaf pointing up-right, stem at the bottom-left (bit n = column n)
      case (dy[1:0])
        2'd0: mask = 4'b1100;
        2'd1: mask = 4'b1110;
        2'd2: mask = 4'b0110;
        default: mask = 4'b0001;
      endcase
      if (!phases[6*k+5]) mask = {mask[0], mask[1], mask[2], mask[3]};  // mirror on each swing
      if (landed[k] && timers[8*k+4 +: 4] == 4'd0)                       // dissolve at the end
        mask = mask & (dy[0] ? 4'b0101 : 4'b1010);
      if (!active[k] || dy >= 7'd4) mask = 4'b0000;
      case (hues[2*k +: 2])
        2'd0: body = 6'b11_01_00;  // orange
        2'd1: body = 6'b11_00_00;  // red
        2'd2: body = 6'b11_10_00;  // gold
        default: body = 6'b10_01_00;  // russet
      endcase
      sprite_row = {mask, (dy[1:0] == 2'd3) ? 6'b01_00_00 : body};
    end
  endfunction

  // Which leaf (if any) covers block px of the prepared row? Lower slots are
  // drawn on top. Returns {hit, rgb}.
  function [6:0] leaf_pixel;
    input [7:0] px;
    integer   k;
    reg [7:0] dx;
    reg [3:0] mask;
    begin
      leaf_pixel = 7'd0;
      for (k = N - 1; k >= 0; k = k - 1) begin
        dx   = px - row_xs[8*k +: 8];
        mask = row_infos[10*k + 6 +: 4];
        if (dx < 8'd4 && mask[dx[1:0]])
          leaf_pixel = {1'b1, row_infos[10*k +: 6]};
      end
    end
  endfunction
  /* verilator lint_on BLKSEQ */

  reg [10*N-1:0] row_infos;  // sprite_row() of each leaf for the current line
  reg [8*N-1:0]  row_xs;     // block column of each leaf
  reg [6:0]      pixel;      // {hit, rgb}

  assign {hit, rgb} = pixel;

  integer j;
  always @(posedge clk) begin
    if (!rst_n) begin
      pixel     <= 7'd0;
      row_infos <= {10*N{1'b0}};
      row_xs    <= {8*N{1'b0}};
    end else if (row_load) begin
      for (j = 0; j < N; j = j + 1) begin
        row_infos[10*j +: 10] <= sprite_row(j, row_by);
        row_xs[8*j +: 8]      <= xs[10*j+2 +: 8];
      end
    end else if (en) begin
      pixel <= leaf_pixel(bx);
    end
  end

  wire _unused = &{rnd[31], rnd[25:8], 1'b0};
endmodule
