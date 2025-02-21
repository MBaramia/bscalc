`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// d1d2 Module for Black-Scholes
// Computes d1 and d2 in Q16.16 fixed-point format and asserts a one-cycle pulse
// on 'norm_start' once valid d1/d2 are available. This pulse can then drive the
// 'start' input of your norm module.
//////////////////////////////////////////////////////////////////////////////////

module d1d2 #(
    parameter WIDTH = 32
)(
    input                     clk,
    input                     reset,
    input                     start,   // one-cycle external start pulse for a new calculation
    input  signed [WIDTH-1:0] S0,      // Spot price (Q16.16)
    input  signed [WIDTH-1:0] K,       // Strike (Q16.16)
    input  signed [WIDTH-1:0] T,       // Time (Q16.16)
    input  signed [WIDTH-1:0] sigma,   // Volatility (Q16.16)
    input  signed [WIDTH-1:0] r,       // Risk-free rate (Q16.16)

    output reg signed [WIDTH-1:0] d1,  // Final d1 (Q16.16)
    output reg signed [WIDTH-1:0] d2,  // Final d2 (Q16.16)

    // Submodule valid signals (debug)
    output wire div_valid_out,
    output wire sqrt_valid_out,
    output wire log_valid_out,

    // One-cycle pulse when pipeline completes
    // (Used to trigger norm module's 'start')
    output wire norm_start
);

    //--------------------------------------------------
    // 0. Latch all inputs on external start (and hold them)
    //--------------------------------------------------
    reg signed [WIDTH-1:0] latched_S0;
    reg signed [WIDTH-1:0] latched_K;
    reg signed [WIDTH-1:0] latched_T;
    reg signed [WIDTH-1:0] latched_sigma;
    reg signed [WIDTH-1:0] latched_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            latched_S0    <= 0;
            latched_K     <= 0;
            latched_T     <= 0;
            latched_sigma <= 0;
            latched_r     <= 0;
        end else if (start) begin
            latched_S0    <= S0;
            latched_K     <= K;
            latched_T     <= T;
            latched_sigma <= sigma;
            latched_r     <= r;
        end
    end

    // Generate an internal start pulse delayed by one cycle.
    reg start_d;
    reg internal_start;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            start_d        <= 0;
            internal_start <= 0;
        end else begin
            start_d        <= start;
            internal_start <= start_d;
        end
    end

    //--------------------------------------------------
    // 1. Instantiate submodules using latched inputs & internal_start
    //--------------------------------------------------

    // --- Divider: S0 / K ---
    wire signed [WIDTH-1:0] div_result;
    wire                    div_valid;
    divider #(.WIDTH(WIDTH), .FBITS(16)) div_unit (
        .clk(clk),
        .rst(reset),
        .start(internal_start),
        .busy(),
        .done(),
        .valid(div_valid),
        .dbz(),
        .ovf(),
        .a(latched_S0),
        .b(latched_K),
        .val(div_result)
    );
    assign div_valid_out = div_valid;

    // --- Sqrt: sqrt(T) ---
    wire signed [WIDTH-1:0] sqrt_result;
    wire                    sqrt_valid;
    sqrt #(.WIDTH(WIDTH), .FBITS(16)) sqrt_unit_inst (
        .clk(clk),
        .reset(reset),
        .start(internal_start),
        .busy(),
        .valid(sqrt_valid),
        .rad(latched_T),
        .root(sqrt_result),
        .rem()
    );
    assign sqrt_valid_out = sqrt_valid;

    // --- Logarithm: ln(div_result) ---
    wire signed [WIDTH-1:0] ln_result;
    wire                    log_valid;
    reg                     log_start;
    reg  signed [WIDTH-1:0] latched_div_for_log;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            latched_div_for_log <= 0;
            log_start           <= 0;
        end else begin
            log_start <= 0;
            if (div_valid) begin
                latched_div_for_log <= div_result;
                log_start           <= 1;
            end
        end
    end
    logarithm #(.WIDTH(WIDTH)) log_unit_inst (
        .clk(clk),
        .reset(reset),
        .start(log_start),
        .in(latched_div_for_log),
        .out(ln_result),
        .valid(log_valid)
    );
    assign log_valid_out = log_valid;

    //--------------------------------------------------
    // 2. Latch submodule outputs when valid
    //--------------------------------------------------
    reg signed [WIDTH-1:0] latched_div_result;
    reg signed [WIDTH-1:0] latched_sqrt_result;
    reg signed [WIDTH-1:0] latched_ln_result;
    reg                    latched_div_valid;
    reg                    latched_sqrt_valid;
    reg                    latched_log_valid;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            latched_div_valid   <= 0;
            latched_sqrt_valid  <= 0;
            latched_log_valid   <= 0;
            latched_div_result  <= 0;
            latched_sqrt_result <= 0;
            latched_ln_result   <= 0;
        end else begin
            if (start) begin
                latched_div_valid   <= 0;
                latched_sqrt_valid  <= 0;
                latched_log_valid   <= 0;
            end
            if (div_valid && !latched_div_valid) begin
                latched_div_result <= div_result;
                latched_div_valid  <= 1;
            end
            if (sqrt_valid && !latched_sqrt_valid) begin
                latched_sqrt_result <= sqrt_result;
                latched_sqrt_valid  <= 1;
            end
            if (log_valid && !latched_log_valid) begin
                latched_ln_result <= ln_result;
                latched_log_valid <= 1;
            end
        end
    end

    //--------------------------------------------------
    // 3. Pipeline for d1/d2 computation (8-cycle pipeline)
    //--------------------------------------------------
    reg signed [WIDTH-1:0] ln_S0_K;
    reg signed [WIDTH-1:0] sqrt_T;
    reg signed [WIDTH-1:0] sigma_sqrt_T;
    reg signed [WIDTH-1:0] sigma_squared;
    reg signed [WIDTH-1:0] sigma_squared_half;
    reg signed [WIDTH-1:0] r_plus_sigma_squared_half;
    reg signed [WIDTH-1:0] numerator_d1;
    reg signed [WIDTH-1:0] d1_candidate;
    reg signed [WIDTH-1:0] temp_d2;

    wire signed [63:0] sigma_times_sqrtT_full;
    wire signed [63:0] sigma_squared_full;
    wire signed [63:0] r_plus_sigma_squared_half_full;
    assign sigma_times_sqrtT_full = $signed(latched_sigma) * $signed(sqrt_T);
    assign sigma_squared_full     = $signed(latched_sigma) * $signed(latched_sigma);
    assign r_plus_sigma_squared_half_full = $signed(r_plus_sigma_squared_half) * $signed(latched_T);

    // Divider for final d1_candidate = numerator_d1 / (sigma * sqrt_T)
    wire signed [WIDTH-1:0] d1_div_result;
    wire d1_div_valid;
    reg  d1_div_start;
    divider #(.WIDTH(WIDTH), .FBITS(16)) d1_divider_inst (
        .clk(clk),
        .rst(reset),
        .start(d1_div_start),
        .busy(),
        .done(),
        .valid(d1_div_valid),
        .dbz(),
        .ovf(),
        .a(numerator_d1),
        .b(sigma_sqrt_T),
        .val(d1_div_result)
    );

    // Extended pipeline states
    reg [2:0] state;
    reg pipeline_done; // internal: latched for one cycle

    // We will also produce norm_start from pipeline_done
    // (so that the norm module sees a one-cycle pulse after d1/d2 are valid)
    reg norm_start_r;
    assign norm_start = norm_start_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state                     <= 3'b000;
            ln_S0_K                   <= 0;
            sqrt_T                    <= 0;
            sigma_sqrt_T              <= 0;
            sigma_squared             <= 0;
            sigma_squared_half        <= 0;
            r_plus_sigma_squared_half <= 0;
            numerator_d1              <= 0;
            d1_candidate              <= 0;
            temp_d2                   <= 0;
            d1                        <= 0;
            d2                        <= 0;
            d1_div_start              <= 0;
            pipeline_done             <= 0;
            norm_start_r              <= 0;
        end else begin
            // Deassert pipeline_done & norm_start after 1 cycle
            if (pipeline_done)  pipeline_done  <= 0;
            if (norm_start_r)   norm_start_r   <= 0;

            case (state)
                3'b000: begin
                    // Wait for latched submodules
                    if (latched_div_valid && latched_sqrt_valid && latched_log_valid) begin
                        ln_S0_K <= latched_ln_result;     // ln(S0/K)
                        sqrt_T  <= latched_sqrt_result;   // sqrt(T)
                        state   <= 3'b001;
                    end
                end

                3'b001: begin
                    // Compute sigma_sqrt_T, sigma_squared
                    sigma_sqrt_T  <= sigma_times_sqrtT_full >>> 16;
                    sigma_squared <= sigma_squared_full     >>> 16;
                    state <= 3'b010;
                end

                3'b010: begin
                    // sigma_squared_half = sigma_squared / 2
                    // r_plus_sigma_squared_half = r + sigma_squared_half
                    sigma_squared_half          <= sigma_squared >>> 1;
                    r_plus_sigma_squared_half   <= latched_r + (sigma_squared >>> 1);
                    state <= 3'b011;
                end

                3'b011: begin
                    // partial numerator = (r + sigma^2/2)*T
                    numerator_d1 <= (r_plus_sigma_squared_half_full >>> 16);
                    state <= 3'b100;
                end

                3'b100: begin
                    // final numerator = ln(S0/K) + partial numerator
                    numerator_d1 <= ln_S0_K + numerator_d1;
                    state <= 3'b101;
                end

                3'b101: begin
                    // trigger divider for d1
                    d1_div_start <= 1;
                    state <= 3'b110;
                end

                3'b110: begin
                    d1_div_start <= 0;
                    if (d1_div_valid) begin
                        d1_candidate <= d1_div_result;
                        state <= 3'b111;
                    end
                end

                3'b111: begin
                    // d2 = d1 - sigma_sqrt_T
                    d1 <= d1_candidate;
                    d2 <= d1_candidate - sigma_sqrt_T;
                    pipeline_done <= 1;   // one-cycle pulse
                    // Next cycle, we assert norm_start
                    norm_start_r  <= 1;   // one-cycle pulse to norm
                    state <= 3'b000;      // go back to idle
                end
            endcase
        end
    end

endmodule
