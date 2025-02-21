`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Norm Module (for a single input)
// Computes N(d) = cumulative normal probability in Q16.16 format.
// For d >= 0, the approximation is:
//   N(d) = 1 - n(d)*P(k)
// where n(d) = (1/sqrt(2*pi))*exp(-d^2/2)
// and for d < 0, symmetry is used: N(d) = 1 - N(-d).
//
// The module sends the absolute value of (-d^2/2) to the exponential module,
// latches its output when exp_done is high, and then completes the calculation.
//////////////////////////////////////////////////////////////////////////////////
module norm_single #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,                      // One-cycle pulse to latch new input.
    input signed [WIDTH-1:0] d,       // Q16.16 input.
    output reg signed [WIDTH-1:0] N,  // Q16.16 output.
    output reg done                  // Asserted for one cycle when computation completes.
);

    // Optimized constants in Q16.16.
    localparam signed [WIDTH-1:0] gamma         = 32'sh00003B5E; // 0.23164190
    localparam signed [WIDTH-1:0] inv_sqrt_2_pi = 32'sh00006618; // 0.39894228
    localparam signed [WIDTH-1:0] a1            = 32'sh000051A9; // 0.31938153
    localparam signed [WIDTH-1:0] a2            = 32'shFFFFA4A0; // -0.35656378
    localparam signed [WIDTH-1:0] a3            = 32'sh0001C863; // 1.78147794
    localparam signed [WIDTH-1:0] a4            = 32'shFFFE2DF6; // -1.82125598
    localparam signed [WIDTH-1:0] a5            = 32'sh000154DE; // 1.33027443
    localparam signed [WIDTH-1:0] one           = 32'sh00010000; // 1.0 (65536)
    localparam signed [WIDTH-1:0] half          = 32'sh00008000; // 0.5 (32768)

    // Internal signals.
    reg signed [WIDTH-1:0] orig_d; // Latched input.
    reg signed [WIDTH-1:0] x;      // Absolute value of input.
    reg signed [WIDTH-1:0] x_squared;
    reg signed [WIDTH-1:0] neg_x_squared_over_2;
    
    // Use absolute value for driving the exponential module.
    wire signed [WIDTH-1:0] exp_in;
    assign exp_in = (neg_x_squared_over_2[WIDTH-1]) ? -neg_x_squared_over_2 : neg_x_squared_over_2;
    
    // Exponential module handshake signals.
    reg exp_start;
    wire signed [WIDTH-1:0] exp_term;
    wire exp_done;
    
    // Latch for the exponential value.
    reg signed [WIDTH-1:0] exp_val;
    
    reg signed [WIDTH-1:0] n_prime;
    reg signed [WIDTH-1:0] k;
    reg signed [WIDTH-1:0] k_squared;
    reg signed [WIDTH-1:0] k_cubed;
    reg signed [WIDTH-1:0] k_fourth;
    reg signed [WIDTH-1:0] k_fifth;
    reg signed [WIDTH-1:0] poly_term;
    reg signed [WIDTH-1:0] n_x;
    reg signed [WIDTH-1:0] one_plus_gamma_x;
    reg negative; // 1 if d was negative.

    // Temporary registers.
    reg signed [63:0] temp;
    reg signed [WIDTH-1:0] term1, term2, term3, term4, term5;

    // State machine (states 0..15).
    reg [4:0] state;

    // Instantiate the exponential module.
    // It receives exp_in (absolute value of -x^2/2) and produces exp_term.
    exponential exp_module (
        .clk(clk),
        .reset(reset),
        .start(exp_start),
        .x(exp_in),
        .y(exp_term),
        .done(exp_done)
    );
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state                  <= 5'd0;
            N                      <= 0;
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
            negative             <= 0;
            exp_start            <= 0;
            exp_val              <= 0;
            done                 <= 0;
        end else begin
            case (state)
                5'd0: begin
                    done <= 0;
                    if (start) begin
                        orig_d <= d;
                        if (d[WIDTH-1] == 1) begin
                            negative <= 1;
                            x <= -d;
                        end else begin
                            negative <= 0;
                            x <= d;
                        end
                        $display("Time %t: [State 0] Latching input. d = %h", $time, d);
                        state <= 5'd1;
                    end
                end
                5'd1: begin
                    temp = x * x;
                    x_squared <= temp[47:16];
                    $display("Time %t: [State 1] x = %d, x_squared = %d", $time, x, temp[47:16]);
                    state <= 5'd2;
                end
                5'd2: begin
                    temp = x_squared * half;
                    neg_x_squared_over_2 <= -temp[47:16];
                    $display("Time %t: [State 2] x_squared = %d, -x_squared/2 = %d", $time, x_squared, -temp[47:16]);
                    state <= 5'd3;
                end
                5'd3: begin
                    exp_start <= 1;
                    $display("Time %t: [State 3] Assert exp_start.", $time);
                    state <= 5'd4;
                end
                5'd4: begin
                    if (exp_done) begin
                        exp_start <= 0;
                        $display("Time %t: [State 4] exp_done asserted. exp_term = %d", $time, exp_term);
                        state <= 5'd5;
                    end
                end
                5'd5: begin
                    exp_val <= exp_term;
                    $display("Time %t: [State 5] Latching exp_term. exp_val = %d", $time, exp_term);
                    state <= 5'd6;
                end
                5'd6: begin
                    temp = inv_sqrt_2_pi * exp_val;
                    n_prime <= temp[47:16];
                    $display("Time %t: [State 6] inv_sqrt_2_pi = %d, exp_val = %d, n_prime = %d", 
                             $time, inv_sqrt_2_pi, exp_val, temp[47:16]);
                    state <= 5'd7;
                end
                5'd7: begin
                    temp = gamma * x;
                    one_plus_gamma_x <= one + temp[47:16];
                    $display("Time %t: [State 7] gamma = %d, x = %d, (gamma*x) = %d, one_plus_gamma_x = %d", 
                             $time, gamma, x, temp[47:16], one_plus_gamma_x);
                    state <= 5'd8;
                end
                5'd8: begin
                    k <= ((({32'b0, one}) << 16)) / one_plus_gamma_x;
                    $display("Time %t: [State 8] one = %d, one_plus_gamma_x = %d, k = %d", 
                             $time, one, one_plus_gamma_x, k);
                    state <= 5'd9;
                end
                5'd9: begin
                    temp = k * k;
                    k_squared <= temp[47:16];
                    $display("Time %t: [State 9] k = %d, k_squared = %d", $time, k, temp[47:16]);
                    state <= 5'd10;
                end
                5'd10: begin
                    temp = k_squared * k;
                    k_cubed <= temp[47:16];
                    $display("Time %t: [State 10] k_squared = %d, k = %d, k_cubed = %d", 
                             $time, k_squared, k, temp[47:16]);
                    state <= 5'd11;
                end
                5'd11: begin
                    temp = k_cubed * k;
                    k_fourth <= temp[47:16];
                    $display("Time %t: [State 11] k_cubed = %d, k = %d, k_fourth = %d", 
                             $time, k_cubed, k, temp[47:16]);
                    state <= 5'd12;
                end
                5'd12: begin
                    temp = k_fourth * k;
                    k_fifth <= temp[47:16];
                    $display("Time %t: [State 12] k_fourth = %d, k = %d, k_fifth = %d", 
                             $time, k_fourth, k, temp[47:16]);
                    state <= 5'd13;
                end
                5'd13: begin
                    temp = a1 * k;         term1 = temp[47:16];
                    temp = a2 * k_squared;   term2 = temp[47:16];
                    temp = a3 * k_cubed;     term3 = temp[47:16];
                    temp = a4 * k_fourth;    term4 = temp[47:16];
                    temp = a5 * k_fifth;     term5 = temp[47:16];
                    poly_term = term1 + term2 + term3 + term4 + term5;
                    $display("Time %t: [State 13] poly_term = %d", $time, poly_term);
                    state <= 5'd14;
                end
                5'd14: begin
                    temp = n_prime * poly_term;
                    n_x = one - temp[47:16];
                    $display("Time %t: [State 14] n_prime = %d, poly_term = %d, n_x = %d", 
                             $time, n_prime, poly_term, n_x);
                    // IMPORTANT: Reverse the symmetry.
                    // For a positive input (negative==0), we want N = one - n_x.
                    // For a negative input (negative==1), we want N = n_x.
                    if (negative)
                        N <= n_x;
                    else
                        N <= one - n_x;
                    done <= 1;
                    state <= 5'd15;
                end
                5'd15: begin
                    done <= 1;  // Hold done for one extra cycle.
                    state <= 5'd16;
                end
                5'd16: begin
                    if (~start)
                        state <= 5'd0;
                end
                default: state <= 5'd0;
            endcase
        end
    end

endmodule
