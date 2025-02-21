`timescale 1ns / 1ps

module logarithm #(
    parameter WIDTH = 32
)(
    input                         clk,
    input                         reset,
    input                         start,  // one-cycle start pulse
    input  signed [WIDTH-1:0]     in,     // Input (Q16.16)
    output reg signed [WIDTH-1:0] out,    // Output ln(x) (Q16.16)
    output reg                    valid   // asserted for two cycles now
);

    // Precomputed coefficients for a cubic polynomial approximation of ln(m) on [1,2)
    localparam signed [WIDTH-1:0] c0  = 32'hFFFE4B8D; // -1.594772
    localparam signed [WIDTH-1:0] c1  = 32'h00021C30; //  2.09987
    localparam signed [WIDTH-1:0] c2  = 32'hFFFE46EB; // -0.72036
    localparam signed [WIDTH-1:0] c3  = 32'h00001B95; //  0.10775
    localparam signed [WIDTH-1:0] ln2 = 32'h0000B172; // ~0.6931

    // Offset to fix the polynomial result, equal to +1.594772 in Q16.16.
    localparam signed [WIDTH-1:0] offset = 32'h00019834; // +1.594772

    // Normalization: represent in as mantissa * 2^(exponent) with mantissa in [1.0,2.0)
    reg signed [WIDTH-1:0] mantissa;  // normalized mantissa (Q16.16)
    reg signed [31:0]      exponent;  // integer exponent
    reg [1:0]              state;
    integer                msb_index;

    // State encoding
    localparam IDLE      = 2'b00,
               NORMALIZE = 2'b01,
               COMPUTE   = 2'b10,
               HOLD      = 2'b11;

    // --- Combinational Polynomial Evaluation ---
    // Computes:
    //   poly = c0 + (mantissa*c1 >>> 16)
    //          + (((mantissa*mantissa) >>> 16 * c2) >>> 16)
    //          + ((((mantissa*mantissa) >>> 16 * mantissa) >>> 16 * c3) >>> 16)
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

    // --- Function to find the most-significant '1' ---
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
    // IDLE: Wait for a start pulse.
    // NORMALIZE: Normalize the input.
    // COMPUTE: Compute ln(x) and assert valid.
    // HOLD: Hold valid high for one extra cycle.
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
                        mantissa  <= in >> (msb_index - 16);
                        state     <= NORMALIZE;
                    end
                end
                NORMALIZE: begin
                    // Compute: ln(x) = poly + (exponent*ln2) + offset.
                    out <= poly + (exponent * ln2) + offset;
                    state <= COMPUTE;
                end
                COMPUTE: begin
                    valid <= 1;
                    state <= HOLD;
                end
                HOLD: begin
                    // Hold valid for an extra cycle.
                    valid <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
