module exp_fixed_point #(
  parameter WIDTH = 8
) (
  input  logic               clk,
  input  logic               rst,
  input  logic               enable,
  input  logic [WIDTH-1:0]   x_in,
  output logic [2*WIDTH-1:0] exp_out
);

  localparam int FRAC      = WIDTH - 1;
  localparam int OUT_WIDTH = 2 * WIDTH;
  localparam int X2_WIDTH  = 2 * WIDTH;
  localparam int X3_WIDTH  = 3 * WIDTH;

  logic                 valid_s1;
  logic [WIDTH-1:0]     x_s1;
  logic [X2_WIDTH-1:0]  x2_s1;
  logic [X3_WIDTH-1:0]  x3_s1;

  logic [OUT_WIDTH-1:0] stage2_sum;
  logic [OUT_WIDTH-1:0] one_term;
  logic [OUT_WIDTH-1:0] x_term;
  logic [OUT_WIDTH-1:0] x2_term;
  logic [OUT_WIDTH-1:0] x3_term;

  always_comb begin
    one_term   = '0;
    x_term     = '0;
    x2_term    = '0;
    x3_term    = '0;
    stage2_sum = '0;

    one_term[FRAC] = 1'b1;
    x_term         = {{WIDTH{1'b0}}, x_s1};
    x2_term        = ({{(OUT_WIDTH - X2_WIDTH){1'b0}}, x2_s1} >> FRAC) >> 1;
    x3_term        = ({{(OUT_WIDTH - WIDTH){1'b0}}, (x3_s1 >> (2 * FRAC))}) / 6;
    stage2_sum     = one_term + x_term + x2_term + x3_term;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      valid_s1 <= 1'b0;
      x_s1     <= '0;
      x2_s1    <= '0;
      x3_s1    <= '0;
      exp_out  <= '0;
    end else begin
      valid_s1 <= enable;

      if (enable) begin
        x_s1  <= x_in;
        x2_s1 <= x_in * x_in;
        x3_s1 <= (x_in * x_in) * x_in;
      end else begin
        x_s1  <= '0;
        x2_s1 <= '0;
        x3_s1 <= '0;
      end

      if (valid_s1) begin
        exp_out <= stage2_sum;
      end else begin
        exp_out <= '0;
      end
    end
  end

endmodule
