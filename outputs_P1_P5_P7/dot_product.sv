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

    localparam int OUT_W  = 2 * WIDTH + 4;
    localparam int PROD_W = 2 * WIDTH;

    logic signed [N-1:0][PROD_W-1:0] product_reg;
    logic                             valid_stage1;

    integer i;
    integer j;
    logic signed [OUT_W-1:0] sum_next;

    always_comb begin
        sum_next = '0;
        for (j = 0; j < N; j = j + 1) begin
            sum_next = sum_next + OUT_W'(product_reg[j]);
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N; i = i + 1) begin
                product_reg[i] <= '0;
            end
            valid_stage1 <= 1'b0;
            dot_out      <= '0;
            valid        <= 1'b0;
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                product_reg[i] <= A[i] * B[i];
            end
            valid_stage1 <= 1'b1;
            dot_out      <= sum_next;
            valid        <= valid_stage1;
        end
    end

endmodule
