module fp16_multiplier(
  input  logic [15:0] a,
  input  logic [15:0] b,
  output logic [15:0] result
);

  integer i;
  integer exp_a_unbiased;
  integer exp_b_unbiased;
  integer exp_unbiased;
  integer shift_amt;

  logic sign_a;
  logic sign_b;
  logic sign_res;
  logic [4:0] exp_a;
  logic [4:0] exp_b;
  logic [9:0] frac_a;
  logic [9:0] frac_b;

  logic a_is_zero;
  logic b_is_zero;
  logic a_is_inf;
  logic b_is_inf;
  logic a_is_nan;
  logic b_is_nan;

  logic [10:0] sig_a;
  logic [10:0] sig_b;
  logic [21:0] product;
  logic [21:0] norm_product;

  logic [10:0] sig_base;
  logic [11:0] sig_rounded;
  logic [10:0] sub_base;
  logic [10:0] sub_rounded;

  logic guard_bit;
  logic sticky_bit;

  always @* begin
    sign_a = a[15];
    sign_b = b[15];
    sign_res = sign_a ^ sign_b;
    exp_a = a[14:10];
    exp_b = b[14:10];
    frac_a = a[9:0];
    frac_b = b[9:0];

    a_is_zero = (exp_a == 5'd0) && (frac_a == 10'd0);
    b_is_zero = (exp_b == 5'd0) && (frac_b == 10'd0);
    a_is_inf  = (exp_a == 5'h1f) && (frac_a == 10'd0);
    b_is_inf  = (exp_b == 5'h1f) && (frac_b == 10'd0);
    a_is_nan  = (exp_a == 5'h1f) && (frac_a != 10'd0);
    b_is_nan  = (exp_b == 5'h1f) && (frac_b != 10'd0);

    sig_a = (exp_a == 5'd0) ? {1'b0, frac_a} : {1'b1, frac_a};
    sig_b = (exp_b == 5'd0) ? {1'b0, frac_b} : {1'b1, frac_b};

    exp_a_unbiased = (exp_a == 5'd0) ? -14 : (exp_a - 15);
    exp_b_unbiased = (exp_b == 5'd0) ? -14 : (exp_b - 15);
    exp_unbiased = exp_a_unbiased + exp_b_unbiased;

    product = sig_a * sig_b;
    norm_product = product;

    sig_base = 11'd0;
    sig_rounded = 12'd0;
    sub_base = 11'd0;
    sub_rounded = 11'd0;
    guard_bit = 1'b0;
    sticky_bit = 1'b0;
    shift_amt = 0;
    result = 16'd0;

    if (a_is_nan || b_is_nan || ((a_is_inf || b_is_inf) && (a_is_zero || b_is_zero))) begin
      result = 16'h7e00;
    end else if (a_is_inf || b_is_inf) begin
      result = {sign_res, 5'h1f, 10'd0};
    end else if (a_is_zero || b_is_zero) begin
      result = {sign_res, 15'd0};
    end else begin
      if (norm_product[21]) begin
        norm_product = norm_product >> 1;
        exp_unbiased = exp_unbiased + 1;
      end else begin
        for (i = 0; i < 21; i = i + 1) begin
          if (!norm_product[20] && (norm_product != 22'd0)) begin
            norm_product = norm_product << 1;
            exp_unbiased = exp_unbiased - 1;
          end
        end
      end

      if (exp_unbiased > 15) begin
        result = {sign_res, 5'h1f, 10'd0};
      end else if (exp_unbiased >= -14) begin
        sig_base = norm_product[20:10];
        guard_bit = norm_product[9];
        sticky_bit = (norm_product[8:0] != 9'd0);
        sig_rounded = {1'b0, sig_base};

        if (guard_bit && (sticky_bit || sig_base[0])) begin
          sig_rounded = sig_rounded + 12'd1;
        end

        if (sig_rounded[11]) begin
          sig_rounded = sig_rounded >> 1;
          exp_unbiased = exp_unbiased + 1;
        end

        if (exp_unbiased > 15) begin
          result = {sign_res, 5'h1f, 10'd0};
        end else begin
          result = {sign_res, exp_unbiased[4:0] + 5'd15, sig_rounded[9:0]};
        end
      end else begin
        shift_amt = -exp_unbiased - 4;

        if (shift_amt > 22) begin
          sub_base = 11'd0;
          guard_bit = 1'b0;
          sticky_bit = (norm_product != 22'd0);
        end else begin
          sub_base = norm_product >> shift_amt;

          if (shift_amt > 0) begin
            guard_bit = norm_product[shift_amt - 1];
          end else begin
            guard_bit = 1'b0;
          end

          sticky_bit = 1'b0;
          if (shift_amt > 1) begin
            for (i = 0; i < 22; i = i + 1) begin
              if (i < (shift_amt - 1)) begin
                sticky_bit = sticky_bit | norm_product[i];
              end
            end
          end
        end

        sub_rounded = sub_base;
        if (guard_bit && (sticky_bit || sub_base[0])) begin
          sub_rounded = sub_rounded + 11'd1;
        end

        if (sub_rounded >= 11'd1024) begin
          result = {sign_res, 5'd1, 10'd0};
        end else begin
          result = {sign_res, 5'd0, sub_rounded[9:0]};
        end
      end
    end
  end

endmodule
