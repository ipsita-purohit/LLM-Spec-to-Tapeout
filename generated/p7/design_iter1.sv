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

  logic                 valid_s1;
  logic [WIDTH-1:0]     x_s1;
  logic [OUT_WIDTH-1:0] x2_s1;
  logic [OUT_WIDTH-1:0] x3_s1;

  logic [OUT_WIDTH-1:0] x2_scaled_c;
  logic [OUT_WIDTH-1:0] x3_scaled_c;
  logic [OUT_WIDTH-1:0] exp_sum_c;

  logic [2*WIDTH-1:0] x_sq_full;
  logic [3*WIDTH-1:0] x_cu_full;

  always_comb begin
    x_sq_full   = x_in * x_in;
    x2_scaled_c = x_sq_full >> FRAC;

    x_cu_full   = x2_scaled_c * x_in;
    x3_scaled_c = x_cu_full >> FRAC;

    exp_sum_c   = {{(OUT_WIDTH - FRAC - 1){1'b0}}, 1'b1, {FRAC{1'b0}}}
                + {{WIDTH{1'b0}}, x_s1}
                + (x2_s1 >> 1)
                + (x3_s1 / 6);
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
        x2_s1 <= x2_scaled_c;
        x3_s1 <= x3_scaled_c;
      end else begin
        x_s1  <= '0;
        x2_s1 <= '0;
        x3_s1 <= '0;
      end

      if (valid_s1) begin
        exp_out <= exp_sum_c;
      end else begin
        exp_out <= '0;
      end
    end
  end

endmodule
