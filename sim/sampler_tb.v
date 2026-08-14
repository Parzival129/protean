// sampler_tb.v — self-checking testbench for the LA sampler.
// Drives a sequence of known probe values and checks that each strobed sample
// matches. DIV is overridden small so sim runs fast. Prints PASS/FAIL + error count.
//
//   run:  make sim-sampler
//   wave: gtkwave build/sampler_tb.vcd
`timescale 1ns/1ps
module sampler_tb;
    reg        clk = 0;
    reg  [7:0] probes = 8'h00;
    wire [7:0] sample;
    wire       sample_stb;

    // small divider for sim; enough clocks between strobes for the 2-FF sync to settle
    localparam DIV = 8;
    sampler #(.DIV(DIV)) dut (.clk(clk), .probes(probes), .sample(sample), .sample_stb(sample_stb));

    always #5 clk = ~clk;  // 100 MHz sim clock

    // known test vectors — one checked per strobe
    reg [7:0] vec [0:4];
    integer   vi = 0, seen = 0, errors = 0;

    initial begin
        vec[0] = 8'h00; vec[1] = 8'hFF; vec[2] = 8'hA5; vec[3] = 8'h3C; vec[4] = 8'h81;
        probes = vec[0];
        $dumpfile("build/sampler_tb.vcd");
        $dumpvars(0, sampler_tb);
    end

    // on each sample strobe: compare, then advance probes to the next vector
    always @(posedge clk) begin
        if (sample_stb) begin
            if (sample !== probes) begin
                errors = errors + 1;
                $display("  FAIL strobe %0d: sample=%h expected=%h", seen, sample, probes);
            end else begin
                $display("  ok   strobe %0d: sample=%h", seen, sample);
            end
            seen = seen + 1;
            vi   = vi + 1;
            if (vi <= 4) probes <= vec[vi];
            if (seen == 5) begin
                $display("----");
                if (errors == 0) $display("PASS  sampler: 5/5 samples correct");
                else             $display("FAIL  sampler: %0d error(s)", errors);
                $finish;
            end
        end
    end

    // safety timeout so a broken DUT (no strobe) doesn't hang the run
    initial begin
        #10000;
        $display("FAIL  sampler: timeout — no/too-few strobes (check your divider)");
        $finish;
    end
endmodule
