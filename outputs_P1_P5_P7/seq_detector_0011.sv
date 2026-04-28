module seq_detector_0011(
    input clk,
    input reset,
    input data_in,
    output reg detected
);

reg [2:0] history = 3'b000;
initial detected = 1'b0;

always @(posedge clk) begin
    if (reset) begin
        history  <= 3'b000;
        detected <= 1'b0;
    end else begin
        detected <= (history == 3'b001) && (data_in == 1'b1);
        history  <= {history[1:0], data_in};
    end
end

endmodule
