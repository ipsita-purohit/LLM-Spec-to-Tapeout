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

    localparam int OUT_WIDTH = 2*WIDTH + 4;

    logic signed [OUT_WIDTH-1:0] dot_sum;
    logic computed;
    integer i;

    always_comb begin
        dot_sum = '0;
        for (i = 0; i < N; i = i + 1) begin
            dot_sum = dot_sum + (A[i] * B[i]);
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            dot_out  <= '0;
            valid    <= 1'b0;
            computed <= 1'b0;
        end else if (!computed) begin
            dot_out  <= dot_sum;
            valid    <= 1'b1;
            computed <= 1'b1;
        end else begin
            valid    <= 1'b0;
        end
    end

endmodule
