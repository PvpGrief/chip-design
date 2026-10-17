`default_nettype none

// 640x480 @ 60 Hz VGA timing (25.175 MHz pixel clock, 25 MHz works too).
// hsync/vsync are active-low, as this mode requires.
module hvsync_generator (
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
