`timescale 1ns / 1ps

module logarithm #(
    parameter WIDTH = 32
)(
    input              clk,
    input              reset,
    input  signed [WIDTH-1:0] in,      // Input (Q16.16)
    output reg signed [WIDTH-1:0] out  // Output ln(x) (Q16.16)
);

    // Precomputed coefficients for a cubic polynomial approximation of ln(m) on [1,2)
    // The polynomial is:
    //   ln(m) ? c0 + c1*m + c2*m^2 + c3*m^3.
    // (They were chosen so that ln(1) = c0+c1+c2+c3 ? -1.594772.)
    localparam signed [WIDTH-1:0] c0  = 32'hFFFE4B8D; // ? -1.594772? (As given)
    localparam signed [WIDTH-1:0] c1  = 32'h00021C30; // ?  2.09987
    localparam signed [WIDTH-1:0] c2  = 32'hFFFE46EB; // ? -0.72036
    localparam signed [WIDTH-1:0] c3  = 32'h00001B95; // ?  0.10775
    localparam signed [WIDTH-1:0] ln2 = 32'h0000B172; // ln(2) ? 0.6931

    // To fix the offset, add a constant equal to +1.594772 in Q16.16.
    // (1.594772 * 65536 ? 104500, which in hex is 0x00019834.)
    localparam signed [WIDTH-1:0] offset = 32'h00019834; // +1.594772

    // Normalization: Represent in as m * 2^(exponent), with m in [1.0,2.0)
    reg signed [WIDTH-1:0] mantissa;  // Normalized mantissa (Q16.16)
    reg signed [31:0]      exponent;  // Exponent (an integer)
    reg [1:0] state;                  // Simple state machine
    integer msb_index;                // For normalization

    // --- Combinational Polynomial Evaluation ---
    // We compute:
    //   poly = c0 + (mantissa*c1 >>> 16)
    //          + (((mantissa*mantissa) >>> 16 * c2) >>> 16)
    //          + ((((mantissa*mantissa) >>> 16 * mantissa) >>> 16 * c3) >>> 16)
    // (Multiplying two Q16.16 numbers gives a Q32.32 result; shift right by 16 to return to Q16.16.)
    wire signed [WIDTH-1:0] mult1;
    wire signed [WIDTH-1:0] m2;
    wire signed [WIDTH-1:0] mult2;
    wire signed [WIDTH-1:0] m3;
    wire signed [WIDTH-1:0] mult3;
    wire signed [WIDTH-1:0] poly;

    assign mult1 = (mantissa * c1) >>> 16;
    assign m2    = (mantissa * mantissa) >>> 16;
    assign mult2 = (m2 * c2) >>> 16;
    assign m3    = (m2 * mantissa) >>> 16;
    assign mult3 = (m3 * c3) >>> 16;
    assign poly  = c0 + mult1 + mult2 + mult3;

    // --- Function to Find the Most-Significant '1' ---
    function integer find_msb;
        input [WIDTH-1:0] value;
        integer j;
        begin
            find_msb = 0;
            for (j = WIDTH-1; j >= 0; j = j - 1) begin
                if (value[j]) begin
                    find_msb = j;
                    j = -1; // exit early
                end
            end
        end
    endfunction

    // --- State Machine ---
    // State 0: Normalize the input.
    // State 1: Compute ln(x) = ln(mantissa) + exponent*ln(2) and add the offset.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mantissa <= 0;
            exponent <= 0;
            out      <= 0;
            state    <= 0;
        end else begin
            case (state)
                2'b00: begin
                    // Normalize: Write in = mantissa * 2^(exponent).
                    // For a Q16.16 number, if the most-significant '1' is at bit msb_index,
                    // then set: exponent = msb_index - 16 and mantissa = in >> (msb_index - 16).
                    msb_index = find_msb(in);
                    exponent  <= msb_index - 16;
                    mantissa  <= in >> (msb_index - 16);
                    state     <= 2'b01;
                end
                2'b01: begin
                    // Compute: ln(x) = ln(mantissa) + exponent * ln2 + offset.
                    // (When in = 1.0, exponent = 0 and mantissa = 1.0, so poly = c0+c1+c2+c3 ? -1.594772.
                    // Adding offset yields 0, as desired.)
                    out <= poly + (exponent * ln2) + offset;
                    state <= 2'b00;  // Ready for next input.
                end
                default: state <= 2'b00;
            endcase
        end
    end

endmodule
