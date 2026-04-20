module fixed_sqrt_newton #(
    parameter int N = 16
) (
    input  logic         clk,
    input  logic         arst_n,
    input  logic         valid_in,
    input  logic [N-1:0] a,
    output logic         valid_out,
    output logic [N-1:0] sqrt
);

    // =========================================================
    // initial guess
    // =========================================================
    localparam logic [N-1:0] FP_ONE  = {1'b1, {(N-1){1'b0}}};

    localparam logic [N-1:0] X0_INT0 = (9472 * FP_ONE + 5000) / 10000; // 0.9472
    localparam logic [N-1:0] X0_INT1 = (8555 * FP_ONE + 5000) / 10000; // 0.8555
    localparam logic [N-1:0] X0_INT2 = (7862 * FP_ONE + 5000) / 10000; // 0.7862
    localparam logic [N-1:0] X0_INT3 = (7315 * FP_ONE + 5000) / 10000; // 0.7315

    logic [N-1:0] r0_comb;

    always_comb begin
        case ({a[N-2], a[N-3]})
            2'b00:   r0_comb = X0_INT0;
            2'b01:   r0_comb = X0_INT1;
            2'b10:   r0_comb = X0_INT2;
            2'b11:   r0_comb = X0_INT3;
            default: r0_comb = X0_INT1;
        endcase
    end

    // =========================================================
    // rsqrt newton step
    // r_next = r * (3 - a*r*r) / 2
    //
    // fixed-point format:
    //   a, r_prev : Q1.(N-1)
    //   r_sq      : Q2.(2N-2)
    //   a_r_sq    : Q3.(3N-3)
    //   r_next    : Q1.(N-1)
    //
    // round-to-nearest
    // =========================================================
    function automatic [N-1:0] rsqrt_newton_step (
        input logic [N-1:0] a_i,
        input logic [N-1:0] r_prev
    );
        logic [2*N-1:0] r_sq;
        logic [3*N-1:0] a_r_sq;
        logic [3*N-1:0] three_minus;
        logic [4*N-1:0] r_next_full;

        logic [3*N-1:0] const_3;
        logic [4*N-1:0] round_r;

        begin
            const_3 = {1'b0, 2'b11, {(3*N-3){1'b0}}};         // 3.0 in Q3.(3N-3)
            round_r = {{(N+2){1'b0}}, 1'b1, {(3*N-3){1'b0}}}; // 2^(3N-3)

            r_sq        = r_prev * r_prev;
            a_r_sq      = a_i * r_sq;
            three_minus = const_3 - a_r_sq;
            r_next_full = r_prev * three_minus;

            rsqrt_newton_step = (r_next_full + round_r) >> (3*N - 2);
        end
    endfunction

    // =========================================================
    // final floor correction
    //
    // target:
    //   floor( sqrt(a_real) * 2^(N-1) )
    //
    // compare y^2 with (a << (N-1)):
    //   y^2 <= a * 2^(N-1)  <=>  y <= floor-scaled sqrt
    //
    // allow correction by up to +/-2 LSB
    // =========================================================
    function automatic [N-1:0] correct_sqrt_floor_2step (
        input logic [N-1:0] a_i,
        input logic [N-1:0] y0
    );
        logic [2*N-1:0] target;
        logic [2*N-1:0] y0_sq;
        logic [2*N-1:0] y1_sq;
        logic [2*N-1:0] y2_sq;

        logic [N-1:0] y1;
        logic [N-1:0] y2;

        begin
            target = {1'b0, a_i, {(N-1){1'b0}}}; // a << (N-1)

            y0_sq = y0 * y0;

            if (y0_sq > target) begin
                y1    = y0 - 1'b1;
                y1_sq = y1 * y1;

                if (y1_sq > target) begin
                    y2 = y1 - 1'b1;
                    correct_sqrt_floor_2step = y2;
                end else begin
                    correct_sqrt_floor_2step = y1;
                end
            end else begin
                y1    = y0 + 1'b1;
                y1_sq = y1 * y1;

                if (y1_sq <= target) begin
                    y2    = y1 + 1'b1;
                    y2_sq = y2 * y2;

                    if (y2_sq <= target) begin
                        correct_sqrt_floor_2step = y2;
                    end else begin
                        correct_sqrt_floor_2step = y1;
                    end
                end else begin
                    correct_sqrt_floor_2step = y0;
                end
            end
        end
    endfunction

    // =========================================================
    // pipeline
    // latency = 3
    //   s1: latch a, r0
    //   s2: r1
    //   s3: r2 + y0 + floor-correction + output register
    // =========================================================
    logic [N-1:0] a_s1, a_s2;
    logic [N-1:0] r0_s1, r1_s2;
    logic         v_s1,  v_s2;

    logic [N-1:0]   r2_comb;
    logic [2*N-1:0] y_full_comb;
    logic [N-1:0]   y0_comb;
    logic [N-1:0]   sqrt_comb;

    // stage 1
    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            a_s1  <= '0;
            r0_s1 <= '0;
            v_s1  <= 1'b0;
        end else begin
            if (valid_in) begin
                a_s1  <= a;
                r0_s1 <= r0_comb;
            end
            v_s1 <= valid_in;
        end
    end

    // stage 2
    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            a_s2  <= '0;
            r1_s2 <= '0;
            v_s2  <= 1'b0;
        end else begin
            if (v_s1) begin
                a_s2  <= a_s1;
                r1_s2 <= rsqrt_newton_step(a_s1, r0_s1);
            end
            v_s2 <= v_s1;
        end
    end

    // stage 3 combinational
    always_comb begin
        r2_comb    = rsqrt_newton_step(a_s2, r1_s2);
        y_full_comb = a_s2 * r2_comb;
        y0_comb    = y_full_comb >> (N - 1); // truncation
        sqrt_comb  = correct_sqrt_floor_2step(a_s2, y0_comb);
    end

    // output
    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            sqrt      <= '0;
            valid_out <= 1'b0;
        end else begin
            if (v_s2) begin
                sqrt <= sqrt_comb;
            end
            valid_out <= v_s2;
        end
    end

endmodule
