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

  localparam YW = 2*WIDTH + $clog2(N) + 1;

  logic signed [WIDTH-1:0] x_delay [0:N-1];
  logic signed [YW-1:0] sum_next;

  integer i;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      for (i = 0; i < N; i = i + 1) begin
        x_delay[i] <= '0;
      end
      y_out <= '0;
    end else begin
      x_delay[0] <= x_in;
      for (i = 1; i < N; i = i + 1) begin
        x_delay[i] <= x_delay[i-1];
      end
      y_out <= sum_next;
    end
  end

  always_comb begin
    sum_next = '0;
    for (i = 0; i < N; i = i + 1) begin
      sum_next = sum_next + ($signed(x_delay[i]) * $signed(h[i]));
    end
  end

endmodule
