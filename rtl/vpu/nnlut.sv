import posit_types_pkg::*;

// NN LUT 模块
// 实现 LUT 推理功能：y = slope * x + intercept
// 支持 32 组参数存储（breakpoints, slopes, intercepts）
// 通过地址接口配置参数，使用 posit_mac 进行计算
//
// 地址映射（默认 ADDR_WIDTH=8）：
// - 0x00-0x1E: breakpoints (31 entries，用于界定 32 个区间)
// - 0x20-0x3F: slopes (32 entries)
// - 0x40-0x5F: intercepts (32 entries)
//
// 推理流程：
// 1. 通过 cfg 接口写入参数
// 2. 拉高 infer_start_i，输入 infer_x_i
// 3. 3 个时钟周期后 infer_done_o 拉高，infer_y_o 有效
module nnlut #(
    parameter int unsigned N_ENTRIES = 32,     // LUT 段数（slopes/intercepts）
    parameter int unsigned N_BREAKPOINTS = 31, // breakpoints 数量（N_ENTRIES-1）
    parameter int unsigned N_I = 16,           // 输入 posit 位宽
    parameter int unsigned ES_I = 2,           // 输入 posit es
    parameter int unsigned N_O = 16,           // 输出 posit 位宽
    parameter int unsigned ES_O = 2,           // 输出 posit es
    parameter int unsigned ADDR_WIDTH = 8,   // 地址位宽
    parameter int unsigned ALIGN_WIDTH = 14    // MAC 对齐宽度
)(
    input  logic clk_i,
    input  logic rstn_i,

    // 参数配置接口
    input  logic                      cfg_en_i,     // 配置使能
    input  logic [ADDR_WIDTH-1:0]   cfg_addr_i,   // 配置地址
    input  logic [N_I-1:0]          cfg_data_i,   // 配置数据（posit 格式）
    input  logic                      cfg_wr_en_i,  // 写使能
    output logic [N_I-1:0]          cfg_data_o,   // 读数据

    // 推理接口
    input  logic                      infer_start_i,  // 推理启动
    input  logic [N_I-1:0]          infer_x_i,      // 输入 x (posit 格式)
    output logic [N_O-1:0]          infer_y_o,      // 输出 y (posit 格式)
    output logic                      infer_done_o    // 推理完成
);

    // ================= 地址映射 =================
    localparam logic [ADDR_WIDTH-1:0] BP_BASE_ADDR = 8'h00;
    localparam logic [ADDR_WIDTH-1:0] SLOPE_BASE_ADDR = 8'h20;
    localparam logic [ADDR_WIDTH-1:0] INTERCEPT_BASE_ADDR = 8'h40;
    localparam logic [ADDR_WIDTH-1:0] BP_END_ADDR = BP_BASE_ADDR + N_BREAKPOINTS[ADDR_WIDTH-1:0];
    localparam logic [ADDR_WIDTH-1:0] SLOPE_END_ADDR = SLOPE_BASE_ADDR + N_ENTRIES[ADDR_WIDTH-1:0];
    localparam logic [ADDR_WIDTH-1:0] INTERCEPT_END_ADDR = INTERCEPT_BASE_ADDR + N_ENTRIES[ADDR_WIDTH-1:0];

    // ================= 参数寄存器 =================
    // breakpoints: 31 个，用于界定 32 个区间
    logic [N_I-1:0] breakpoints [N_BREAKPOINTS];
    // slopes 和 intercepts: 各 32 个，每个区间一组
    logic [N_I-1:0] slopes [N_ENTRIES];
    logic [N_I-1:0] intercepts [N_ENTRIES];

    // ================= 参数读写逻辑 =================
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            // 复位时清零所有参数
            for (int i = 0; i < N_BREAKPOINTS; i++) begin
                breakpoints[i] <= '0;
            end
            for (int i = 0; i < N_ENTRIES; i++) begin
                slopes[i] <= '0;
                intercepts[i] <= '0;
            end
        end else if (cfg_en_i && cfg_wr_en_i) begin
            // 写操作
            if (cfg_addr_i >= BP_BASE_ADDR && cfg_addr_i < SLOPE_BASE_ADDR) begin
                // breakpoints 区域（地址 0x00-0x1E）
                automatic logic [4:0] bp_idx = cfg_addr_i[4:0];
                if (bp_idx < N_BREAKPOINTS[4:0]) begin
                    breakpoints[bp_idx] <= cfg_data_i;
                end
            end else if (cfg_addr_i >= SLOPE_BASE_ADDR && cfg_addr_i < INTERCEPT_BASE_ADDR) begin
                // slopes 区域（地址 0x20-0x3F）
                slopes[cfg_addr_i[4:0]] <= cfg_data_i;
            end else if (cfg_addr_i >= INTERCEPT_BASE_ADDR && cfg_addr_i < 8'h60) begin
                // intercepts 区域（地址 0x40-0x5F）
                intercepts[cfg_addr_i[4:0]] <= cfg_data_i;
            end
        end
    end

    // 读操作（组合逻辑）
    always_comb begin
        cfg_data_o = '0;
        if (cfg_en_i && !cfg_wr_en_i) begin
            if (cfg_addr_i >= BP_BASE_ADDR && cfg_addr_i < SLOPE_BASE_ADDR) begin
                automatic logic [4:0] bp_idx = cfg_addr_i[4:0];
                if (bp_idx < N_BREAKPOINTS[4:0]) begin
                    cfg_data_o = breakpoints[bp_idx];
                end
            end else if (cfg_addr_i >= SLOPE_BASE_ADDR && cfg_addr_i < INTERCEPT_BASE_ADDR) begin
                cfg_data_o = slopes[cfg_addr_i[4:0]];
            end else if (cfg_addr_i >= INTERCEPT_BASE_ADDR && cfg_addr_i < 8'h60) begin
                cfg_data_o = intercepts[cfg_addr_i[4:0]];
            end
        end
    end

    // ================= Stage 0: 输入捕获 =================
    logic [N_I-1:0] infer_x_reg;
    logic infer_valid_s0;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            infer_x_reg <= '0;
            infer_valid_s0 <= 1'b0;
        end else begin
            infer_valid_s0 <= infer_start_i;
            if (infer_start_i) begin
                infer_x_reg <= infer_x_i;
            end
        end
    end

    // ================= Stage 1: 区间查找 =================
    // 目标：实现 Python 的
    //   seg_idx = np.searchsorted(breakpoints, x, side="right")
    // breakpoints 为升序（包含负到正），slopes/intercepts 长度为 32
    //
    // 注意：这里的比较必须是“数值意义上的有序比较”，不能直接把 posit bits 当无符号整数比。
    // 由于本项目 breakpoints 本身也是 Posit<16,2> 编码后的位模式，且训练时的断点是单调的，
    // 我们用“符号扩展后按有符号整数比较”的方式实现（与当前参数集匹配）。
    // 对外/对 testbench 暴露的 segment 索引（便于调试比对）
    // 约定：为与输入对齐，这里输出的是 Stage1 寄存后的 segment_idx_s1
    logic [4:0] segment_idx;
    logic [4:0] segment_idx_s1;
    logic [4:0] segment_idx_comb;
    logic [N_I-1:0] infer_x_s1;
    logic infer_valid_s1;

    // 符号扩展到 17-bit 后按 signed 比较
    wire signed [16:0] x_signed = {infer_x_reg[15], infer_x_reg};

    always_comb begin
        segment_idx_comb = 5'd0;
        // 从前往后做 searchsorted(side="right") 等价实现：
        // 统计满足 x >= bp[i] 的 breakpoint 个数，seg = count
        // （因为 side="right"，当 x 恰好等于 bp[i] 也要进入右侧区间）
        for (int i = 0; i < N_BREAKPOINTS; i++) begin
            logic signed [16:0] bp_i;
            bp_i = {breakpoints[i][15], breakpoints[i]};
            if (x_signed >= bp_i) begin
                segment_idx_comb = i[4:0] + 5'd1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            infer_x_s1 <= '0;
            infer_valid_s1 <= 1'b0;
            segment_idx_s1 <= 5'd0;
        end else begin
            infer_x_s1 <= infer_x_reg;
            infer_valid_s1 <= infer_valid_s0;
            if (infer_valid_s0) begin
                segment_idx_s1 <= segment_idx_comb;
            end
        end
    end

    assign segment_idx = segment_idx_s1;

    // ================= Stage 2: 参数选择 =================
    logic [N_I-1:0] selected_slope;
    logic [N_I-1:0] selected_intercept;
    logic [N_I-1:0] infer_x_s2;
    logic infer_valid_s2;

    // 调试：检查 seg16 的参数值
    wire [15:0] debug_slope_16 = slopes[16];
    wire [15:0] debug_intercept_16 = intercepts[16];
    wire [15:0] debug_slope_0 = slopes[0];
    wire [15:0] debug_intercept_0 = intercepts[0];

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            infer_x_s2 <= '0;
            selected_slope <= '0;
            selected_intercept <= '0;
            infer_valid_s2 <= 1'b0;
        end else begin
            infer_x_s2 <= infer_x_s1;
            selected_slope <= slopes[segment_idx_s1];
            selected_intercept <= intercepts[segment_idx_s1];
            infer_valid_s2 <= infer_valid_s1;
        end
    end

    // ================= MAC 实例化 =================
    // y = x * slope + intercept
    // posit_mac 需要 3 个时钟周期产生结果（内部有 3 级流水线）
    logic [N_O-1:0] mac_result;
    logic mac_done;

    posit_mac #(
        .n_i(N_I),
        .es_i(ES_I),
        .n_o(N_O),
        .es_o(ES_O),
        .ALIGN_WIDTH(ALIGN_WIDTH)
    ) u_posit_mac (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .calc_start_i(infer_valid_s2),      // Stage 2 的 valid 启动 MAC
        .calc_done_o(mac_done),
        .a_posit_i(infer_x_s2),             // x
        .b_posit_i(selected_slope),          // slope
        .c_posit_i(selected_intercept),      // intercept
        .d_posit_o(mac_result)               // y = x * slope + intercept
    );

    // ================= 输出 =================
    assign infer_y_o = mac_result;
    assign infer_done_o = mac_done;

endmodule
