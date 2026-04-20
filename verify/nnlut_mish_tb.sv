// NN LUT Mish 函数验证测试平台（带 Golden Model 比对）
// 使用 outputs/mish_default/lut_params.json 中的训练参数
// 对比硬件输出与软件 Golden Model 计算结果

`timescale 1ns/1ps

module nnlut_mish_tb;

    // 参数
    localparam int unsigned N_ENTRIES = 32;
    localparam int unsigned N_BREAKPOINTS = 31;
    localparam int unsigned N_I = 16;
    localparam int unsigned ES_I = 2;
    localparam int unsigned N_O = 16;
    localparam int unsigned ES_O = 2;
    localparam int unsigned ADDR_WIDTH = 8;
    localparam int unsigned ALIGN_WIDTH = 14;

    // 地址常量
    localparam logic [7:0] BP_BASE_ADDR = 8'h00;
    localparam logic [7:0] SLOPE_BASE_ADDR = 8'h20;
    localparam logic [7:0] INTERCEPT_BASE_ADDR = 8'h40;

    // 信号
    logic clk_i;
    logic rstn_i;
    logic                      cfg_en_i;
    logic [ADDR_WIDTH-1:0]   cfg_addr_i;
    logic [N_I-1:0]          cfg_data_i;
    logic                      cfg_wr_en_i;
    logic [N_I-1:0]          cfg_data_o;
    logic                      infer_start_i;
    logic [N_I-1:0]          infer_x_i;
    logic [N_O-1:0]          infer_y_o;
    logic                      infer_done_o;

    // 被测模块实例化
    nnlut #(
        .N_ENTRIES(N_ENTRIES),
        .N_BREAKPOINTS(N_BREAKPOINTS),
        .N_I(N_I),
        .ES_I(ES_I),
        .N_O(N_O),
        .ES_O(ES_O),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALIGN_WIDTH(ALIGN_WIDTH)
    ) u_nnlut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .cfg_en_i(cfg_en_i),
        .cfg_addr_i(cfg_addr_i),
        .cfg_data_i(cfg_data_i),
        .cfg_wr_en_i(cfg_wr_en_i),
        .cfg_data_o(cfg_data_o),
        .infer_start_i(infer_start_i),
        .infer_x_i(infer_x_i),
        .infer_y_o(infer_y_o),
        .infer_done_o(infer_done_o)
    );

    // 波形 dump
    initial begin
        $fsdbDumpfile("nnlut_mish_tb.fsdb");
        $fsdbDumpvars(0, nnlut_mish_tb, "+all");
    end

    // 时钟生成
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;  // 100MHz
    end

    // ============================================================
    // 真实训练参数（来自 outputs/mish_default/lut_params.json）
    // ============================================================

    // Breakpoints: 31 个断点（地址 0x00-0x1E）
    localparam logic [15:0] BP_HEX [31] = '{
        16'ha900, 16'haa00, 16'hab00, 16'hac00, 16'had00,  // -7.5 ~ -5.5
        16'hae00, 16'haf00, 16'hafff, 16'hb200, 16'hb400,  // -5.0 ~ -3.0
        16'hb600, 16'hb7ff, 16'hbc00, 16'hbfff, 16'hc7ff,  // -2.5 ~ -0.5
        16'h0000,                                          //  0.0
        16'h3800, 16'h4065, 16'h4400, 16'h4800,           //  0.5 ~ 2.0
        16'h4a00, 16'h4c00, 16'h4e00, 16'h5000, 16'h5100, //  2.5 ~ 5.0
        16'h5200, 16'h5300, 16'h5400, 16'h5500, 16'h5600, //  5.5 ~ 7.0
        16'h5700                                           //  7.5
    };

    // Slopes: 32 个斜率（地址 0x20-0x3F）
    localparam logic [15:0] SLOPE_HEX [32] = '{
        16'heaf9, 16'heaf9, 16'heaf9, 16'heaf9, 16'heaf9, 16'heaf9,  // seg 0-5
        16'he2ba, 16'he2ba, 16'he2ba,                                 // seg 6-8
        16'hdbdb, 16'hdbdb,                                         // seg 9-10
        16'hd4ff,                                                   // seg 11
        16'hdc91, 16'h175a, 16'h2a42, 16'h31fc, 16'h3b5f,           // seg 12-16
        16'h400e, 16'h40aa, 16'h40aa, 16'h4060, 16'h4060,           // seg 17-21
        16'h4019, 16'h4019,                                         // seg 22-23
        16'h4001, 16'h4001, 16'h4001, 16'h4001,                     // seg 24-27
        16'h4001, 16'h4001, 16'h4001, 16'h4001                      // seg 28-31
    };

    // Intercepts: 32 个截距（地址 0x40-0x5F）
    localparam logic [15:0] INTERCEPT_HEX [32] = '{
        16'hde16, 16'hde16, 16'hde16, 16'hde16, 16'hde16, 16'hde16,  // seg 0-5
        16'hd0c7, 16'hd0c7, 16'hd0c7,                                // seg 6-8
        16'hca1f, 16'hca1f,                                         // seg 9-10
        16'hc63a,                                                   // seg 11
        16'hca1f, 16'hceaf, 16'hd605, 16'he148, 16'heb80,           // seg 12-16
        16'hd6ab, 16'hd1c9, 16'hd1c9, 16'hd691, 16'hd691,           // seg 17-21
        16'he152, 16'he152,                                         // seg 22-23
        16'hee9c, 16'hee9c, 16'hee9c, 16'hee9c,                     // seg 24-27
        16'hee9c, 16'hee9c, 16'hee9c, 16'hee9c                      // seg 28-31
    };

    // ============================================================
    // Golden Model 期望值（从 Python 软件模型生成）
    // 通过运行: python generate_golden.py 获取这些值
    // 这些值代表了 y = x * slope + intercept 在 posit 域的计算结果
    // ============================================================

    typedef struct {
        logic [15:0] x_hex;           // 输入 posit hex
        logic [15:0] expected_y_hex;  // 期望输出（软件 golden model 结果）
        real x_fp;                    // 输入浮点值（用于显示）
        string description;           // 测试描述
    } golden_vector_t;

    // Golden Model 测试向量
    // 格式: {input_hex, expected_output_hex, input_fp, description}
    // 这些期望值通过 Python PositLUTInference 计算得到
    // 生成命令: python3 -m src.posit_inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 15
    localparam golden_vector_t GOLDEN_VECTORS[15] = '{
        // 负饱和区
        '{16'hA7FF, 16'h0C30, -8.0, "x=-8.0 (neg_sat)"},        // 0xa7ff -> 0x0c30
        '{16'hAA49, 16'hEACC, -6.857, "x=-6.86 (neg_sat)"},     // 0xaa49 -> 0xeacc
        '{16'hAC92, 16'hE687, -5.714, "x=-5.71 (neg_sat)"},     // 0xac92 -> 0xe687
        '{16'hAEDB, 16'hE1A5, -4.571, "x=-4.57 (neg_trans)"},   // 0xaedb -> 0xe1a5

        // 负过渡区
        '{16'hB249, 16'hDA1D, -3.429, "x=-3.43 (neg_trans)"},   // 0xb249 -> 0xda1d
        '{16'hB6DB, 16'hD20F, -2.286, "x=-2.29 (neg_trans)"},   // 0xb6db -> 0xd20f
        '{16'hBEDB, 16'hCE29, -1.143, "x=-1.14 (neg_trans)"},   // 0xbedb -> 0xce29

        // 零点附近
        '{16'h0000, 16'hEB81, 0.0, "x=0.0 (zero)"},            // 0x0000 -> 0xeb81

        // 正过渡区
        '{16'h4125, 16'h4021, 1.143, "x=1.14 (pos_trans)"},    // 0x4125 -> 0x4021
        '{16'h4925, 16'h48FC, 2.286, "x=2.29 (pos_trans)"},     // 0x4925 -> 0x48fc
        '{16'h4DB7, 16'h4DAC, 3.429, "x=3.43 (pos_trans)"},     // 0x4db7 -> 0x4dac

        // 正线性区
        '{16'h5125, 16'h5123, 4.571, "x=4.57 (linear)"},       // 0x5125 -> 0x5123
        '{16'h536E, 16'h536D, 5.714, "x=5.71 (linear)"},         // 0x536e -> 0x536d
        '{16'h55B7, 16'h55B6, 6.857, "x=6.86 (linear)"},        // 0x55b7 -> 0x55b6
        '{16'h5800, 16'h57FF, 8.0, "x=8.0 (linear)"}            // 0x5800 -> 0x57ff
    };

    localparam int NUM_GOLDEN_TESTS = 15;

    // 测试统计
    int total_tests;
    int pass_count;
    int fail_count;
    int mismatch_count;

    // 主测试过程
    initial begin
        total_tests = 0;
        pass_count = 0;
        fail_count = 0;
        mismatch_count = 0;

        $display("============================================================");
        $display("NN LUT Mish Function - Golden Model Verification");
        $display("============================================================");
        $display("Parameters: outputs/mish_default/lut_params.json");
        $display("Function: mish(x) = x * tanh(softplus(x))");
        $display("Domain: [-8.0, 8.0], Entries: 32");
        $display("Posit Format: <16,2>");
        $display("Golden Model: Python PositLUTInference");
        $display("============================================================");

        // 初始化信号
        rstn_i = 0;
        cfg_en_i = 0;
        cfg_addr_i = '0;
        cfg_data_i = '0;
        cfg_wr_en_i = 0;
        infer_start_i = 0;
        infer_x_i = '0;

        // 复位
        #100;
        rstn_i = 1;
        #20;

        // ============================================================
        // Phase 1: 加载参数
        // ============================================================
        $display("\n[Phase 1] Loading LUT Parameters");
        $display("------------------------------------------------------------");

        // 加载 breakpoints (31个)
        for (int i = 0; i < N_BREAKPOINTS; i++) begin
            write_cfg(BP_BASE_ADDR + i[7:0], BP_HEX[i]);
        end
        $display("  Loaded %0d breakpoints", N_BREAKPOINTS);

        // 加载 slopes (32个)
        for (int i = 0; i < N_ENTRIES; i++) begin
            write_cfg(SLOPE_BASE_ADDR + i[7:0], SLOPE_HEX[i]);
        end
        $display("  Loaded %0d slopes", N_ENTRIES);

        // 加载 intercepts (32个)
        for (int i = 0; i < N_ENTRIES; i++) begin
            write_cfg(INTERCEPT_BASE_ADDR + i[7:0], INTERCEPT_HEX[i]);
        end
        $display("  Loaded %0d intercepts", N_ENTRIES);

        #20;

        // ============================================================
        // Phase 2: Golden Model 比对测试
        // ============================================================
        $display("\n[Phase 2] Golden Model Comparison");
        $display("------------------------------------------------------------");
        $display("Format: y = x * slope + intercept (in posit domain)");
        $display("------------------------------------------------------------");
        $display("%-5s %-20s %-10s %-12s %-12s %-10s",
                 "Idx", "Description", "x(hex)", "HW y(hex)", "Golden(hex)", "Match");
        $display("------------------------------------------------------------");

        for (int i = 0; i < NUM_GOLDEN_TESTS; i++) begin
            test_with_golden(i, GOLDEN_VECTORS[i], pass_count, fail_count, mismatch_count);
            total_tests++;
        end

        #50;

        // ============================================================
        // Phase 3: 边界测试
        // ============================================================
        $display("\n[Phase 3] Boundary Tests");
        $display("------------------------------------------------------------");

        // 测试超出定义域的值（应 clip 到边界区间）
        test_boundary("Below domain (clip to seg0)", 16'h8000);  // -16 -> clip to -8
        test_boundary("Above domain (clip to seg31)", 16'h6000); // +16 -> clip to +8

        total_tests += 2;

        #50;

        // ============================================================
        // Summary
        // ============================================================
        $display("\n============================================================");
        $display("Test Summary");
        $display("============================================================");
        $display("Total tests:       %0d", total_tests);
        $display("Exact match:       %0d", pass_count);
        $display("Mismatch:          %0d", mismatch_count);
        $display("Failed (no output):%0d", fail_count);

        if (pass_count == NUM_GOLDEN_TESTS)
            $display("Pass rate:         100%% (All Golden Model tests passed)");
        else
            $display("Pass rate:         %0.1f%%", (pass_count * 100.0) / NUM_GOLDEN_TESTS);

        $display("============================================================");

        if (fail_count == 0 && mismatch_count == 0)
            $display("STATUS: ALL TESTS PASSED - Hardware matches Golden Model");
        else if (mismatch_count > 0)
            $display("STATUS: %0d MISMATCHES - Hardware output differs from Golden Model", mismatch_count);
        else
            $display("STATUS: %0d TESTS FAILED", fail_count);

        $display("============================================================");

        $display("\nNote: To regenerate Golden Model vectors:");
        $display("  cd /home/jet/Work/nnlut");
        $display("  python -m src.posit_inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 15");

        $finish;
    end

    // 配置写入任务
    task automatic write_cfg(logic [7:0] addr, logic [15:0] data);
        @(posedge clk_i);
        cfg_en_i = 1;
        cfg_wr_en_i = 1;
        cfg_addr_i = addr;
        cfg_data_i = data;
        @(posedge clk_i);
        cfg_en_i = 0;
        cfg_wr_en_i = 0;
    endtask

    // Golden Model 比对测试任务
    task automatic test_with_golden(
        int idx,
        golden_vector_t test,
        ref int pass,
        ref int fail,
        ref int mismatch
    );
        logic [15:0] hw_result;
        string status;
        int actual_seg;

        // 启动推理
        @(posedge clk_i);
        infer_start_i = 1;
        infer_x_i = test.x_hex;
        @(posedge clk_i);
        infer_start_i = 0;

        // 等待完成（在 infer_done_o 后再等一个时钟周期确保数据稳定）
        wait(infer_done_o);
        @(posedge clk_i);  // 关键：再等一拍让数据稳定
        hw_result = infer_y_o;
        actual_seg = u_nnlut.segment_idx;

        // 调试：显示 seg16 和 seg0 的参数值
        if (idx == 7) begin  // x=0.0 测试点
            $display("    [DEBUG] seg16 slope=0x%04h, intercept=0x%04h",
                     u_nnlut.debug_slope_16, u_nnlut.debug_intercept_16);
            $display("    [DEBUG] seg0 slope=0x%04h, intercept=0x%04h",
                     u_nnlut.debug_slope_0, u_nnlut.debug_intercept_0);
            $display("    [DEBUG] selected_slope=0x%04h, selected_intercept=0x%04h",
                     u_nnlut.selected_slope, u_nnlut.selected_intercept);
        end

        // 比对结果
        if (hw_result === test.expected_y_hex) begin
            status = "MATCH";
            pass++;
        end else if (hw_result === 16'hXXXX || hw_result === 16'h0000 && test.expected_y_hex !== 16'h0000) begin
            status = "FAIL";
            fail++;
        end else begin
            status = "MISMATCH";
            mismatch++;
        end

        // 显示结果（包含 segment 索引）
        $display("%-5d %-20s 0x%04h   0x%04h(seg%0d) 0x%04h     %-10s",
                 idx, test.description, test.x_hex, hw_result, actual_seg, test.expected_y_hex, status);
    endtask

    // 边界测试
    task automatic test_boundary(string desc, logic [15:0] x_val);
        logic [15:0] result;

        @(posedge clk_i);
        infer_start_i = 1;
        infer_x_i = x_val;
        @(posedge clk_i);
        infer_start_i = 0;

        wait(infer_done_o);
        result = infer_y_o;
        @(posedge clk_i);

        $display("%-35s x=0x%04h -> y=0x%04h", desc, x_val, result);
    endtask

    // 监控输出
    always @(posedge infer_done_o) begin
        if (rstn_i) begin
            // 调试信息（可选）
            // $display("  [DEBUG] @%0t: seg=%0d, y=0x%04h", $time, u_nnlut.segment_idx, infer_y_o);
        end
    end

endmodule
