`timescale 1ns / 1ps
module norm_single #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,
    input signed [WIDTH-1:0] d,
    output reg signed [WIDTH-1:0] N,
    output reg done
);
    // Constants in Q16.16 format
    localparam signed [WIDTH-1:0] one      = 32'h00010000; // 1.0
    localparam signed [WIDTH-1:0] half     = 32'h00008000; // 0.5
    
    // Using simplified polynomial approximation constants
    // N(x) ? 0.5 + sgn(x) * (0.5 - P(|x|)) for |x| ? 5
    // P(x) = sum[a_i * x^i]
    localparam signed [WIDTH-1:0] a0      = 32'h00008000; // 0.5
    localparam signed [WIDTH-1:0] a1      = 32'hFFFFB46F; // -0.2929
    localparam signed [WIDTH-1:0] a2      = 32'h00000080; // 0.00195
    localparam signed [WIDTH-1:0] a3      = 32'h00000934; // 0.0035656
    localparam signed [WIDTH-1:0] a4      = 32'h00000070; // 0.0006808
    
    // State machine
    localparam IDLE        = 0;
    localparam CALC_X      = 1;
    localparam CALC_X2     = 2;
    localparam CALC_X3     = 3;
    localparam CALC_X4     = 4;
    localparam CALC_POLY   = 5;
    localparam CALC_RESULT = 6;
    localparam DONE        = 7;
    
    reg [3:0] state;
    
    // Registers for calculation
    reg signed [WIDTH-1:0] x_abs;
    reg is_negative;
    reg signed [WIDTH-1:0] x2, x3, x4;
    reg signed [WIDTH-1:0] term0, term1, term2, term3, term4;
    reg signed [WIDTH-1:0] poly_result;
    reg signed [63:0] temp;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            N <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        is_negative <= d[WIDTH-1];
                        x_abs <= d[WIDTH-1] ? -d : d;
                        $display("Time %t: [State %0d] Input d = %h, x_abs = %d", $time, state, d, d[WIDTH-1] ? -d : d);
                        state <= CALC_X;
                    end
                end
                
                CALC_X: begin
                    // Handle special cases
                    if (x_abs == 0) begin
                        // N(0) = 0.5 exactly
                        N <= half;
                        state <= DONE;
                    end
                    else if (x_abs >= 32'h00050000) begin // if |x| >= 5.0
                        // N(x) ? 1 for large positive x, ? 0 for large negative x
                        N <= is_negative ? 32'h00000000 : one;
                        state <= DONE;
                    end else begin
                        // Calculate x^2
                        temp = x_abs * x_abs;
                        x2 <= temp[47:16];
                        $display("Time %t: [State %0d] x_abs = %d, x^2 = %d", $time, state, x_abs, temp[47:16]);
                        state <= CALC_X2;
                    end
                end
                
                CALC_X2: begin
                    // Calculate x^3
                    temp = x2 * x_abs;
                    x3 <= temp[47:16];
                    $display("Time %t: [State %0d] x^2 = %d, x^3 = %d", $time, state, x2, temp[47:16]);
                    state <= CALC_X3;
                end
                
                CALC_X3: begin
                    // Calculate x^4
                    temp = x3 * x_abs;
                    x4 <= temp[47:16];
                    $display("Time %t: [State %0d] x^3 = %d, x^4 = %d", $time, state, x3, temp[47:16]);
                    state <= CALC_POLY;
                end
                
                CALC_POLY: begin
                    // Calculate polynomial P(x) = a0 + a1*x + a2*x^2 + a3*x^3 + a4*x^4
                    term0 = a0;
                    
                    temp = a1 * x_abs;
                    term1 = temp[47:16];
                    
                    temp = a2 * x2;
                    term2 = temp[47:16];
                    
                    temp = a3 * x3;
                    term3 = temp[47:16];
                    
                    temp = a4 * x4;
                    term4 = temp[47:16];
                    
                    // Sum the terms
                    poly_result = term0 + term1 + term2 + term3 + term4;
                    $display("Time %t: [State %0d] Polynomial result = %d", $time, state, poly_result);
                    
                    state <= CALC_RESULT;
                end
                
                CALC_RESULT: begin
                    // For x ? 0: N(x) ? 0.5 + (0.5 - P(x))
                    // For x < 0: N(x) ? 0.5 - (0.5 - P(|x|))
                    if (is_negative) begin
                        N <= poly_result;
                    end else begin
                        N <= one - poly_result; 
                    end
                    $display("Time %t: [State %0d] Final result = %d", $time, state, is_negative ? poly_result : (one - poly_result));
                    state <= DONE;
                end
                
                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule