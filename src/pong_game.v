`default_nettype none

// Pong game logic, updated once per frame.
//
// Field: walls above y=8 and below y=472. Paddles are 10x64 at x=24 (left)
// and x=606 (right). The ball is 10x10; where it hits a paddle sets how
// steeply it bounces off. First to 9 wins.
//
// Speeds are in 1/16 px per frame. The ball starts at 4 px/frame across and
// gets 1/4 px/frame faster on every return, up to 10 px/frame. The paddles
// always move 3 px/frame faster than the ball does across (7 at the start,
// up to 13), so they keep up as a rally heats up. Both reset after a point.
//
// The last five ball positions (sampled every other frame) are kept for the
// trail drawn behind the ball.
module pong_game (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pre_tick1,   // two lines before frame_tick
    input  wire        pre_tick2,   // one line before frame_tick
    input  wire        frame_tick,
    input  wire        new_game,
    input  wire        l_up,
    input  wire        l_down,
    input  wire        r_up,
    input  wire        r_down,
    input  wire [2:0]  rnd,
    output reg  [8:0]  pl_y,       // left paddle top
    output reg  [8:0]  pr_y,       // right paddle top
    output reg  [9:0]  ball_x,     // ball top-left
    output reg  [8:0]  ball_y,
    output reg  [49:0] trail_x,    // trail position k is trail_x[10*k +: 10], newest first
    output reg  [44:0] trail_y,    // ... and trail_y[9*k +: 9]
    output reg  [3:0]  score_l,
    output reg  [3:0]  score_r,
    output wire        serving,    // ball waiting in the middle
    output wire        game_over,
    output reg         winner_r,   // who won (valid when game_over)
    output wire        blink       // ~2 Hz, for blinking things
);
  localparam [8:0] TOP      = 9'd8;
  localparam [8:0] BOTTOM   = 9'd472;
  localparam [8:0] PADDLE_H = 9'd64;
  localparam [9:0] LEFT_FACE  = 10'd34;   // right edge of the left paddle
  localparam [9:0] RIGHT_FACE = 10'd606;  // left edge of the right paddle
  localparam [9:0] BALL     = 10'd10;
  localparam [9:0] CENTER_X = 10'd315;
  localparam [8:0] CENTER_Y = 9'd235;
  localparam [8:0] PADDLE_MID = 9'd208;
  localparam [3:0] WIN      = 4'd9;

  localparam [7:0] VX_START = 8'h40;  // 4.0 px/frame (4.4 fixed point)
  localparam [7:0] VX_STEP  = 8'h04;  // +0.25 px/frame per return
  localparam [7:0] VX_MAX   = 8'hA0;  // 10.0 px/frame
  localparam [7:0] PADDLE_EXTRA = 8'h30;  // paddles: ball speed + 3.0
  localparam [12:0] PADDLE_MIN = {TOP, 4'd0};                  // 9.4 fixed point
  localparam [12:0] PADDLE_MAX = {BOTTOM - PADDLE_H, 4'd0};

  localparam [1:0] SERVE = 2'd0, PLAY = 2'd1, OVER = 2'd2;

  reg [1:0] state;
  reg [7:0] timer;
  reg [7:0] vx;          // ball speed across, 1/16 px per frame
  reg [3:0] ball_xf;     // fractional parts of the ball and paddle positions
  reg [3:0] pl_f, pr_f;
  reg       vx_left;
  reg [2:0] vy;
  reg       vy_up;
  reg       serve_left;  // direction of the next serve
  reg       trail_tick;
  reg [4:0] frames;

  assign serving   = (state == SERVE);
  assign game_over = (state == OVER);
  assign blink     = frames[4];

  // Bounce angle from where the ball meets the paddle: distance between the
  // ball's centre and the paddle's centre, /8, at least 1 and at most 6.
  /* verilator lint_off BLKSEQ */
  function [3:0] bounce;  // {up, speed}
    input [8:0] by, py;
    reg [9:0] d;
    /* verilator lint_off UNUSED */
    reg [9:0] ad;  // only ad/8 is used
    /* verilator lint_on UNUSED */
    begin
      d  = {1'b0, by} + 10'd5 - {1'b0, py} - 10'd32;
      ad = d[9] ? 10'd0 - d : d;
      if (ad[9:3] == 7'd0)      bounce = {d[9], 3'd1};
      else if (ad[9:3] > 7'd6)  bounce = {d[9], 3'd6};
      else                      bounce = {d[9], ad[5:3]};
    end
  endfunction
  /* verilator lint_on BLKSEQ */

  // The frame update is prepared on the two lines before it, in registers,
  // so this logic only runs a few times per frame (instead of being
  // continuous logic, which a cycle-based simulator evaluates every clock).
  reg [13:0] next_x;     // ball x after this frame, 10.4 fixed point
  reg [8:0] next_y;
  reg [3:0] bounce_l, bounce_r;
  reg       hits_left, hits_right, out_left, out_right;

  always @(posedge clk) begin
    if (pre_tick1) begin
      next_x   <= vx_left ? {ball_x, ball_xf} - {6'd0, vx} : {ball_x, ball_xf} + {6'd0, vx};
      next_y   <= vy_up   ? ball_y - {6'd0, vy} : ball_y + {6'd0, vy};
      bounce_l <= bounce(ball_y, pl_y);
      bounce_r <= bounce(ball_y, pr_y);
    end
    if (pre_tick2) begin
      hits_left  <= vx_left && ball_x >= LEFT_FACE && next_x[13:4] < LEFT_FACE &&
                    ball_y + 9'd10 > pl_y && ball_y < pl_y + PADDLE_H;
      hits_right <= !vx_left && ball_x + BALL <= RIGHT_FACE && next_x[13:4] + BALL > RIGHT_FACE &&
                    ball_y + 9'd10 > pr_y && ball_y < pr_y + PADDLE_H;
      out_left   <= vx_left && {ball_x, ball_xf} <= {6'd0, vx};
      out_right  <= !vx_left && {ball_x, ball_xf} + {6'd0, vx} >= {10'd630, 4'd0};
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state      <= SERVE;
      timer      <= 8'd90;
      pl_y       <= PADDLE_MID;
      pr_y       <= PADDLE_MID;
      ball_x     <= CENTER_X;
      ball_y     <= CENTER_Y;
      trail_x    <= {5{CENTER_X}};
      trail_y    <= {5{CENTER_Y}};
      vx         <= VX_START;
      ball_xf    <= 4'd0;
      pl_f       <= 4'd0;
      pr_f       <= 4'd0;
      vx_left    <= 1'b0;
      vy         <= 3'd1;
      vy_up      <= 1'b0;
      serve_left <= 1'b0;
      score_l    <= 4'd0;
      score_r    <= 4'd0;
      winner_r   <= 1'b0;
      trail_tick <= 1'b0;
      frames     <= 5'd0;
    end else if (frame_tick) begin
      frames <= frames + 5'd1;

      // Paddles move in every state
      if (l_up && !l_down)
        {pl_y, pl_f} <= ({pl_y, pl_f} > PADDLE_MIN + {5'd0, vx + PADDLE_EXTRA})
                        ? {pl_y, pl_f} - {5'd0, vx + PADDLE_EXTRA} : PADDLE_MIN;
      else if (l_down && !l_up)
        {pl_y, pl_f} <= ({pl_y, pl_f} + {5'd0, vx + PADDLE_EXTRA} < PADDLE_MAX)
                        ? {pl_y, pl_f} + {5'd0, vx + PADDLE_EXTRA} : PADDLE_MAX;
      if (r_up && !r_down)
        {pr_y, pr_f} <= ({pr_y, pr_f} > PADDLE_MIN + {5'd0, vx + PADDLE_EXTRA})
                        ? {pr_y, pr_f} - {5'd0, vx + PADDLE_EXTRA} : PADDLE_MIN;
      else if (r_down && !r_up)
        {pr_y, pr_f} <= ({pr_y, pr_f} + {5'd0, vx + PADDLE_EXTRA} < PADDLE_MAX)
                        ? {pr_y, pr_f} + {5'd0, vx + PADDLE_EXTRA} : PADDLE_MAX;

      if (new_game) begin
        state   <= SERVE;
        timer   <= 8'd60;
        score_l <= 4'd0;
        score_r <= 4'd0;
        vx      <= VX_START;
        ball_x  <= CENTER_X;
        ball_xf <= 4'd0;
        ball_y  <= CENTER_Y;
        trail_x <= {5{CENTER_X}};
        trail_y <= {5{CENTER_Y}};
      end else begin
        case (state)
          SERVE: begin
            if (timer == 8'd0) begin
              state   <= PLAY;
              vx      <= VX_START;
              vx_left <= serve_left;
              vy      <= 3'd1 + {1'b0, rnd[1:0] == 2'd3 ? 2'd2 : rnd[1:0]};
              vy_up   <= rnd[2];
            end else begin
              timer <= timer - 8'd1;
            end
          end

          PLAY: begin
            // trail: remember where the ball was, every other frame
            trail_tick <= ~trail_tick;
            if (trail_tick) begin
              trail_x <= {trail_x[39:0], ball_x};
              trail_y <= {trail_y[35:0], ball_y};
            end

            if (hits_left) begin
              ball_x  <= LEFT_FACE;
              ball_xf <= 4'd0;
              vx_left <= 1'b0;
              if (vx != VX_MAX) vx <= vx + VX_STEP;
              {vy_up, vy} <= bounce_l;
            end else if (hits_right) begin
              ball_x  <= RIGHT_FACE - BALL;
              ball_xf <= 4'd0;
              vx_left <= 1'b1;
              if (vx != VX_MAX) vx <= vx + VX_STEP;
              {vy_up, vy} <= bounce_r;
            end else if (out_left || out_right) begin
              // point to the other player; the loser receives the next serve
              if (out_left) score_r <= score_r + 4'd1;
              else          score_l <= score_l + 4'd1;
              serve_left <= out_left;
              vx         <= VX_START;
              ball_x     <= CENTER_X;
              ball_xf    <= 4'd0;
              ball_y     <= CENTER_Y;
              trail_x    <= {5{CENTER_X}};
              trail_y    <= {5{CENTER_Y}};
              if ((out_left ? score_r : score_l) == WIN - 4'd1) begin
                state    <= OVER;
                timer    <= 8'd240;
                winner_r <= out_left;
              end else begin
                state <= SERVE;
                timer <= 8'd60;
              end
            end else begin
              {ball_x, ball_xf} <= next_x;
            end

            // top and bottom walls
            if (!(out_left || out_right)) begin
              if (vy_up && next_y <= TOP) begin
                ball_y <= TOP;
                vy_up  <= 1'b0;
              end else if (!vy_up && next_y + 9'd10 >= BOTTOM) begin
                ball_y <= BOTTOM - 9'd10;
                vy_up  <= 1'b1;
              end else if (!(hits_left || hits_right)) begin
                ball_y <= next_y;
              end
            end
          end

          default: begin  // OVER: show the result for a few seconds, then start again
            if (timer == 8'd0) begin
              state   <= SERVE;
              timer   <= 8'd60;
              score_l <= 4'd0;
              score_r <= 4'd0;
            end else begin
              timer <= timer - 8'd1;
            end
          end
        endcase
      end
    end
  end
endmodule
