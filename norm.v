`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Norm Module
// Computes Nd1 = N(d1) and Nd2 = N(d2) in Q16.16 format using an approximation 
// of the standard normal cumulative distribution function.
// For x ? 0 the approximation is:
//   N(x) = 1 - n(x)*P(k)
// where n(x) = (1/sqrt(2?)) * exp(-x²/2),
//       k = 1/(1 + ?*x),
//       P(k) = a1*k + a2*k² + a3*k³ + a4*k? + a5*k?.
// For x < 0, symmetry is used (i.e. N(x) = 1 - N(-x)).
// All values are in Q16.16 format.
//////////////////////////////////////////////////////////////////////////////////
module norm #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,                      // When high, latch new input d1/d2
    input signed [WIDTH-1:0] d1,       // Input d1 (Q16.16)
    input signed [WIDTH-1:0] d2,       // Input d2 (Q16.16)
    output reg signed [WIDTH-1:0] Nd1, // Output N(d1) (Q16.16)
    output reg signed [WIDTH-1:0] Nd2, // Output N(d2) (Q16.16)
    output reg done                  // Asserted for one clock cycle when computation completes
);

    // Constants (all Q16.16)
    localparam signed [WIDTH-1:0] gamma         = 32'sh00003B5E; // ~0.2316419
    localparam signed [WIDTH-1:0] inv_sqrt_2_pi = 32'sh00006618; // ~0.39894228
    localparam signed [WIDTH-1:0] a1            = 32'sh000051A9; // ~0.319381530
    localparam signed [WIDTH-1:0] a2            = 32'shFFFFA4A0; // ~-0.356563782
    localparam signed [WIDTH-1:0] a3            = 32'sh0001C863; // ~1.781477937
    localparam signed [WIDTH-1:0] a4            = 32'shFFFE2DF6; // ~-1.821255978
    localparam signed [WIDTH-1:0] a5            = 32'sh000154DE; // ~1.330274429
    localparam signed [WIDTH-1:0] one           = 32'sh00010000; // 1.0 in Q16.16 (65536)
    localparam signed [WIDTH-1:0] half          = 32'sh00008000; // 0.5 in Q16.16

    // Internal signals (all signed)
    reg signed [WIDTH-1:0] orig_d; // Saved input (for debug)
    reg signed [WIDTH-1:0] x;      // Absolute value of input
    reg signed [WIDTH-1:0] x_squared;
    reg signed [WIDTH-1:0] neg_x_squared_over_2;
    // The exponential module computes exp(-x) given x in Q16.16.
    wire signed [WIDTH-1:0] exp_term;
    reg signed [WIDTH-1:0] n_prime;
    reg signed [WIDTH-1:0] k;
    reg signed [WIDTH-1:0] k_squared;
    reg signed [WIDTH-1:0] k_cubed;
    reg signed [WIDTH-1:0] k_fourth;
    reg signed [WIDTH-1:0] k_fifth;
    reg signed [WIDTH-1:0] poly_term;
    reg signed [WIDTH-1:0] n_x;
    reg signed [WIDTH-1:0] one_plus_gamma_x;
    reg negative; // 1 if original input was negative

    // Debug registers (captured when the computation is complete)
    reg signed [WIDTH-1:0] dbg_orig_d, dbg_x, dbg_x_squared,
                            dbg_neg_x_squared_over_2, dbg_n_prime,
                            dbg_k, dbg_poly_term, dbg_n_x;

    // Temporary 64-bit register for multiplications
    reg signed [63:0] temp;
    // Temporary registers for polynomial terms.
    reg signed [WIDTH-1:0] term1, term2, term3, term4, term5;

    // State machine:
    //  0: Idle (wait for start)
    //  1: Compute x²
    //  2: Compute -x²/2
    //  3: Wait one cycle for exponential module
    //  4: Compute n'(x)
    //  5: Compute one_plus_gamma_x = 1 + (?*x)
    //  6: Compute k = (one << 16) / one_plus_gamma_x
    //  7: Compute k²
    //  8: Compute k³
    //  9: Compute k?
    // 10: Compute k?
    // 11: Compute poly_term = a1*k + a2*k² + a3*k³ + a4*k? + a5*k? (blocking assignments)
    // 12: Compute final result n(x)= 1 - (n'(x)*poly_term) and capture debug signals (blocking)
    // 13: DONE state - hold outputs until a new test vector is requested.
    reg [3:0] state;
    // processing_d1: 1 if processing d1; 0 for d2.
    reg processing_d1;

    // Instantiate the exponential module.
    // (Assumed to work correctly.)
    exponential exp_module (
        .clk(clk),
        .reset(reset),
        .start(1'b1),
        .x(neg_x_squared_over_2),
        .y(exp_term),
        .done()  // Not used here.
    );

    // Main state machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state                  <= 4'd0;
            Nd1                  <= 0;
            Nd2                  <= 0;
            orig_d               <= 0;
            x                    <= 0;
            x_squared            <= 0;
            neg_x_squared_over_2 <= 0;
            n_prime              <= 0;
            k                    <= 0;
            k_squared            <= 0;
            k_cubed              <= 0;
            k_fourth             <= 0;
            k_fifth              <= 0;
            poly_term            <= 0;
            n_x                  <= 0;
            one_plus_gamma_x     <= 0;
            processing_d1      <= 1;
            done                 <= 0;
            negative             <= 0;
            dbg_orig_d           <= 0;
            dbg_x                <= 0;
            dbg_x_squared        <= 0;
            dbg_neg_x_squared_over_2 <= 0;
            dbg_n_prime          <= 0;
            dbg_k                <= 0;
            dbg_poly_term        <= 0;
            dbg_n_x              <= 0;
        end else begin
            case (state)
                // State 0: Idle - wait for a start pulse.
                4'd0: begin
                    done <= 0;
                    if (start) begin
                        // Latch the input and compute its absolute value.
                        if (processing_d1) begin
                            orig_d <= d1;
                            if (d1[WIDTH-1] == 1) begin
                                negative <= 1;
                                x <= -d1;
                            end else begin
                                negative <= 0;
                                x <= d1;
                            end
                        end else begin
                            orig_d <= d2;
                            if (d2[WIDTH-1] == 1) begin
                                negative <= 1;
                                x <= -d2;
                            end else begin
                                negative <= 0;
                                x <= d2;
                            end
                        end
                        state <= 4'd1;
                    end
                end
                // State 1: Compute x².
                4'd1: begin
                    temp = x * x;      // Q32.32 result.
                    x_squared <= temp[47:16];
                    state <= 4'd2;
                end
                // State 2: Compute -x²/2.
                4'd2: begin
                    temp = x_squared * half;
                    neg_x_squared_over_2 <= -temp[47:16];
                    state <= 4'd3;
                end
                // State 3: Wait one cycle for the exponential module.
                4'd3: begin
                    state <= 4'd4;
                end
                // State 4: Compute n'(x) = (1/sqrt(2?)) * exp(-x²/2).
                4'd4: begin
                    temp = inv_sqrt_2_pi * exp_term;
                    n_prime <= temp[47:16];
                    state <= 4'd5;
                end
                // State 5: Compute one_plus_gamma_x = 1 + (?*x).
                4'd5: begin
                    temp = gamma * x;
                    one_plus_gamma_x <= one + temp[47:16];
                    state <= 4'd6;
                end
                // State 6: Compute k = (one << 16) / one_plus_gamma_x.
                4'd6: begin
                    k <= ((({32'b0, one}) << 16)) / one_plus_gamma_x;
                    state <= 4'd7;
                end
                // State 7: Compute k².
                4'd7: begin
                    temp = k * k;
                    k_squared <= temp[47:16];
                    state <= 4'd8;
                end
                // State 8: Compute k³.
                4'd8: begin
                    temp = k_squared * k;
                    k_cubed <= temp[47:16];
                    state <= 4'd9;
                end
                // State 9: Compute k?.
                4'd9: begin
                    temp = k_cubed * k;
                    k_fourth <= temp[47:16];
                    state <= 4'd10;
                end
                // State 10: Compute k?.
                4'd10: begin
                    temp = k_fourth * k;
                    k_fifth <= temp[47:16];
                    state <= 4'd11;
                end
                // State 11: Compute poly_term = a1*k + a2*k² + a3*k³ + a4*k? + a5*k?.
                // Use blocking assignments so that intermediate results are available immediately.
                4'd11: begin
                    temp = a1 * k;      term1 = temp[47:16];
                    temp = a2 * k_squared;  term2 = temp[47:16];
                    temp = a3 * k_cubed;    term3 = temp[47:16];
                    temp = a4 * k_fourth;   term4 = temp[47:16];
                    temp = a5 * k_fifth;    term5 = temp[47:16];
                    poly_term = term1 + term2 + term3 + term4 + term5;
                    state <= 4'd12;
                end
                // State 12: Compute final result n(x) = 1 - (n'(x)*poly_term) and capture debug signals.
                // Use blocking assignments.
                4'd12: begin
                    temp = n_prime * poly_term;
                    n_x = one - temp[47:16];
                    // Capture debug values.
                    dbg_orig_d = orig_d;
                    dbg_x = x;
                    dbg_x_squared = x_squared;
                    dbg_neg_x_squared_over_2 = neg_x_squared_over_2;
                    dbg_n_prime = n_prime;
                    dbg_k = k;
                    dbg_poly_term = poly_term;
                    dbg_n_x = n_x;
                    // Apply symmetry: if the original input was negative, use 1 - n(x)
                    if (processing_d1) begin
                        if (negative)
                            Nd1 = one - n_x;
                        else
                            Nd1 = n_x;
                        processing_d1 = 0;
                    end else begin
                        if (negative)
                            Nd2 = one - n_x;
                        else
                            Nd2 = n_x;
                        processing_d1 = 1;
                    end
                    done = 1;
                    state = 4'd13;  // Move to hold state.
                end
                // State 13: Hold the computed result until a new test vector is requested.
                // In this state, wait for start to be deassert and then assert a new start pulse.
                4'd13: begin
                    done = 1;
                    // Wait until start is low, then when start rises again the new vector will be latched.
                    if (~start)
                        state = 4'd13; // Remain here until a new start pulse.
                    else
                        state = 4'd0;  // New start detected: exit hold state.
                end
                default: state <= 4'd0;
            endcase
        end
    end

endmodule
