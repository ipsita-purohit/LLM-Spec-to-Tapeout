module seq_detector_0011 (clk,
    data_in,
    detected,
    reset);
 input clk;
 input data_in;
 output detected;
 input reset;

 wire _00_;
 wire _01_;
 wire _02_;
 wire _03_;
 wire _04_;
 wire _05_;
 wire _06_;
 wire _07_;
 wire _08_;
 wire _09_;
 wire _10_;
 wire clknet_0_clk;
 wire clknet_1_0__leaf_clk;
 wire clknet_1_1__leaf_clk;
 wire [2:0] history;

 INV_X1 _11_ (.A(reset),
    .ZN(_05_));
 AND2_X1 _12_ (.A1(_05_),
    .A2(history[0]),
    .ZN(_01_));
 AND2_X1 _13_ (.A1(_05_),
    .A2(data_in),
    .ZN(_02_));
 INV_X1 _14_ (.A(history[2]),
    .ZN(_06_));
 NOR2_X1 _15_ (.A1(_00_),
    .A2(history[1]),
    .ZN(_07_));
 AND4_X1 _16_ (.A1(_06_),
    .A2(_07_),
    .A3(_05_),
    .A4(data_in),
    .ZN(_03_));
 AND2_X1 _17_ (.A1(_05_),
    .A2(history[1]),
    .ZN(_04_));
 DFF_X1 _18_ (.D(_03_),
    .CK(clknet_1_0__leaf_clk),
    .Q(detected),
    .QN(_09_));
 DFF_X1 _19_ (.D(_02_),
    .CK(clknet_1_1__leaf_clk),
    .Q(history[0]),
    .QN(_00_));
 DFF_X1 _20_ (.D(_01_),
    .CK(clknet_1_0__leaf_clk),
    .Q(history[1]),
    .QN(_10_));
 DFF_X1 _21_ (.D(_04_),
    .CK(clknet_1_1__leaf_clk),
    .Q(history[2]),
    .QN(_08_));
 CLKBUF_X1 clkbuf_0_clk (.A(clk),
    .Z(clknet_0_clk));
 CLKBUF_X1 clkbuf_1_0__f_clk (.A(clknet_0_clk),
    .Z(clknet_1_0__leaf_clk));
 CLKBUF_X1 clkbuf_1_1__f_clk (.A(clknet_0_clk),
    .Z(clknet_1_1__leaf_clk));
endmodule
