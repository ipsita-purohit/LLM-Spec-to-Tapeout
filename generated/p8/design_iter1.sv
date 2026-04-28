module fp16_multiplier(
  input  logic [15:0] a,
  input  logic [15:0] b,
  output logic [15:0] result
);

  function automatic [3:0] leading_zeros10(input logic [9:0] value);
    begin
      casex (value)
        10'b1xxxxxxxxx: leading_zeros10 = 4'd0;
        10'b01xxxxxxxx: leading_zeros10 = 4'd1;
        10'b001xxxxxxx: leading_zeros10 = 4'd2;
        10'b0001xxxxxx: leading_zeros10 = 4'd3;
        10'b00001xxxxx: leading_zeros10 = 4'd4;
        10'b000001xxxx: leading_zeros10 = 4'd5;
        10'b0000001xxx: leading_zeros10 = 4'd6;
        10'b00000001xx: leading_zeros10 = 4'd7;
        10'b000000001x: leading_zeros10 = 4'd8;
        10'b0000000001: leading_zeros10 = 4'd9;
        default:        leading_zeros10 = 4'd10;
      endcase
    end
  endfunction

  function automatic logic any_lower_bits(
    input logic [11:0] value,
    input integer      count
  );
    integer i;
    begin
      any_lower_bits = 1'b0;
      for (i = 0; i < 12; i = i + 1) begin
        if (i < count) begin
          any_lower_bits = any_lower_bits | value[i];
        end
      end
    end
  endfunction

  always_comb begin : fp16_mul_comb
    logic        sign_a;
    logic        sign_b;
    logic        sign_out;
    logic [4:0]  exp_a;
    logic [4:0]  exp_b;
    logic [9:0]  frac_a;
    logic [9:0]  frac_b;
    logic        a_zero;
    logic        b_zero;
    logic        a_inf;
    logic        b_inf;
    logic        a_nan;
    logic        b_nan;
    logic [10:0] mant_a;
    logic [10:0] mant_b;
    logic [3:0]  shift_a;
    logic [3:0]  shift_b;
    logic [21:0] product;
    logic [10:0] mant_pre;
    logic [11:0] mant_round;
    logic [10:0] sub_base;
    logic [11:0] sub_round;
    logic [4:0]  exp_out;
    logic        guard_bit;
    logic        round_bit;
    logic        sticky_bit;
    logic        round_up;
    logic        sub_guard;
    logic        sub_sticky;
    integer      e_a;
    integer      e_b;
    integer      e_prod;
    integer      e_norm;
    integer      e_pack;
    integer      sub_shift;

    sign_a     = a[15];
    sign_b     = b[15];
    sign_out   = sign_a ^ sign_b;
    exp_a      = a[14:10];
    exp_b      = b[14:10];
    frac_a     = a[9:0];
    frac_b     = b[9:0];
    a_zero     = (exp_a == 5'd0) && (frac_a == 10'd0);
    b_zero     = (exp_b == 5'd0) && (frac_b == 10'd0);
    a_inf      = (exp_a == 5'h1f) && (frac_a == 10'd0);
    b_inf      = (exp_b == 5'h1f) && (frac_b == 10'd0);
    a_nan      = (exp_a == 5'h1f) && (frac_a != 10'd0);
    b_nan      = (exp_b == 5'h1f) && (frac_b != 10'd0);
    mant_a     = 11'd0;
    mant_b     = 11'd0;
    shift_a    = 4'd0;
    shift_b    = 4'd0;
    product    = 22'd0;
    mant_pre   = 11'd0;
    mant_round = 12'd0;
    sub_base   = 11'd0;
    sub_round  = 12'd0;
    exp_out    = 5'd0;
    guard_bit  = 1'b0;
    round_bit  = 1'b0;
    sticky_bit = 1'b0;
    round_up   = 1'b0;
    sub_guard  = 1'b0;
    sub_sticky = 1'b0;
    e_a        = 0;
    e_b        = 0;
    e_prod     = 0;
    e_norm     = 0;
    e_pack     = 0;
    sub_shift  = 0;
    result     = 16'h0000;

    if (a_nan || b_nan || ((a_inf || b_inf) && (a_zero || b_zero))) begin
      result = 16'h7e00;
    end else if (a_inf || b_inf) begin
      result = {sign_out, 5'h1f, 10'h000};
    end else if (a_zero || b_zero) begin
      result = {sign_out, 15'd0};
    end else begin
      if (exp_a == 5'd0) begin
        shift_a = leading_zeros10(frac_a);
        mant_a  = {1'b0, frac_a} << shift_a;
        e_a     = -14 - shift_a;
      end else begin
        mant_a  = {1'b1, frac_a};
        e_a     = exp_a - 15;
      end

      if (exp_b == 5'd0) begin
        shift_b = leading_zeros10(frac_b);
        mant_b  = {1'b0, frac_b} << shift_b;
        e_b     = -14 - shift_b;
      end else begin
        mant_b  = {1'b1, frac_b};
        e_b     = exp_b - 15;
      end

      product = mant_a * mant_b;
      e_prod  = e_a + e_b;

      if (product[21]) begin
        mant_pre   = product[21:11];
        guard_bit  = product[10];
        round_bit  = product[9];
        sticky_bit = |product[8:0];
        e_norm     = e_prod + 1;
      end else begin
        mant_pre   = product[20:10];
        guard_bit  = product[9];
        round_bit  = product[8];
        sticky_bit = |product[7:0];
        e_norm     = e_prod;
      end

      round_up   = guard_bit && (round_bit || sticky_bit || mant_pre[0]);
      mant_round = {1'b0, mant_pre} + round_up;
      e_pack     = e_norm;

      if (mant_round[11]) begin
        mant_round = mant_round >> 1;
        e_pack     = e_pack + 1;
      end

      if (e_pack > 15) begin
        result = {sign_out, 5'h1f, 10'h000};
      end else if (e_pack >= -14) begin
        exp_out = e_pack + 15;
        result  = {sign_out, exp_out, mant_round[9:0]};
      end else begin
        sub_shift = -14 - e_pack;

        if (sub_shift > 11) begin
          sub_base   = 11'd0;
          sub_guard  = 1'b0;
          sub_sticky = (mant_round != 12'd0);
        end else begin
          sub_base   = mant_round[10:0] >> sub_shift;
          sub_guard  = (sub_shift > 0) ? mant_round[sub_shift - 1] : 1'b0;
          sub_sticky = (sub_shift > 1) ? any_lower_bits(mant_round, sub_shift - 1) : 1'b0;
        end

        sub_round = {1'b0, sub_base} + (sub_guard && (sub_sticky || sub_base[0]));

        if (sub_round >= 12'd1024) begin
          result = {sign_out, 5'd1, 10'd0};
        end else begin
          result = {sign_out, 5'd0, sub_round[9:0]};
        end
      end
    end
  end

endmodule
