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

    localparam int OUT_WIDTH  = 2 * WIDTH + 4;
    localparam int PROD_WIDTH = 2 * WIDTH;

    logic signed [OUT_WIDTH-1:0]  dot_sum_comb;
    logic signed [OUT_WIDTH-1:0]  sum_stage1;
    logic signed [PROD_WIDTH-1:0] product;
    logic                         capture_done;
    logic                         valid_stage1;
    integer                       i;

    always_comb begin
        dot_sum_comb = '0;
        for (i = 0; i < N; i = i + 1) begin
            product = $signed(A[i]) * $signed(B[i]);
            dot_sum_comb = dot_sum_comb
                         + {{(OUT_WIDTH-PROD_WIDTH){product[PROD_WIDTH-1]}}, product};
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            sum_stage1   <= '0;
            dot_out      <= '0;
            capture_done <= 1'b0;
            valid_stage1 <= 1'b0;
            valid        <= 1'b0;
        end else begin
            sum_stage1 <= dot_sum_comb;
            dot_out    <= sum_stage1;

            if (!capture_done) begin
                capture_done <= 1'b1;
                valid_stage1 <= 1'b1;
            end else begin
                valid_stage1 <= 1'b0;
            end

            valid <= valid_stage1;
        end
    end

endmodule
