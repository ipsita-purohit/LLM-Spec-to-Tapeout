module tb;
  localparam N = 8;
  localparam WIDTH = 8;
  logic clk;
  logic rst;
  logic signed [N-1:0][WIDTH-1:0] A;
  logic signed [N-1:0][WIDTH-1:0] B;
  logic signed [2*WIDTH+3:0] dot_out;
  logic valid;
  integer cycle;

  dot_product #(.N(N), .WIDTH(WIDTH)) uut (
    .clk(clk), .rst(rst), .A(A), .B(B), .dot_out(dot_out), .valid(valid)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    rst = 1;
    A = '0;
    B = '0;
    A[0] = -40;
    A[1] = 50;
    A[2] = -50;
    A[3] = 31;
    A[4] = 14;
    A[5] = 9;
    A[6] = 6;
    A[7] = -32;
    B[0] = -1;
    B[1] = 30;
    B[2] = 41;
    B[3] = 14;
    B[4] = 37;
    B[5] = 50;
    B[6] = 22;
    B[7] = 29;
    #10;
    rst = 0;

    for (cycle = 0; cycle < 6; cycle = cycle + 1) begin
      @(posedge clk);
      #1;
      $display("OBS valid=%b dot_out=%0d", valid, dot_out);
      @(negedge clk);
    end

    #10;
    $finish;
  end
endmodule
