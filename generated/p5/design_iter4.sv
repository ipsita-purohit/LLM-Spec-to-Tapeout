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

    localparam int OUT_W  = 2*WIDTH + 4;
    localparam int PROD_W = 2*WIDTH;

    logic signed [OUT_W-1:0] sum_next;
    logic signed [OUT_W-1:0] sum_reg;
    logic                    stage1_valid;
    logic                    stage2_valid;
    integer                  i;

    always_comb begin
        sum_next = '0;
        for (i = 0; i < N; i = i + 1) begin
            sum_next = sum_next + OUT_W'(A[i] * B[i]);
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            sum_reg       <= '0;
            dot_out       <= '0;
            stage1_valid  <= 1'b0;
            stage2_valid  <= 1'b0;
            valid         <= 1'b0;
        end else begin
            sum_reg      <= sum_next;
            stage1_valid <= 1'b1;
            stage2_valid <= stage1_valid;
            dot_out      <= sum_reg;
            valid        <= stage2_valid;
        end
    end

endmodule
