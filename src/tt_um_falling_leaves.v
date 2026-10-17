`default_nettype none

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
      leaf u_leaf (
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
  tree_scene scene (
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
