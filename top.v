`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top Module
// Instantiates d1d2, two CNDF (norm) modules, and the OptionPrice module.
// Debug statements in an initial block continuously monitor key signals.
//////////////////////////////////////////////////////////////////////////////////

module top #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input signed [WIDTH-1:0] spot,      // Spot price (Q16.16)
    input signed [WIDTH-1:0] strike,    // Strike price (Q16.16)
    input signed [WIDTH-1:0] timetm,    // Time to maturity (Q16.16)
    input signed [WIDTH-1:0] sigma,     // Volatility (Q16.16)
    input signed [WIDTH-1:0] rate,      // Risk-free interest rate (Q16.16)
    input otype,                 // Option type control signal (0 for call, 1 for put)
    output signed [WIDTH-1:0] OptionPrice // Output option price (Q16.16)
);

    // Internal signals must be nets.
    wire signed [WIDTH-1:0] d1;
    wire signed [WIDTH-1:0] d2;
    wire signed [WIDTH-1:0] Nd1;
    wire signed [WIDTH-1:0] Nd2;

    // Dummy wires for unused outputs.
    wire [WIDTH-1:0] dummy1, dummy2;
    
    // Instantiate d1d2 Module.
    d1d2 d1d2_module (
        .clk(clk),
        .reset(reset),
        .S0(spot),
        .K(strike),
        .T(timetm),
        .sigma(sigma),
        .r(rate),
        .d1(d1),
        .d2(d2)
    );

    norm cndf_d1_module (
    .clk(clk),
    .reset(reset),
    .start(1'b1),  // or generate a pulse if you need pipelined operation
    .d1(d1),
    .d2(32'sh0),
    .Nd1(Nd1),
    .Nd2(dummy1),
    .done() // if you use the done flag
);

norm cndf_d2_module (
    .clk(clk),
    .reset(reset),
    .start(1'b1),  // or generate a pulse if you need pipelined operation
    .d1(32'sh0),
    .d2(d2),
    .Nd1(dummy),
    .Nd2(Nd2),
    .done() // if you use the done flag
);



    // Instantiate OptionPrice Module.
    OptionPrice option_price_module (
        .clk(clk),
        .reset(reset),
        .rate(rate),
        .timetm(timetm),
        .spot(spot),
        .strike(strike),
        .Nd1(Nd1),
        .Nd2(Nd2),
        .otype(otype),
        .OptionPrice(OptionPrice)
    );

    initial begin
        $monitor("Time=%t | spot=%d (%f), strike=%d (%f), timetm=%d (%f), sigma=%d (%f), rate=%d (%f), otype=%b, OptionPrice=%d (%f)",
            $time,
            spot, $itor($signed(spot))/65536.0,
            strike, $itor($signed(strike))/65536.0,
            timetm, $itor($signed(timetm))/65536.0,
            sigma, $itor($signed(sigma))/65536.0,
            rate, $itor($signed(rate))/65536.0,
            otype,
            OptionPrice, $itor($signed(OptionPrice))/65536.0);
    end

endmodule
