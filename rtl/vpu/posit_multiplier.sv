/*
 * Posit 乘法器内核：无编解码 (No Encoder/Decoder)
 * 功能：接收两个解码后的 Posit 分量，完成乘法计算，输出待编码的 Posit 分量
 * 流水线结构：3 级 (Input Register -> Multiply -> Normalize/Round -> Output Register)
 */
`include "registers.svh"
import posit_types_pkg::*;

module posit_multiplier #(
    parameter int unsigned n_i = 16,                 // Posit 字长 (输入输出一致)
    parameter int unsigned es_i = 2,
    parameter int unsigned n_o = 16,                // 输出Posit字长
    parameter int unsigned es_o = 2,                // 输出指数大小
    parameter int unsigned ALIGN_WIDTH = 14                // 指数大小 (输入输出一致)
)(
    // 时钟与复位
    input  logic clk_i,
    input  logic rstn_i,
    
    // 流水线使能信号
    input  logic calc_start_i,

    input logic  [n_i-1:0] a_i,
    input logic  [n_i-1:0] b_i,
    output logic [n_o-1:0] c_o,

    output logic calc_done_o
);



    logic en_i_1, en_i_2, en_i_3;

    assign en_i_1 = calc_start_i;
    // `FFARN(en_i_1,      calc_start_i,    0,  clk_i,  rstn_i)
    `FFARN(en_i_2,      en_i_1,          0,  clk_i,  rstn_i)
    `FFARN(en_i_3,      en_i_2,          0,  clk_i,  rstn_i)
    `FFARN(calc_done_o, en_i_3,          0,  clk_i,  rstn_i)

logic a_sign_i, b_sign_i, c_sign_o;
logic [EXP_I_W-1:0] a_rg_exp_i, b_rg_exp_i;
logic [MANT_I_W-1:0] a_mant_i, b_mant_i;

logic [ACC_EXP_W-1:0] c_rg_exp_o;
logic [ACC_MANT_W-1:0] c_mant_o;


posit_decoder #(
    .n(n_i),
    .es(es_i)
) u_a_decoder(
    .operand_i  (a_i),
    .sign_o     (a_sign_i),
    .rg_exp_o   (a_rg_exp_i),
    .mant_norm_o(a_mant_i)
);

posit_decoder #(
    .n(n_i),
    .es(es_i)
) u_b_decoder(
    .operand_i  (b_i),
    .sign_o     (b_sign_i),
    .rg_exp_o   (b_rg_exp_i),
    .mant_norm_o(b_mant_i)
);




posit_mult_kernel #(
    .n_i(n_i),
    .es_i(es_i),
    .n_o(n_o),
    .es_o(es_o),
    .ALIGN_WIDTH(ALIGN_WIDTH)
) u_posit_mult_kernel (
    // 时钟与复位
    .clk_i(clk_i),
    .rstn_i(rstn_i),
    
    // 流水线使能信号
    .en_i_1(en_i_1), 
    .en_i_2(en_i_2), 
    .en_i_3(en_i_3),

    // ================= 输入接口 (解码后的格式) =================
    .a_sign_i  (a_sign_i),
    .a_rg_exp_i(a_rg_exp_i),
    .a_mant_i  (a_mant_i),

    .b_sign_i  (b_sign_i),
    .b_rg_exp_i(b_rg_exp_i),
    .b_mant_i  (b_mant_i),

    // ================= 输出接口 (待编码的格式) =================
    .c_sign_o  (c_sign_o),
    .c_rg_exp_o(c_rg_exp_o),
    .c_mant_o  (c_mant_o)
);


posit_encoder #(
    .n(n_o),
    .es(es_o),
    .EXP_WIDTH(ACC_EXP_W-1),
    .MANT_WIDTH(ACC_MANT_W-1)
) u_c_encoder(
    .sign_i       (c_sign_o),
    .rg_exp_i     (c_rg_exp_o),
    .mant_norm_i  (c_mant_o),
    .result_o     (c_o)
);

endmodule