// trigger_tb.v — self-checking testbench for the LA edge trigger.
// Watches channel 2, rising edge. Establishes a low baseline, arms, holds low
// (must NOT fire), drives a 0->1 edge (must fire once), then more edges while
// disarmed (must stay quiet). Prints PASS/FAIL.
//
//   run:  make sim-trigger
//   wave: gtkwave build/trigger_tb.vcd
`timescale 1ns/1ps
module trigger_tb;
    reg        clk = 0, arm = 0, sample_stb = 0;
    reg  [7:0] sample = 0;
    reg  [2:0] sel  = 3'd2;
    reg  [1:0] mode = 2'b00;   // rising
    wire       trig, armed;

    trigger dut (
        .clk(clk), .sample(sample), .sample_stb(sample_stb), .arm(arm),
        .sel(sel), .mode(mode), .trig(trig), .armed(armed)
    );

    always #5 clk = ~clk;

    integer trig_count = 0, errors = 0;

    // count every trig pulse
    always @(posedge clk) if (trig) begin
        trig_count = trig_count + 1;
        $display("  trig fired (count=%0d) at sample=%h", trig_count, sample);
    end

    // one sample strobe carrying value v
    task strobe(input [7:0] v);
        begin
            @(posedge clk); #1 sample = v; sample_stb = 1;
            @(posedge clk); #1 sample_stb = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("build/trigger_tb.vcd");
        $dumpvars(0, trigger_tb);

        repeat (3) @(posedge clk);

        strobe(8'h00);                 // baseline: channel 2 low
        @(posedge clk); #1 arm = 1;    // arm
        @(posedge clk); #1 arm = 0;

        strobe(8'h00);                 // hold low — must NOT fire
        if (trig_count != 0) begin errors = errors + 1; $display("  FAIL: fired with no edge"); end

        strobe(8'h04);                 // channel 2 rises 0->1 — must fire
        @(posedge clk);
        if (trig_count != 1) begin errors = errors + 1; $display("  FAIL: expected 1 trig, got %0d", trig_count); end

        strobe(8'h00);                 // more edges, but disarmed now
        strobe(8'h04);
        if (trig_count != 1) begin errors = errors + 1; $display("  FAIL: re-fired while disarmed, count=%0d", trig_count); end

        $display("----");
        if (errors == 0) $display("PASS  trigger: fired once, on the rising edge, stayed disarmed");
        else             $display("FAIL  trigger: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #20000;
        $display("FAIL  trigger: timeout");
        $finish;
    end
endmodule
