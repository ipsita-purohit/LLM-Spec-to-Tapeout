module tb;
  localparam WIDTH = 8;
  reg clk;
  reg rst;
  reg enable;
  reg [WIDTH-1:0] x_in;
  wire [2*WIDTH-1:0] exp_out;
  integer cycle;

  exp_fixed_point #(.WIDTH(WIDTH)) uut (
    .clk(clk), .rst(rst), .enable(enable), .x_in(x_in), .exp_out(exp_out)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    rst = 1;
    enable = 0;
    x_in = 0;
    #10;
    rst = 0;

    for (cycle = 0; cycle < 7; cycle = cycle + 1) begin
      if (cycle == 0) begin
        rst = 1'b1;
        enable = 1'b1;
        x_in = 0;
      end
      if (cycle == 1) begin
        rst = 1'b0;
        enable = 1'b1;
        x_in = 128;
      end
      if (cycle == 2) begin
        rst = 1'b0;
        enable = 1'b1;
        x_in = 128;
      end
      if (cycle == 3) begin
        rst = 1'b0;
        enable = 1'b1;
        x_in = 128;
      end
      if (cycle == 4) begin
        rst = 1'b0;
        enable = 1'b1;
        x_in = 128;
      end
      if (cycle == 5) begin
        rst = 1'b0;
        enable = 1'b1;
        x_in = 128;
      end
      if (cycle == 6) begin
        rst = 1'b0;
        enable = 1'b1;
        x_in = 128;
      end
      @(posedge clk);
      #1;
      $display("OBS exp_out=%0d", exp_out);
      @(negedge clk);
    end
    $finish;
  end
endmodule
