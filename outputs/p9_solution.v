module fir_filter #(
  parameter WIDTH = 16,
  parameter N = 8
) (
  input  logic                              clk,
  input  logic                              rst,
  input  logic signed [WIDTH-1:0]           x_in,
  input  logic signed [N-1:0][WIDTH-1:0]    h,
  output logic signed [2*WIDTH+$clog2(N):0] y_out
);

  localparam ACC_WIDTH = 2*WIDTH + $clog2(N) + 1;

  logic signed [WIDTH-1:0] sample_delay [0:N-1];
  logic signed [ACC_WIDTH-1:0] acc_next;
  integer i;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < N; i = i + 1) begin
        sample_delay[i] <= '0;
      end
    end else begin
      sample_delay[0] <= x_in;
      for (i = 1; i < N; i = i + 1) begin
        sample_delay[i] <= sample_delay[i-1];
      end
    end
  end

  always_comb begin
    acc_next = '0;
    for (i = 0; i < N; i = i + 1) begin
      acc_next += sample_delay[i] * h[i];
    end
    y_out = acc_next;
  end

endmodule
