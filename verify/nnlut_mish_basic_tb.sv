// NN LUT Mish 基础验证测试平台
// 不依赖预定义 golden 值，通过基本检查验证硬件功能
// 适合在获取 golden model 之前进行快速验证

`timescale 1ns/1ps

module nnlut_mish_basic_tb;

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
        $fsdbDumpfile("nnlut_mish_basic_tb.fsdb");
        $fsdbDumpvars(0, nnlut_mish_basic_tb, "+all");
    end

    // 时钟生成
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;  // 100MHz
    end

    // ============================================================
    // 真实训练参数
    // ============================================================

    localparam logic [15:0] BP_HEX [31] = '{
        16'ha900, 16'haa00, 16'hab00, 16'hac00, 16'had00,
        16'hae00, 16'haf00, 16'hafff, 16'hb200, 16'hb400,
        16'hb600, 16'hb7ff, 16'hbc00, 16'hbfff, 16'hc7ff,
        16'h0000,
        16'h3800, 16'h4065, 16'h4400, 16'h4800,
        16'h4a00, 16'h4c00, 16'h4e00, 16'h5000, 16'h5100,
        16'h5200, 16'h5300, 16'h5400, 16'h5500, 16'h5600,
        16'h5700
    };

    localparam logic [15:0] SLOPE_HEX [32] = '{
        16'heaf9, 16'heaf9, 16'heaf9, 16'heaf9, 16'heaf9, 16'heaf9,
        16'he2ba, 16'he2ba, 16'he2ba, 16'hdbdb, 16'hdbdb, 16'hd4ff,
        16'hdc91, 16'h175a, 16'h2a42, 16'h31fc, 16'h3b5f,
        16'h400e, 16'h40aa, 16'h40aa, 16'h4060, 16'h4060,
        16'h4019, 16'h4019, 16'h4001, 16'h4001, 16'h4001, 16'h4001,
        16'h4001, 16'h4001, 16'h4001, 16'h4001
    };

    localparam logic [15:0] INTERCEPT_HEX [32] = '{
        16'hde16, 16'hde16, 16'hde16, 16'hde16, 16'hde16, 16'hde16,
        16'hd0c7, 16'hd0c7, 16'hd0c7, 16'hca1f, 16'hca1f, 16'hc63a,
        16'hca1f, 16'hceaf, 16'hd605, 16'he148, 16'heb80,
        16'hd6ab, 16'hd1c9, 16'hd1c9, 16'hd691, 16'hd691,
        16'he152, 16'he152, 16'hee9c, 16'hee9c, 16'hee9c, 16'hee9c,
        16'hee9c, 16'hee9c, 16'hee9c, 16'hee9c
    };

    // 测试点结构
    typedef struct {
        logic [15:0] x_hex;
        real x_fp;
        string region;
        logic [15:0] expected_seg;  // 期望的区间索引
    } test_point_t;

    localparam test_point_t TEST_POINTS [15] = '{
        '{16'hAC00, -6.0, "neg_sat", 2},
        '{16'hAF00, -4.5, "neg_sat", 6},
        '{16'hB7FF, -2.0, "neg_trans", 11},
        '{16'hBFFF, -1.0, "neg_trans", 13},
        '{16'h0000, 0.0, "zero", 15},
        '{16'h3800, 0.5, "pos_trans", 16},
        '{16'h4065, 1.05, "pos_trans", 17},
        '{16'h4400, 1.5, "pos_trans", 18},
        '{16'h4800, 2.0, "pos_trans", 19},
        '{16'h4A00, 2.5, "pos_trans", 20},
        '{16'h4C00, 3.0, "linear", 21},
        '{16'h5000, 4.0, "linear", 23},
        '{16'h5200, 5.0, "linear", 25},
        '{16'h5400, 6.0, "linear", 27},
        '{16'h5700, 7.5, "linear", 31}
    };

    // 测试结果收集
    logic [15:0] hw_outputs [15];
    int test_count;
    string comma;

    // 主测试
    initial begin
        int pass_count = 0;
        int fail_count = 0;
        test_count = 0;

        $display("============================================================");
        $display("NN LUT Mish Basic Verification (Pre-Golden-Model)");
        $display("============================================================");
        $display("This test verifies hardware functionality without golden model");
        $display("Use nnlut_mish_tb.sv for full golden model comparison");
        $display("============================================================");

        // 初始化
        rstn_i = 0;
        cfg_en_i = 0;
        cfg_wr_en_i = 0;
        infer_start_i = 0;
        #100;
        rstn_i = 1;
        #20;

        // 加载参数
        $display("\n[Phase 1] Loading Parameters");
        $display("------------------------------------------------------------");
        for (int i = 0; i < N_BREAKPOINTS; i++) write_cfg(BP_BASE_ADDR + i[7:0], BP_HEX[i]);
        for (int i = 0; i < N_ENTRIES; i++) write_cfg(SLOPE_BASE_ADDR + i[7:0], SLOPE_HEX[i]);
        for (int i = 0; i < N_ENTRIES; i++) write_cfg(INTERCEPT_BASE_ADDR + i[7:0], INTERCEPT_HEX[i]);
        $display("  Parameters loaded");

        #20;

        // 运行测试收集结果
        $display("\n[Phase 2] Running Tests & Collecting Results");
        $display("------------------------------------------------------------");
        $display("%-5s %-20s %-10s %-10s %-10s %-10s",
                 "Idx", "Description", "x(hex)", "y(hex)", "Segment", "Valid");
        $display("------------------------------------------------------------");

        for (int i = 0; i < 15; i++) begin
            logic [15:0] result;
            int seg;
            string valid;

            run_test(TEST_POINTS[i], result, seg);
            hw_outputs[i] = result;

            // 基本验证：检查输出不为 X，段号符合期望
            if (result !== 16'hXXXX && seg == TEST_POINTS[i].expected_seg) begin
                valid = "OK";
                pass_count++;
            end else begin
                valid = "CHECK";
                fail_count++;
            end

            $display("%-5d %-20s 0x%04h   0x%04h   %-9d %-10s",
                     i, TEST_POINTS[i].region, TEST_POINTS[i].x_hex, result, seg, valid);
            test_count++;
        end

        $display("------------------------------------------------------------");

        // 单调性检查（Mish 在定义域内应该是单调递增的）
        $display("\n[Phase 3] Monotonicity Check");
        $display("------------------------------------------------------------");
        check_monotonicity();

        // 边界检查
        $display("\n[Phase 4] Boundary Tests");
        $display("------------------------------------------------------------");
        test_boundary("x < domain_min", 16'h8000);  // 应 clip 到 seg0
        test_boundary("x > domain_max", 16'h6000);  // 应 clip 到 seg31

        // 结果输出
        $display("\n============================================================");
        $display("Basic Verification Summary");
        $display("============================================================");
        $display("Tests run:      %0d", test_count);
        $display("Basic check OK: %0d", pass_count);
        $display("Need review:    %0d", fail_count);
        $display("============================================================");

        // 输出收集的硬件结果（可用于生成 golden model）
        $display("\n[Hardware Output Values for Golden Model]");
        $display("Copy these to nnlut_mish_tb.sv after verification:");
        $display("------------------------------------------------------------");
        for (int i = 0; i < 15; i++) begin
            comma = (i < 14) ? "," : "";
            $display("    '{16'h%04h, 16'h%04h, %6.2f, \"%s\"}%s",
                     TEST_POINTS[i].x_hex, hw_outputs[i], TEST_POINTS[i].x_fp, TEST_POINTS[i].region, comma);
        end
        $display("------------------------------------------------------------");

        $display("\nNext step: Run Python model to verify these outputs");
        $display("  cd /home/jet/Work/nnlut");
        $display("  python -m src.posit_inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 15");

        $finish;
    end

    // 配置写入
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

    // 运行测试
    task automatic run_test(test_point_t test, output logic [15:0] result, output int seg);
        @(posedge clk_i);
        infer_start_i = 1;
        infer_x_i = test.x_hex;
        @(posedge clk_i);
        infer_start_i = 0;

        wait(infer_done_o);
        result = infer_y_o;
        seg = u_nnlut.segment_idx;
        @(posedge clk_i);
    endtask

    // 边界测试
    task automatic test_boundary(string desc, logic [15:0] x_val);
        logic [15:0] result;
        int seg;

        @(posedge clk_i);
        infer_start_i = 1;
        infer_x_i = x_val;
        @(posedge clk_i);
        infer_start_i = 0;

        wait(infer_done_o);
        result = infer_y_o;
        seg = u_nnlut.segment_idx;
        @(posedge clk_i);

        $display("%-20s x=0x%04h -> seg=%0d, y=0x%04h", desc, x_val, seg, result);
    endtask

    // 单调性检查
    function automatic void check_monotonicity();
        int violations = 0;

        // 检查相邻测试点的单调性
        for (int i = 0; i < 14; i++) begin
            // 对于 Mish 函数，输出应该随输入增加而增加
            // 注意：这里使用有符号比较
            if ($signed(hw_outputs[i+1]) < $signed(hw_outputs[i])) begin
                $display("  WARNING: Non-monotonic at test %0d -> %0d", i, i+1);
                violations++;
            end
        end

        if (violations == 0)
            $display("  Monotonicity: OK (all points increasing)");
        else
            $display("  Monotonicity: %0d violations found", violations);
    endfunction

    // 调试监控
    always @(posedge infer_done_o) begin
        if (rstn_i) begin
            // $display("  [DEBUG] seg=%0d, y=0x%04h", u_nnlut.segment_idx, infer_y_o);
        end
    end

endmodule
