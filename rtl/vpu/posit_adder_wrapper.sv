`include "registers.svh"
import posit_types_pkg::*;

// 3.29: Posit16_2 加法器顶层包装模块，便于用来仿真
// 输入：原始16bit Posit 数 | 输出：原始16bit Posit 和
// 内部：Decoder -> posit_adder -> Encoder
module posit_adder_wrapper #(
    // 固定为 Posit16_2 配置
    parameter int unsigned n = 16,
    parameter int unsigned es = 2,
    parameter int unsigned ALIGN_WIDTH = 14
)(
    // 时钟与复位
    input  logic         clk_i,
    input  logic         rstn_i,
    // 使能信号（和posit_adder对齐）
    input  logic         calc_start_i,
    output logic         calc_done_o,

    // ================= 顶层输入：原始 16bit Posit16_2 数 =================
    input  logic [n-1:0]  a_posit_i,   // 加数A
    input  logic [n-1:0]  b_posit_i,   // 加数B

    // ================= 顶层输出：原始 16bit Posit16_2 和 =================
    output logic [n-1:0]  sum_posit_o
);

    // ================= 参数==============
    localparam int unsigned EXP_WIDTH_I  = get_exp_width_i(n, es);
    localparam int unsigned MANT_WIDTH_I = get_mant_width_i(n, es);
    localparam int unsigned MAX_EXP_W    = get_max_exp_width(n, es, n, es);
    localparam int unsigned MANT_WIDTH_O = get_mant_width_o(n, es);

    // ================= 内部信号：解码后的分量 =================
    // A 解码结果
    logic                        a_sign;
    logic signed [EXP_WIDTH_I:0] a_rg_exp;
    logic        [MANT_WIDTH_I:0] a_mant;

    // B 解码结果
    logic                        b_sign;
    logic signed [EXP_WIDTH_I:0] b_rg_exp;
    logic        [MANT_WIDTH_I:0] b_mant;

    // 加法器输出（待编码分量）
    logic                        sum_sign;
    logic signed [MAX_EXP_W:0]   sum_rg_exp;
    logic        [MANT_WIDTH_O+2:0] sum_mant;

    // =====================================================================
    // 步骤1：对两个输入Posit进行解码
    // =====================================================================
    posit_decoder #(
        .n(n),
        .es(es)
    ) u_decoder_a (
        .operand_i   (a_posit_i),
        .sign_o      (a_sign),
        .rg_exp_o    (a_rg_exp),
        .mant_norm_o (a_mant)
    );

    posit_decoder #(
        .n(n),
        .es(es)
    ) u_decoder_b (
        .operand_i   (b_posit_i),
        .sign_o      (b_sign),
        .rg_exp_o    (b_rg_exp),
        .mant_norm_o (b_mant)
    );

    // =====================================================================
    // 步骤2：调用核心加法器（解码分量运算）
    // =====================================================================
    posit_adder #(
        .n_i        (n),
        .es_i       (es),
        .n_o        (n),
        .es_o       (es),
        .ALIGN_WIDTH(ALIGN_WIDTH)
    ) u_posit_adder (
        .clk_i         (clk_i),
        .rstn_i        (rstn_i),
        .calc_start_i  (calc_start_i),
        .calc_done_o   (calc_done_o),

        .a_sign_i   (a_sign),
        .a_rg_exp_i (a_rg_exp),
        .a_mant_i   (a_mant),

        .b_sign_i   (b_sign),
        .b_rg_exp_i (b_rg_exp),
        .b_mant_i   (b_mant),

        .sum_sign_o (sum_sign),
        .sum_rg_exp_o(sum_rg_exp),
        .sum_mant_o (sum_mant)
    );

    // =====================================================================
    // 步骤3：编码回原始Posit16_2格式
    // =====================================================================
    posit_encoder #(
        .n(n),
        .es(es),
        .EXP_WIDTH(EXP_WIDTH_I+1), //按照SA_top里的encoder改一下
        .MANT_WIDTH(MANT_WIDTH_O+2)
    ) u_encoder_sum (
        .sign_i      (sum_sign),
        .rg_exp_i    (sum_rg_exp),
        .mant_norm_i      (sum_mant),
        .result_o   (sum_posit_o)
    );

endmodule