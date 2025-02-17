`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// d1d2 Module for Black-Scholes
// Computes d1 and d2 in Q16.16 fixed-point format from inputs:
//   S0: Spot price, K: Strike, T: Time, sigma: Volatility, r: Risk-free rate
//
// The calculations are pipelined over 7 clock cycles. The module now waits until
// the divider, sqrt, and logarithm submodules have valid outputs before advancing.
//////////////////////////////////////////////////////////////////////////////////
module d1d2 (
    input                 clk,
    input                 reset,
    input signed [31:0]   S0,      // Spot price (Q16.16)
    input signed [31:0]   K,       // Strike (Q16.16)
    input signed [31:0]   T,       // Time (Q16.16)
    input signed [31:0]   sigma,   // Volatility (Q16.16)
    input signed [31:0]   r,       // Risk-free rate (Q16.16)
    output reg signed [31:0] d1,  // Output d1 (Q16.16)
    output reg signed [31:0] d2   // Output d2 (Q16.16)
);

    // Internal registers (Q16.16)
    reg signed [31:0] ln_S0_K;
    reg signed [31:0] sqrt_T;
    reg signed [31:0] sigma_sqrt_T;
    reg signed [31:0] sigma_squared;
    reg signed [31:0] sigma_squared_half;
    reg signed [31:0] r_plus_sigma_squared_half;
    reg signed [31:0] numerator_d1;
    reg signed [31:0] temp_d1;
    reg signed [31:0] temp_d2;

    // Pipeline state: 3-bit state (0 to 7)
    reg [2:0] state;

    // --------------------------------------------------------------------
    // Instantiate submodules with valid signals
    // --------------------------------------------------------------------

    // Divider: computes S0/K in Q16.16.
    wire signed [31:0] div_result;
    wire div_valid;
    divider #(.WIDTH(32), .FBITS(16)) div_unit (
        .clk(clk),
        .rst(reset),
        .start(1'b1),  // Tie start high for continuous operation
        .busy(),       
        .done(),       
        .valid(div_valid),
        .dbz(),        
        .ovf(),        
        .a(S0),
        .b(K),
        .val(div_result)
    );

    // Sqrt: computes sqrt(T) in Q16.16.
    wire signed [31:0] sqrt_result;
    wire sqrt_valid;
    sqrt #(.WIDTH(32), .FBITS(16)) sqrt_unit_inst (
        .clk(clk),
        .reset(reset),
        .start(1'b1),
        .busy(),       
        .valid(sqrt_valid),
        .rad(T),
        .root(sqrt_result),
        .rem()         
    );

    // Logarithm: computes ln(S0/K) in Q16.16.
    wire signed [31:0] ln_result;
    logarithm #(.WIDTH(32)) log_unit_inst (
        .clk(clk),
        .reset(reset),
        .in(div_result),
        .out(ln_result)
    );
    // Assume ln_result is valid after one cycle:
    wire log_valid = 1'b1;

    // --------------------------------------------------------------------
    // Pipeline state machine.
    // Wait in state 0 until both sqrt and ln outputs are valid.
    // --------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= 3'b000;
            ln_S0_K <= 32'd0;
            sqrt_T <= 32'd0;
            sigma_sqrt_T <= 32'd0;
            sigma_squared <= 32'd0;
            sigma_squared_half <= 32'd0;
            r_plus_sigma_squared_half <= 32'd0;
            numerator_d1 <= 32'd0;
            temp_d1 <= 32'd0;
            temp_d2 <= 32'd0;
            d1 <= 32'd0;
            d2 <= 32'd0;
        end else begin
            case (state)
                3'b000: begin
                    // Wait until sqrt and ln outputs are valid.
                    if (sqrt_valid && log_valid) begin
                        ln_S0_K <= ln_result;
                        sqrt_T  <= sqrt_result;
                        $display("Cycle 1: ln_S0_K = %d (%f), sqrt_T = %d (%f)",
                            ln_S0_K, $itor($signed(ln_S0_K))/65536.0,
                            sqrt_T, $itor($signed(sqrt_T))/65536.0);
                        state <= 3'b001;
                    end else begin
                        state <= 3'b000;
                    end
                end
                3'b001: begin
                    sigma_sqrt_T  <= (sigma * sqrt_T) >>> 16;
                    sigma_squared <= (sigma * sigma) >>> 16;
                    $display("Cycle 2: sigma_sqrt_T = %d (%f), sigma_squared = %d (%f)",
                        sigma_sqrt_T, $itor($signed(sigma_sqrt_T))/65536.0,
                        sigma_squared, $itor($signed(sigma_squared))/65536.0);
                    state <= 3'b010;
                end
                3'b010: begin
                    sigma_squared_half <= sigma_squared >>> 1;
                    r_plus_sigma_squared_half <= r + sigma_squared_half;
                    $display("Cycle 3: sigma_squared_half = %d (%f), r_plus_sigma_squared_half = %d (%f)",
                        sigma_squared_half, $itor($signed(sigma_squared_half))/65536.0,
                        r_plus_sigma_squared_half, $itor($signed(r_plus_sigma_squared_half))/65536.0);
                    state <= 3'b011;
                end
                3'b011: begin
                    numerator_d1 <= (r_plus_sigma_squared_half * T) >>> 16;
                    $display("Cycle 4: Partial numerator_d1 = %d (%f)",
                        numerator_d1, $itor($signed(numerator_d1))/65536.0);
                    state <= 3'b100;
                end
                3'b100: begin
                    numerator_d1 <= ln_S0_K + numerator_d1;
                    $display("Cycle 5: Final numerator_d1 = %d (%f)",
                        numerator_d1, $itor($signed(numerator_d1))/65536.0);
                    state <= 3'b101;
                end
                3'b101: begin
                    // Division: d1 = numerator_d1 / sigma_sqrt_T.
                    temp_d1 <= numerator_d1 / sigma_sqrt_T;
                    $display("Cycle 6: temp_d1 (d1 candidate) = %d (%f)",
                        temp_d1, $itor($signed(temp_d1))/65536.0);
                    state <= 3'b110;
                end
                3'b110: begin
                    // d2 = d1 - sigma_sqrt_T.
                    temp_d2 <= temp_d1 - sigma_sqrt_T;
                    d1 <= temp_d1;
                    d2 <= temp_d2;
                    $display("Cycle 7: d1 = %d (%f), d2 = %d (%f)",
                        d1, $itor($signed(d1))/65536.0,
                        d2, $itor($signed(d2))/65536.0);
                    state <= 3'b000;  // Ready for new input
                end
                default: state <= 3'b000;
            endcase
        end
    end

endmodule
