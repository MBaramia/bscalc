`timescale 1ns / 1ps
module norm_tb;
    parameter WIDTH = 32;
    // Inputs to norm (Q16.16); these are signed.
    reg clk;
    reg reset;
    reg start;  // one-cycle pulse to latch new inputs
    reg signed [WIDTH-1:0] d1;  // e.g., 1.0 = 32'h00010000, -1.0 = 32'hFFFF0000
    reg signed [WIDTH-1:0] d2;
    // Outputs from norm (Q16.16)
    wire signed [WIDTH-1:0] Nd1;
    wire signed [WIDTH-1:0] Nd2;
    wire done;
    
    // For storing test results
    integer test_file;
    integer num_tests;
    
    // Variables for loops and test cases - moved to module level
    integer i, j, k, step;
    reg signed [WIDTH-1:0] test_val;
    reg [2:0] lut_idx;  // For test_case 2
    
    // Instantiate the norm module.
    norm #(WIDTH) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .d1(d1),
        .d2(d2),
        .Nd1(Nd1),
        .Nd2(Nd2),
        .done(done)
    );
    
    // Clock generation: period = 10 ns.
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Function to wait for calculation to complete
    task wait_for_done;
        begin
            @(posedge done);
            #20;
        end
    endtask
    
    // Task to run a single test case
    task run_test_case;
        input signed [WIDTH-1:0] test_d;
        input [31:0] test_num;
        begin
            d1 = test_d;
            d2 = test_d;
            
            $display("[Test %0d] Testing d = %f (0x%h)", test_num, $itor(test_d)/65536.0, test_d);
            
            start = 1; #10; start = 0;
            wait_for_done;
            
            $fdisplay(test_file, "%d,%d,%f,%d,%f,%b", test_d, Nd1, $itor(Nd1)/65536.0, Nd2, $itor(Nd2)/65536.0, (Nd1 == Nd2));
            
            if (test_d == 0) begin
                // Special case: N(0) should be exactly 0.5
                if (Nd1 != 32'h00008000) begin
                    $display("ERROR: N(0.0) = %f, expected 0.5", $itor(Nd1)/65536.0);
                end
            end
            
            // Wait for system to reset
            wait(!done); #20;
        end
    endtask
    
    // Test procedure.
    initial begin
        // Initialize and assert reset.
        test_file = $fopen("norm_test_results.csv", "w");
        $fdisplay(test_file, "input,Nd1_raw,Nd1_float,Nd2_raw,Nd2_float,matches");
        
        reset = 1;
        start = 0;
        d1 = 0;
        d2 = 0;
        num_tests = 0;
        #20;
        reset = 0;
        #20; // Allow initialization
        
        // Test 1: Basic sanity tests
        $display("\n=== Running Basic Sanity Tests ===");
        
        // Test for d = 0
        run_test_case(32'h00000000, num_tests); // 0.0
        num_tests = num_tests + 1;
        
        // Test exact points in lookup table
        run_test_case(32'h00010000, num_tests); // 1.0
        num_tests = num_tests + 1;
        
        run_test_case(32'h00020000, num_tests); // 2.0
        num_tests = num_tests + 1;
        
        run_test_case(32'h00030000, num_tests); // 3.0
        num_tests = num_tests + 1;
        
        run_test_case(32'hFFFF0000, num_tests); // -1.0
        num_tests = num_tests + 1;
        
        run_test_case(32'hFFFE0000, num_tests); // -2.0
        num_tests = num_tests + 1;
        
        // Test 2: Systematic testing - dense coverage in critical range (-3 to 3)
        $display("\n=== Testing Critical Range (-3 to 3) ===");
        
        // Test every 0.1 in the critical range (-3 to 3)
        // From -3.0 to 3.0 in steps of 0.1
        for (i = -30; i <= 30; i = i + 1) begin
            // Convert to Q16.16: multiply by 0.1 (6554 in Q16.16)
            test_val = i * 32'h00001999; // 0.1 in Q16.16 is approximately 0x1999
            run_test_case(test_val, num_tests);
            num_tests = num_tests + 1;
        end
        
        // Test 3: Wide range testing - smaller increments near zero, larger farther away
        $display("\n=== Testing Wide Range ===");
        
        // Test from -32 to 32 in progressively larger steps
        for (j = -32; j <= 32; j = j + (j < -10 || j > 10 ? 4 : (j < -5 || j > 5 ? 2 : 1))) begin
            test_val = j * 32'h00010000; // Convert to Q16.16
            run_test_case(test_val, num_tests);
            num_tests = num_tests + 1;
        end
        
        // More extreme values (approaching limits)
        for (step = 64; step <= 32768; step = step * 2) begin
            test_val = step * 32'h00010000; // Positive value
            run_test_case(test_val, num_tests);
            num_tests = num_tests + 1;
            
            test_val = -step * 32'h00010000; // Negative value
            run_test_case(test_val, num_tests);
            num_tests = num_tests + 1;
        end
        
        // Test 4: Very small values (fractional)
        $display("\n=== Testing Very Small Values ===");
        
        // Powers of 2 from 2^-1 to 2^-16
        for (k = 1; k <= 16; k = k + 1) begin
            test_val = 32'h00010000 >> k; // Positive small value
            run_test_case(test_val, num_tests);
            num_tests = num_tests + 1;
            
            test_val = -1 * (32'h00010000 >> k); // Negative small value
            run_test_case(test_val, num_tests);
            num_tests = num_tests + 1;
        end
        
        // Test 5: Edge cases (min/max values)
        $display("\n=== Testing Edge Cases ===");
        
        // Maximum Q16.16 value (just under 2^15)
        run_test_case(32'h7FFFFFFF, num_tests);
        num_tests = num_tests + 1;
        
        // Minimum Q16.16 value (-2^15)
        run_test_case(32'h80000000, num_tests);
        num_tests = num_tests + 1;
        
        $display("\nTesting complete. %0d test cases executed.", num_tests);
        $display("Results saved in norm_test_results.csv");
        
        $fclose(test_file);
        $finish;
    end

    // Monitor with more detailed info
    initial begin
        $monitor("Time=%t | start=%b | done=%b | d1=%f | d2=%f | Nd1=%f | Nd2=%f", 
                 $time, start, done, 
                 $itor(d1)/65536.0, $itor(d2)/65536.0, 
                 $itor(Nd1)/65536.0, $itor(Nd2)/65536.0);
    end
endmodule