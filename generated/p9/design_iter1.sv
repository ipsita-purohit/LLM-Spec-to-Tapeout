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

  localparam int OUT_W  = 2*WIDTH + $clog2(N) + 1;
  localparam int LEVELS = (N > 1) ? $clog2(N) : 1;

  logic signed [WIDTH-1:0] x_delay [0:N-1];
  logic signed [2*WIDTH-1:0] mult_reg [0:N-1];
  logic signed [OUT_W-1:0] sum_stage [0:LEVELS][0:N-1];

  integer i;
  integer j;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < N; i = i + 1) begin
        x_delay[i] <= '0;
      end
    end else begin
      x_delay[0] <= x_in;
      for (i = 1; i < N; i = i + 1) begin
        x_delay[i] <= x_delay[i-1];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < N; i = i + 1) begin
        mult_reg[i]    <= '0;
        sum_stage[0][i] <= '0;
      end
    end else begin
      for (i = 0; i < N; i = i + 1) begin
        mult_reg[i]    <= x_delay[i] * h[i];
        sum_stage[0][i] <= mult_reg[i];
      end
    end
  end

  genvar level;
  generate
    for (level = 1; level <= LEVELS; level = level + 1) begin : gen_sum_levels
      always_ff @(posedge clk) begin
        if (rst) begin
          for (j = 0; j < N; j = j + 1) begin
            sum_stage[level][j] <= '0;
          end
        end else begin
          for (j = 0; j < N; j = j + 1) begin
            if (j < ((N + (1 << level) - 1) >> level)) begin
              if (((2*j) + 1) < ((N + (1 << (level-1)) - 1) >> (level-1))) begin
                sum_stage[level][j] <= sum_stage[level-1][2*j] + sum_stage[level-1][2*j+1];
              end else if ((2*j) < ((N + (1 << (level-1)) - 1) >> (level-1))) begin
                sum_stage[level][j] <= sum_stage[level-1][2*j];
              end else begin
                sum_stage[level][j] <= '0;
              end
            end else begin
              sum_stage[level][j] <= '0;
            end
          end
        end
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (rst) begin
      y_out <= '0;
    end else begin
      y_out <= sum_stage[LEVELS][0];
    end
  end

endmodule
