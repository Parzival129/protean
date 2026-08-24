// i2c_master_tb.v — fake-CardKB harness for the RTL I2C master.
// Models the open-drain bus (wired-AND) and a slave that receives the address,
// ACKs it, then sends a known keycode back — exercising the full read transaction.
`timescale 1ns/1ps

module i2c_master_tb;
    localparam [7:0] EXPECT_ADDR = {7'h5F, 1'b1};   // {addr, read} = 0xBF
    localparam [7:0] KEYVAL      = 8'h41;            // 'A' — what the fake CardKB returns

    reg clk = 0;
    reg start = 0;
    wire scl_oe, sda_oe, busy, valid;
    wire [7:0] key;

    // --- open-drain bus: high unless someone pulls low ---
    wire scl = scl_oe ? 1'b0 : 1'b1;                 // SCL is master-only
    reg  slave_pull = 0;                              // slave pulling SDA low
    wire sda = (sda_oe || slave_pull) ? 1'b0 : 1'b1;  // wired-AND of master + slave

    i2c_master #(.ADDR(7'h5F), .DIV(4)) dut (
        .clk(clk), .start(start),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_in(sda),
        .key(key), .valid(valid), .busy(busy)
    );

    always #5 clk = ~clk;

    // --- slave model: receive address + ACK, then send KEYVAL ---
    localparam S_IDLE = 0, S_ADDR = 1, S_ACK = 2, S_SEND = 3, S_DONE = 4;
    reg [2:0] sstate = S_IDLE;
    reg [7:0] sh = 0;
    integer   sbit = 0;

    // START / STOP: SDA edge while SCL high
    always @(negedge sda) if (scl === 1'b1) begin sstate <= S_ADDR; sbit <= 0; slave_pull <= 0; end
    always @(posedge sda) if (scl === 1'b1) begin sstate <= S_IDLE; slave_pull <= 0; end

    // sample / advance on rising SCL (master's clock)
    always @(posedge scl) begin
        case (sstate)
            S_ADDR: begin
                sh <= {sh[6:0], sda};
                if (sbit == 7) begin sstate <= S_ACK; sbit <= 0; end else sbit <= sbit + 1;
            end
            S_ACK:  begin sstate <= S_SEND; sbit <= 0; end
            S_SEND: begin
                if (sbit == 7) begin sstate <= S_DONE; sbit <= 0; end else sbit <= sbit + 1;
            end
        endcase
    end

    // set up SDA on falling SCL
    always @(negedge scl) begin
        case (sstate)
            S_ACK:  slave_pull <= 1;                  // ack the address
            S_SEND: slave_pull <= ~KEYVAL[7 - sbit];  // present data bit, msb first
            default: slave_pull <= 0;
        endcase
    end

    // catch the valid pulse
    reg got_valid = 0;
    reg [7:0] got_key = 0;
    always @(posedge clk) if (valid) begin got_valid <= 1; got_key <= key; end

    integer i;
    initial begin
        repeat (20) @(posedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        for (i = 0; i < 8000 && (busy || sstate != S_IDLE); i = i + 1) @(posedge clk);
        repeat (10) @(posedge clk);

        $display("INFO: slave saw address 0x%02h; master read key 0x%02h (valid=%0b)", sh, got_key, got_valid);
        if (sh === EXPECT_ADDR && got_valid && got_key === KEYVAL)
            $display("PASS: full read transaction — address out, ACK, data byte in");
        else if (sh !== EXPECT_ADDR)
            $display("FAIL: address wrong (0x%02h) — check START + address shift", sh);
        else if (!got_valid)
            $display("FAIL: valid never pulsed — check DATA state -> key latch");
        else
            $display("FAIL: key mismatch (got 0x%02h, expected 0x%02h) — check receive shift / sample phase", got_key, KEYVAL);
        $finish;
    end

    initial begin
        #8_000_000;
        $display("FAIL: timeout — transaction never finished (busy stuck?)");
        $finish;
    end
endmodule
