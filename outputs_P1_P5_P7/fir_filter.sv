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

  localparam int Y_WIDTH = 2*WIDTH + $clog2(N) + 1;

  logic signed [WIDTH-1:0] sample_hist [0:N-1];
  logic signed [WIDTH-1:0] sample_hist_next [0:N-1];
  logic signed [Y_WIDTH-1:0] sum_next;
  integer i;

  always_comb begin
    sample_hist_next[0] = x_in;
    for (i = 1; i < N; i = i + 1) begin
      sample_hist_next[i] = sample_hist[i-1];
    end

    sum_next = '0;
    for (i = 0; i < N; i = i + 1) begin
      sum_next = sum_next + ($signed(sample_hist_next[i]) * $signed(h[i]));
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      y_out <= '0;
      for (i = 0; i < N; i = i + 1) begin
        sample_hist[i] <= '0;
      end
    end else begin
      y_out <= sum_next;
      for (i = 0; i < N; i = i + 1) begin
        sample_hist[i] <= sample_hist_next[i];
      end
    end
  end

endmodule
