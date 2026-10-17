`default_nettype none

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

  hvsync_generator vga (
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

  leaves #(.N(8)) u_leaves (
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
  tree_scene scene (
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
