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

  localparam int PROD_W = 2*WIDTH;
  localparam int ACC_W  = 2*WIDTH + $clog2(N) + 1;

  logic signed [WIDTH-1:0] x_hist [0:N-1];
  logic signed [ACC_W-1:0] acc_next;
  logic signed [PROD_W-1:0] prod_term;

  integer i;

  always_comb begin
    acc_next = '0;
    for (i = 0; i < N; i = i + 1) begin
      if (i == 0) begin
        prod_term = $signed(x_in) * $signed(h[i]);
      end else begin
        prod_term = $signed(x_hist[i-1]) * $signed(h[i]);
      end
      acc_next = acc_next + {{(ACC_W-PROD_W){prod_term[PROD_W-1]}}, prod_term};
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      y_out <= '0;
      for (i = 0; i < N; i = i + 1) begin
        x_hist[i] <= '0;
      end
    end else begin
      y_out <= acc_next;
      x_hist[0] <= x_in;
      for (i = 1; i < N; i = i + 1) begin
        x_hist[i] <= x_hist[i-1];
      end
    end
  end

endmodule
