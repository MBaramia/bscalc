`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Exponential Module
// Computes y = e^(-x) using an 8-term Taylor series approximation:
//   e^(-x) ? 1 - x + x²/2 - x³/6 + x?/24 - x?/120 + x?/720 - x?/5040
// All values are in Q16.16 fixed-point format.
// A rising edge on "start" latches the input, then the computation is performed.
// When finished, "done" is asserted for two cycles and y holds the result.
//////////////////////////////////////////////////////////////////////////////////
module exponential #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,                            // Pulse high to begin computation.
    input signed [WIDTH-1:0] x,             // Input x (Q16.16)
    output reg signed [WIDTH-1:0] y,        // Output e^(-x) (Q16.16)
    output reg done                       // Asserted for two cycles when result is valid.
);

    // Constants in Q16.16.
    localparam signed [WIDTH-1:0] one                  = 32'h00010000; // 1.0
    localparam signed [WIDTH-1:0] two_inv              = 32'h00008000; // 1/2
    localparam signed [WIDTH-1:0] six_inv              = 32'h00002AAA; // ~1/6 (?0.166667)
    localparam signed [WIDTH-1:0] twenty_four_inv      = 32'h00000AAA; // ~1/24 (?0.041667)
    localparam signed [WIDTH-1:0] one_twenty_inv       = 32'h00000222; // ~1/120 (?0.008333)
    localparam signed [WIDTH-1:0] one_seventy_inv      = 32'h0000005B; // ~1/720 (?0.001389)
    localparam signed [WIDTH-1:0] one_fifty_inv        = 32'h0000000D; // ~1/5040 (?0.000198)

    // Pipeline registers for intermediate results.
    reg signed [WIDTH-1:0] x_reg;       // Latched input.
    reg signed [WIDTH-1:0] x_squared;   // x^2.
    reg signed [WIDTH-1:0] x_cubed;     // x^3.
    reg signed [WIDTH-1:0] x_fourth;    // x^4.
    reg signed [WIDTH-1:0] x_fifth;     // x^5.
    reg signed [WIDTH-1:0] x_sixth;     // x^6.
    reg signed [WIDTH-1:0] x_seventh;   // x^7.

    // 64-bit temporary for multiplications.
    reg signed [63:0] mult;

    // Taylor series terms (with alternating signs).
    reg signed [WIDTH-1:0] term1; // 1
    reg signed [WIDTH-1:0] term2; // - x
    reg signed [WIDTH-1:0] term3; // + x^2/2
    reg signed [WIDTH-1:0] term4; // - x^3/6
    reg signed [WIDTH-1:0] term5; // + x^4/24
    reg signed [WIDTH-1:0] term6; // - x^5/120
    reg signed [WIDTH-1:0] term7; // + x^6/720
    reg signed [WIDTH-1:0] term8; // - x^7/5040
    reg signed [WIDTH-1:0] result;

    // State machine for a 11-cycle pipeline:
    //  0: IDLE - wait for a rising edge on start; clear done.
    //  1: Latch input x into x_reg.
    //  2: Compute x^2.
    //  3: Compute x^3.
    //  4: Compute x^4.
    //  5: Compute x^5.
    //  6: Compute x^6.
    //  7: Compute x^7.
    //  8: Compute the individual Taylor series terms.
    //  9: Sum the terms to produce the result.
    // 10: Update y, assert done.
    // 11: Hold done for an extra cycle then return to idle.
    reg [3:0] state;
    
    // Register to detect a rising edge on start.
    reg prev_start;
    always @(posedge clk) begin
        if (reset)
            prev_start <= 1'b0;
        else
            prev_start <= start;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= 4'd0;
            x_reg     <= 0;
            x_squared <= 0;
            x_cubed   <= 0;
            x_fourth  <= 0;
            x_fifth   <= 0;
            x_sixth   <= 0;
            x_seventh <= 0;
            term1     <= 0;
            term2     <= 0;
            term3     <= 0;
            term4     <= 0;
            term5     <= 0;
            term6     <= 0;
            term7     <= 0;
            term8     <= 0;
            result    <= 0;
            y         <= 0;
            done      <= 0;
        end else begin
            case (state)
                4'd0: begin
                    done <= 0;
                    if (start && !prev_start) begin
                        x_reg <= x;  // Latch input on rising edge.
                        state <= 4'd1;
                    end
                end
                4'd1: begin
                    mult = x_reg * x_reg;
                    x_squared <= mult[47:16];
                    state <= 4'd2;
                end
                4'd2: begin
                    mult = x_squared * x_reg;
                    x_cubed <= mult[47:16];
                    state <= 4'd3;
                end
                4'd3: begin
                    mult = x_cubed * x_reg;
                    x_fourth <= mult[47:16];
                    state <= 4'd4;
                end
                4'd4: begin
                    mult = x_fourth * x_reg;
                    x_fifth <= mult[47:16];
                    state <= 4'd5;
                end
                4'd5: begin
                    mult = x_fifth * x_reg;
                    x_sixth <= mult[47:16];
                    state <= 4'd6;
                end
                4'd6: begin
                    mult = x_sixth * x_reg;
                    x_seventh <= mult[47:16];
                    state <= 4'd7;
                end
                4'd7: begin
                    // Compute the individual Taylor series terms for e^(-x):
                    // term1 = 1
                    // term2 = - x_reg
                    // term3 = x_squared/2
                    // term4 = - x_cubed/6
                    // term5 = x_fourth/24
                    // term6 = - x_fifth/120
                    // term7 = x_sixth/720
                    // term8 = - x_seventh/5040
                    term1 <= one;
                    term2 <= -x_reg;
                    mult = x_squared * two_inv; term3 <= mult[47:16];
                    mult = x_cubed * six_inv;   term4 <= -mult[47:16];
                    mult = x_fourth * twenty_four_inv; term5 <= mult[47:16];
                    mult = x_fifth * one_twenty_inv; term6 <= -mult[47:16];
                    mult = x_sixth * one_seventy_inv; term7 <= mult[47:16];
                    mult = x_seventh * one_fifty_inv; term8 <= -mult[47:16];
                    state <= 4'd8;
                end
                4'd8: begin
                    result <= term1 + term2 + term3 + term4 + term5 + term6 + term7 + term8;
                    state <= 4'd9;
                end
                4'd9: begin
                    y <= result;
                    done <= 1;
                    state <= 4'd10;
                end
                4'd10: begin
                    // Hold done for one extra cycle.
                    done <= 1;
                    state <= 4'd0;
                end
                default: state <= 4'd0;
            endcase
        end
    end

endmodule