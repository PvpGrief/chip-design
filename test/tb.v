`default_nettype none
`timescale 1ns / 1ps

// Quick Icarus Verilog smoke test: two frames, sync timing and a few
// known pixels of the scene (sky, sun, grass, trunk) decoded from uo_out.
module tb;
  reg        clk = 0;
  reg        rst_n = 0;
  reg  [7:0] ui_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;

  tt_um_falling_leaves dut (
      .ui_in(ui_in),
      .uo_out(uo_out),
      .uio_in(8'd0),
      .uio_out(uio_out),
      .uio_oe(uio_oe),
      .ena(1'b1),
      .clk(clk),
      .rst_n(rst_n)
  );

  always #20 clk = ~clk;  // 25 MHz

  wire       hsync = uo_out[7];
  wire       vsync = uo_out[3];
  wire [1:0] r = {uo_out[0], uo_out[4]};
  wire [1:0] g = {uo_out[1], uo_out[5]};
  wire [1:0] b = {uo_out[2], uo_out[6]};

  // The output register adds one clock of latency: remember which beam
  // position the pixel currently on the pins was computed for.
  reg [9:0] sx, sy;
  always @(posedge clk) begin
    sx <= dut.hpos;
    sy <= dut.vpos;
  end

  integer errors = 0;
  integer frames = 0;
  time    t_hfall = 0, t_vfall = 0;
  reg     prev_hs = 1, prev_vs = 1;

  task expect_pixel(input [9:0] x, input [9:0] y, input ok, input [8*24-1:0] what);
    if (!ok) begin
      $display("FAIL: pixel (%0d,%0d) is not %0s: rgb=%0d,%0d,%0d", x, y, what, r, g, b);
      errors = errors + 1;
    end
  endtask

  always @(negedge clk) if (rst_n) begin
    if (prev_hs && !hsync) begin
      if (t_hfall != 0 && $time - t_hfall != 800 * 40) begin
        $display("FAIL: hsync period %0t", $time - t_hfall);
        errors = errors + 1;
      end
      t_hfall = $time;
    end
    if (prev_vs && !vsync) begin
      if (t_vfall != 0 && $time - t_vfall != 800 * 525 * 40) begin
        $display("FAIL: vsync period %0t", $time - t_vfall);
        errors = errors + 1;
      end
      t_vfall = $time;
      frames = frames + 1;
    end
    prev_hs = hsync;
    prev_vs = vsync;

    if (frames >= 1) begin
      if (sx == 10   && sy == 10)  expect_pixel(sx, sy, b >= 2 && r <= 1, "sky");
      if (sx == 548  && sy == 70)  expect_pixel(sx, sy, r == 3 && g == 3, "sun");
      if (sx == 20   && sy == 460) expect_pixel(sx, sy, g >= 1 && r <= 1 && b == 0, "grass");
      if (sx == 320  && sy == 340) expect_pixel(sx, sy, r >= 1 && b <= 1 && r >= g, "trunk");
      if (sx >= 640 && (r | g | b) != 0) begin
        $display("FAIL: colour during blanking at x=%0d", sx);
        errors = errors + 1;
      end
    end
  end

  initial begin
    $display("tb: simulating 2 frames...");
    repeat (10) @(posedge clk);
    rst_n = 1;
    wait (frames == 3);
    if (uio_oe !== 8'd0) begin
      $display("FAIL: uio_oe should be 0");
      errors = errors + 1;
    end
    if (errors == 0) $display("PASS");
    else $display("FAILED with %0d error(s)", errors);
    $finish;
  end
endmodule
