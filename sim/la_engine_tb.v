// la_engine_tb.v — end-to-end test of the wired LA engine.
// Drives the probes with a free-running counter (increments every clock). Fires
// `go`, waits for the whole chain (sampler -> trigger -> capture) to complete a
// capture, then checks the stored samples.
//
// The invariant: the sampler grabs a sample every DIV clocks, so consecutive
// captured samples must differ by exactly DIV (mod 256). That single check proves
// sampling cadence, trigger->capture handoff, and in-order storage all at once.
//
//   run:  make sim-la_engine
//   wave: gtkwave build/la_engine_tb.vcd
`timescale 1ns/1ps
module la_engine_tb;
    localparam DEPTH = 8, AW = 3, DIV = 8;

    reg              clk = 0, go = 0;
    reg  [7:0]       probes = 0;
    reg  [2:0]       sel  = 3'd3;    // trigger on channel 3
    reg  [1:0]       mode = 2'b00;   // rising
    reg  [AW-1:0]    raddr = 0;
    wire             capturing, full;
    wire [7:0]       rdata;

    la_engine #(.DEPTH(DEPTH), .AW(AW), .DIV(DIV)) dut (
        .clk(clk), .probes(probes), .go(go), .sel(sel), .mode(mode),
        .capturing(capturing), .full(full), .raddr(raddr), .rdata(rdata)
    );

    always #5 clk = ~clk;

    // free-running probe source
    always @(posedge clk) probes <= probes + 8'd1;

    integer   i, errors = 0;
    reg [7:0] a, b;

    initial begin
        $dumpfile("build/la_engine_tb.vcd");
        $dumpvars(0, la_engine_tb);

        repeat (5) @(posedge clk);

        @(posedge clk); #1 go = 1;      // arm the trigger
        @(posedge clk); #1 go = 0;

        // wait for a full capture (bounded)
        i = 0;
        while (!full && i < 2000) begin @(posedge clk); i = i + 1; end
        if (!full) begin $display("FAIL  la_engine: `full` never asserted — chain broken"); $finish; end

        // consecutive captured samples must be DIV apart (mod 256)
        for (i = 0; i < DEPTH-1; i = i + 1) begin
            raddr = i[AW-1:0];        #1 a = rdata;
            raddr = (i+1) & (DEPTH-1); #1 b = rdata;
            if (((b - a) & 8'hFF) !== (DIV & 8'hFF)) begin
                errors = errors + 1;
                $display("  FAIL pair %0d: %h -> %h  delta=%0d (expected %0d)", i, a, b, (b-a)&8'hFF, DIV);
            end else begin
                $display("  ok   pair %0d: %h -> %h  delta=%0d", i, a, b, (b-a)&8'hFF);
            end
        end

        $display("----");
        if (errors == 0) $display("PASS  la_engine: triggered + captured %0d samples, all DIV apart", DEPTH);
        else             $display("FAIL  la_engine: %0d bad delta(s)", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL  la_engine: timeout");
        $finish;
    end
endmodule
