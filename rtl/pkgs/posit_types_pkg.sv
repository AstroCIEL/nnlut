package posit_types_pkg;

    // =========================================================
    // Fixed posit format parameters for whole project
    // =========================================================
    localparam int unsigned N_I  = 16;
    localparam int unsigned ES_I = 2;
    localparam int unsigned N_O  = 16;
    localparam int unsigned ES_O = 2;

    // =========================================================
    // Width helper functions
    // =========================================================
    function automatic int unsigned get_exp_width_i(int unsigned n, int unsigned es);
        get_exp_width_i = $clog2(n-1) + es;
    endfunction
    
    function automatic int unsigned get_mant_width_i(int unsigned n, int unsigned es);
        get_mant_width_i = n - es - 3;
    endfunction

    function automatic int unsigned get_exp_width_o(int unsigned n, int unsigned es);
        get_exp_width_o = $clog2(n-1) + es;
    endfunction
    
    function automatic int unsigned get_mant_width_o(int unsigned n, int unsigned es);
        get_mant_width_o = n - es - 3;
    endfunction

    function automatic int unsigned get_max_exp_width(
        int unsigned ni, int unsigned esi,
        int unsigned no, int unsigned eso
    );
        int unsigned exp_i, exp_o;
        exp_i = $clog2(ni-1) + esi + 1;
        exp_o = $clog2(no-1) + eso;
        get_max_exp_width = (exp_i > exp_o) ? exp_i : exp_o;
    endfunction

    // =========================================================
    // Derived widths
    // =========================================================
    localparam int unsigned EXP_I_W   = get_exp_width_i(N_I, ES_I) + 1;
    localparam int unsigned MANT_I_W  = get_mant_width_i(N_I, ES_I) + 1;
    localparam int unsigned EXP_O_W   = get_exp_width_o(N_O, ES_O) + 1;
    localparam int unsigned MANT_O_W  = get_mant_width_o(N_O, ES_O) + 1;
    localparam int unsigned ACC_EXP_W = get_max_exp_width(N_I, ES_I, N_O, ES_O) + 1;
    localparam int unsigned ACC_MANT_W = get_mant_width_o(N_O, ES_O) + 3;

    // =========================================================
    // Fixed typedefs
    // =========================================================
    typedef struct packed {
        logic                       sign;
        logic signed [EXP_I_W-1:0]  rg_exp;
        logic        [MANT_I_W-1:0] mant;
    } posit_in_t;

    typedef struct packed {
        logic                         sign;
        logic signed [ACC_EXP_W-1:0]  rg_exp;
        logic        [ACC_MANT_W-1:0] mant;
    } posit_acc_t;

endpackage
