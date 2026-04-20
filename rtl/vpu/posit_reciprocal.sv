import posit_types_pkg::*;

module posit_reciprocal #(
    parameter N  = 16,
    parameter ES = 2
)(
    input  logic         clk,
    input  logic         rstn,
    input  logic         valid_in,
    input  logic [N-1:0] operand_i,
    output logic         valid_out,
    output logic [N-1:0] result_o
);

    localparam int RECIP_LATENCY = 3;

    // posit special values
    localparam logic [N-1:0] POSIT_ZERO = '0;
    localparam logic [N-1:0] POSIT_NAR  = {1'b1, {(N-1){1'b0}}};

    // mantissa = 1.000...
    localparam logic [MANT_I_W-1:0] MANT_ONE = {1'b1, {(MANT_I_W-1){1'b0}}};

    // signed 1 for exponent/scale arithmetic
    localparam logic signed [EXP_I_W-1:0] EXP_ONE =
        {{(EXP_I_W-1){1'b0}}, 1'b1};

    // ----------------------------------------------------------------
    // Decoder outputs
    // ----------------------------------------------------------------
    logic                       sign_dec;
    logic signed [EXP_I_W-1:0]  rg_exp_dec;
    logic        [MANT_I_W-1:0] mant_norm_dec;

    posit_decoder #(
        .n (N),
        .es(ES)
    ) u_decoder (
        .operand_i   (operand_i),
        .sign_o      (sign_dec),
        .rg_exp_o    (rg_exp_dec),
        .mant_norm_o (mant_norm_dec)
    );

    // ----------------------------------------------------------------
    // Input classify
    // ----------------------------------------------------------------
    logic op_is_zero, op_is_nar, op_is_special;
    logic is_exact_one;
    logic normal_valid, bypass_valid, recip_valid_in;

    assign op_is_zero    = (operand_i == POSIT_ZERO);
    assign op_is_nar     = (operand_i == POSIT_NAR);
    assign op_is_special = op_is_zero || op_is_nar;

    assign is_exact_one  = (mant_norm_dec == MANT_ONE);

    assign normal_valid  = valid_in && !op_is_special;
    assign bypass_valid  = normal_valid && is_exact_one;
    assign recip_valid_in = normal_valid && !is_exact_one;

    // ----------------------------------------------------------------
    // Precompute metadata before pipeline
    // f == 0  -> scale = -scale
    // f != 0  -> scale = -scale - 1
    // ----------------------------------------------------------------
    logic                      sign_meta_in;
    logic signed [EXP_I_W-1:0] rg_exp_meta_in;

    assign sign_meta_in = normal_valid ? sign_dec : 1'b0;

    assign rg_exp_meta_in =
        normal_valid
            ? (is_exact_one ? (-rg_exp_dec) : (-rg_exp_dec - EXP_ONE))
            : '0;

    // ----------------------------------------------------------------
    // Newton reciprocal core
    // Input:  1.f   (1 occupies width)
    // Output: 0.xxx (0 does NOT occupy width)
    //
    // Under your interface convention:
    // the returned bit-vector can be directly reinterpreted as encoder 1.f
    // so NO shift is needed here.
    // ----------------------------------------------------------------
    logic [MANT_I_W-1:0] mant_nr_in;
    logic [MANT_I_W-1:0] mant_norm_newton;
    logic                recip_valid_out;

    // optional input masking to reduce useless switching when not used
    assign mant_nr_in = recip_valid_in ? mant_norm_dec : MANT_ONE;

    fixed_reciprocal_newton #(
        .N(MANT_I_W)
    ) u_dut (
        .clk        (clk),
        .arst_n     (rstn),
        .valid_in   (recip_valid_in),
        .a          (mant_nr_in),
        .valid_out  (recip_valid_out),
        .reciprocal (mant_norm_newton)
    );

    // ----------------------------------------------------------------
    // 3-stage metadata delay to match fixed_reciprocal_newton latency
    // ----------------------------------------------------------------
    logic                      valid_pipe   [0:RECIP_LATENCY-1];
    logic                      special_pipe [0:RECIP_LATENCY-1];
    logic                      bypass_pipe  [0:RECIP_LATENCY-1];
    logic                      sign_pipe    [0:RECIP_LATENCY-1];
    logic signed [EXP_I_W-1:0] rg_exp_pipe  [0:RECIP_LATENCY-1];

    integer i;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < RECIP_LATENCY; i++) begin
                valid_pipe[i]   <= 1'b0;
                special_pipe[i] <= 1'b0;
                bypass_pipe[i]  <= 1'b0;
                sign_pipe[i]    <= 1'b0;
                rg_exp_pipe[i]  <= '0;
            end
        end else begin
            valid_pipe[0]   <= valid_in;
            special_pipe[0] <= valid_in && op_is_special;
            bypass_pipe[0]  <= bypass_valid;
            sign_pipe[0]    <= sign_meta_in;
            rg_exp_pipe[0]  <= rg_exp_meta_in;

            for (i = 1; i < RECIP_LATENCY; i++) begin
                valid_pipe[i]   <= valid_pipe[i-1];
                special_pipe[i] <= special_pipe[i-1];
                bypass_pipe[i]  <= bypass_pipe[i-1];
                sign_pipe[i]    <= sign_pipe[i-1];
                rg_exp_pipe[i]  <= rg_exp_pipe[i-1];
            end
        end
    end

    // ----------------------------------------------------------------
    // Encoder input select
    // bypass: mant = 1.0
    // NR    : mant = mant_norm_newton directly (NO << 1)
    // ----------------------------------------------------------------
    logic                       sign_enc;
    logic signed [EXP_I_W-1:0]  rg_exp_enc;
    logic        [MANT_I_W-1:0] mant_norm_enc;
    logic        [N-1:0]        result_norm;

    assign sign_enc      = sign_pipe[RECIP_LATENCY-1];
    assign rg_exp_enc    = rg_exp_pipe[RECIP_LATENCY-1];
    assign mant_norm_enc = bypass_pipe[RECIP_LATENCY-1] ? MANT_ONE
                                                        : mant_norm_newton;

    posit_encoder #(
        .n (N),
        .es(ES)
    ) u_encoder (
        .sign_i      (sign_enc),
        .rg_exp_i    (rg_exp_enc),
        .mant_norm_i (mant_norm_enc),
        .result_o    (result_norm)
    );

    // ----------------------------------------------------------------
    // Final output
    // special cases:
    //   reciprocal(0)   = NaR
    //   reciprocal(NaR) = NaR
    // ----------------------------------------------------------------
    assign valid_out = valid_pipe[RECIP_LATENCY-1];
    assign result_o  = special_pipe[RECIP_LATENCY-1] ? POSIT_NAR
                                                     : result_norm;


endmodule
