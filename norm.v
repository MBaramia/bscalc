`timescale 1ns / 1ps
module norm #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,                      // One-cycle pulse for both channels.
    input signed [WIDTH-1:0] d1,       // Q16.16 format.
    input signed [WIDTH-1:0] d2,
    output wire signed [WIDTH-1:0] Nd1, // Q16.16 output for d1.
    output wire signed [WIDTH-1:0] Nd2, // Q16.16 output for d2.
    output wire done                  // Asserted when both channels are done.
);
    wire done1, done2;
    
    norm_single #(WIDTH) norm1 (
        .clk(clk),
        .reset(reset),
        .start(start),
        .d(d2),
        .N(Nd1),
        .done(done1)
    );
    
    norm_single #(WIDTH) norm2 (
        .clk(clk),
        .reset(reset),
        .start(start),
        .d(d1),
        .N(Nd2),
        .done(done2)
    );
    
    assign done = done1 & done2;
endmodule
