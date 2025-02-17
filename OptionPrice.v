`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// OptionPrice Module
// Computes the Black-Scholes option price using fixed-point Q16.16 arithmetic.
// Uses an exponential module to compute exp(-r*T) and then computes the call and
// put prices. This version includes detailed $display debug statements for each
// state so that you can see the raw and converted values.
// All signals are declared as signed.
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
                    // Compute exp_input = -rate * timetm in Q16.16.
                    exp_input <= -((rate * timetm) >>> 16);
                    $display("State 0: exp_input raw=%d, float=%f", 
                             exp_input, $itor($signed(exp_input))/65536.0);
                    state <= 3'b001;
                end
                3'b001: begin
                    // Wait one cycle for exp_output then compute Ke_rt = (strike * exp_output)
                    temp64 = $signed(strike) * $signed(exp_output);
                    Ke_rt <= temp64[47:16];
                    $display("State 1: exp_output raw=%d, float=%f, Ke_rt raw=%d, float=%f", 
                             exp_output, $itor($signed(exp_output))/65536.0,
                             Ke_rt, $itor($signed(Ke_rt))/65536.0);
                    state <= 3'b010;
                end
                3'b010: begin
                    // Compute spot_Nd1 = (spot * Nd1)
                    temp64 = $signed(spot) * $signed(Nd1);
                    spot_Nd1 <= temp64[47:16];
                    $display("State 2: spot_Nd1 raw=%d, float=%f", 
                             spot_Nd1, $itor($signed(spot_Nd1))/65536.0);
                    state <= 3'b011;
                end
                3'b011: begin
                    // Compute Ke_rt_Nd2 = (Ke_rt * Nd2)
                    temp64 = $signed(Ke_rt) * $signed(Nd2);
                    Ke_rt_Nd2 <= temp64[47:16];
                    $display("State 3: Ke_rt_Nd2 raw=%d, float=%f", 
                             Ke_rt_Nd2, $itor($signed(Ke_rt_Nd2))/65536.0);
                    state <= 3'b100;
                end
                3'b100: begin
                    // Compute Call Option Price: COptionPrice = spot_Nd1 - Ke_rt_Nd2.
                    COptionPrice <= $signed(spot_Nd1) - $signed(Ke_rt_Nd2);
                    $display("State 4: Call Price raw=%d, float=%f", 
                             COptionPrice, $itor($signed(COptionPrice))/65536.0);
                    state <= 3'b101;
                end
                3'b101: begin
                    // Compute Put Option Price: POptionPrice = Ke_rt - spot_Nd1.
                    POptionPrice <= $signed(Ke_rt) - $signed(spot_Nd1);
                    if (otype == 1'b0) begin
                        OptionPrice <= COptionPrice;
                        $display("State 5: Call Option Selected, OptionPrice raw=%d, float=%f",
                                 OptionPrice, $itor($signed(OptionPrice))/65536.0);
                    end else begin
                        OptionPrice <= POptionPrice;
                        $display("State 5: Put Option Selected, OptionPrice raw=%d, float=%f",
                                 OptionPrice, $itor($signed(OptionPrice))/65536.0);
                    end
                    state <= 3'b000;
                end
                default: state <= 3'b000;
            endcase
        end
    end

endmodule
