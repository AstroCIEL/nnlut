module posit_mac_tb;

logic clk_i;
logic rstn_i;
logic calc_start_i;
logic calc_done_o;
logic [15:0] a_posit_i;
logic [15:0] b_posit_i;
logic [15:0] c_posit_i;
logic [15:0] d_posit_o;


posit_mac #(
    // parameter int unsigned MAC_NUM = 16,
    .n_i        (16),
    .es_i       (2),
    .n_o        (16),
    .es_o       (2),
    .ALIGN_WIDTH(14)
) u_posit_mac(
    .clk_i        (clk_i),
    .rstn_i       (rstn_i),



    .calc_start_i (calc_start_i),
    .calc_done_o  (calc_done_o),

    .a_posit_i  (a_posit_i),
    .b_posit_i  (b_posit_i),
    .c_posit_i  (c_posit_i),

    .d_posit_o  (d_posit_o)

);

initial begin
    $fsdbDumpfile("posit_mac_tb.fsdb");
    $fsdbDumpvars(0, posit_mac_tb, "+all");
end



always #5 clk_i = ~clk_i;

initial begin
    clk_i <= 0;
    rstn_i <= 0;
    set_to_zero;

repeat(10) @(posedge clk_i);

    rstn_i <= 1;

repeat(10) @(posedge clk_i);


give_in_abc(16'h632c,  16'h9781,  16'h0000);
give_in_abc(16'h6935,  16'h99fe,  16'h89fc);
give_in_abc(16'h6954,  16'h623c,  16'h8785);
give_in_abc(16'h9768,  16'h9647,  16'h8827);
give_in_abc(16'hd4d6,  16'h5fec,  16'h76bb);
give_in_abc(16'h9685,  16'h6428,  16'h76ba);
give_in_abc(16'h642d,  16'h9bcb,  16'h9440);
give_in_abc(16'h9e93,  16'h6851,  16'h8b90);
give_in_abc(16'h976f,  16'h9afb,  16'h8952);
give_in_abc(16'h97df,  16'h68df,  16'h6de0);
give_in_abc(16'h99dd,  16'h676e,  16'h87ca);
give_in_abc(16'h584f,  16'h97d9,  16'h8714);
give_in_abc(16'h6538,  16'ha963,  16'h86f9);
give_in_abc(16'h995f,  16'h6830,  16'h86ef);
give_in_abc(16'h9a1d,  16'h99d6,  16'h8680);
give_in_abc(16'haeb2,  16'h6947,  16'h86c9);
give_in_abc(16'ha715,  16'haba3,  16'h86bd);
give_in_abc(16'h68fb,  16'h9870,  16'h86bf);
give_in_abc(16'h6992,  16'h6470,  16'h8628);
give_in_abc(16'h6417,  16'h9a3c,  16'h868b);


@(posedge clk_i) calc_start_i <= 0;

repeat(20) @(posedge clk_i);

$finish;
end


task automatic set_to_zero;
    @(posedge clk_i) begin
        a_posit_i <= 0;
        b_posit_i <= 0;
        c_posit_i <= 0;
        calc_start_i <= 0;
    end
endtask

task automatic give_in_abc;
    input logic [15:0] func_a_posit;
    input logic [15:0] func_b_posit;
    input logic [15:0] func_c_posit;

    @(posedge clk_i) begin
        a_posit_i <= func_a_posit;
        b_posit_i <= func_b_posit;
        c_posit_i <= func_c_posit;
        calc_start_i <= 1;
    end

endtask

endmodule