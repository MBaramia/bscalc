`timescale 1ns / 1ps

module top_tb;
    parameter WIDTH = 32;
    
    // Testbench signals
    reg clk;
    reg reset;
    reg start;
    reg signed [WIDTH-1:0] S0;      // Spot price (Q16.16)
    reg signed [WIDTH-1:0] K;       // Strike price (Q16.16)
    reg signed [WIDTH-1:0] T;       // Time to maturity (Q16.16)
    reg signed [WIDTH-1:0] sigma;   // Volatility (Q16.16)
    reg signed [WIDTH-1:0] r;       // Risk-free rate (Q16.16)
    reg otype;                      // Option type: 0=call, 1=put
    wire signed [WIDTH-1:0] OptionPrice;
    wire done;
    
    // Cycle counter for timing measurement
    integer cycle_count;
    integer start_cycle;
    integer latency_cycles;
    
    // Instantiate the top module
    top #(.WIDTH(WIDTH)) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .S0(S0),
        .K(K),
        .T(T),
        .sigma(sigma),
        .r(r),
        .otype(otype),
        .OptionPrice(OptionPrice),
        .done(done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock (10ns period)
    end
    
    // Test procedure
    initial begin
        // Initialize
        reset = 1;
        start = 0;
        S0 = 32'h00140000;     // 20.0 in Q16.16
        K = 32'h00100000;      // 16.0 in Q16.16
        T = 32'h00010000;      // 1.0 in Q16.16
        sigma = 32'h00004ccd;  // 0.3 in Q16.16
        r = 32'h00000666;      // 0.025 in Q16.16
        otype = 0;             // Call option
        cycle_count = 0;
        start_cycle = 0;
        
        // Reset
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);
        
        // Start calculation
        start = 1;
        start_cycle = cycle_count;
        $display("Starting calculation at cycle %d", start_cycle);
        @(posedge clk);
        start = 0;
        
        // Wait for completion
        wait(done);
        latency_cycles = cycle_count - start_cycle;
        
        // Display results
        $display("Calculation completed at cycle %d", cycle_count);
        $display("Total latency: %d clock cycles", latency_cycles);
        $display("At 100 MHz, latency = %0.2f microseconds", latency_cycles * 0.01);
        $display("Option Price = %h (hex) = %f (decimal)", OptionPrice, $signed(OptionPrice) / 65536.0);
        
        // Run for a few more cycles then finish
        repeat(10) @(posedge clk);
        $finish;
    end
    
    // Cycle counter
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
    end
endmodule