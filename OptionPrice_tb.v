`timescale 1ns / 1ps

module OptionPrice_tb;

    parameter WIDTH = 32;

    // Clock and reset.
    reg clk;
    reg reset;

    // Inputs (Q16.16 format).
    reg signed [WIDTH-1:0] rate;    // Risk-free rate (e.g., 0.05)
    reg signed [WIDTH-1:0] timetm;  // Time to maturity (e.g., 1.0)
    reg signed [WIDTH-1:0] spot;    // Spot price (e.g., 100)
    reg signed [WIDTH-1:0] strike;  // Strike price (e.g., 100)
    reg signed [WIDTH-1:0] Nd1;     // CND of d1 (e.g., 0.8413)
    reg signed [WIDTH-1:0] Nd2;     // CND of d2 (e.g., 0.1587)
    reg otype;                      // 0 for call, 1 for put

    // Output from OptionPrice (Q16.16).
    wire signed [WIDTH-1:0] OptionPrice;

    // Additional signals for the OptionPrice module.
    reg norm_done;
    wire exp_start;
    wire exp_done;

    // Instantiate the OptionPrice module.
    OptionPrice #(WIDTH) uut (
        .clk(clk),
        .reset(reset),
        .rate(rate),
        .timetm(timetm),
        .spot(spot),
        .strike(strike),
        .Nd1(Nd1),
        .Nd2(Nd2),
        .otype(otype),
        .norm_done(norm_done),
        .OptionPrice(OptionPrice),
        .exp_start(exp_start),
        .exp_done(exp_done)
    );

    // Clock generation: 10 ns period.
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test procedure.
    initial begin
        // Initialize signals.
        reset   = 1;
        rate    = 0;
        timetm  = 0;
        spot    = 0;
        strike  = 0;
        Nd1     = 0;
        Nd2     = 0;
        otype   = 0;
        norm_done = 0;

        #20;
        reset = 0;
        #20; // Allow initialization.

        // Set test values:
        // rate = 0.05 * 65536 = ~3277.
        rate   = 32'sd3277;
        // timetm = 1.0 * 65536 = 65536.
        timetm = 32'sd65536;
        // spot = 100 * 65536 = 6,553,600.
        spot   = 32'sd6553600;
        // strike = 100 * 65536 = 6,553,600.
        strike = 32'sd6553600;
        // Nd1 = 0.8413 * 65536 = ~55166.
        Nd1    = 32'sd55166;
        // Nd2 = 0.1587 * 65536 = ~10470.
        Nd2    = 32'sd10470;
        // Option type = 0 for a call option.
        otype  = 1'b0;

        // Assert norm_done to start the OptionPrice module.
        #20;
        norm_done = 1;
        #20;
        norm_done = 0;

        // Wait long enough for the OptionPrice state machine to compute.
        #200000;

        // Display computed result.
        $display("Final OptionPrice = %d (float = %f)",
                  OptionPrice, $itor(OptionPrice)/65536.0);
        // Expected values (approx):
        // Discount factor ? exp(-0.05) = 0.951229.
        // Ke_rt = strike * 0.951229 ? 95.12.
        // spot_Nd1 = spot * 0.8413 ? 84.13.
        // Ke_rt_Nd2 = 95.12 * 0.1587 ? 15.12.
        // Call Price = 84.13 - 15.12 = 69.01.
        // Expected OptionPrice (Q16.16) ? 69.01 * 65536 = ~4,525,000.
        $display("Expected Call Option Price: ~4,525,000 (float ~69.01)");

        $finish;
    end

endmodule