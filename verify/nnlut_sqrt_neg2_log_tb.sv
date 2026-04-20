// NN LUT sqrt_neg2_log 验证测试平台（带 Golden Model 比对）
// 参数来源：nnlut/outputs/sqrt_neg2_log_default/lut_params.json（Posit<16,2>）
//
// Golden vectors 获取参考（见 NNLUT_VERIFICATION_GUIDE.md）：
//   cd /data/home/rh_xu30/Work/DPRL_V3_0401/nnlut
//   python3 -m src.posit_inference --lut outputs/sqrt_neg2_log_default/lut_params.json --range 0.0001 1.0 --samples 15
//
`timescale 1ns/1ps

module nnlut_sqrt_neg2_log_tb;

    localparam int unsigned N_ENTRIES = 32;
    localparam int unsigned N_BREAKPOINTS = 31;
    localparam int unsigned N_I = 16;
    localparam int unsigned ES_I = 2;
    localparam int unsigned N_O = 16;
    localparam int unsigned ES_O = 2;
    localparam int unsigned ADDR_WIDTH = 8;
    localparam int unsigned ALIGN_WIDTH = 14;

    localparam logic [7:0] BP_BASE_ADDR = 8'h00;
    localparam logic [7:0] SLOPE_BASE_ADDR = 8'h20;
    localparam logic [7:0] INTERCEPT_BASE_ADDR = 8'h40;

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

    initial begin
        $fsdbDumpfile("nnlut_sqrt_neg2_log_tb.fsdb");
        $fsdbDumpvars(0, nnlut_sqrt_neg2_log_tb, "+all");
    end

    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end

    // ============================================================
    // 参数（Posit hex）
    // ============================================================
    localparam logic [15:0] BP_HEX [31] = '{
        16'h06A3, 16'h1C03, 16'h2003, 16'h2403, 16'h2801,
        16'h2A39, 16'h2C01, 16'h2E01, 16'h3001, 16'h3101,
        16'h3201, 16'h3301, 16'h3401, 16'h3500, 16'h3600,
        16'h3700, 16'h3800, 16'h3880, 16'h3900, 16'h3980,
        16'h3A00, 16'h3A80, 16'h3B00, 16'h3B80, 16'h3C00,
        16'h3C80, 16'h3D00, 16'h3D80, 16'h3E00, 16'h3EAC,
        16'h3F00
    };

    localparam logic [15:0] SLOPE_HEX [32] = '{
        16'h9A90, 16'h9A90,
        16'hAC6C, 16'hAC6C, 16'hAC6C, 16'hAC6C,
        16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963,
        16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963,
        16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963, 16'hB963,
        16'hB12A, 16'hB12A
    };

    localparam logic [15:0] INTERCEPT_HEX [32] = '{
        16'h4EC3, 16'h4EC3,
        16'h4AFD, 16'h4AFD, 16'h4AFD, 16'h4AFD,
        16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875,
        16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875,
        16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875, 16'h4875,
        16'h4F5D, 16'h4F5D
    };

    // ============================================================
    // Golden vectors（软件输出）
    // ============================================================
    typedef struct {
        logic [15:0] x_hex;
        logic [15:0] expected_y_hex;
        real x_fp;
        string description;
    } golden_vector_t;

    localparam golden_vector_t GOLDEN_VECTORS[15] = '{
        '{16'h06A3, 16'h4EBF, 0.000100000, "x=0.000100 (sqrt_neg2_log)"},
        '{16'h2128, 16'h4955, 0.071521429, "x=0.071521 (sqrt_neg2_log)"},
        '{16'h2926, 16'h475C, 0.142942857, "x=0.142943 (sqrt_neg2_log)"},
        '{16'h2DB8, 16'h45C8, 0.214364286, "x=0.214364 (sqrt_neg2_log)"},
        '{16'h3125, 16'h44BD, 0.285785714, "x=0.285786 (sqrt_neg2_log)"},
        '{16'h336E, 16'h43B2, 0.357207143, "x=0.357207 (sqrt_neg2_log)"},
        '{16'h35B7, 16'h42A7, 0.428628571, "x=0.428629 (sqrt_neg2_log)"},
        '{16'h3800, 16'h419C, 0.500050000, "x=0.500050 (sqrt_neg2_log)"},
        '{16'h3925, 16'h4090, 0.571471429, "x=0.571471 (sqrt_neg2_log)"},
        '{16'h3A49, 16'h3F0C, 0.642892857, "x=0.642893 (sqrt_neg2_log)"},
        '{16'h3B6E, 16'h3CF5, 0.714314286, "x=0.714314 (sqrt_neg2_log)"},
        '{16'h3C92, 16'h3ADF, 0.785735714, "x=0.785736 (sqrt_neg2_log)"},
        '{16'h3DB7, 16'h38C8, 0.857157143, "x=0.857157 (sqrt_neg2_log)"},
        '{16'h3EDB, 16'h34BD, 0.928578571, "x=0.928579 (sqrt_neg2_log)"},
        '{16'h4000, 16'h2880, 1.000000000, "x=1.000000 (sqrt_neg2_log)"}
    };

    localparam int NUM_GOLDEN_TESTS = 15;

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
        $display("NN LUT sqrt_neg2_log - Golden Model Verification");
        $display("============================================================");
        $display("Parameters: outputs/sqrt_neg2_log_default/lut_params.json");
        $display("Domain: [0.0001, 1.0], Entries: 32");
        $display("Posit Format: <16,2>");
        $display("Golden Model: Python PositLUTInference");
        $display("============================================================");

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

        $display("\n[Phase 2] Golden Model Comparison");
        $display("------------------------------------------------------------");
        $display("%-5s %-28s %-10s %-12s %-12s %-10s",
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

        $display("%-5d %-28s 0x%04h   0x%04h(seg%0d) 0x%04h     %-10s",
                 idx, test.description, test.x_hex, hw_result, actual_seg, test.expected_y_hex, status);
    endtask

endmodule

