`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top Module
// Instantiates d1d2, a single norm module (which takes both d1 and d2 and
// produces Nd1 and Nd2), and the OptionPrice module. Note that the norm module
// internally swaps its outputs (Nd1 comes from d2 and Nd2 from d1). Therefore,
// when connecting to OptionPrice, we swap them so that OptionPrice receives:
//   Nd1 (OptionPrice input) = norm's Nd2 (i.e. N(d1))
//   Nd2 (OptionPrice input) = norm's Nd1 (i.e. N(d2))
//////////////////////////////////////////////////////////////////////////////////

module top #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,
    input signed [WIDTH-1:0] spot,      // Spot price (Q16.16)
    input signed [WIDTH-1:0] strike,    // Strike price (Q16.16)
    input signed [WIDTH-1:0] timetm,    // Time to maturity (Q16.16)
    input signed [WIDTH-1:0] sigma,     // Volatility (Q16.16)
    input signed [WIDTH-1:0] rate,      // Risk-free interest rate (Q16.16)
    input otype,                      // Option type control (0 for call, 1 for put)
    output signed [WIDTH-1:0] OptionPrice // Option price (Q16.16)
);

    // Internal nets.
    wire signed [WIDTH-1:0] d1;
    wire signed [WIDTH-1:0] d2;
    wire signed [WIDTH-1:0] norm_Nd1;
    wire signed [WIDTH-1:0] norm_Nd2;
    wire norm_start;
    // Instantiate d1d2 module to compute d1 and d2.
    d1d2 d1d2_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .S0(spot),
        .K(strike),
        .T(timetm),
        .sigma(sigma),
        .r(rate),
        .d1(d1),
        .d2(d2),
        .norm_start(norm_start)
    );
    
    // Instantiate the norm module.
    // (This module takes both d1 and d2 and outputs Nd1 and Nd2.
    //  However, note that internally norm instantiates:
    //    norm_single(norm1) with d = d2 and outputs Nd1,
    //    norm_single(norm2) with d = d1 and outputs Nd2.)
    norm norm_inst (
        .clk(clk),
        .reset(reset),
        .start(norm_start), // Always start (for simplicity)
        .d1(d1),
        .d2(d2),
        .Nd1(norm_Nd1),
        .Nd2(norm_Nd2),
        .done(done)      // Unused
    );
    
    // Instantiate the OptionPrice module.
    // Since norm_inst outputs are swapped relative to the original d inputs,
    // we swap them when connecting to OptionPrice:
    //   OptionPrice expects Nd1 = N(d1) and Nd2 = N(d2).
    // Therefore, we connect:
    //   OptionPrice.Nd1 = norm_inst.Nd2 (which is computed from d1)
    //   OptionPrice.Nd2 = norm_inst.Nd1 (which is computed from d2)
    OptionPrice option_price_inst (
        .clk(clk),
        .reset(reset),
        .rate(rate),
        .timetm(timetm),
        .spot(spot),
        .strike(strike),
        .Nd1(norm_Nd2), // Swapped connection.
        .Nd2(norm_Nd1), // Swapped connection.
        .otype(otype),
        .norm_done(done),
        .OptionPrice(OptionPrice)
    );
    
    // Minimal debug: display final OptionPrice and expected value.
    // For example, for a call option with:
    //   spot = 100, strike = 100, timetm = 1.0, rate = 0.05,
    //   Nd1 ? 0.8413 and Nd2 ? 0.1587,
    // the expected call price is:
    //   spot * Nd1 ? 100 * 0.8413 = 84.13,
    //   effective strike = 100 * exp(-0.05) ? 95.12,
    //   strike * exp(-r*T)*Nd2 ? 95.12 * 0.1587 = 15.12,
    //   Call Price ? 84.13 - 15.12 = 69.01,
    // and in Q16.16, ~69.01*65536 ? 4,525,000.
    initial begin
        #3000; // Wait for simulation to finish.
        $display("Final OptionPrice = %d (float = %f)", OptionPrice, $itor(OptionPrice)/65536.0);
        $display("Expected OptionPrice ? 4525000 (float ? 69.01)");
        $finish;
    end

endmodule