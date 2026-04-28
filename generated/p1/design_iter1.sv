module seq_detector_0011(
    input clk,
    input reset,
    input data_in,
    output reg detected
);

reg [3:0] shift_reg;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        shift_reg <= 4'b0000;
        detected <= 1'b0;
    end else begin
        shift_reg <= {shift_reg[2:0], data_in};
        if ({shift_reg[2:0], data_in} == 4'b0011)
            detected <= 1'b1;
        else
            detected <= 1'b0;
    end
end

endmodule
