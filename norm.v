`timescale 1ns / 1ps
module norm #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,                      // One-cycle pulse for both channels.
    input signed [WIDTH-1:0] d1,       // Q16.16 format.
    input signed [WIDTH-1:0] d2,
    output reg signed [WIDTH-1:0] Nd1, // Q16.16 output for d1.
    output reg signed [WIDTH-1:0] Nd2, // Q16.16 output for d2.
    output reg done                    // Asserted when both channels are done.
);
    // Internal signals for norm_single outputs and control
    wire done1, done2;
    reg start_norm2;
    reg done1_detected;
    
    // Intermediate calculations (standard normal CDF)
    wire signed [WIDTH-1:0] cdf1;
    wire signed [WIDTH-1:0] cdf2;
    
    // For storing absolute values of inputs
    reg signed [WIDTH-1:0] abs_d1;
    reg signed [WIDTH-1:0] abs_d2;
    
    // Remember input signs
    reg d1_is_negative;
    reg d2_is_negative;
    
    // Calculate the absolute values of inputs
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            abs_d1 <= 0;
            abs_d2 <= 0;
            d1_is_negative <= 0;
            d2_is_negative <= 0;
        end else if (start) begin
            // Capture sign bits
            d1_is_negative <= d1[WIDTH-1];
            d2_is_negative <= d2[WIDTH-1];
            
            // Take absolute values properly (2's complement)
            abs_d1 <= d1[WIDTH-1] ? (~d1 + 1'b1) : d1;
            abs_d2 <= d2[WIDTH-1] ? (~d2 + 1'b1) : d2;
        end
    end
    
    // First normalization module
    norm_single #(WIDTH) norm1 (
        .clk(clk),
        .reset(reset),
        .start(start),
        .d(abs_d1),  // Use absolute value
        .N(cdf1),
        .done(done1)
    );
    
    // Second normalization module - starts after first one completes
    norm_single #(WIDTH) norm2 (
        .clk(clk),
        .reset(reset),
        .start(start_norm2),
        .d(abs_d2),  // Use absolute value
        .N(cdf2),
        .done(done2)
    );
    
    // Logic for sequential operation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            start_norm2 <= 1'b0;
            done1_detected <= 1'b0;
            done <= 1'b0;
            Nd1 <= 0;
            Nd2 <= 0;
        end else begin
            // Start norm2 after norm1 completes
            if (done1 && !done1_detected) begin
                done1_detected <= 1'b1;
                start_norm2 <= 1'b1;
                
                // Calculate Nd1 based on sign
                if (d1_is_negative) begin
                    // For negative input: N(-x) = 1 - N(x)
                    Nd1 <= 32'h00010000 - cdf1;  // 1.0 (fixed-point) - cdf
                end else begin
                    Nd1 <= cdf1;
                end
            end else if (start_norm2) begin
                start_norm2 <= 1'b0;
            end
            
            // Calculate Nd2 and set done when norm2 completes
            if (done2) begin
                if (d2_is_negative) begin
                    // For negative input: N(-x) = 1 - N(x)
                    Nd2 <= 32'h00010000 - cdf2;  // 1.0 (fixed-point) - cdf
                end else begin
                    Nd2 <= cdf2;
                end
                done <= 1'b1;
            end
            
            // Reset control signals for next calculation
            if (done && !start) begin
                done <= 1'b0;
                done1_detected <= 1'b0;
            end
        end
    end
    
endmodule