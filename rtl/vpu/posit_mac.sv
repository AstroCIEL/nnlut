`include "registers.svh"

//PE_line：由多个PE组成一行，互相之间没有直接的连线；行为相同，因此共享控制信号的寄存器
import posit_types_pkg::*;
module posit_mac #(
    // parameter int unsigned MAC_NUM = 16,
    parameter int unsigned n_i = 16,
    parameter int unsigned es_i = 2,
    parameter int unsigned n_o = 16,
    parameter int unsigned es_o = 2,
    parameter int unsigned ALIGN_WIDTH = 14
)(
    input  logic clk_i,
    input  logic rstn_i,



    input  logic calc_start_i,
    output logic calc_done_o,

    input  logic [n_i-1:0]  a_posit_i,
    input  logic [n_i-1:0]  b_posit_i,
    input  logic [n_o-1:0]  c_posit_i,

    output logic [n_o-1:0]  d_posit_o
);
    // ================= 参数==============
    localparam int unsigned EXP_WIDTH_I  = get_exp_width_i  (n_i, es_i);
    localparam int unsigned MANT_WIDTH_I = get_mant_width_i (n_i, es_i);
    localparam int unsigned MAX_EXP_W    = get_max_exp_width(n_i, es_i, n_o, es_o);
    localparam int unsigned MANT_WIDTH_O = get_mant_width_o (n_o, es_o);


logic a_sign, b_sign, c_sign, d_sign;
logic [EXP_WIDTH_I:0] a_rg_exp, b_rg_exp  ;
logic [MANT_WIDTH_I:0] a_mant, b_mant ;

logic [MAX_EXP_W:0] c_rg_exp,d_rg_exp;
logic [MANT_WIDTH_O+2:0] c_mant,d_mant;

    posit_decoder #(
        .n(n_i),
        .es(es_i)
    ) u_decoder_a (
        .operand_i   (a_posit_i),
        .sign_o      (a_sign),
        .rg_exp_o    (a_rg_exp),
        .mant_norm_o (a_mant)
    );

    posit_decoder #(
        .n(n_i),
        .es(es_i)
    ) u_decoder_b (
        .operand_i   (b_posit_i),
        .sign_o      (b_sign),
        .rg_exp_o    (b_rg_exp),
        .mant_norm_o (b_mant)
    );

    posit_decoder #(
        .n(n_o),
        .es(es_o),
        .MANT_WIDTH(MANT_WIDTH_O+2)
    ) u_decoder_c (
        .operand_i   (c_posit_i),
        .sign_o      (c_sign),
        .rg_exp_o    (c_rg_exp),
        .mant_norm_o (c_mant)
    );



    logic en_i_1, en_i_2, en_i_3;
    
    assign en_i_1 = calc_start_i;
    // `FFARN(en_i_1,      calc_start_i,    0,  clk_i,  rstn_i)
    `FFARN(en_i_2,      en_i_1,          0,  clk_i,  rstn_i)
    `FFARN(en_i_3,      en_i_2,          0,  clk_i,  rstn_i)
    `FFARN(calc_done_o, en_i_3,          0,  clk_i,  rstn_i)








    posit_mac_kernel #(
        .n_i(n_i),
        .es_i(es_i),
        .n_o(n_o),
        .es_o(es_o),
        .ALIGN_WIDTH(ALIGN_WIDTH)
    ) u_posit_mac_kernel (
        .clk_i       (clk_i),
        .rstn_i      (rstn_i),
        .en_i_1      (en_i_1),
        .en_i_2      (en_i_2),
        .en_i_3      (en_i_3),

        .act_sign_i  (a_sign),
        .act_rg_exp_i(a_rg_exp),
        .act_mant_i  (a_mant),

        .wgt_sign_i  (b_sign),
        .wgt_rg_exp_i(b_rg_exp),
        .wgt_mant_i  (b_mant),

        .acc_sign_i  (c_sign),
        .acc_rg_exp_i(c_rg_exp),
        .acc_mant_i  (c_mant),

        .acc_sign_o  (d_sign),
        .acc_rg_exp_o(d_rg_exp),
        .acc_mant_o  (d_mant)
    );



    posit_encoder #(
        .n(n_o),
        .es(es_o),
        .EXP_WIDTH(MAX_EXP_W),
        .MANT_WIDTH(MANT_WIDTH_O+2)
    ) u_encoder_d (
        .sign_i      (d_sign),
        .rg_exp_i    (d_rg_exp),
        .mant_norm_i (d_mant),
        .result_o    (d_posit_o)
    );


endmodule