module seq_detector_0011(
    input clk,
    input reset,
    input data_in,
    output reg detected
);

reg [2:0] state;
reg [2:0] next_state;
reg next_detected;

localparam S0 = 3'd0;
localparam S1 = 3'd1;
localparam S2 = 3'd2;
localparam S3 = 3'd3;
localparam S4 = 3'd4;

always @(*) begin
    next_state = state;
    next_detected = 1'b0;

    case (state)
        S0: begin
            if (data_in == 1'b0)
                next_state = S1;
            else
                next_state = S0;
        end

        S1: begin
            if (data_in == 1'b0)
                next_state = S2;
            else
                next_state = S0;
        end

        S2: begin
            if (data_in == 1'b0)
                next_state = S2;
            else
                next_state = S3;
        end

        S3: begin
            if (data_in == 1'b1) begin
                next_state = S4;
                next_detected = 1'b1;
            end else
                next_state = S1;
        end

        S4: begin
            if (data_in == 1'b0)
                next_state = S1;
            else
                next_state = S0;
        end

        default: begin
            next_state = S0;
            next_detected = 1'b0;
        end
    endcase
end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= S0;
        detected <= 1'b0;
    end else begin
        state <= next_state;
        detected <= next_detected;
    end
end

endmodule
