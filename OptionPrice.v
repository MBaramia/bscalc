`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OptionPrice Module
// Computes the Black-Scholes option price using fixed-point Q16.16 arithmetic.
// Uses an exponential module to compute exp(-r*T) and then computes the call price.
// 
// In Q16.16:
//   rate: risk-free rate (e.g., 0.05 * 65536 ? 3277)
//   timetm: time to maturity (e.g., 1 year = 65536)
//   spot: spot price (e.g., 100*65536 = 6,553,600)
//   strike: strike price (e.g., 100*65536 = 6,553,600)
//   Nd1, Nd2: cumulative normal distribution values for d1 and d2
//
// The discount factor is computed as:
//   exp_input = (rate * timetm) >>> 16  (i.e., 0.05 in Q16.16 for a 5% rate)
// then the exponential module computes exp(-exp_input), which yields ~0.95123.
// The option price is computed as:
//   Call Price = (spot * Nd1) - (strike * exp(-r*T) * Nd2)
// For example, with Nd1 ? 0.8413 and Nd2 ? 0.1587, we expect:
//   spot_Nd1 ? 100*0.8413 = 84.13,
//   Ke_rt = 100*0.95123 ? 95.12,
//   Ke_rt_Nd2 ? 95.12*0.1587 = 15.12,
//   Call Price ? 84.13 - 15.12 = 69.01,
// which in Q16.16 is approximately 69.01*65536 ? 4,525,000.
//////////////////////////////////////////////////////////////////////////////////

module OptionPrice #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input signed [WIDTH-1:0] rate,      // Risk-free rate (Q16.16)
    input signed [WIDTH-1:0] timetm,    // Time to maturity (Q16.16)
    input signed [WIDTH-1:0] spot,      // Spot price (Q16.16)
    input signed [WIDTH-1:0] strike,    // Strike (Q16.16)
    input signed [WIDTH-1:0] Nd1,       // CND of d1 (Q16.16)
    input signed [WIDTH-1:0] Nd2,       // CND of d2 (Q16.16)
    input otype,                      // 0 for call, 1 for put
    output reg signed [WIDTH-1:0] OptionPrice // Option price (Q16.16)
);

    // Internal signals (all Q16.16 signed)
    reg signed [WIDTH-1:0] exp_input;   // Input to exponential module
    wire signed [WIDTH-1:0] exp_output; // Output from exponential module
    reg signed [WIDTH-1:0] Ke_rt;
    reg signed [WIDTH-1:0] spot_Nd1;
    reg signed [WIDTH-1:0] Ke_rt_Nd2;
    reg signed [WIDTH-1:0] COptionPrice;
    reg signed [WIDTH-1:0] POptionPrice;
    reg [2:0] state;                  // 3-bit state machine

    // 64-bit temporary for multiplications
    reg signed [63:0] temp64;

    // Generate a one-cycle start pulse for the exponential module.
    reg exp_start;
    // (For this example, we generate a pulse when OptionPrice state machine is at 0)
    always @(posedge clk or posedge reset) begin
        if (reset)
            exp_start <= 1'b0;
        else if (state == 3'b000)
            exp_start <= 1'b1;
        else
            exp_start <= 1'b0;
    end

    // Instantiate the exponential module.
    // (Ensure that your exponential module uses a rising-edge detector internally.)
    exponential exp_module (
        .clk(clk),
        .reset(reset),
        .start(exp_start),
        .x(exp_input),
        .y(exp_output),
        .done()  // Not used here
    );

    // OptionPrice state machine with detailed debug prints.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= 3'b000;
            OptionPrice <= 0;
            exp_input <= 0;
            Ke_rt <= 0;
            spot_Nd1 <= 0;
            Ke_rt_Nd2 <= 0;
            COptionPrice <= 0;
            POptionPrice <= 0;
        end else begin
            case (state)
                3'b000: begin
                    // Compute exp_input = (rate * timetm) >>> 16.
                    // (Remove the negative sign so that the exponential module computes exp(-0.05))
                    exp_input <= ((rate * timetm) >>> 16);
                    state <= 3'b001;
                end
                3'b001: begin
                    // Wait one cycle for exp_output then compute Ke_rt = (strike * exp_output)
                    temp64 = $signed(strike) * $signed(exp_output);
                    Ke_rt <= temp64[47:16];
                    state <= 3'b010;
                end
                3'b010: begin
                    // Compute spot_Nd1 = (spot * Nd1)
                    temp64 = $signed(spot) * $signed(Nd1);
                    spot_Nd1 <= temp64[47:16];
                    state <= 3'b011;
                end
                3'b011: begin
                    // Compute Ke_rt_Nd2 = (Ke_rt * Nd2)
                    temp64 = $signed(Ke_rt) * $signed(Nd2);
                    Ke_rt_Nd2 <= temp64[47:16];
                    state <= 3'b100;
                end
                3'b100: begin
                    // Compute Call Option Price: COptionPrice = spot_Nd1 - Ke_rt_Nd2.
                    COptionPrice <= $signed(spot_Nd1) - $signed(Ke_rt_Nd2);
                    state <= 3'b101;
                end
                3'b101: begin
                    // Compute Put Option Price: POptionPrice = Ke_rt - spot_Nd1.
                    POptionPrice <= $signed(Ke_rt) - $signed(spot_Nd1);
                    if (otype == 1'b0) begin
                        OptionPrice <= COptionPrice;
                        
                    end else begin
                        OptionPrice <= POptionPrice;
                        
                    end
                    state <= 3'b000;
                end
                default: state <= 3'b000;
            endcase
        end
    end

endmodule
