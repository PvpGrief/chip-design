`default_nettype none

// Reads the Tiny Tapeout Gamepad Pmod: two SNES-style controllers sent as a
// serial stream on latch/clock/data. 24 bits are shifted in on rising pmod_clk
// edges and taken over on a rising pmod_latch edge; controller 1 is the last
// 12 bits. A controller that isn't plugged in reads as all ones.
//
// Each pad output is {b, y, select, start, up, down, left, right, a, x, l, r}
// with 1 = pressed (all zero when the controller is missing).
module pong_gamepad (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pmod_latch,
    input  wire        pmod_clk,
    input  wire        pmod_data,
    output wire [11:0] pad1,
    output wire [11:0] pad2
);
  reg [1:0]  latch_s, clk_s, data_s;  // synchronisers
  reg        latch_prev, clk_prev;
  reg [23:0] shift, data;

  always @(posedge clk) begin
    if (!rst_n) begin
      latch_s    <= 2'b00;
      clk_s      <= 2'b00;
      data_s     <= 2'b00;
      latch_prev <= 1'b0;
      clk_prev   <= 1'b0;
      shift      <= {24{1'b1}};
      data       <= {24{1'b1}};
    end else begin
      latch_s    <= {latch_s[0], pmod_latch};
      clk_s      <= {clk_s[0], pmod_clk};
      data_s     <= {data_s[0], pmod_data};
      latch_prev <= latch_s[1];
      clk_prev   <= clk_s[1];
      if (clk_s[1] && !clk_prev) shift <= {shift[22:0], data_s[1]};
      if (latch_s[1] && !latch_prev) data <= shift;
    end
  end

  assign pad1 = (data[11:0]  == 12'hFFF) ? 12'd0 : data[11:0];
  assign pad2 = (data[23:12] == 12'hFFF) ? 12'd0 : data[23:12];
endmodule
