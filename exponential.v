`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Exponential Module
// Computes y = e^(-x) using an 8-term Taylor series approximation:
//   e^(-x) ? 1 - x + x^2/2 - x^3/6 + x^4/24 - x^5/120 + x^6/720 - x^7/5040
// All values are in Q16.16 fixed-point format.
// Uses a start signal to latch the input (only on a rising edge)
// and a done flag to indicate that the computed result (y) is valid.
//////////////////////////////////////////////////////////////////////////////////

module exponential #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,                            // Pulse high to begin computation
    input signed [WIDTH-1:0] x,             // Input x (Q16.16)
    output reg signed [WIDTH-1:0] y,        // Output e^(-x) (Q16.16)
    output reg done                       // Asserted for one cycle when result is valid
);

    // Constants in Q16.16 (signed)
    localparam signed [WIDTH-1:0] one                 = 32'h00010000; // 1.0
    localparam signed [WIDTH-1:0] two_inv             = 32'h00008000; // 1/2
    localparam signed [WIDTH-1:0] six_inv             = 32'h00002AAA; // 1/6 (~0.166667)
    localparam signed [WIDTH-1:0] twenty_four_inv     = 32'h00000AAA; // 1/24 (~0.041667)
    localparam signed [WIDTH-1:0] one_twenty_inv      = 32'h00000222; // 1/120 (~0.008333)
    localparam signed [WIDTH-1:0] one_seventy_inv     = 32'h0000005B; // 1/720 (~0.001389)
    localparam signed [WIDTH-1:0] one_seventy_five_inv= 32'h0000000D; // 1/5040 (~0.000198)

    // Pipeline registers for intermediate computation (all Q16.16, signed)
    reg signed [WIDTH-1:0] x_reg;       // Latched input
    reg signed [WIDTH-1:0] x_squared;   // x^2
    reg signed [WIDTH-1:0] x_cubed;     // x^3
    reg signed [WIDTH-1:0] x_fourth;    // x^4
    reg signed [WIDTH-1:0] x_fifth;     // x^5
    reg signed [WIDTH-1:0] x_sixth;     // x^6
    reg signed [WIDTH-1:0] x_seventh;   // x^7

    // 64-bit temporary for multiplications
    reg signed [63:0] mult;

    // Taylor series terms
    reg signed [WIDTH-1:0] term1; // 1
    reg signed [WIDTH-1:0] term2; // - x
    reg signed [WIDTH-1:0] term3; // + x^2/2
    reg signed [WIDTH-1:0] term4; // - x^3/6
    reg signed [WIDTH-1:0] term5; // + x^4/24
    reg signed [WIDTH-1:0] term6; // - x^5/120
    reg signed [WIDTH-1:0] term7; // + x^6/720
    reg signed [WIDTH-1:0] term8; // - x^7/5040
    reg signed [WIDTH-1:0] result;

    // State machine for a 10-cycle pipeline:
    //  0: IDLE - wait for start; clear done.
    //  1: Latch input x into x_reg.
    //  2: Compute x^2.
    //  3: Compute x^3.
    //  4: Compute x^4.
    //  5: Compute x^5.
    //  6: Compute x^6.
    //  7: Compute x^7.
    //  8: Compute individual Taylor series terms.
    //  9: Sum the terms (result) and then assert done (and update y) in the next cycle.
    reg [3:0] state;
    
    // Register to detect rising edge on start.
    reg prev_start;

    // Update prev_start every clock cycle.
    always @(posedge clk) begin
        if (reset)
            prev_start <= 1'b0;
        else
            prev_start <= start;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= 4'd0;
            x_reg         <= 0;
            x_squared     <= 0;
            x_cubed       <= 0;
            x_fourth      <= 0;
            x_fifth       <= 0;
            x_sixth       <= 0;
            x_seventh     <= 0;
            term1         <= 0;
            term2         <= 0;
            term3         <= 0;
            term4         <= 0;
            term5         <= 0;
            term6         <= 0;
            term7         <= 0;
            term8         <= 0;
            result        <= 0;
            y             <= 0;
            done          <= 0;
        end else begin
            case (state)
                4'd0: begin
                    done <= 0;  // Clear done flag
                    // Latch input only on a rising edge of start.
                    if (start && !prev_start) begin
                        x_reg <= x;
                        state <= 4'd1;
                    end
                end
                4'd1: begin
                    // Compute x^2 = x_reg * x_reg (64-bit multiply)
                    mult = x_reg * x_reg;
                    x_squared <= mult[47:16];
                    state <= 4'd2;
                end
                4'd2: begin
                    // Compute x^3 = x_squared * x_reg
                    mult = x_squared * x_reg;
                    x_cubed <= mult[47:16];
                    state <= 4'd3;
                end
                4'd3: begin
                    // Compute x^4 = x_cubed * x_reg
                    mult = x_cubed * x_reg;
                    x_fourth <= mult[47:16];
                    state <= 4'd4;
                end
                4'd4: begin
                    // Compute x^5 = x_fourth * x_reg
                    mult = x_fourth * x_reg;
                    x_fifth <= mult[47:16];
                    state <= 4'd5;
                end
                4'd5: begin
                    // Compute x^6 = x_fifth * x_reg
                    mult = x_fifth * x_reg;
                    x_sixth <= mult[47:16];
                    state <= 4'd6;
                end
                4'd6: begin
                    // Compute x^7 = x_sixth * x_reg
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
                    mult = x_seventh * one_seventy_five_inv; term8 <= -mult[47:16];
                    state <= 4'd8;
                end
                4'd8: begin
                    // Sum all the terms to get the Taylor series approximation.
                    result <= term1 + term2 + term3 + term4 + term5 + term6 + term7 + term8;
                    state <= 4'd9;
                end
                4'd9: begin
                    // Update y with the computed result.
                    y <= result;
                    done <= 1;  // Assert done for one cycle.
                    state <= 4'd0; // Return to idle.
                end
                default: state <= 4'd0;
            endcase
        end
    end

endmodule
