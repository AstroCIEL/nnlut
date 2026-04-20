// 强制规定是1.f格式，即小数点固定在第1位
// 输入范围：a ∈ (1, 2)
// 求倒数 1/a
// 优化版：合并 Stage 3/4，Latency = 3
module fixed_reciprocal_newton #(
    parameter N = 16
) (
    input  wire clk,
    input  wire arst_n,
    input  wire valid_in,           // 输入有效（同时作为所有寄存器的load使能）
    input  wire [N-1:0] a,
    output reg  valid_out,
    output reg  [N-1:0] reciprocal
);

// -------------------------------------------------------------------------
// 步骤1：根据小数点后两位选初值 x0（纯组合逻辑）
// -------------------------------------------------------------------------
reg [N-1:0] x0_q0n1_comb;

localparam [N-1:0] X0_INT0 = (8 * (1 << (N-1)) + 4) / 9;
localparam [N-1:0] X0_INT1 = (8 * (1 << (N-1)) + 5) / 11;
localparam [N-1:0] X0_INT2 = (8 * (1 << (N-1)) + 6) / 13;
localparam [N-1:0] X0_INT3 = (8 * (1 << (N-1)) + 7) / 15;

always @(*) begin
    case ({a[N-2], a[N-3]})
        2'b00: x0_q0n1_comb = X0_INT0;
        2'b01: x0_q0n1_comb = X0_INT1;
        2'b10: x0_q0n1_comb = X0_INT2;
        2'b11: x0_q0n1_comb = X0_INT3;
        default: x0_q0n1_comb = X0_INT1;
    endcase
end

// -------------------------------------------------------------------------
// 步骤2：定义通用的单步迭代函数（纯组合逻辑）
// -------------------------------------------------------------------------
function [N-1:0] newton_step;
    input [N-1:0] a;
    input [N-1:0] x_prev;
    reg [2*N-1:0] a_x;
    reg [2*N-1:0] two_minus;
    reg [3*N-1:0] x_next_full;
    localparam [2*N-1:0] CONST_2 = 1 << (2*N - 1);
    localparam SHIFT = 2*N - 2;
    localparam ROUND = 1 << (SHIFT - 1);
    begin
        a_x = a * x_prev;
        two_minus = CONST_2 - a_x;
        x_next_full = x_prev * two_minus;
        newton_step = (x_next_full + ROUND) >> SHIFT;
    end
endfunction

// -------------------------------------------------------------------------
// 步骤3：第一级流水线（输入 -> x0）
// -------------------------------------------------------------------------
reg [N-1:0] a_reg1;
reg [N-1:0] x0_reg;
reg valid_reg1;

// 注意：这里假设你的代码环境中已经定义了 `FFLARN 和 `FFARN 宏
// 如果没有，请替换为标准的 always @(posedge clk or negedge arst_n) 写法
`FFLARN(a_reg1, a, valid_in, '0, clk, arst_n)
`FFLARN(x0_reg, x0_q0n1_comb, valid_in, '0, clk, arst_n)
`FFARN (valid_reg1, valid_in,          1'b0, clk, arst_n)

// -------------------------------------------------------------------------
// 步骤4：第二级流水线（x0 -> x1，第一次迭代）
// -------------------------------------------------------------------------
wire [N-1:0] x1_q0n1_comb = newton_step(a_reg1, x0_reg);
reg [N-1:0] a_reg2;
reg [N-1:0] x1_reg;
reg valid_reg2;

`FFLARN(a_reg2, a_reg1, valid_reg1, '0, clk, arst_n)
`FFLARN(x1_reg, x1_q0n1_comb, valid_reg1, '0, clk, arst_n)
`FFARN (valid_reg2, valid_reg1,          1'b0, clk, arst_n)

// -------------------------------------------------------------------------
// 步骤5：第三级流水线（x1 -> x2 -> 最终结果，合并逻辑）
// -------------------------------------------------------------------------
// 5.1 先进行第二次牛顿迭代（组合逻辑）
wire [N-1:0] x2_q0n1_comb = newton_step(a_reg2, x1_reg);

// 5.2 紧接着进行最终修正（组合逻辑，原 Stage 4 的逻辑前移）
reg [2*N-1:0] a_x2;
reg [2*N-1:0] two_minus_x2;
reg [3*N-1:0] x2_full;
reg [N-1:0] reciprocal_comb;
localparam [2*N-1:0] CONST_2_FINAL = 1 << (2*N - 1);
localparam SHIFT_FINAL = 2*N - 3;
localparam ROUND_FINAL = (3 * (1 << SHIFT_FINAL)) / 5;

always @(*) begin
    // 注意：这里直接使用 a_reg2 和 x2_q0n1_comb，不经过寄存器打拍
    a_x2 = a_reg2 * x2_q0n1_comb;
    two_minus_x2 = CONST_2_FINAL - a_x2;
    x2_full = x2_q0n1_comb * two_minus_x2;
    reciprocal_comb = (x2_full + ROUND_FINAL) >> SHIFT_FINAL;
end

// 5.3 直接锁存最终结果（由 valid_reg2 驱动，跳过了原 valid_reg3）
`FFLARN(reciprocal, reciprocal_comb, valid_reg2, '0, clk, arst_n)
`FFARN(valid_out, valid_reg2,                  1'b0, clk, arst_n)

endmodule