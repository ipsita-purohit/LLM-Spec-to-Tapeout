module tb;
  logic [15:0] a;
  logic [15:0] b;
  logic [15:0] result;

  fp16_multiplier uut (
    .a(a), .b(b), .result(result)
  );

  initial begin
    a = 16'b0011110000000000;
    b = 16'b0100000000000000;
    #1;
    $display("OBS result=%b", result);
    #1;
    $finish;
  end
endmodule
