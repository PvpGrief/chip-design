`default_nettype none
`timescale 1ns / 1ps

// Quick Icarus Verilog smoke test: two frames, sync timing and a few
// known pixels of the opening screen decoded from uo_out.
module tb_smoke;
  reg        clk = 0;
  reg        rst_n = 0;
  reg  [7:0] ui_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;

  tt_um_pvpgrief_pong dut (
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
  // position the pixel currently on the pins belongs to.
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
      if (sx == 100 && sy == 100) expect_pixel(sx, sy, r == 0 && g == 0 && b == 1, "background");
      if (sx == 100 && sy == 4)   expect_pixel(sx, sy, r == 2 && g == 2 && b == 2, "top wall");
      if (sx == 100 && sy == 475) expect_pixel(sx, sy, r == 2 && g == 2 && b == 2, "bottom wall");
      if (sx == 28  && sy == 240) expect_pixel(sx, sy, r == 0 && g == 3 && b == 3, "left paddle");
      if (sx == 610 && sy == 240) expect_pixel(sx, sy, r == 3 && g == 0 && b == 3, "right paddle");
      if (sx == 320 && sy == 240) expect_pixel(sx, sy, r == 3 && g == 3 && b == 0, "ball");
      if (sx == 320 && sy == 20)  expect_pixel(sx, sy, r == 2 && g == 2 && b == 2, "centre line");
      if (sx == 260 && sy == 36)  expect_pixel(sx, sy, r == 0 && g == 3 && b == 3, "left score");
      if (sx == 268 && sy == 52)  expect_pixel(sx, sy, r == 0 && g == 0 && b == 1, "inside of the 0");
      if (sx == 364 && sy == 36)  expect_pixel(sx, sy, r == 3 && g == 0 && b == 3, "right score");
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
