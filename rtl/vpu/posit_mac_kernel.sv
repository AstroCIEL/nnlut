/*
 * 改进版 PDPU 内核：无编解码 (No Encoder/Decoder)
 * 功能：接收解码后的 Posit 分量，完成乘累加计算，输出待编码的 Posit 分量
 * 适用场景：Weight Stationary 脉动阵列内部 PE，消除中间舍入误差
 */
`include "registers.svh"
import posit_types_pkg::*;

module posit_mac_kernel #(
    parameter int unsigned n_i = 16,                 // 输入Posit字长
    parameter int unsigned es_i = 2,                // 输入指数大小
    parameter int unsigned n_o = 16,                // 输出Posit字长
    parameter int unsigned es_o = 2,                // 输出指数大小
    parameter int unsigned ALIGN_WIDTH = 14         // 对齐位宽
)(
    // 时钟与复位
    input  logic clk_i,
    input  logic rstn_i,
    
    // 流水线使能信号
    input  logic en_i_1, en_i_2, en_i_3, //这个是计算流水线的控制信号

    // ================= 输入接口 (解码后的格式) =================
    input  logic                                                     act_sign_i,
    input  logic signed [get_exp_width_i(n_i, es_i):0]               act_rg_exp_i,
    input  logic        [get_mant_width_i(n_i, es_i):0]              act_mant_i,

    input  logic                                                     wgt_sign_i,
    input  logic signed [get_exp_width_i(n_i, es_i):0]               wgt_rg_exp_i,
    input  logic        [get_mant_width_i(n_i, es_i):0]              wgt_mant_i,

    input  logic                                                     acc_sign_i,
    input  logic signed [get_max_exp_width(n_i, es_i, n_o, es_o):0]  acc_rg_exp_i,
    input  logic        [get_mant_width_o(n_o, es_o)+2:0]            acc_mant_i,




    output  logic                                                    acc_sign_o,
    output  logic signed [get_max_exp_width(n_i, es_i, n_o, es_o):0] acc_rg_exp_o,
    output  logic        [get_mant_width_o(n_o, es_o)+2:0]           acc_mant_o
);


    // ================= 局部参数定义 =================
    localparam int unsigned EXP_WIDTH_I  = get_exp_width_i(n_i, es_i);
    localparam int unsigned MANT_WIDTH_I = get_mant_width_i(n_i, es_i);
    localparam int unsigned EXP_WIDTH_O  = get_exp_width_o(n_o, es_o);
    localparam int unsigned MANT_WIDTH_O = get_mant_width_o(n_o, es_o);
    localparam int unsigned EXP_WIDTH    = get_max_exp_width(n_i, es_i, n_o, es_o);

    // ================= 修复点1：声明 Pipeline 0 的内部寄存器信号 =================
    logic                                        pipe0_act_sign;
    logic signed [EXP_WIDTH_I:0]                 pipe0_act_rg_exp;
    logic        [MANT_WIDTH_I:0]                pipe0_act_mant;


    
    logic                                        pipe0_wgt_sign;
    logic signed [EXP_WIDTH_I:0]                 pipe0_wgt_rg_exp;
    logic        [MANT_WIDTH_I:0]                pipe0_wgt_mant;
    
    logic                                        pipe0_acc_sign;
    logic signed [EXP_WIDTH:0]                   pipe0_acc_rg_exp;
    logic        [MANT_WIDTH_O+2:0]              pipe0_acc_mant;

    // ********************
    // Pipeline 0: 输入寄存器 (前移至此)
    // ********************
    `FFLARN(pipe0_act_sign,      act_sign_i,     en_i_1,  0,  clk_i,  rstn_i)
    `FFLARN(pipe0_act_rg_exp,    act_rg_exp_i,   en_i_1,  0,  clk_i,  rstn_i)
    `FFLARN(pipe0_act_mant,      act_mant_i,     en_i_1,  0,  clk_i,  rstn_i)

    `FFLARN(pipe0_wgt_sign,      wgt_sign_i,     en_i_1,      0,  clk_i,  rstn_i)
    `FFLARN(pipe0_wgt_rg_exp,    wgt_rg_exp_i,   en_i_1,      0,  clk_i,  rstn_i)
    `FFLARN(pipe0_wgt_mant,      wgt_mant_i,     en_i_1,      0,  clk_i,  rstn_i)

    `FFLARN(pipe0_acc_sign,      acc_sign_i,     en_i_1,      0,  clk_i,  rstn_i)
    `FFLARN(pipe0_acc_rg_exp,    acc_rg_exp_i,   en_i_1,      0,  clk_i,  rstn_i)
    `FFLARN(pipe0_acc_mant,      acc_mant_i,     en_i_1,      0,  clk_i,  rstn_i)

    // ********************
    // Pipeline 0到1 之间的组合逻辑
    // ********************
    
    // 符号处理
    logic         signs_ab;
    logic [1:0]   signs;

    assign signs_ab = pipe0_act_sign ^ pipe0_wgt_sign;
    assign signs    = {pipe0_acc_sign, signs_ab};

    // 指数加法 (修复点2：去掉了错误的 _i 后缀)
    logic signed [EXP_WIDTH:0] rg_exp_prod;
    assign rg_exp_prod = signed'(pipe0_act_rg_exp) + signed'(pipe0_wgt_rg_exp);

    // 尾数乘法 (Booth)
    localparam int unsigned MUL_WIDTH = 2 * (MANT_WIDTH_I + 1);
    logic [MUL_WIDTH-1:0] mul_sum, mul_carry;

    radix4_booth_multiplier #(
        .WIDTH_A(MANT_WIDTH_I + 1),
        .WIDTH_B(MANT_WIDTH_I + 1)
    ) u_radix4_booth_multiplier (
        .operand_a(pipe0_act_mant),
        .operand_b(pipe0_wgt_mant),
        .sum_o    (mul_sum),
        .carry_o  (mul_carry)
    );

    // 指数比较 (找最大值)
    logic signed [1:0][EXP_WIDTH:0] rg_exp_items;
    assign rg_exp_items[0] = rg_exp_prod;
    assign rg_exp_items[1] = signed'(pipe0_acc_rg_exp);

    logic signed [EXP_WIDTH:0] rg_exp_max;
    comp_tree #(
        .N    (2),
        .WIDTH(EXP_WIDTH)
    ) u_comp_tree (
        .operands_i(rg_exp_items),
        .result_o  (rg_exp_max)
    );

    // Booth 结果合并
    logic [MUL_WIDTH-1:0] mants_prod;
    assign mants_prod = mul_sum + mul_carry;

    // 尾数对齐
    logic [1:0][ALIGN_WIDTH-1:0] product;
    logic [1:0][ALIGN_WIDTH-1:0] product_shifted;

    // 乘积位宽适配
    if (ALIGN_WIDTH > MUL_WIDTH) begin
        assign product[0] = mants_prod << (ALIGN_WIDTH - MUL_WIDTH);
    end
    else begin
        assign product[0] = mants_prod >> (MUL_WIDTH - ALIGN_WIDTH);
    end

    // 累加值位宽适配
    if (ALIGN_WIDTH > (MANT_WIDTH_O) + 2) begin
        assign product[1] = pipe0_acc_mant << (ALIGN_WIDTH - (MANT_WIDTH_O) - 2);
    end
    else begin
        assign product[1] = pipe0_acc_mant >> ((MANT_WIDTH_O) + 2 - ALIGN_WIDTH);
    end

    // 桶形移位器对齐
    localparam int unsigned SHIFT_WIDTH = $clog2(ALIGN_WIDTH + 1);
    logic [1:0][EXP_WIDTH:0] rg_exp_diff;
    logic [1:0][SHIFT_WIDTH-1:0] shift_amount;

    generate
        genvar z, s;
        for (z = 0; z < 2; z++) begin
            assign rg_exp_diff[z] = unsigned'(rg_exp_max - rg_exp_items[z]);
        end

        if (EXP_WIDTH + 1 > SHIFT_WIDTH) begin : gen_shift_limited
            for (s = 0; s < 2; s++) begin
                assign shift_amount[s] = (|rg_exp_diff[s][EXP_WIDTH:SHIFT_WIDTH]) ? ALIGN_WIDTH : rg_exp_diff[s][SHIFT_WIDTH-1:0];

                barrel_shifter #(
                    .WIDTH      (ALIGN_WIDTH),
                    .SHIFT_WIDTH(SHIFT_WIDTH),
                    .MODE       (1'b1)
                ) u_barrel_shifter (
                    .operand_i   (product[s]),
                    .shift_amount(shift_amount[s]),
                    .result_o    (product_shifted[s])
                );
            end
        end
        else begin : gen_shift_direct
            for (s = 0; s < 2; s++) begin
                barrel_shifter #(
                    .WIDTH      (ALIGN_WIDTH),
                    .SHIFT_WIDTH(EXP_WIDTH + 1),
                    .MODE       (1'b1)
                ) u_barrel_shifter (
                    .operand_i   (product[s]),
                    .shift_amount(rg_exp_diff[s]),
                    .result_o    (product_shifted[s])
                );
            end
        end
    endgenerate

    // 补码累加 (CSA Tree)
    localparam int unsigned CARRY_WIDTH = $clog2(2);
    localparam int unsigned SUM_WIDTH   = ALIGN_WIDTH + CARRY_WIDTH;

    logic [1:0][SUM_WIDTH:0] mantissa, mantissa_comp;

    generate
        genvar y;
        for (y = 0; y < 2; y++) begin
            assign mantissa[y]      = product_shifted[y];
            assign mantissa_comp[y] = signs[y] ? (~mantissa[y] + 1'b1) : mantissa[y];
        end
    endgenerate

    logic [SUM_WIDTH:0] csa_sum, csa_carry;
    csa_tree #(
        .N      (2),
        .WIDTH_I(SUM_WIDTH + 1),
        .WIDTH_O(SUM_WIDTH + 1)
    ) u_csa_tree (
        .operands_i(mantissa_comp),
        .sum_o     (csa_sum),
        .carry_o   (csa_carry)
    );

    logic [SUM_WIDTH:0] sum_result;
    assign sum_result = csa_sum + csa_carry;

    // ********************
    // Pipeline 2: 归一化
    // ********************
    logic [SUM_WIDTH:0]          pipe1_sum_result;
    logic signed [EXP_WIDTH:0]   pipe1_rg_exp_max;




    `FFLARN(pipe1_sum_result, sum_result,    en_i_2, 0, clk_i, rstn_i)
    `FFLARN(pipe1_rg_exp_max, rg_exp_max,    en_i_2, 0, clk_i, rstn_i)

    logic               final_sign;
    logic [SUM_WIDTH-1:0] sum_c;

    assign final_sign = pipe1_sum_result[SUM_WIDTH];
    assign sum_c      = final_sign ? (~pipe1_sum_result + 1'b1) : pipe1_sum_result[SUM_WIDTH-1:0];

    // 尾数归一化
    logic signed [EXP_WIDTH:0] rg_exp_adjust;
    logic signed [EXP_WIDTH:0] final_rg_exp;
    logic [SUM_WIDTH-1:0] sum_norm;

    mantissa_norm #(
        .WIDTH        (SUM_WIDTH),
        .EXP_WIDTH    (EXP_WIDTH),
        .DECIMAL_POINT(CARRY_WIDTH + 2)
    ) u_mantissa_norm (
        .operand_i (sum_c),
        .exp_adjust(rg_exp_adjust),
        .result_o  (sum_norm)
    );

    assign final_rg_exp = pipe1_rg_exp_max + rg_exp_adjust;

    // 舍入
    logic [MANT_WIDTH_O+2:0] final_mant;

    if (SUM_WIDTH > MANT_WIDTH_O + 3) begin : gen_round_trunc
        logic sticky_bit;
        assign sticky_bit = |sum_norm[SUM_WIDTH-MANT_WIDTH_O-3:0];
        assign final_mant = {sum_norm[SUM_WIDTH-1:SUM_WIDTH-MANT_WIDTH_O-2], sticky_bit};
    end
    else begin : gen_round_pad
        assign final_mant = sum_norm << (MANT_WIDTH_O + 3 - SUM_WIDTH);
    end

    // ********************
    // Pipeline 3: 输出寄存器
    // ********************
    logic                          pipe2_final_sign;
    logic signed [EXP_WIDTH:0]     pipe2_final_rg_exp;
    logic [MANT_WIDTH_O+2:0]       pipe2_final_mant;




    `FFLARN(pipe2_final_sign,   final_sign,   en_i_3, 0, clk_i, rstn_i)
    `FFLARN(pipe2_final_rg_exp, final_rg_exp, en_i_3, 0, clk_i, rstn_i)
    `FFLARN(pipe2_final_mant,   final_mant,   en_i_3, 0, clk_i, rstn_i)

    // 连接输出 (修复点3：信号名改为与端口一致的 acc_*)
    assign acc_sign_o = pipe2_final_sign;
    assign acc_rg_exp_o = pipe2_final_rg_exp;
    assign acc_mant_o = pipe2_final_mant;











endmodule