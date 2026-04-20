// NN LUT mish_derivative 验证测试平台（带 Golden Model 比对）
// 参数来源：nnlut/outputs/mish_derivative_default/lut_params.json（Posit<16,2>）
//
// Golden vectors 生成参考（见 NNLUT_VERIFICATION_GUIDE.md）：
//   cd /data/home/rh_xu30/Work/DPRL_V3_0401/nnlut
//   python3 -m src.posit_inference --lut outputs/mish_derivative_default/lut_params.json --range -8 8 --samples 15
//
`timescale 1ns/1ps

module nnlut_mish_derivative_tb;

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
    logic                    cfg_en_i;
    logic [ADDR_WIDTH-1:0]   cfg_addr_i;
    logic [N_I-1:0]          cfg_data_i;
    logic                    cfg_wr_en_i;
    logic [N_I-1:0]          cfg_data_o;
    logic                    infer_start_i;
    logic [N_I-1:0]          infer_x_i;
    logic [N_O-1:0]          infer_y_o;
    logic                    infer_done_o;

    // 被测模块
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

    // dump
    initial begin
        $fsdbDumpfile("nnlut_mish_derivative_tb.fsdb");
        $fsdbDumpvars(0, nnlut_mish_derivative_tb, "+all");
    end

    // 时钟
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end

    // ============================================================
    // 真实训练参数（Posit hex）
    // ============================================================

    localparam logic [15:0] BP_HEX [31] = '{
        16'hA900, 16'hAA00, 16'hAB00, 16'hAC00, 16'hAD00,
        16'hAE00, 16'hAF00, 16'hAFFF, 16'hB200, 16'hB400,
        16'hB600, 16'hB7FF, 16'hBC00, 16'hBFFF, 16'hC7FF,
        16'h0000, 16'h39F4, 16'h4000, 16'h42F3, 16'h4800,
        16'h4A00, 16'h4CE0, 16'h4E00, 16'h5000, 16'h5100,
        16'h5200, 16'h5300, 16'h5400, 16'h5500, 16'h5600,
        16'h5700
    };

    localparam logic [15:0] SLOPE_HEX [32] = '{
        16'hEBF7, 16'hEBF7, 16'hEBF7, 16'hEBF7, 16'hEBF7, 16'hEBF7,
        16'hE359, 16'hE359, 16'hE359, 16'hE359, 16'hE359, 16'hE359,
        16'h20AF, 16'h2A90, 16'h3768, 16'h3A0D, 16'h3A69, 16'h311C,
        16'h235A, 16'hE19E, 16'hE19E, 16'hE19E,
        16'hF164, 16'hF164, 16'hF164, 16'hF164, 16'hF164, 16'hF164,
        16'hF164, 16'hF164, 16'hF164, 16'hF164
    };

    localparam logic [15:0] INTERCEPT_HEX [32] = '{
        16'hE008, 16'hE008, 16'hE008, 16'hE008, 16'hE008, 16'hE008,
        16'hD31F, 16'hD31F, 16'hD31F, 16'hD31F, 16'hD31F, 16'hD31F,
        16'h1ABB, 16'h2BDB, 16'h385C, 16'h3990, 16'h3961, 16'h3C55,
        16'h3F7D, 16'h4157, 16'h4157, 16'h4157,
        16'h4020, 16'h4020, 16'h4020, 16'h4020, 16'h4020, 16'h4020,
        16'h4020, 16'h4020, 16'h4020, 16'h4020
    };

    // ============================================================
    // Golden Model vectors（软件输出）
    // ============================================================

    typedef struct {
        logic [15:0] x_hex;
        logic [15:0] expected_y_hex;
        real x_fp;
        string description;
    } golden_vector_t;

    localparam golden_vector_t GOLDEN_VECTORS[15] = '{
        '{16'hA7FF, 16'h0B20, -8.000000, "x=-8.00 (mish_derivative)"},
        '{16'hAA49, 16'hEBC6, -6.857143, "x=-6.86 (mish_derivative)"},
        '{16'hAC92, 16'hE795, -5.714286, "x=-5.71 (mish_derivative)"},
        '{16'hAEDB, 16'hE37E, -4.571429, "x=-4.57 (mish_derivative)"},
        '{16'hB249, 16'hDE2F, -3.428571, "x=-3.43 (mish_derivative)"},
        '{16'hB6DB, 16'hD8DF, -2.285714, "x=-2.29 (mish_derivative)"},
        '{16'hBEDB, 16'hF097, -1.142857, "x=-1.14 (mish_derivative)"},
        '{16'h0000, 16'h3961,  0.000000, "x=0.00 (mish_derivative)"},
        '{16'h4125, 16'h408E,  1.142857, "x=1.14 (mish_derivative)"},
        '{16'h4925, 16'h406E,  2.285714, "x=2.29 (mish_derivative)"},
        '{16'h4DB7, 16'h400E,  3.428571, "x=3.43 (mish_derivative)"},
        '{16'h5125, 16'h4008,  4.571429, "x=4.57 (mish_derivative)"},
        '{16'h536E, 16'h4002,  5.714286, "x=5.71 (mish_derivative)"},
        '{16'h55B7, 16'h3FF9,  6.857143, "x=6.86 (mish_derivative)"},
        '{16'h5800, 16'h3FED,  8.000000, "x=8.00 (mish_derivative)"}
    };

    localparam int NUM_GOLDEN_TESTS = 15;

    // 统计
    int total_tests;
    int pass_count;
    int mismatch_count;
    int fail_count;

    initial begin
        total_tests = 0;
        pass_count = 0;
        mismatch_count = 0;
        fail_count = 0;

        $display("============================================================");
        $display("NN LUT mish_derivative - Golden Model Verification");
        $display("============================================================");
        $display("Parameters: outputs/mish_derivative_default/lut_params.json");
        $display("Domain: [-8.0, 8.0], Entries: 32");
        $display("Posit Format: <16,2>");
        $display("Golden Model: Python PositLUTInference");
        $display("============================================================");

        // init
        rstn_i = 0;
        cfg_en_i = 0;
        cfg_addr_i = '0;
        cfg_data_i = '0;
        cfg_wr_en_i = 0;
        infer_start_i = 0;
        infer_x_i = '0;

        #100;
        rstn_i = 1;
        #20;

        // load params
        $display("\n[Phase 1] Loading LUT Parameters");
        for (int i = 0; i < N_BREAKPOINTS; i++) begin
            write_cfg(BP_BASE_ADDR + i[7:0], BP_HEX[i]);
        end
        for (int i = 0; i < N_ENTRIES; i++) begin
            write_cfg(SLOPE_BASE_ADDR + i[7:0], SLOPE_HEX[i]);
        end
        for (int i = 0; i < N_ENTRIES; i++) begin
            write_cfg(INTERCEPT_BASE_ADDR + i[7:0], INTERCEPT_HEX[i]);
        end
        $display("  Loaded breakpoints/slopes/intercepts");

        #20;

        // run tests
        $display("\n[Phase 2] Golden Model Comparison");
        $display("------------------------------------------------------------");
        $display("%-5s %-26s %-10s %-12s %-12s %-10s",
                 "Idx", "Description", "x(hex)", "HW y(hex)", "Golden(hex)", "Match");
        $display("------------------------------------------------------------");

        for (int i = 0; i < NUM_GOLDEN_TESTS; i++) begin
            test_with_golden(i, GOLDEN_VECTORS[i], pass_count, fail_count, mismatch_count);
            total_tests++;
        end

        #50;

        $display("\n============================================================");
        $display("Test Summary");
        $display("============================================================");
        $display("Total tests:       %0d", total_tests);
        $display("Exact match:       %0d", pass_count);
        $display("Mismatch:          %0d", mismatch_count);
        $display("Failed:            %0d", fail_count);
        $display("Pass rate:         %0.1f%%", (pass_count * 100.0) / NUM_GOLDEN_TESTS);
        $display("============================================================");

        if (mismatch_count == 0 && fail_count == 0)
            $display("STATUS: ALL TESTS PASSED");
        else
            $display("STATUS: %0d MISMATCHES", mismatch_count);

        $finish;
    end

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

        @(posedge clk_i);
        infer_start_i = 1;
        infer_x_i = test.x_hex;
        @(posedge clk_i);
        infer_start_i = 0;

        // done 后再等一拍采样
        wait(infer_done_o);
        @(posedge clk_i);
        hw_result = infer_y_o;
        actual_seg = u_nnlut.segment_idx;

        if (hw_result === test.expected_y_hex) begin
            status = "MATCH";
            pass++;
        end else if (hw_result === 16'hXXXX) begin
            status = "FAIL";
            fail++;
        end else begin
            status = "MISMATCH";
            mismatch++;
        end

        $display("%-5d %-26s 0x%04h   0x%04h(seg%0d) 0x%04h     %-10s",
                 idx, test.description, test.x_hex, hw_result, actual_seg, test.expected_y_hex, status);
    endtask

endmodule

