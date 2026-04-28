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

  localparam YW = 2*WIDTH + $clog2(N) + 1;

  logic signed [WIDTH-1:0] sample_reg [0:N-1];
  logic signed [YW-1:0] acc;
  logic signed [2*WIDTH-1:0] product;
  integer i;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < N; i = i + 1) begin
        sample_reg[i] <= '0;
      end
    end else begin
      sample_reg[0] <= x_in;
      for (i = 1; i < N; i = i + 1) begin
        sample_reg[i] <= sample_reg[i-1];
      end
    end
  end

  always_comb begin
    acc = '0;
    for (i = 0; i < N; i = i + 1) begin
      product = sample_reg[i] * h[i];
      acc = acc + {{(YW-(2*WIDTH)){product[2*WIDTH-1]}}, product};
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      y_out <= '0;
    end else begin
      y_out <= acc;
    end
  end

endmodule
