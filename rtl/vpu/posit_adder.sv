/*
在PE_kernel基础上去掉乘法的逻辑，改成二输入加法a+b，用在cordic中.
输入和输出都是解码后的形式。
*/
`include "registers.svh"
import posit_types_pkg::*;

module posit_adder #(
    parameter int unsigned n_i = 16,          // 输入Posit位宽
    parameter int unsigned es_i = 2,          // 输入指数位
    parameter int unsigned n_o = 16,          // 输出Posit位宽
    parameter int unsigned es_o = 2,          // 输出指数位
    parameter int unsigned ALIGN_WIDTH = 32   // 尾数对齐位宽
)(
    // 时钟与复位
    input  logic clk_i,
    input  logic rstn_i,
    
    // 流水线使能信号

    input  logic en_i_1, // 第一级流水线使能
    input  logic en_i_2,
    input  logic en_i_3,


    // ================= 输入：两个 Posit 解码分量（加数 A + 加数 B） =================
    input  logic                                                     a_sign_i,
    input  logic signed [get_exp_width_i(n_i, es_i):0]               a_rg_exp_i,
    input  logic        [get_mant_width_i(n_i, es_i):0]              a_mant_i,

    input  logic                                                     b_sign_i,
    input  logic signed [get_exp_width_i(n_i, es_i):0]               b_rg_exp_i,
    input  logic        [get_mant_width_i(n_i, es_i):0]              b_mant_i,

    // ================= 输出 =================
    // 加法结果输出：A + B
    output  logic                                                    sum_sign_o,
    output  logic signed [get_max_exp_width(n_i, es_i, n_o, es_o):0] sum_rg_exp_o,
    output  logic        [get_mant_width_o(n_o, es_o)+2:0]           sum_mant_o
);

    // ================= 局部参数 =================
    localparam int unsigned EXP_WIDTH_I  = get_exp_width_i(n_i, es_i);
    localparam int unsigned MANT_WIDTH_I = get_mant_width_i(n_i, es_i);
    localparam int unsigned MANT_WIDTH_O = get_mant_width_o(n_o, es_o);
    localparam int unsigned EXP_WIDTH    = get_max_exp_width(n_i, es_i, n_o, es_o);
    localparam int unsigned CARRY_WIDTH  = $clog2(2);
    localparam int unsigned SUM_WIDTH    = ALIGN_WIDTH + CARRY_WIDTH;
    localparam int unsigned SHIFT_WIDTH  = $clog2(ALIGN_WIDTH + 1);

    // //======================流水线使能====================
    // logic en_i_1, en_i_2, en_i_3;
    
    // assign en_i_1 = calc_start_i;
    // `FFARN(en_i_2,      en_i_1,          0,  clk_i,  rstn_i)
    // `FFARN(en_i_3,      en_i_2,          0,  clk_i,  rstn_i)
    // `FFARN(calc_done_o, en_i_3,          0,  clk_i,  rstn_i)
    
    
    // ================= Pipeline 0：输入寄存器 =================
    logic                        pipe0_a_sign;
    logic signed [EXP_WIDTH_I:0] pipe0_a_rg_exp;
    logic        [MANT_WIDTH_I:0] pipe0_a_mant;

    logic                        pipe0_b_sign;
    logic signed [EXP_WIDTH_I:0] pipe0_b_rg_exp;
    logic        [MANT_WIDTH_I:0] pipe0_b_mant;

    `FFLARN(pipe0_a_sign,     a_sign_i,     en_i_1, 0, clk_i, rstn_i)
    `FFLARN(pipe0_a_rg_exp,   a_rg_exp_i,   en_i_1, 0, clk_i, rstn_i)
    `FFLARN(pipe0_a_mant,     a_mant_i,     en_i_1, 0, clk_i, rstn_i)

    `FFLARN(pipe0_b_sign,     b_sign_i,     en_i_1, 0, clk_i, rstn_i)
    `FFLARN(pipe0_b_rg_exp,   b_rg_exp_i,   en_i_1, 0, clk_i, rstn_i)
    `FFLARN(pipe0_b_mant,     b_mant_i,     en_i_1, 0, clk_i, rstn_i)

    // ********************
    // 纯 Posit 加法逻辑
    // ********************

    // 1. 两个操作数的符号
    logic [1:0] signs;
    assign signs[0] = pipe0_a_sign;
    assign signs[1] = pipe0_b_sign;

    // 2. 指数列表（A 和 B 的指数）
    logic signed [1:0][EXP_WIDTH:0] rg_exp_items;
    assign rg_exp_items[0] = pipe0_a_rg_exp;
    assign rg_exp_items[1] = pipe0_b_rg_exp;

    // 3. 直接用2输入比较器找最大指数（替换comp_tree）
    logic signed [EXP_WIDTH:0] rg_exp_max;
    comparator #(
        .WIDTH(EXP_WIDTH)
    ) u_max_comparator (
        .operand_a(rg_exp_items[0]),  // a的指数
        .operand_b(rg_exp_items[1]),  // b的指数
        .result_o (rg_exp_max)        // 输出最大值
    );

    // 4. 尾数位宽适配
    logic [1:0][ALIGN_WIDTH-1:0] operand_aligned;
    // A 尾数适配
    assign operand_aligned[0] = (ALIGN_WIDTH > MANT_WIDTH_I + 1) ? 
                                (pipe0_a_mant << (ALIGN_WIDTH - (MANT_WIDTH_I + 1))) : 
                                (pipe0_a_mant >> ((MANT_WIDTH_I + 1) - ALIGN_WIDTH));
    // B 尾数适配
    assign operand_aligned[1] = (ALIGN_WIDTH > MANT_WIDTH_I + 1) ? 
                                (pipe0_b_mant << (ALIGN_WIDTH - (MANT_WIDTH_I + 1))) : 
                                (pipe0_b_mant >> ((MANT_WIDTH_I + 1) - ALIGN_WIDTH));

    // 5. 指数差计算 + 桶形移位对齐
    logic [1:0][EXP_WIDTH:0]    rg_exp_diff;
    logic [1:0][SHIFT_WIDTH-1:0] shift_amount;
    logic [1:0][ALIGN_WIDTH-1:0] operand_shifted;

    generate
        for (genvar z = 0; z < 2; z++) begin
            assign rg_exp_diff[z] = unsigned'(rg_exp_max - rg_exp_items[z]);
        end

        for (genvar s = 0; s < 2; s++) begin
            assign shift_amount[s] = (|rg_exp_diff[s][EXP_WIDTH:SHIFT_WIDTH]) ? 
                                      ALIGN_WIDTH : rg_exp_diff[s][SHIFT_WIDTH-1:0];
            barrel_shifter #(
                .WIDTH(ALIGN_WIDTH), .SHIFT_WIDTH(SHIFT_WIDTH), .MODE(1'b1)
            ) u_barrel_shifter (
                .operand_i(operand_aligned[s]), .shift_amount(shift_amount[s]), .result_o(operand_shifted[s])
            );
        end
    endgenerate

    // 6. 补码转换 + CSA 加法器
    logic [1:0][SUM_WIDTH:0] mantissa_comp;
    generate
        for (genvar y = 0; y < 2; y++) begin
            assign mantissa_comp[y] = signs[y] ? (~operand_shifted[y] + 1'b1) : operand_shifted[y];
        end
    endgenerate

    logic [SUM_WIDTH:0] csa_sum, csa_carry, sum_result;
    //TODO:N=2的时候时直通的，这个csa_tree没必要
    csa_tree #(
        .N(2), .WIDTH_I(SUM_WIDTH+1), .WIDTH_O(SUM_WIDTH+1)
    ) u_csa_tree (
        .operands_i(mantissa_comp), .sum_o(csa_sum), .carry_o(csa_carry)
    );
    assign sum_result = csa_sum + csa_carry;

    // ================= Pipeline 1：加法结果寄存 =================
    logic                        pipe1_a_sign;
    logic signed [EXP_WIDTH_I:0] pipe1_a_rg_exp;
    logic        [MANT_WIDTH_I:0] pipe1_a_mant;

    logic                        pipe1_b_sign;
    logic signed [EXP_WIDTH_I:0] pipe1_b_rg_exp;
    logic        [MANT_WIDTH_I:0] pipe1_b_mant;

    logic [SUM_WIDTH:0]          pipe1_sum_result;
    logic signed [EXP_WIDTH:0]   pipe1_rg_exp_max;



    `FFLARN(pipe1_sum_result, sum_result, en_i_2, 0, clk_i, rstn_i)
    `FFLARN(pipe1_rg_exp_max, rg_exp_max, en_i_2, 0, clk_i, rstn_i)

    // 结果符号 + 绝对值
    logic               final_sign;
    logic [SUM_WIDTH-1:0] sum_abs;
    assign final_sign = pipe1_sum_result[SUM_WIDTH];
    assign sum_abs    = final_sign ? (~pipe1_sum_result + 1'b1) : pipe1_sum_result[SUM_WIDTH-1:0];

    // 尾数归一化
    logic signed [EXP_WIDTH:0] rg_exp_adjust, final_rg_exp;
    logic [SUM_WIDTH-1:0] sum_norm;
    //DECIMOL_POINT设为3（CARRY_WIDTH+2）不对，设为2呢？
    mantissa_norm #(
        .WIDTH(SUM_WIDTH), .EXP_WIDTH(EXP_WIDTH), .DECIMAL_POINT(CARRY_WIDTH + 1)
    ) u_mantissa_norm (
        .operand_i(sum_abs), .exp_adjust(rg_exp_adjust), .result_o(sum_norm)
    );
    assign final_rg_exp = pipe1_rg_exp_max + rg_exp_adjust;

    // 舍入处理
    logic [MANT_WIDTH_O+2:0] final_mant;
    assign final_mant = (SUM_WIDTH > MANT_WIDTH_O + 3) ? 
                        {sum_norm[SUM_WIDTH-1:SUM_WIDTH-MANT_WIDTH_O-2], |sum_norm[SUM_WIDTH-MANT_WIDTH_O-3:0]} : 
                        (sum_norm << (MANT_WIDTH_O + 3 - SUM_WIDTH));

    // ================= Pipeline 2：输出寄存器 =================
    logic                        pipe2_a_sign;
    logic signed [EXP_WIDTH_I:0] pipe2_a_rg_exp;
    logic        [MANT_WIDTH_I:0] pipe2_a_mant;

    logic                        pipe2_b_sign;
    logic signed [EXP_WIDTH_I:0] pipe2_b_rg_exp;
    logic        [MANT_WIDTH_I:0] pipe2_b_mant;

    logic                          pipe2_final_sign;
    logic signed [EXP_WIDTH:0]     pipe2_final_rg_exp;
    logic [MANT_WIDTH_O+2:0]       pipe2_final_mant;



    `FFLARN(pipe2_final_sign,   final_sign,   en_i_3, 0, clk_i, rstn_i)
    `FFLARN(pipe2_final_rg_exp, final_rg_exp, en_i_3, 0, clk_i, rstn_i)
    `FFLARN(pipe2_final_mant,   final_mant,   en_i_3, 0, clk_i, rstn_i)

    // ================= 最终输出 =================
    // assign a_sign_o    = pipe2_a_sign;
    // assign a_rg_exp_o  = pipe2_a_rg_exp;
    // assign a_mant_o    = pipe2_a_mant;

    // assign b_sign_o    = pipe2_b_sign;
    // assign b_rg_exp_o  = pipe2_b_rg_exp;
    // assign b_mant_o    = pipe2_b_mant;

    assign sum_sign_o  = pipe2_final_sign;
    assign sum_rg_exp_o= pipe2_final_rg_exp;
    assign sum_mant_o  = pipe2_final_mant;

endmodule