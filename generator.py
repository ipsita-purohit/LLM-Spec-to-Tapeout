def generate_rtl_from_spec(info):
    module_name = info["module_name"]
    sequence = info["sequence_to_detect"]

    n = len(sequence)

    # Create states dynamically
    states = [f"S{i}" for i in range(n)]

    state_defs = ",\n               ".join(
        [f"{states[i]} = {n}'d{i}" for i in range(n)]
    )

    rtl = f"""module {module_name}(
    input clk,
    input reset,
    input data_in,
    output reg detected
);

    reg [{n-1}:0] state, next_state;

    localparam {state_defs};

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
            detected <= (state == S{n-1} && data_in == 1'b{sequence[-1]});
        end
    end

    always @(*) begin
        case (state)
"""

    # Build transitions (simple linear FSM)
    for i in range(n):
        if i == 0:
            rtl += f"            S0: next_state = (data_in == 1'b{sequence[0]}) ? S1 : S0;\n"
        elif i < n - 1:
            rtl += f"            S{i}: next_state = (data_in == 1'b{sequence[i]}) ? S{i+1} : S0;\n"
        else:
            rtl += f"            S{i}: next_state = (data_in == 1'b{sequence[i]}) ? S0 : S0;\n"

    rtl += """            default: next_state = S0;
        endcase
    end

endmodule
"""
    return rtl
def save_rtl_to_file(rtl_code, output_file):
    with open(output_file, "w") as f:
        f.write(rtl_code)
