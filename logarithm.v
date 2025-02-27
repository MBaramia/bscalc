`timescale 1ns / 1ps

module logarithm #(
    parameter WIDTH = 32
)(
    input                         clk,
    input                         reset,
    input                         start,  // one-cycle start pulse
    input  signed [WIDTH-1:0]     in,     // Input in Q16.16
    output reg signed [WIDTH-1:0] out,    // Output ln(x) in Q16.16
    output reg                    valid   // asserted for two cycles
);

    // Constant for ln2 in Q16.16 (~0.6931)
    localparam signed [WIDTH-1:0] ln2 = 32'h0000B172;

    // Coefficients for the polynomial approximation of ln(1+x) ? x - x^2/2 + x^3/3
    // (Coefficients are given in Q16.16.)
    localparam signed [WIDTH-1:0] coeff1 = 32'h00010000;   //  1.0
    localparam signed [WIDTH-1:0] coeff2 = 32'hFFFF8000;   // -0.5
    localparam signed [WIDTH-1:0] coeff3 = 32'h00005555;   // ~1/3

    // Normalization: write in = m * 2^e with m in [1.0,2.0)
    reg signed [WIDTH-1:0] mantissa;  // normalized mantissa (Q16.16)
    reg signed [31:0]      exponent;  // integer exponent
    reg [1:0]              state;
    integer                msb_index;
    integer                shift_amount;

    // State encoding
    localparam IDLE      = 2'b00,
               NORMALIZE = 2'b01,
               COMPUTE   = 2'b10,
               HOLD      = 2'b11;

    // --- Polynomial Evaluation ---
    // Let x = m - 1.0 (with m = mantissa), then approximate ln(1+x) as:
    //    x - (x^2)/2 + (x^3)/3
    wire signed [WIDTH-1:0] x;  // deviation from 1.0
    assign x = mantissa - 32'h00010000;  // subtract 1.0

    wire signed [WIDTH-1:0] x2;
    assign x2 = (x * x) >>> 16;  // x^2 in Q16.16

    wire signed [WIDTH-1:0] x3;
    assign x3 = ((x2 * x) >>> 16);  // x^3 in Q16.16

    wire signed [WIDTH-1:0] term1;
    assign term1 = x;  // coefficient 1

    wire signed [WIDTH-1:0] term2;
    assign term2 = (x2 * coeff2) >>> 16;  // -0.5 * x^2

    wire signed [WIDTH-1:0] term3;
    assign term3 = (x3 * coeff3) >>> 16;  // (1/3) * x^3

    wire signed [WIDTH-1:0] poly;
    assign poly = term1 + term2 + term3;

    // --- Function: find most-significant '1' ---
    function integer find_msb;
        input [WIDTH-1:0] value;
        integer j;
        begin
            find_msb = -1;
            for (j = WIDTH-1; j >= 0; j = j - 1)
                if (value[j] && (find_msb == -1))
                    find_msb = j;
            if (find_msb == -1)
                find_msb = 0;
        end
    endfunction

    // --- State Machine ---
    // IDLE: Wait for start.
    // NORMALIZE: Normalize the input.
    // COMPUTE: Compute ln(x) = ln(m) + e*ln2, with ln(m) ? poly.
    // HOLD: Hold valid for one extra cycle.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= IDLE;
            valid    <= 0;
            out      <= 0;
            mantissa <= 0;
            exponent <= 0;
        end else begin
            case (state)
                IDLE: begin
                    valid <= 0;
                    if (start) begin
                        msb_index = find_msb(in);
                        exponent  <= msb_index - 16;
                        shift_amount = msb_index - 16;
                        // Use rounding when normalizing.
                        if(shift_amount > 0)
                            mantissa <= (in + (1 << (shift_amount - 1))) >> shift_amount;
                        else
                            mantissa <= in;
                        state <= NORMALIZE;
                    end
                end
                NORMALIZE: begin
                    // Proceed to polynomial evaluation.
                    state <= COMPUTE;
                end
                COMPUTE: begin
                    // ln(x) = ln(m) + exponent*ln2 where ln(m) ? poly.
                    out <= poly + (exponent * ln2);
                    valid <= 1;
                    state <= HOLD;
                end
                HOLD: begin
                    valid <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
