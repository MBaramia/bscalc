`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench for the divider module
// This testbench instantiates the divider, generates clock and reset, applies
// test vectors (in Q16.16 format), and monitors the outputs.
//////////////////////////////////////////////////////////////////////////////////

module divider_tb;

    parameter WIDTH = 32;
    parameter FBITS = 16;

    // Clock and reset signals
    reg clk;
    reg rst;
    
    // Control signal for starting the division
    reg start;
    
    // Inputs (signed Q16.16)
    reg signed [WIDTH-1:0] a;  // Dividend
    reg signed [WIDTH-1:0] b;  // Divisor
    
    // Outputs from the divider (declared as wires)
    wire busy;
    wire done;
    wire valid;
    wire dbz;
    wire ovf;
    wire signed [WIDTH-1:0] val;
    
    // Instantiate the divider with explicit port connections
    divider #(.WIDTH(WIDTH), .FBITS(FBITS)) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .busy(busy),
        .done(done),
        .valid(valid),
        .dbz(dbz),
        .ovf(ovf),
        .a(a),
        .b(b),
        .val(val)
    );
    
    // Clock generation: 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test procedure
    initial begin
        // Initialize signals
        rst = 1;
        start = 0;
        a = 0;
        b = 0;
        #20;
        rst = 0;
        
        // Wait a few clock cycles before starting
        #20;
        
        // Test Case 1: 100 / 2.0
        // 100.0 in Q16.16 is 100 * 65536 = 6553600
        // 2.0 in Q16.16 is 2 * 65536 = 131072
        a = 32'sd6553600;
        b = 32'sd131072;
        start = 1;
        #10;
        start = 0;
        #500;  // Wait sufficient time for the divider to complete
        
        // Test Case 2: -100 / 2.0
        a = -32'sd6553600;
        b = 32'sd131072;
        start = 1;
        #10;
        start = 0;
        #500;
        
        // Test Case 3: 100 / -2.0
        a = 32'sd6553600;
        b = -32'sd131072;
        start = 1;
        #10;
        start = 0;
        #500;
        
        // Test Case 4: -100 / -2.0
        a = -32'sd6553600;
        b = -32'sd131072;
        start = 1;
        #10;
        start = 0;
        #500;
        
        // Test Case 5: Division by zero (should assert dbz)
        a = 32'sd123456;
        b = 0;
        start = 1;
        #10;
        start = 0;
        #500;
        
        $finish;
    end
    
    // Monitor the signals
    initial begin
        $monitor("Time=%t: a=%d (%f), b=%d (%f) => busy=%b, done=%b, valid=%b, dbz=%b, ovf=%b, val=%d (%f)",
            $time,
            a, $itor(a)/65536.0,
            b, $itor(b)/65536.0,
            busy, done, valid, dbz, ovf,
            val, $itor(val)/65536.0);
    end

endmodule
