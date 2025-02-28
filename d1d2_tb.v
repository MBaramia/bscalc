`timescale 1ns / 1ps

module d1d2_tb;

    parameter WIDTH = 32;

    // Inputs
    reg clk;
    reg reset;
    reg start;
    reg signed [WIDTH-1:0] S0;
    reg signed [WIDTH-1:0] K;
    reg signed [WIDTH-1:0] T;
    reg signed [WIDTH-1:0] sigma;
    reg signed [WIDTH-1:0] r;

    // Outputs
    wire signed [WIDTH-1:0] d1;
    wire signed [WIDTH-1:0] d2;
    wire pipeline_done;
    wire norm_start;

    // Debug signals
    wire div_valid_out;
    wire sqrt_valid_out;
    wire log_valid_out;

    // Instantiate the revised d1d2
    d1d2 #(WIDTH) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .S0(S0),
        .K(K),
        .T(T),
        .sigma(sigma),
        .r(r),
        .d1(d1),
        .d2(d2),
        .pipeline_done(pipeline_done),
        .norm_start(norm_start),
        .div_valid_out(div_valid_out),
        .sqrt_valid_out(sqrt_valid_out),
        .log_valid_out(log_valid_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        // 1) Assert reset
        reset = 1;
        start = 0;
        // Initialize all inputs to 1.0 in Q16.16
        S0    = 32'h00010000;
        K     = 32'h00010000;
        T     = 32'h00010000;
        sigma = 32'h00010000;
        r     = 32'h00010000;

        // 2) Deassert reset after 50 ns
        #50;
        reset = 0;

        // 3) Wait a few cycles, then do test #1
        #20;
        // Test 1: S0=1, K=1, T=1, sigma=1, r=1
        $display("\n[TB] Setting up Test 1...");
        S0    = 32'h00010000;  // 1.0
        K     = 32'h00010000;  // 1.0
        T     = 32'h00010000;  // 1.0
        sigma = 32'h00010000;  // 1.0
        r     = 32'h00010000;  // 1.0

        // Fire start for one cycle
        start = 1; #10; start = 0;

        // Wait for pipeline_done
        @(posedge pipeline_done);
        #20; // Let signals settle
        $display("=== Test Case 1 ===");
        $display("S0=1, K=1, T=1, sigma=1, r=1");
        $display("Expected d1 = 0x00018000 (1.5), d2 = 0x00008000 (0.5)");
        $display("Got d1=0x%h (%f), d2=0x%h (%f)\n",
                 d1, $itor(d1)/65536.0,
                 d2, $itor(d2)/65536.0);

        // 4) Test 2: S0=100, K=100, T=1, sigma=0.2, r=0.05
        $display("\n[TB] Setting up Test 2...");
        S0    = 32'h00640000; // 100.0 in Q16.16
        K     = 32'h00640000; // 100.0 in Q16.16
        T     = 32'h00010000; // 1.0 in Q16.16
        sigma = 32'h00003333; // ~0.2 in Q16.16
        r     = 32'h00000ccd; // ~0.05 in Q16.16

        start = 1; #10; start = 0;
        @(posedge pipeline_done);
        #20; // Let signals settle
        $display("=== Test Case 2 ===");
        $display("S0=100, K=100, T=1, sigma=0.2, r=0.05");
        $display("Expected d1 ~ 0.15, d2 ~ -0.05");
        $display("Got d1=0x%h (%f), d2=0x%h (%f)\n",
                 d1, $itor(d1)/65536.0,
                 d2, $itor(d2)/65536.0);

        $finish;
    end

endmodule