`timescale 1ns / 1ps

module sqrt_tb;

    parameter CLK_PERIOD = 10;
    parameter WIDTH = 32;
    parameter FBITS = 16;  // number of fractional bits

    reg clk;
    reg reset;
    reg start;                // one-cycle start pulse
    wire busy;                // busy signal from DUT
    wire valid;               // valid signal from DUT
    reg [WIDTH-1:0] rad;      // radicand input in Q16.16
    wire [WIDTH-1:0] root;    // computed sqrt in Q16.16
    wire [WIDTH-1:0] rem;     // remainder in Q16.16

    // Instantiate the DUT.
    sqrt #(
        .WIDTH(WIDTH),
        .FBITS(FBITS)
    ) sqrt_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .busy(busy),
        .valid(valid),
        .rad(rad),
        .root(root),
        .rem(rem)
    );

    // Generate a 10 ns clock.
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset logic.
    initial begin
        reset = 1;
        start = 0;
        rad   = 0;
        #20;
        reset = 0;
    end

    // Loop from 1..20, apply each as Q16.16, wait for the pipeline to finish,
    // then print the final result as a decimal.
    integer i;
    real rad_real, root_real, rem_real;

    initial begin
        // Wait a bit after reset.
        #100;
        for (i = 1; i <= 20; i = i + 1) begin
            // Convert integer i to Q16.16 by shifting left 16 bits.
            rad = i << FBITS;

            // Issue a one-cycle start pulse.
            start = 1;
            #10;
            start = 0;

            // Wait long enough for the pipeline to complete.
            #600;

            // Convert from Q16.16 to real.
            rad_real  = $itor(rad)  / 65536.0;
            root_real = $itor(root) / 65536.0;
            rem_real  = $itor(rem)  / 65536.0;

            // Print final result in decimal format.
            $display("Time=%0t: sqrt(%0.8f) = %0.8f (remainder=%0.8f), valid=%b",
                     $time, rad_real, root_real, rem_real, valid);
        end

        $finish;
    end

endmodule
