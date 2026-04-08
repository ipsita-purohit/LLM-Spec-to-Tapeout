module seq_detector_0011(
    input clk,
    input reset,
    input data_in,
    output reg detected
);

    reg [3:0] state, next_state;

    localparam S0 = 4'd0,
               S1 = 4'd1,
               S2 = 4'd2,
               S3 = 4'd3;

    initial begin
        state = S0;
        next_state = S0;
        detected = 1'b0;
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= S0;
            detected <= 1'b0;
        end else begin
            state <= next_state;
            detected <= (state == S3 && data_in == 1'b1);
        end
    end

    always @(*) begin
        case (state)
            S0: next_state = (data_in == 1'b0) ? S1 : S0;
            S1: next_state = (data_in == 1'b0) ? S2 : S0;
            S2: next_state = (data_in == 1'b1) ? S3 : S0;
            S3: next_state = (data_in == 1'b1) ? S0 : S0;
            default: next_state = S0;
        endcase
    end

endmodule
