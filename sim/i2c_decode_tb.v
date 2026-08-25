// i2c_decode_tb.v — validates the passive decoder against real bus traffic.
// Wires the actual i2c_master + a fake CardKB slave + the decoder on one open-drain
// bus, runs a read transaction, and checks the decoder recovers the same address
// and data byte that the master/slave exchanged.
`timescale 1ns/1ps

module i2c_decode_tb;
    localparam [7:0] EXPECT_ADDR = {7'h5F, 1'b1};   // 0xBF
    localparam [7:0] KEYVAL      = 8'h41;           // 'A'

    reg clk = 0, start = 0;
    wire scl_oe, sda_oe;

    // open-drain bus shared by master, slave, and (passively) the decoder
    wire scl = scl_oe ? 1'b0 : 1'b1;
    reg  slave_pull = 0;
    wire sda = (sda_oe || slave_pull) ? 1'b0 : 1'b1;

    i2c_master #(.ADDR(7'h5F), .DIV(4)) u_m (
        .clk(clk), .start(start),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_in(sda),
        .key(), .valid(), .acked(), .busy()
    );

    // fake CardKB slave: receive address + ACK, then send KEYVAL
    localparam S_IDLE=0, S_ADDR=1, S_ACK=2, S_SEND=3, S_DONE=4;
    reg [2:0] sstate = S_IDLE; reg [7:0] sh = 0; integer sbit = 0;
    always @(negedge sda) if (scl === 1'b1) begin sstate <= S_ADDR; sbit <= 0; slave_pull <= 0; end
    always @(posedge sda) if (scl === 1'b1) begin sstate <= S_IDLE; slave_pull <= 0; end
    always @(posedge scl) begin
        case (sstate)
            S_ADDR: begin sh <= {sh[6:0], sda}; if (sbit==7) begin sstate<=S_ACK; sbit<=0; end else sbit<=sbit+1; end
            S_ACK:  begin sstate<=S_SEND; sbit<=0; end
            S_SEND: begin if (sbit==7) begin sstate<=S_DONE; sbit<=0; end else sbit<=sbit+1; end
        endcase
    end
    always @(negedge scl) begin
        case (sstate)
            S_ACK:  slave_pull <= 1;
            S_SEND: slave_pull <= ~KEYVAL[7 - sbit];
            default: slave_pull <= 0;
        endcase
    end

    // the decoder under test — watches the same lines, drives nothing
    wire [7:0] d_data; wire d_valid, d_isaddr, d_ack, d_start, d_stop;
    i2c_decode dut (
        .clk(clk), .scl(scl), .sda(sda),
        .data(d_data), .data_valid(d_valid), .is_addr(d_isaddr),
        .ackd(d_ack), .start_seen(d_start), .stop_seen(d_stop)
    );

    always #5 clk = ~clk;

    // record what the decoder reports
    reg got_addr = 0, got_data = 0, saw_start = 0, saw_stop = 0;
    reg [7:0] addr_byte = 0, data_byte = 0;
    always @(posedge clk) begin
        if (d_start) saw_start <= 1;
        if (d_stop)  saw_stop  <= 1;
        if (d_valid && d_isaddr)  begin got_addr <= 1; addr_byte <= d_data; end
        if (d_valid && !d_isaddr) begin got_data <= 1; data_byte <= d_data; end
    end

    integer i, errors = 0;
    initial begin
        repeat (20) @(posedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        for (i = 0; i < 8000 && !saw_stop; i = i + 1) @(posedge clk);
        repeat (20) @(posedge clk);

        $display("INFO: decoder saw start=%0b addr=0x%02h(%0b) data=0x%02h(%0b) stop=%0b",
                 saw_start, addr_byte, got_addr, data_byte, got_data, saw_stop);
        if (!saw_start)                 begin $display("FAIL: no START detected"); errors=errors+1; end
        if (!got_addr || addr_byte!==EXPECT_ADDR) begin $display("FAIL: address wrong/missing"); errors=errors+1; end
        if (!got_data || data_byte!==KEYVAL)      begin $display("FAIL: data wrong/missing"); errors=errors+1; end
        if (!saw_stop)                  begin $display("FAIL: no STOP detected"); errors=errors+1; end
        if (errors==0) $display("PASS: decoder recovered START, address 0x%02h, data 0x%02h, STOP", addr_byte, data_byte);
        $finish;
    end

    initial begin #6_000_000; $display("FAIL: timeout"); $finish; end
endmodule
