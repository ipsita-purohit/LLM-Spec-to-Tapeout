module tb;
  localparam WIDTH = 16;
  localparam N = 8;
  reg clk;
  reg rst;
  reg signed [WIDTH-1:0] x_in;
  reg signed [N-1:0][WIDTH-1:0] h;
  wire signed [2*WIDTH+$clog2(N):0] y_out;
  integer cycle;

  fir_filter #(.WIDTH(WIDTH), .N(N)) uut (
    .clk(clk), .rst(rst), .x_in(x_in), .h(h), .y_out(y_out)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    rst = 1;
    x_in = 0;
    h = {16'sd8, 16'sd7, 16'sd6, 16'sd5, 16'sd4, 16'sd3, 16'sd2, 16'sd1};

    repeat (1) begin
      @(posedge clk);
      #1;
    end
    rst = 0;

    for (cycle = 0; cycle < 8; cycle = cycle + 1) begin
      if (cycle == 0) begin
        x_in = 16'sd1;
      end
      if (cycle == 1) begin
        x_in = 16'sd1;
      end
      if (cycle == 2) begin
        x_in = 16'sd1;
      end
      if (cycle == 3) begin
        x_in = 16'sd1;
      end
      if (cycle == 4) begin
        x_in = 16'sd1;
      end
      if (cycle == 5) begin
        x_in = 16'sd1;
      end
      if (cycle == 6) begin
        x_in = 16'sd1;
      end
      if (cycle == 7) begin
        x_in = 16'sd1;
      end
      @(posedge clk);
      #1;
      $display("OBS y_out=%0d", y_out);
      @(negedge clk);
    end

    $finish;
  end
endmodule
