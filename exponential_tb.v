`timescale 1ns / 1ps
module exponential_tb;

    parameter WIDTH = 32;
    
    reg clk;
    reg reset;
    reg start;
    reg signed [WIDTH-1:0] x;        // Input x in Q16.16 format.
    wire signed [WIDTH-1:0] y;       // Output e^(-x) in Q16.16.
    wire done;
    
    // For storing test results
    integer test_file;
    integer num_tests;
    
    // Variables for test loops
    integer i, j, k;
    real test_val, expected_exp, computed_exp, error;
    reg [WIDTH-1:0] q16_input;
    
    // Instantiate the exponential module.
    exponential #(WIDTH) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .x(x),
        .y(y),
        .done(done)
    );
    
    // Clock generation: period = 10 ns.
    initial begin
         clk = 0;
         forever #5 clk = ~clk;
    end
    
    // Task to generate a one-cycle start pulse.
    task pulse_start;
        begin
            start = 1;
            @(posedge clk);
            #1; // Small delay after clock edge
            start = 0;
        end
    endtask
    
    // Task to wait for done signal
    task wait_for_done;
        begin
            @(posedge done);
            #5; // Small delay to stabilize the output
        end
    endtask
    
    // Task to run a single test case
    task run_test_case;
        input [WIDTH-1:0] test_x;
        input real expected_value;
        input [31:0] test_num;
        begin
            x = test_x;
            
            $display("[Test %0d] Testing e^(-%f) (0x%h)", test_num, $itor(test_x)/65536.0, test_x);
            
            pulse_start();
            wait_for_done();
            
            computed_exp = $itor(y)/65536.0;
            error = computed_exp - expected_value;
            
            // Save input (raw and float), output (raw and float), expected output, and error
            $fdisplay(test_file, "%d,%f,%d,%f,%f,%f", 
                     test_x, $itor(test_x)/65536.0,
                     y, computed_exp, expected_value, error);
                     
            #20; // Wait between tests
        end
    endtask
    
    // Reset and initial signal values.
    initial begin
        // Open output file
        test_file = $fopen("exponential_test_results.csv", "w");
        // Write CSV header
        $fdisplay(test_file, "raw_input,float_input,raw_output,float_output,expected_exp,error");
        
        reset = 1;
        start = 0;
        x = 0;
        num_tests = 0;
        #20;
        reset = 0;
        #20; // Allow initialization
        
        // Test 1: Basic range test (original test cases: 0.1, 0.15, 0.2, ..., 1.0)
        $display("\n=== Running Basic Range Test (0.1 to 1.0) ===");
        for (i = 0; i < 19; i = i + 1) begin
            test_val = 0.1 + i * 0.05;
            q16_input = $rtoi(test_val * 65536);
            expected_exp = $exp(-test_val); // Compute expected e^(-x)
            run_test_case(q16_input, expected_exp, num_tests);
            num_tests = num_tests + 1;
        end
        
        // Test 2: Expanded range (from -10.0 to 10.0 in steps of 0.5)
        $display("\n=== Testing Expanded Range (-10.0 to 10.0) ===");
        for (j = -20; j <= 20; j = j + 1) begin
            test_val = j * 0.5;
            q16_input = $rtoi(test_val * 65536);
            expected_exp = $exp(-test_val);
            run_test_case(q16_input, expected_exp, num_tests);
            num_tests = num_tests + 1;
        end
        
        // Test 3: Small values near zero (critical for precision)
        $display("\n=== Testing Small Values Near Zero ===");
        for (k = -100; k <= 100; k = k + 5) begin
            test_val = k * 0.01; // From -1.0 to 1.0 in steps of 0.05
            q16_input = $rtoi(test_val * 65536);
            expected_exp = $exp(-test_val);
            run_test_case(q16_input, expected_exp, num_tests);
            num_tests = num_tests + 1;
        end
        
        // Test 4: Powers of 2 (for testing handling of powers)
        $display("\n=== Testing Powers of 2 ===");
        for (i = -8; i <= 8; i = i + 1) begin
            if (i != 0) begin
                test_val = 2.0 ** i;
                q16_input = $rtoi(test_val * 65536);
                expected_exp = $exp(-test_val);
                run_test_case(q16_input, expected_exp, num_tests);
                num_tests = num_tests + 1;
            end
        end
        
        // Test 5: Special values
        $display("\n=== Testing Special Values ===");
        
        // Test x = 0 (e^0 = 1.0)
        test_val = 0.0;
        q16_input = 32'h00000000;
        expected_exp = 1.0;
        run_test_case(q16_input, expected_exp, num_tests);
        num_tests = num_tests + 1;
        
        // Test x = 1.0 (e^(-1) = 0.367879...)
        test_val = 1.0;
        q16_input = 32'h00010000;
        expected_exp = $exp(-1.0);
        run_test_case(q16_input, expected_exp, num_tests);
        num_tests = num_tests + 1;
        
        // Test x = ln(2) (e^(-ln(2)) = 0.5)
        test_val = $ln(2.0);
        q16_input = $rtoi(test_val * 65536);
        expected_exp = 0.5;
        run_test_case(q16_input, expected_exp, num_tests);
        num_tests = num_tests + 1;
        
        // Test large positive and negative values
        test_val = 16.0;
        q16_input = 32'h00100000; // 16.0 in Q16.16
        expected_exp = $exp(-16.0);
        run_test_case(q16_input, expected_exp, num_tests);
        num_tests = num_tests + 1;
        
        test_val = -16.0;
        q16_input = 32'hFF000000; // -16.0 in Q16.16
        expected_exp = $exp(16.0);
        run_test_case(q16_input, expected_exp, num_tests);
        num_tests = num_tests + 1;
        
        $display("\nTesting complete. %0d test cases executed.", num_tests);
        $display("Results saved in exponential_test_results.csv");
        
        $fclose(test_file);
        $finish;
    end

    // Monitor with more detailed info
    initial begin
        $monitor("Time=%t | start=%b | done=%b | x=%f | y=%f", 
                 $time, start, done, 
                 $itor(x)/65536.0, $itor(y)/65536.0);
    end

endmodule