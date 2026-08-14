// capture_tb.v — self-checking testbench for the LA capture buffer.
// Arms the buffer, streams DEPTH known samples (one strobe every few clocks),
// waits for `full`, then reads every slot back and checks it. Prints PASS/FAIL.
//
//   run:  make sim-capture
//   wave: gtkwave build/capture_tb.vcd
`timescale 1ns/1ps
module capture_tb;
    localparam DEPTH = 8, AW = 3;

    reg              clk = 0, arm = 0, sample_stb = 0;
    reg  [7:0]       sample = 0;
    reg  [AW-1:0]    raddr = 0;
    wire             capturing, full;
    wire [7:0]       rdata;

    capture #(.DEPTH(DEPTH), .AW(AW)) dut (
        .clk(clk), .sample(sample), .sample_stb(sample_stb), .arm(arm),
        .capturing(capturing), .full(full), .raddr(raddr), .rdata(rdata)
    );

    always #5 clk = ~clk;

    reg [7:0] expected [0:DEPTH-1];
    integer   i, errors = 0;

    initial begin
        $dumpfile("build/capture_tb.vcd");
        $dumpvars(0, capture_tb);
        for (i = 0; i < DEPTH; i = i + 1) expected[i] = 8'hA0 + i;  // distinct pattern A0..A7

        // idle a few clocks
        repeat (3) @(posedge clk);

        // arm for one clock
        @(posedge clk); #1 arm = 1;
        @(posedge clk); #1 arm = 0;

        // stream DEPTH samples, one strobe every 3 clocks
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk); #1 sample = expected[i]; sample_stb = 1;
            @(posedge clk); #1 sample_stb = 0;
            @(posedge clk);                          // gap between strobes
        end

        // wait for full (bounded)
        i = 0;
        while (!full && i < 100) begin @(posedge clk); i = i + 1; end
        if (!full) begin $display("FAIL  capture: `full` never asserted"); $finish; end

        // read every slot back and check
        for (i = 0; i < DEPTH; i = i + 1) begin
            raddr = i[AW-1:0]; #1;
            if (rdata !== expected[i]) begin
                errors = errors + 1;
                $display("  FAIL addr %0d: rdata=%h expected=%h", i, rdata, expected[i]);
            end else begin
                $display("  ok   addr %0d: %h", i, rdata);
            end
        end

        $display("----");
        if (errors == 0) $display("PASS  capture: %0d/%0d samples stored correctly", DEPTH, DEPTH);
        else             $display("FAIL  capture: %0d error(s)", errors);
        $finish;
    end

    // safety timeout
    initial begin
        #20000;
        $display("FAIL  capture: timeout");
        $finish;
    end
endmodule
