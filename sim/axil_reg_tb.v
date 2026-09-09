`timescale 1ns/1ps
// axil_reg_tb: a tiny AXI4-Lite master BFM that exercises axil_reg.

module axil_reg_tb;

    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;   // 100 MHz

    // master-driven stimulus / slave outputs
    reg  [31:0] awaddr = 0;  reg awvalid = 0;  wire awready;
    reg  [31:0] wdata  = 0;  reg [3:0] wstrb = 0; reg wvalid = 0; wire wready;
    wire [ 1:0] bresp;       wire bvalid;       reg bready = 0;
    reg  [31:0] araddr = 0;  reg arvalid = 0;  wire arready;
    wire [31:0] rdata;       wire [1:0] rresp;  wire rvalid; reg rready = 0;

    integer errors = 0;
    reg [31:0] rd;

    axil_reg dut (
        .clk(clk), .resetn(resetn),
        .s_awaddr(awaddr), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rvalid(rvalid), .s_rready(rready)
    );

    // AXI4-Lite write: present AW+W together, hold bready, wait for the B beat
    task axi_write(input [31:0] addr, input [31:0] wd, input [3:0] strb);
        begin
            @(negedge clk);
            awaddr <= addr; awvalid <= 1;
            wdata  <= wd;   wstrb   <= strb; wvalid <= 1;
            bready <= 1;
            @(posedge clk);
            while (!bvalid) @(posedge clk);       // B beat completes the write
            if (bresp !== 2'b00) begin
                $display("  FAIL: write bresp=%b (expected OKAY)", bresp);
                errors = errors + 1;
            end
            @(negedge clk);
            awvalid <= 0; wvalid <= 0; bready <= 0;
        end
    endtask

    // AXI4-Lite read: present AR, hold rready, capture on the R beat
    task axi_read(input [31:0] addr, output [31:0] data_out);
        begin
            @(negedge clk);
            araddr <= addr; arvalid <= 1; rready <= 1;
            @(posedge clk);
            while (!rvalid) @(posedge clk);   // R beat delivers the data
            data_out = rdata;
            if (rresp !== 2'b00) begin
                $display("  FAIL: read rresp=%b (expected OKAY)", rresp);
                errors = errors + 1;
            end
            @(negedge clk);
            arvalid <= 0; rready <= 0;
        end
    endtask

    task expect_eq(input [31:0] got, input [31:0] exp, input [127:0] label);
        begin
            if (got === exp) $display("  PASS: %-0s = 0x%08x", label, got);
            else begin
                $display("  FAIL: %-0s = 0x%08x (expected 0x%08x)", label, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // reset
        resetn = 0;
        repeat (4) @(posedge clk);
        resetn = 1;
        @(negedge clk);

        $display("T1: full-word write/read-back");
        axi_write(32'h0, 32'hDEAD_BEEF, 4'b1111);
        axi_read (32'h0, rd);
        expect_eq(rd, 32'hDEAD_BEEF, "readback");

        $display("T2: byte-strobe merge (wstrb=0010, only byte1 -> 0xCC)");
        axi_write(32'h0, 32'hAABB_CCDD, 4'b0010);
        axi_read (32'h0, rd);
        expect_eq(rd, 32'hDEAD_CCEF, "merged");   // byte1 CC over DEADBEEF

        $display("T3: second full-word write/read-back");
        axi_write(32'h0, 32'h1234_5678, 4'b1111);
        axi_read (32'h0, rd);
        expect_eq(rd, 32'h1234_5678, "readback");

        if (errors == 0) $display("\nALL TESTS PASSED");
        else             $display("\n%0d FAILURE(S)", errors);
        $finish;
    end

    // watchdog: a stuck handshake would otherwise hang forever
    initial begin
        #100000;
        $display("\nTIMEOUT — a handshake never completed (likely a stuck VALID/READY)");
        $finish;
    end

endmodule
