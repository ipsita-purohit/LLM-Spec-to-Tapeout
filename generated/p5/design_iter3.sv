module dot_product #(
    parameter int N = 8,
    parameter int WIDTH = 8
) (
    input  logic clk,
    input  logic rst,
    input  logic signed [N-1:0][WIDTH-1:0] A,
    input  logic signed [N-1:0][WIDTH-1:0] B,
    output logic signed [2*WIDTH+3:0] dot_out,
    output logic valid
);

    localparam int OUT_W = 2*WIDTH + 4;

    logic signed [2*WIDTH-1:0] prod_reg [0:N-1];
    logic signed [OUT_W-1:0] sum_comb;
    logic [1:0] valid_pipe;

    integer i;

    always_comb begin
        sum_comb = '0;
        for (i = 0; i < N; i = i + 1) begin
            sum_comb = sum_comb + $signed({{(OUT_W-2*WIDTH){prod_reg[i][2*WIDTH-1]}}, prod_reg[i]});
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N; i = i + 1) begin
                prod_reg[i] <= '0;
            end
            dot_out    <= '0;
            valid_pipe <= 2'b00;
            valid      <= 1'b0;
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                prod_reg[i] <= A[i] * B[i];
            end
            dot_out    <= sum_comb;
            valid_pipe <= {valid_pipe[0], 1'b1};
            valid      <= valid_pipe[1] & ~valid_pipe[0];
        end
    end

endmodule
