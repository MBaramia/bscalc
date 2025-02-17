`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Divider Module
//   Computes: result = (a << 16) / b, where a, b, and result are in Q16.16 format.
//   This version uses a restoring division algorithm with a start signal.
//////////////////////////////////////////////////////////////////////////////////
module divider #(
    parameter WIDTH = 32,  // width of Q16.16 numbers
    parameter FBITS = 16   // fractional bits
)(
    input clk,
    input rst,
    input start,                     // Pulse high to start a new division
    output reg busy,               // High while division is in progress
    output reg done,               // Asserted for one clock cycle when calculation completes
    output reg valid,              // Result is valid
    output reg dbz,                // Divide by zero flag
    output reg ovf,                // Overflow flag
    input  signed [WIDTH-1:0] a,     // Dividend (Q16.16)
    input  signed [WIDTH-1:0] b,     // Divisor (Q16.16)
    output reg signed [WIDTH-1:0] val // Quotient result (Q16.16)
);

    // Unsigned widths are 1 bit narrower.
    localparam WIDTHU = WIDTH - 1;
    // Avoid negative vector width when FBITS=0.
    localparam FBITSW = (FBITS == 0) ? 1 : FBITS;
    // Smallest negative number in Q16.16 (unsigned representation).
    localparam SMALLEST = {1'b1, {WIDTHU{1'b0}}};

    // ITER = width of dividend (unsigned) + fractional bits.
    localparam ITER = WIDTHU + FBITS;
    // For ITER up to 64, 6 bits is enough.
    localparam ITER_BITS = 6;
    reg [ITER_BITS-1:0] i;

    // Declare input sign bits and absolute value registers.
    reg a_sig, b_sig, sig_diff;
    reg [WIDTHU-1:0] au, bu;
    // Intermediate quotient and its next value.
    reg [WIDTHU-1:0] quo, quo_next;
    // Accumulator (one bit wider than WIDTHU+1).
    reg [WIDTHU:0] acc, acc_next;

    // ----------------------------
    // Input sign extraction (combinational)
    // ----------------------------
    always @(*) begin
        a_sig = a[WIDTH-1];
        b_sig = b[WIDTH-1];
    end

    // ----------------------------
    // Division algorithm iteration (combinational)
    // ----------------------------
    always @(*) begin
        if (acc >= {1'b0, bu}) begin
            acc_next = acc - bu;
            {acc_next, quo_next} = {acc_next[WIDTHU-1:0], quo, 1'b1};
        end else begin
            {acc_next, quo_next} = {acc, quo} << 1;
        end
    end

    // ----------------------------
    // State machine for division calculation.
    // Use standard Verilog with a state encoding defined via parameters.
    // ----------------------------
    localparam IDLE  = 0,
               INIT  = 1,
               CALC  = 2,
               ROUND = 3,
               SIGN  = 4;
    reg [2:0] state;

    // ----------------------------
    // Main sequential logic (state machine)
    // ----------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            valid <= 0;
            dbz <= 0;
            ovf <= 0;
            val <= 0;
            i <= 0;
        end else begin
            case (state)
                IDLE: begin
                    busy <= 0;
                    done <= 0;
                    valid <= 0;
                    dbz <= 0;
                    ovf <= 0;
                    if (start) begin
                        if (b == 0) begin
                            state <= IDLE;
                            busy <= 0;
                            done <= 1;
                            dbz <= 1;
                            ovf <= 0;
                        end else if (a == SMALLEST || b == SMALLEST) begin
                            state <= IDLE;
                            busy <= 0;
                            done <= 1;
                            dbz <= 0;
                            ovf <= 1;
                        end else begin
                            state <= INIT;
                            // Compute absolute values of inputs.
                            if (a_sig)
                                au <= -a[WIDTHU-1:0];
                            else
                                au <= a[WIDTHU-1:0];
                            if (b_sig)
                                bu <= -b[WIDTHU-1:0];
                            else
                                bu <= b[WIDTHU-1:0];
                            sig_diff <= a_sig ^ b_sig;
                            busy <= 1;
                            dbz <= 0;
                            ovf <= 0;
                        end
                    end
                end
                INIT: begin
                    state <= CALC;
                    ovf <= 0;
                    i <= 0;
                    {acc, quo} <= { {WIDTHU{1'b0}}, au, 1'b0 };  // initialize accumulator and quotient
                end
                CALC: begin
                    // Check for potential overflow: if we are near the final iteration and high fractional bits are nonzero.
                    if (i == WIDTHU-1 && quo_next[WIDTHU-1:WIDTHU-FBITSW] != 0) begin
                        state <= IDLE;
                        busy <= 0;
                        done <= 1;
                        ovf <= 1;
                    end else begin
                        if (i == ITER-1)
                            state <= ROUND;  // Finished iterations, go to rounding
                        i <= i + 1;
                        acc <= acc_next;
                        quo <= quo_next;
                    end
                end
                ROUND: begin  // Gaussian rounding
                    state <= SIGN;
                    if (quo_next[0] == 1'b1) begin
                        // Round up if quotient is odd or remainder nonzero
                        if (quo[0] == 1'b1 || acc_next[WIDTHU:1] != 0)
                            quo <= quo + 1;
                    end
                end
                SIGN: begin
                    state <= IDLE;
                    if (quo != 0)
                        val <= (sig_diff) ? {1'b1, -quo} : {1'b0, quo};
                    busy <= 0;
                    done <= 1;
                    valid <= 1;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
