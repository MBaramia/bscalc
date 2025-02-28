`timescale 1ns / 1ps

module log_tb;

  parameter WIDTH = 32;

  // Inputs (Q16.16)
  reg clk;
  reg reset;
  reg start;  // one-cycle start pulse
  reg signed [WIDTH-1:0] in;  // Input in Q16.16

  // Outputs (Q16.16)
  wire signed [WIDTH-1:0] out;  // Output ln(x) in Q16.16
  wire valid;

  // File handle for output CSV
  integer test_file;
  integer num_tests;
  
  // Variables for test loops
  integer i, j, k;
  real x_value, expected_ln, computed_ln, error;
  reg [WIDTH-1:0] q16_input;

  // Instantiate the logarithm unit.
  logarithm #(WIDTH) uut (
    .clk(clk),
    .reset(reset),
    .start(start),
    .in(in),
    .out(out),
    .valid(valid)
  );

  // Clock generation: 10 ns period.
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Function to wait for valid output
  task wait_for_valid;
    begin
      @(posedge valid);
      #5; // Small delay to stabilize the output
    end
  endtask

  // Task to generate a one-cycle start pulse.
  task pulse_start;
    begin
      start = 1;
      @(posedge clk);
      #1; // Small delay after clock edge
      start = 0;
    end
  endtask
  
  // Task to run a single test case
  task run_test_case;
    input [WIDTH-1:0] test_in;
    input real expected_value;
    input [31:0] test_num;
    begin
      in = test_in;
      
      $display("[Test %0d] Testing ln(%f) (0x%h)", test_num, $itor(test_in)/65536.0, test_in);
      
      pulse_start();
      wait_for_valid();
      
      computed_ln = $itor($signed(out))/65536.0;
      error = computed_ln - expected_value;
      
      // Save input (raw and float), output (raw and float), expected output, and error
      $fdisplay(test_file, "%d,%f,%d,%f,%f,%f", 
                test_in, $itor(test_in)/65536.0,
                out, computed_ln, expected_value, error);
                
      #20; // Wait between tests
    end
  endtask

  // Test procedure: generate a comprehensive set of tests across valid input range
  initial begin
    // Open output file
    test_file = $fopen("log_test_results.csv", "w");
    // Write CSV header
    $fdisplay(test_file, "raw_input,float_input,raw_output,float_output,expected_ln,error");
    
    reset = 1;
    start = 0;
    in = 32'h00010000; // default to 1.0 in Q16.16
    num_tests = 0;
    #20;
    reset = 0;
    #20;  // wait a couple of cycles after reset

    // Test 1: Basic sanity tests with integers 1 through 20
    $display("\n=== Running Basic Sanity Tests (Integers 1-20) ===");
    for (i = 1; i <= 20; i = i + 1) begin
      q16_input = i << 16;  // convert integer i to Q16.16 format
      expected_ln = $ln(i*1.0); // Compute expected natural logarithm
      run_test_case(q16_input, expected_ln, num_tests);
      num_tests = num_tests + 1;
    end
    
    // Test 2: Powers of 2 (2^-10 to 2^15)
    $display("\n=== Testing Powers of 2 ===");
    for (j = -10; j <= 15; j = j + 1) begin
      x_value = 2.0 ** j;
      expected_ln = $ln(x_value);
      // Convert to Q16.16
      if (j >= 0) begin
        // For positive powers: shift left
        q16_input = 32'h00010000 << j;
      end else begin
        // For negative powers: shift right
        q16_input = 32'h00010000 >> (-j);
      end
      run_test_case(q16_input, expected_ln, num_tests);
      num_tests = num_tests + 1;
    end
    
    // Test 3: Detailed range (0.1 to 10.0 in steps of 0.1)
    $display("\n=== Testing Detailed Range (0.1 to 10.0) ===");
    for (k = 1; k <= 100; k = k + 1) begin
      x_value = k * 0.1;
      expected_ln = $ln(x_value);
      // Convert to Q16.16
      q16_input = $rtoi(x_value * 65536.0);
      run_test_case(q16_input, expected_ln, num_tests);
      num_tests = num_tests + 1;
    end
    
    // Test 4: Special values and edge cases
    $display("\n=== Testing Special Values and Edge Cases ===");
    // Test e (result should be 1.0)
    x_value = 2.718281828459045;
    expected_ln = 1.0;
    q16_input = $rtoi(x_value * 65536.0);
    run_test_case(q16_input, expected_ln, num_tests);
    num_tests = num_tests + 1;
    
    // Test 10 (result should be ln(10))
    x_value = 10.0;
    expected_ln = 2.302585092994046;
    q16_input = 10 << 16;
    run_test_case(q16_input, expected_ln, num_tests);
    num_tests = num_tests + 1;
    
    // Test very small values
    x_value = 0.001;
    expected_ln = $ln(x_value);
    q16_input = $rtoi(x_value * 65536.0);
    run_test_case(q16_input, expected_ln, num_tests);
    num_tests = num_tests + 1;
    
    // Test larger values
    x_value = 1000.0;
    expected_ln = $ln(x_value);
    q16_input = $rtoi(x_value * 65536.0);
    run_test_case(q16_input, expected_ln, num_tests);
    num_tests = num_tests + 1;
    
    // Test 5: Values just above 1.0 (critical region)
    $display("\n=== Testing Critical Region (Near 1.0) ===");
    for (i = 0; i <= 100; i = i + 1) begin
      x_value = 1.0 + (i * 0.01);
      expected_ln = $ln(x_value);
      q16_input = $rtoi(x_value * 65536.0);
      run_test_case(q16_input, expected_ln, num_tests);
      num_tests = num_tests + 1;
    end

    $display("\nTesting complete. %0d test cases executed.", num_tests);
    $display("Results saved in log_test_results.csv");
    
    $fclose(test_file);
    $finish;
  end

  // Monitor for detailed output
  initial begin
    $monitor("Time=%0t | start=%b | valid=%b | in=%f | out=%f", 
             $time, start, valid, 
             $itor(in)/65536.0, $itor($signed(out))/65536.0);
  end

endmodule