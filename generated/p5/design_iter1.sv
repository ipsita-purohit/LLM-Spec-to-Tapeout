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

    localparam int PROD_W = 2*WIDTH;
    localparam int ACC_W  = 2*WIDTH + 4;

    logic signed [PROD_W-1:0] prod_reg [0:N-1];
    logic signed [ACC_W-1:0]  sum_reg;
    logic [1:0]               valid_pipe;

    integer i;
    logic signed [ACC_W-1:0] acc_next;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N; i = i + 1) begin
                prod_reg[i] <= '0;
            end
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                prod_reg[i] <= $signed(A[i]) * $signed(B[i]);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            sum_reg <= '0;
        end else begin
            acc_next = '0;
            for (i = 0; i < N; i = i + 1) begin
                acc_next = acc_next + $signed(prod_reg[i]);
            end
            sum_reg <= acc_next;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_pipe <= 2'b00;
            valid     <= 1'b0;
            dot_out   <= '0;
        end else begin
            valid_pipe[0] <= 1'b1;
            valid_pipe[1] <= valid_pipe[0];
            valid         <= valid_pipe[1];
            dot_out       <= sum_reg;
        end
    end

endmodule
