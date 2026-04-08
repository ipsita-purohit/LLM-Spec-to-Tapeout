module exp_fixed_point #(
  parameter WIDTH = 8
) (
  input  logic               clk,
  input  logic               rst,
  input  logic               enable,
  input  logic [WIDTH-1:0]   x_in,
  output logic [2*WIDTH-1:0] exp_out
);

  localparam int FRAC = WIDTH - 1;
  localparam int OUT_WIDTH = 2 * WIDTH;
  localparam int CALC_WIDTH = 4 * WIDTH;

  logic [OUT_WIDTH-1:0] x_s1;
  logic [OUT_WIDTH-1:0] x2_s1;
  logic [OUT_WIDTH-1:0] x3_s1;

  logic [CALC_WIDTH-1:0] x_ext;
  logic [CALC_WIDTH-1:0] x2_full;
  logic [CALC_WIDTH-1:0] x3_full;
  logic [OUT_WIDTH-1:0]  x_scaled;
  logic [OUT_WIDTH-1:0]  x2_scaled;
  logic [OUT_WIDTH-1:0]  x3_scaled;
  logic [OUT_WIDTH-1:0]  one_scaled;
  logic [OUT_WIDTH-1:0]  taylor_sum;

  always_comb begin
    x_ext = {{(CALC_WIDTH-WIDTH){1'b0}}, x_in};

    x2_full = (x_ext * x_ext) >> FRAC;
    x3_full = (x2_full * x_ext) >> FRAC;

    x_scaled   = {{WIDTH{1'b0}}, x_in};
    x2_scaled  = x2_full;
    x3_scaled  = x3_full;
    one_scaled = {{(OUT_WIDTH-FRAC-1){1'b0}}, 1'b1, {FRAC{1'b0}}};

    taylor_sum = one_scaled + x_s1 + (x2_s1 >> 1) + (x3_s1 / 6);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      x_s1    <= '0;
      x2_s1   <= '0;
      x3_s1   <= '0;
      exp_out <= '0;
    end else if (enable) begin
      x_s1    <= x_scaled;
      x2_s1   <= x2_scaled;
      x3_s1   <= x3_scaled;
      exp_out <= taylor_sum;
    end
  end

endmodule
