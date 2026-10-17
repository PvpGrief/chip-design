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
// Output is 640x480 @ 60 Hz on the TinyVGA Pmod pinout, drawn in chunky
// 4x4-pixel blocks (160x120). A free-running LFSR decides when the next leaf
// lets go (every ~0.5-2.6 s), where on the tree it starts, its colour and how
// long it lies on the grass afterwards.
//
// All drawing logic is evaluated once per block (one clock in four) and held,
// which keeps the design small and fast to simulate.
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

  // Draw the block under the beam on its first pixel
  wire       en = display_on && (hpos[1:0] == 2'd0);
  wire [7:0] bx = hpos[9:2];
  wire [6:0] by = vpos[8:2];

  // Leaf sprite rows for the next line are prepared during horizontal blank
  wire       row_load = (hpos == 10'd700);
  wire [9:0] next_vpos = (vpos == 10'd524) ? 10'd0 : vpos + 10'd1;
  wire [6:0] row_by   = next_vpos[8:2];

  // ---- randomness: 32-bit maximal-length Galois LFSR, stepped every line ---
  reg [31:0] lfsr;
  always @(posedge clk) begin
    if (!rst_n)
      lfsr <= 32'hACE1_2468;
    else if (hpos == 10'd0)
      lfsr <= {1'b0, lfsr[31:1]} ^ (lfsr[0] ? 32'h8020_0003 : 32'h0);
  end

  // ---- leaf spawner ---------------------------------------------------------
  reg  [7:0] spawn_timer;  // frames until the next leaf lets go
  wire       spawn_now = step && (spawn_timer == 8'd0);

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

  wire       rotted, leaf_hit;
  wire [5:0] leaf_rgb;

  falling_leaves_leaves #(.N(8)) u_leaves (
      .clk(clk),
      .rst_n(rst_n),
      .frame_tick(frame_tick),
      .freeze(freeze),
      .wind(storm),
      .spawn_now(spawn_now),
      .spawn_x(spawn_x),
      .spawn_y(spawn_y),
      .rnd(lfsr),
      .row_load(row_load),
      .row_by(row_by),
      .en(en),
      .bx(bx),
      .rotted(rotted),
      .hit(leaf_hit),
      .rgb(leaf_rgb)
  );

  // ---- scenery state --------------------------------------------------------
  reg [7:0] cloud_x;
  reg [3:0] cloud_div;
  reg [3:0] litter;  // grows as leaves rot on the grass, slowly blows away
  reg [7:0] decay;

  always @(posedge clk) begin
    if (!rst_n) begin
      spawn_timer <= 8'd20;
      cloud_x     <= 8'd10;
      cloud_div   <= 4'd0;
      litter      <= 4'd0;
      decay       <= 8'd0;
    end else if (step) begin
      if (spawn_timer == 8'd0)
        spawn_timer <= storm ? 8'd3 + {4'd0, lfsr[24:21]}
                             : 8'd30 + {1'b0, lfsr[27:21]};
      else
        spawn_timer <= spawn_timer - 8'd1;

      cloud_div <= cloud_div + 4'd1;
      if (storm ? cloud_div[0] : (cloud_div == 4'd0)) cloud_x <= cloud_x + 8'd1;

      decay <= decay + 8'd1;
      if (rotted) begin
        if (litter != 4'd15) litter <= litter + 4'd1;
      end else if (litter != 4'd0 && (decay == 8'd0 || (storm && decay[3:0] == 4'd0)))
        litter <= litter - 4'd1;
    end
  end

  // ---- pixel output ---------------------------------------------------------
  wire [5:0] scene_rgb;
  falling_leaves_scene scene (
      .clk(clk),
      .en(en),
      .bx(bx),
      .by(by),
      .cloud_x(cloud_x),
      .litter(litter),
      .storm(storm),
      .rgb(scene_rgb)
  );

  // The block colours appear one clock after `en`, so sync and blanking are
  // delayed by one clock to match.
  reg       hsync_d, vsync_d, display_d;
  reg       hsync_r, vsync_r;
  reg [5:0] rgb_r;
  always @(posedge clk) begin
    if (!rst_n) begin
      hsync_d   <= 1'b1;
      vsync_d   <= 1'b1;
      display_d <= 1'b0;
      hsync_r   <= 1'b1;
      vsync_r   <= 1'b1;
      rgb_r     <= 6'd0;
    end else begin
      hsync_d   <= hsync;
      vsync_d   <= vsync;
      display_d <= display_on;
      hsync_r   <= hsync_d;
      vsync_r   <= vsync_d;
      rgb_r     <= !display_d ? 6'd0 : leaf_hit ? leaf_rgb : scene_rgb;
    end
  end

  // TinyVGA Pmod: {hsync, B0, G0, R0, vsync, B1, G1, R1}
  assign uo_out  = {hsync_r, rgb_r[0], rgb_r[2], rgb_r[4], vsync_r, rgb_r[1], rgb_r[3], rgb_r[5]};
  assign uio_out = 8'd0;
  assign uio_oe  = 8'd0;

  wire _unused = &{ena, uio_in, ui_in[7:2], next_vpos[9], next_vpos[1:0], 1'b0};
endmodule

// ---- leaves.v --------------------------------------------------------------

// The falling leaves: N independent leaf slots.
//
// Physics run in pixel units once per frame. Drawing is in 4x4-pixel blocks:
// once per line each leaf's sprite row is looked up (row_load), and per block
// only a subtract and a bit test per leaf remain. A leaf is a 4x4-block
// sprite (16x16 pixels) that flutters down from (spawn_x, spawn_y), swinging
// side to side, lies on the grass for a random while, dissolves and frees
// its slot. In a storm it falls faster, drifts right and gets blown away.
module falling_leaves_leaves #(
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

// ---- tree_scene.v ----------------------------------------------------------

// Background: sky, sun, a drifting cloud, grassy mound, the tree and the
// pile of fallen leaves under it, drawn in 4x4-pixel blocks (160x120).
// Only evaluated when `en` is high (once per block); the result is held.
module falling_leaves_scene (
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
