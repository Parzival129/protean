// gb_boot_tb.v — is the core alive? Wire gb_clock + boy + gb_cart with the
// placeholder ROM (all 0x00 = NOPs). On reset the CPU starts at 0x0000, slides
// through the zero boot ROM, and should climb into cartridge space (a >= 0x0100)
// with no fault. That proves clock + reset + boot handoff + cart read all work.
`timescale 1ns/1ps

module gb_boot_tb;
    reg clk_in = 0;
    always #18 clk_in = ~clk_in;   // ~27 MHz

    wire clk_gb, rst;
    gb_clock dut_clk (.clk_in(clk_in), .rst_btn(1'b0), .clk_gb(clk_gb), .rst(rst));

    wire [15:0] a;
    wire [7:0]  d_to_cpu, d_fr_cpu;
    wire        rd, wr;
    wire        hs, vs, cpl, valid;
    wire [1:0]  pixel;
    wire [15:0] left, right;
    wire        done, fault;

    boy dut_boy (
        .rst(rst), .clk(clk_gb), .phi(),
        .a(a), .dout(d_fr_cpu), .din(d_to_cpu), .wr(wr), .rd(rd),
        .key(8'h00),
        .hs(hs), .vs(vs), .cpl(cpl), .pixel(pixel), .valid(valid),
        .left(left), .right(right), .done(done), .fault(fault)
    );

    gb_cart dut_cart (
        .clk(clk_gb), .a(a), .rd(rd), .wr(wr),
        .data_from_cpu(d_fr_cpu), .data_to_cpu(d_to_cpu)
    );

    reg reached_cart = 0;
    reg saw_fault = 0;

    always @(posedge clk_gb) begin
        if (!rst) begin
            if (a >= 16'h0100 && a < 16'h8000) reached_cart <= 1;
            if (fault) saw_fault <= 1;
        end
    end

    initial begin
        $dumpfile("build/gb_boot.vcd");
        $dumpvars(0, gb_boot_tb);
        // run long enough to slide 0x0000 -> past 0x0100 (256 NOPs @ 4 M-cycles)
        repeat (40000) @(posedge clk_in);

        $display("--- gb_boot_tb ---");
        $display("max/last cart addr seen crossing: reached_cart=%0d", reached_cart);
        $display("fault seen: %0d", saw_fault);
        if (reached_cart && !saw_fault)
            $display("PASS: CPU came out of reset and fetched from cartridge space.");
        else
            $display("FAIL: CPU never reached cart space (or faulted).");
        $finish;
    end
endmodule
