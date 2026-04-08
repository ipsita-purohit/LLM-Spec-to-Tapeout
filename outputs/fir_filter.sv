module fir_filter #(
  parameter WIDTH = 16,
  parameter N = 8
) (
  input  logic                             clk,
  input  logic                             rst,
  input  logic signed [WIDTH-1:0]          x_in,
  input  logic signed [N-1:0][WIDTH-1:0]   h,
  output logic signed [2*WIDTH+$clog2(N):0] y_out
);

  localparam int ACC_WIDTH = 2*WIDTH + $clog2(N) + 1;

  logic signed [WIDTH-1:0] delay_line [0:N-1];
  logic signed [2*WIDTH-1:0] product;
  logic signed [ACC_WIDTH-1:0] acc_sum;
  integer tap;
  integer shift_idx;

  always_comb begin
    acc_sum = '0;
    for (tap = 0; tap < N; tap = tap + 1) begin
      if (tap == 0) begin
        product = x_in * h[tap];
      end else begin
        product = delay_line[tap-1] * h[tap];
      end
      acc_sum = acc_sum + $signed(product);
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      y_out <= '0;
      for (shift_idx = 0; shift_idx < N; shift_idx = shift_idx + 1) begin
        delay_line[shift_idx] <= '0;
      end
    end else begin
      y_out <= acc_sum;
      delay_line[0] <= x_in;
      for (shift_idx = 1; shift_idx < N; shift_idx = shift_idx + 1) begin
        delay_line[shift_idx] <= delay_line[shift_idx-1];
      end
    end
  end

endmodule
