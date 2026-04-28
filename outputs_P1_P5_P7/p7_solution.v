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

  logic [WIDTH-1:0] x_s1;
  logic [OUT_WIDTH-1:0] x2_s1;
  logic [OUT_WIDTH-1:0] x3_s1;

  logic [OUT_WIDTH-1:0] x2_scaled;
  logic [OUT_WIDTH-1:0] x3_scaled;
  logic [OUT_WIDTH-1:0] term_const;
  logic [OUT_WIDTH-1:0] sum_s2;

  always_comb begin
    x2_scaled = (x_in * x_in) >> FRAC;
    x3_scaled = (x2_scaled * x_in) >> FRAC;
    term_const = {{(OUT_WIDTH-FRAC-1){1'b0}}, 1'b1, {FRAC{1'b0}}};
    sum_s2 = term_const
           + {{WIDTH{1'b0}}, x_s1}
           + (x2_s1 >> 1)
           + (x3_s1 / 6);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      x_s1   <= '0;
      x2_s1  <= '0;
      x3_s1  <= '0;
      exp_out <= '0;
    end else if (enable) begin
      x_s1   <= x_in;
      x2_s1  <= x2_scaled;
      x3_s1  <= x3_scaled;
      exp_out <= sum_s2;
    end
  end

endmodule
