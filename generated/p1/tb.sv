module tb;
  reg clk;
  reg reset;
  reg data_in;
  wire detected;
  reg [15:0] stimulus;
  integer i;

  seq_detector_0011 uut (
    .clk(clk),
    .reset(reset),
    .data_in(data_in),
    .detected(detected)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    reset = 1;
    data_in = 0;
    stimulus = 16'b0001100110110010;
    #10;
    reset = 0;

    for (i = 15; i >= 0; i = i - 1) begin
      data_in = stimulus[i];
      @(posedge clk);
      @(negedge clk);
      $display("OBS detected=%b", detected);
    end

    #10;
    $finish;
  end
endmodule
