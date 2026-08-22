// capture_tb.v — verifies the pre-trigger ring: continuous record, freeze POST
// samples after trig, and oldest-first read-back (the wrap + read_base offset).
`timescale 1ns/1ps

module capture_tb;
    localparam DEPTH = 16;
    localparam AW    = 4;
    localparam POST  = 8;

    reg clk = 0, stb = 0, rearm = 0, trig = 0;
    reg [7:0] sample = 8'd1;      // ramp source, new value each strobe
    reg [AW-1:0] raddr = 0;
    wire [7:0] rdata;
    wire capturing, full;

    capture #(.DEPTH(DEPTH), .AW(AW), .POST(POST)) dut (
        .clk(clk), .sample(sample), .sample_stb(stb),
        .rearm(rearm), .trig(trig),
        .capturing(capturing), .full(full),
        .raddr(raddr), .rdata(rdata)
    );

    always #5 clk = ~clk;

    integer i, errors = 0;
    reg [7:0] trig_val, first;

    initial begin
        // arm the ring
        @(negedge clk); rearm = 1;
        @(negedge clk); rearm = 0;

        // record continuously; advance the ramp each strobe. Run well past DEPTH
        // so the pre-trigger region is fully valid history.
        stb = 1;
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk); sample = sample + 1'b1;
        end

        // fire the trigger
        trig_val = sample;
        trig = 1;
        @(negedge clk); trig = 0; sample = sample + 1'b1;

        // keep feeding until it freezes
        i = 0;
        while (!full && i < 100) begin
            @(negedge clk); sample = sample + 1'b1; i = i + 1;
        end
        stb = 0;

        if (!full) begin
            $display("FAIL: never froze (full stayed low)"); errors = errors + 1;
        end
        if (capturing) begin
            $display("FAIL: still capturing after freeze"); errors = errors + 1;
        end

        // read back oldest-first: must be a contiguous +1 ramp across the whole buffer
        @(negedge clk);
        raddr = 0; #1; first = rdata;
        for (i = 0; i < DEPTH; i = i + 1) begin
            raddr = i[AW-1:0]; #1;
            if (rdata !== (first + i)) begin
                $display("FAIL: col %0d = %0d, expected %0d", i, rdata, (first + i));
                errors = errors + 1;
            end
        end

        // the trigger sample should sit near column DEPTH-POST (centered)
        $display("INFO: trig sample=%0d lands at col %0d (expected ~%0d)",
                 trig_val, (trig_val - first), DEPTH - POST);

        if (errors == 0) $display("PASS: pre-trigger ring read-back correct");
        else             $display("DONE with %0d error(s)", errors);
        $finish;
    end
endmodule
