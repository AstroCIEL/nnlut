import posit_types_pkg::*;

// Posit 格式开根号模块
// 算法：
//   1) posit 解码
//   2) 指数折半：new_exp = floor(exp/2)
//   3) 尾数开根号：sqrt(mant_norm_dec)
//   4) 若原指数为奇数，再对尾数补偿乘 sqrt(2)
//   5) posit 编码
//
// Latency = 3，要求 fixed_sqrt_newton 的 latency 也为 3
module posit_sqrt #(
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

    localparam int SQRT_LATENCY = 3;

    // Posit 特殊值定义
    localparam logic [N-1:0] POSIT_ZERO = '0;
    localparam logic [N-1:0] POSIT_NAR  = {1'b1, {(N-1){1'b0}}};

    // 标准尾数 1.000...
    localparam logic [MANT_I_W-1:0] MANT_ONE = {1'b1, {(MANT_I_W-1){1'b0}}};

    // sqrt(2) ≈ 92682 / 65536 = 1.414215
    // 以 Q1.(MANT_I_W-1) 格式表示
    localparam logic [MANT_I_W-1:0] SQRT2_CONST =
        (92682 * MANT_ONE + 32768) / 65536;

    // -------------------------------------------------------------------------
    // Posit 解码
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // 输入分类
    // 规则：
    //   0      -> 输出 0
    //   NaR    -> 输出 NaR
    //   负数   -> 输出 NaR
    //   正常正数 -> 正常开根号
    // -------------------------------------------------------------------------
    logic op_is_zero, op_is_nar, op_is_negative;
    logic op_is_special;
    logic normal_valid;

    assign op_is_zero     = (operand_i == POSIT_ZERO);
    assign op_is_nar      = (operand_i == POSIT_NAR);
    assign op_is_negative = sign_dec && !op_is_zero && !op_is_nar;
    assign op_is_special  = op_is_zero || op_is_nar || op_is_negative;
    assign normal_valid   = valid_in && !op_is_special;

    // -------------------------------------------------------------------------
    // 指数/尾数预处理
    //
    // operand = mant * 2^exp_total
    //
    // sqrt(operand) =
    //   if exp_total even:
    //       sqrt(mant) * 2^(exp_total/2)
    //   if exp_total odd:
    //       sqrt(mant) * sqrt(2) * 2^floor(exp_total/2)
    //
    // 注意：
    //   floor(exp/2) 对负奇数不能用 /2，必须用算术右移 >>> 1
    // -------------------------------------------------------------------------
    logic signed [EXP_I_W-1:0] exp_total;
    logic signed [EXP_I_W-1:0] new_exp;
    logic                      exp_odd;
    logic [MANT_I_W-1:0]       mant_pre;

    assign exp_total = rg_exp_dec;
    assign new_exp   = exp_total >>> 1;    // floor(exp_total/2)
    assign exp_odd   = exp_total[0];
    assign mant_pre  = mant_norm_dec;      // 始终保持输入在 [1,2)

    // -------------------------------------------------------------------------
    // 定点开根号核
    // 输入：mant_pre，Q1.(MANT_I_W-1)，范围 [1,2)
    // 输出：sqrt(mant_pre)，Q1.(MANT_I_W-1)，范围 [1,sqrt(2))
    // -------------------------------------------------------------------------
    logic [MANT_I_W-1:0] mant_sqrt_base;

    fixed_sqrt_newton #(
        .N(MANT_I_W)
    ) u_fixed_sqrt (
        .clk       (clk),
        .arst_n    (rstn),
        .valid_in  (normal_valid),
        .a         (mant_pre),
        .valid_out (),
        .sqrt      (mant_sqrt_base)
    );

    // -------------------------------------------------------------------------
    // 元数据流水线
    // 与 fixed_sqrt_newton 的 latency 对齐
    // -------------------------------------------------------------------------
    logic                      valid_pipe   [0:SQRT_LATENCY-1];
    logic                      special_pipe [0:SQRT_LATENCY-1];
    logic                      zero_pipe    [0:SQRT_LATENCY-1];
    logic                      odd_pipe     [0:SQRT_LATENCY-1];
    logic signed [EXP_I_W-1:0] exp_pipe     [0:SQRT_LATENCY-1];

    integer i;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < SQRT_LATENCY; i++) begin
                valid_pipe[i]   <= 1'b0;
                special_pipe[i] <= 1'b0;
                zero_pipe[i]    <= 1'b0;
                odd_pipe[i]     <= 1'b0;
                exp_pipe[i]     <= '0;
            end
        end else begin
            valid_pipe[0]   <= valid_in;
            special_pipe[0] <= op_is_special;
            zero_pipe[0]    <= op_is_zero;
            odd_pipe[0]     <= exp_odd;
            exp_pipe[0]     <= new_exp;

            for (i = 1; i < SQRT_LATENCY; i++) begin
                valid_pipe[i]   <= valid_pipe[i-1];
                special_pipe[i] <= special_pipe[i-1];
                zero_pipe[i]    <= zero_pipe[i-1];
                odd_pipe[i]     <= odd_pipe[i-1];
                exp_pipe[i]     <= exp_pipe[i-1];
            end
        end
    end

    // -------------------------------------------------------------------------
    // 奇数指数补偿：输出尾数乘 sqrt(2)
    //
    // mant_sqrt_base ∈ [1, sqrt(2))
    // 若 exp 为奇数：
    //   mant_sqrt_adj = mant_sqrt_base * sqrt(2)
    // 结果仍落在 [sqrt(2), 2)，不会超过归一化范围
    //
    // 这里用 truncation，避免 round 后偶发到 2.0 边界
    // -------------------------------------------------------------------------
    logic [2*MANT_I_W-1:0] mant_mul_full;
    logic [MANT_I_W-1:0]   mant_sqrt_adj;

    always_comb begin
        if (odd_pipe[SQRT_LATENCY-1]) begin
            mant_mul_full = mant_sqrt_base * SQRT2_CONST;
            mant_sqrt_adj = mant_mul_full >> (MANT_I_W - 1);
        end else begin
            mant_mul_full = '0;
            mant_sqrt_adj = mant_sqrt_base;
        end
    end

    // -------------------------------------------------------------------------
    // Posit 编码输入
    // 开根号结果恒为非负
    // -------------------------------------------------------------------------
    logic                       sign_enc;
    logic signed [EXP_I_W-1:0]  rg_exp_enc;
    logic [MANT_I_W-1:0]        mant_norm_enc;
    logic [N-1:0]               result_norm;

    assign sign_enc      = 1'b0;
    assign rg_exp_enc    = exp_pipe[SQRT_LATENCY-1];
    assign mant_norm_enc = mant_sqrt_adj;

    posit_encoder #(
        .n (N),
        .es(ES)
    ) u_encoder (
        .sign_i      (sign_enc),
        .rg_exp_i    (rg_exp_enc),
        .mant_norm_i (mant_norm_enc),
        .result_o    (result_norm)
    );

    // -------------------------------------------------------------------------
    // 最终输出
    // -------------------------------------------------------------------------
    assign valid_out = valid_pipe[SQRT_LATENCY-1];

    always_comb begin
        if (special_pipe[SQRT_LATENCY-1]) begin
            if (zero_pipe[SQRT_LATENCY-1])
                result_o = POSIT_ZERO;
            else
                result_o = POSIT_NAR;
        end else begin
            result_o = result_norm;
        end
    end

endmodule
