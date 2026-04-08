module seq_detector_0011(
    input clk,
    input reset,
    input data_in,
    output reg detected
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_0    = 2'd1;
    localparam [1:0] S_00   = 2'd2;
    localparam [1:0] S_001  = 2'd3;

    reg [1:0] state;
    reg [1:0] next_state;

    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: next_state = data_in ? S_IDLE : S_0;
            S_0:    next_state = data_in ? S_IDLE : S_00;
            S_00:   next_state = data_in ? S_001  : S_00;
            S_001:  next_state = data_in ? S_IDLE : S_0;
            default: next_state = data_in ? S_IDLE : S_0;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            detected <= 1'b0;
        end else begin
            state <= next_state;
            case (state)
                S_001: detected <= data_in;
                default: detected <= 1'b0;
            endcase
        end
    end

endmodule
