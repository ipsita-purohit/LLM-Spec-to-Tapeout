module fp16_multiplier(
  input  logic [15:0] a,
  input  logic [15:0] b,
  output logic [15:0] result
);

  function automatic [3:0] leading_zero_shift_10(input logic [9:0] frac);
    begin
      casez (frac)
        10'b1?????????: leading_zero_shift_10 = 4'd0;
        10'b01????????: leading_zero_shift_10 = 4'd1;
        10'b001???????: leading_zero_shift_10 = 4'd2;
        10'b0001??????: leading_zero_shift_10 = 4'd3;
        10'b00001?????: leading_zero_shift_10 = 4'd4;
        10'b000001????: leading_zero_shift_10 = 4'd5;
        10'b0000001???: leading_zero_shift_10 = 4'd6;
        10'b00000001??: leading_zero_shift_10 = 4'd7;
        10'b000000001?: leading_zero_shift_10 = 4'd8;
        10'b0000000001: leading_zero_shift_10 = 4'd9;
        default:        leading_zero_shift_10 = 4'd0;
      endcase
    end
  endfunction

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
  logic [10:0] sig_a;
  logic [10:0] sig_b;
  logic [21:0] product;
  logic [10:0] sig_pre_round;
  logic [11:0] sig_rounded;
  logic [10:0] sub_sig;
  logic [11:0] sub_rounded;
  logic        guard_bit;
  logic        round_bit;
  logic        sticky_bit;
  logic        round_up;
  logic [3:0]  shift_a;
  logic [3:0]  shift_b;
  integer      exp_a_unbiased;
  integer      exp_b_unbiased;
  integer      exp_product_unbiased;
  integer      exp_normalized_unbiased;
  integer      exp_final_unbiased;
  integer      sub_shift;

  always_comb begin
    sign_out               = a[15] ^ b[15];
    exp_a                  = a[14:10];
    exp_b                  = b[14:10];
    frac_a                 = a[9:0];
    frac_b                 = b[9:0];
    a_zero                 = (exp_a == 5'd0) && (frac_a == 10'd0);
    b_zero                 = (exp_b == 5'd0) && (frac_b == 10'd0);
    a_inf                  = (exp_a == 5'h1f) && (frac_a == 10'd0);
    b_inf                  = (exp_b == 5'h1f) && (frac_b == 10'd0);
    a_nan                  = (exp_a == 5'h1f) && (frac_a != 10'd0);
    b_nan                  = (exp_b == 5'h1f) && (frac_b != 10'd0);
    sig_a                  = 11'd0;
    sig_b                  = 11'd0;
    product                = 22'd0;
    sig_pre_round          = 11'd0;
    sig_rounded            = 12'd0;
    sub_sig                = 11'd0;
    sub_rounded            = 12'd0;
    guard_bit              = 1'b0;
    round_bit              = 1'b0;
    sticky_bit             = 1'b0;
    round_up               = 1'b0;
    shift_a                = 4'd0;
    shift_b                = 4'd0;
    exp_a_unbiased         = 0;
    exp_b_unbiased         = 0;
    exp_product_unbiased   = 0;
    exp_normalized_unbiased = 0;
    exp_final_unbiased     = 0;
    sub_shift              = 0;
    result                 = 16'h0000;

    if (a_nan || b_nan || ((a_inf || b_inf) && (a_zero || b_zero))) begin
      result = 16'h7e00;
    end else if (a_inf || b_inf) begin
      result = {sign_out, 5'h1f, 10'd0};
    end else if (a_zero || b_zero) begin
      result = {sign_out, 15'd0};
    end else begin
      if (exp_a == 5'd0) begin
        shift_a        = leading_zero_shift_10(frac_a);
        sig_a          = ({1'b0, frac_a} << shift_a);
        exp_a_unbiased = -14 - shift_a;
      end else begin
        sig_a          = {1'b1, frac_a};
        exp_a_unbiased = exp_a - 15;
      end

      if (exp_b == 5'd0) begin
        shift_b        = leading_zero_shift_10(frac_b);
        sig_b          = ({1'b0, frac_b} << shift_b);
        exp_b_unbiased = -14 - shift_b;
      end else begin
        sig_b          = {1'b1, frac_b};
        exp_b_unbiased = exp_b - 15;
      end

      product              = sig_a * sig_b;
      exp_product_unbiased = exp_a_unbiased + exp_b_unbiased;

      if (product[21]) begin
        sig_pre_round          = product[21:11];
        guard_bit              = product[10];
        round_bit              = product[9];
        sticky_bit             = |product[8:0];
        exp_normalized_unbiased = exp_product_unbiased + 1;
      end else begin
        sig_pre_round          = product[20:10];
        guard_bit              = product[9];
        round_bit              = product[8];
        sticky_bit             = |product[7:0];
        exp_normalized_unbiased = exp_product_unbiased;
      end

      round_up    = guard_bit && (round_bit || sticky_bit || sig_pre_round[0]);
      sig_rounded = {1'b0, sig_pre_round} + round_up;

      if (sig_rounded[11]) begin
        sig_rounded         = sig_rounded >> 1;
        exp_final_unbiased  = exp_normalized_unbiased + 1;
      end else begin
        exp_final_unbiased  = exp_normalized_unbiased;
      end

      if (exp_final_unbiased > 15) begin
        result = {sign_out, 5'h1f, 10'd0};
      end else if (exp_final_unbiased >= -14) begin
        result = {sign_out, exp_final_unbiased[4:0] + 5'd15, sig_rounded[9:0]};
      end else begin
        sub_shift = -14 - exp_final_unbiased;

        if (sub_shift > 11) begin
          sub_sig     = 11'd0;
          guard_bit   = 1'b0;
          round_bit   = 1'b0;
          sticky_bit  = (sig_rounded != 12'd0);
        end else begin
          sub_sig = sig_rounded[10:0] >> sub_shift;

          if (sub_shift == 0) begin
            guard_bit  = 1'b0;
            round_bit  = 1'b0;
            sticky_bit = 1'b0;
          end else if (sub_shift == 1) begin
            guard_bit  = sig_rounded[0];
            round_bit  = 1'b0;
            sticky_bit = 1'b0;
          end else begin
            guard_bit  = (sig_rounded >> (sub_shift - 1)) & 12'd1;
            round_bit  = (sig_rounded >> (sub_shift - 2)) & 12'd1;
            sticky_bit = ((sig_rounded & ((12'd1 << (sub_shift - 2)) - 12'd1)) != 12'd0);
          end
        end

        round_up    = guard_bit && (round_bit || sticky_bit || sub_sig[0]);
        sub_rounded = {1'b0, sub_sig} + round_up;

        if (sub_rounded >= 12'd1024) begin
          result = {sign_out, 5'd1, 10'd0};
        end else begin
          result = {sign_out, 5'd0, sub_rounded[9:0]};
        end
      end
    end
  end

endmodule
