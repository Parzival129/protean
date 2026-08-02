module flash_switch(
    input wire clk,
    input wire btn, // to kick off fabric switch
    output reg cs = 1'b1, // chip select
    output wire sclk,  // form the byte engine
    output wire mosi, // from byte engine
    input wire miso, // to spi byte engine
    output reg [5:0] led = 6'b111111, // for testing
    output reg recfg_n = 1'b1 // reboot pin! => boot from address 0x0
);

    parameter COPY_LEN = 24'd4096; // how many bytes to copy (override from the Makefile)

    // how many whole pages and 64k blocks cover COPY_LEN (round up)
    localparam PAGES  = (COPY_LEN + 255) / 256;
    localparam BLOCKS = (COPY_LEN + 65535) / 65536;
    localparam TOTAL  = PAGES * 256; // bytes we actually touch (padded up to a page)

    reg start;
    reg [7:0] tx;
    wire done;
    wire [7:0] rx;

    spi u_spi ( // instantiate byte engine
        .clk(clk),
        .start(start),
        .tx(tx),
        .done(done),
        .rx(rx),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .led()
    );

    localparam IDLE = 5'd0, // step up FSM states
                E_WREN_KICK = 5'd1,   // erase: write enable
                E_WREN_WAIT = 5'd2,
                E_CMD_KICK  = 5'd3,   // erase: 0xD8 + 24 bit block address
                E_CMD_WAIT  = 5'd4,
                E_POLL_KICK = 5'd5,   // erase: read status (0x05)
                E_POLL_WAIT = 5'd6,
                E_STAT_KICK = 5'd7,   // erase: dummy byte, check WIP, loop or next block
                E_STAT_WAIT = 5'd8,
                R_CMD_KICK  = 5'd9,   // copy: 0x03 + 24 bit source address
                R_CMD_WAIT  = 5'd10,
                R_BYTE_KICK = 5'd11,  // copy: stream 256 bytes into rbuf
                R_BYTE_WAIT = 5'd12,
                C_WREN_KICK = 5'd13,  // copy: write enable before the program
                C_WREN_WAIT = 5'd14,
                P_CMD_KICK  = 5'd15,  // copy: 0x02 + 24 bit dest address
                P_CMD_WAIT  = 5'd16,
                P_BYTE_KICK = 5'd17,  // copy: send 256 bytes out of rbuf
                P_BYTE_WAIT = 5'd18,
                P_POLL_KICK = 5'd19,  // copy: read status (0x05)
                P_POLL_WAIT = 5'd20,
                P_STAT_KICK = 5'd21,  // copy: dummy byte, check WIP, loop or next page
                P_STAT_WAIT = 5'd22,
                V_CMD_KICK  = 5'd23,  // verify: 0x03 + 24 bit dest address
                V_CMD_WAIT  = 5'd24,
                V_BYTE_KICK = 5'd25,  // verify: stream the whole dest back
                V_BYTE_WAIT = 5'd26,
                DONE = 5'd27;

    reg [4:0] state = IDLE;
    reg [1:0] counter = 2'd0;   // which opcode/address byte to send (0..3)
    reg [8:0] bcount = 9'd0;    // which byte inside the 256 byte page
    reg [15:0] page = 16'd0;    // which page were copying
    reg [7:0] blk = 8'd0;       // which 64k block were erasing
    reg [23:0] eaddr = 24'h000000; // erase address, walks the dest block by block
    reg [23:0] saddr = 24'h200000; // source address to read from
    reg [23:0] daddr = 24'h000000; // dest address to program to
    reg [23:0] vaddr = 24'h000000; // dest address to verify from
    reg [23:0] vcount = 24'd0;  // bytes left to stream during verify
    reg [15:0] rsum = 16'd0;    // checksum of everything read from the source
    reg [15:0] vsum = 16'd0;    // checksum of everything read back from the dest

    reg [7:0] rbuf [0:255];     // one page of data on its way across

    reg [24:0] blinker = 0;

    always @(posedge clk) begin
        start <= 1'b0;              // default: only the KICK states override it

        case (state)
            IDLE: begin
                cs <= 1'b0;
                eaddr <= 24'h000000;
                blk <= 8'd0;
                counter <= 2'd0;

                led <= ~{5'b0, blinker[24]};
                blinker <= blinker + 1;
                if (btn == 1) state <= E_WREN_KICK;
            end

            // IDLE: begin
            //     cs <= 1'b0;
            //     eaddr <= 24'h300000;
            //     blk <= 8'd0;
            //     counter <= 2'd0;

            //     led <= ~{5'b0, blinker[24]};
            //     blinker <= blinker + 1;
            //     // if (btn == 0) state <= E_WREN_KICK;   // <-- comment this out for the test
            // end

            // erase the dest, one 64k block at a time 
            E_WREN_KICK: begin
                cs <= 1'b0;
                tx <= 8'h06; // write enable
                start <= 1'b1;
                state <= E_WREN_WAIT;
            end

            E_WREN_WAIT: begin
                if (done) begin
                    cs <= 1'd1; // WEL latches on the cs rise
                    state <= E_CMD_KICK;
                end
            end

            E_CMD_KICK: begin
                cs <= 1'b0;
                case (counter)
                    2'd0: tx <= 8'hD8; // 64k block erase
                    2'd1: tx <= eaddr[23:16];
                    2'd2: tx <= eaddr[15:8];
                    2'd3: tx <= eaddr[7:0];
                endcase
                start <= 1'b1;
                state <= E_CMD_WAIT;
            end

            E_CMD_WAIT: begin
                if (done && counter < 2'd3) begin
                    counter <= counter + 1'd1;
                    state <= E_CMD_KICK;
                end
                if (done && counter == 2'd3) begin
                    counter <= 2'd0;
                    cs <= 1'd1; // cs rise kicks off the erase
                    state <= E_POLL_KICK;
                end
            end

            E_POLL_KICK: begin
                cs <= 1'b0;
                tx <= 8'h05;
                start <= 1'b1;
                state <= E_POLL_WAIT;
            end

            E_POLL_WAIT: begin
                if (done) state <= E_STAT_KICK;
            end

            E_STAT_KICK: begin
                tx <= 8'h00;
                start <= 1'b1;
                state <= E_STAT_WAIT;
            end

            E_STAT_WAIT: begin
                if (done) begin
                    cs <= 1'd1;
                    if (rx[0] == 1) begin
                        state <= E_POLL_KICK; // still busy erasing
                    end else if (blk < BLOCKS - 1) begin
                        blk <= blk + 1'd1;
                        eaddr <= eaddr + 24'h10000; // next 64k block
                        state <= E_WREN_KICK;
                    end else begin
                        // dest is blank, set up the copy loop
                        page <= 16'd0;
                        saddr <= 24'h200000;
                        daddr <= 24'h000000;
                        rsum <= 16'd0;
                        counter <= 2'd0;
                        state <= R_CMD_KICK;
                    end
                end
            end

            // read one page from the source into rbuf 
            R_CMD_KICK: begin
                cs <= 1'b0;
                case (counter)
                    2'd0: tx <= 8'h03;
                    2'd1: tx <= saddr[23:16];
                    2'd2: tx <= saddr[15:8];
                    2'd3: tx <= saddr[7:0];
                endcase
                start <= 1'b1;
                state <= R_CMD_WAIT;
            end

            R_CMD_WAIT: begin
                if (done && counter < 2'd3) begin
                    counter <= counter + 1'd1;
                    state <= R_CMD_KICK;
                end
                if (done && counter == 2'd3) begin
                    counter <= 2'd0;
                    bcount <= 9'd0;
                    state <= R_BYTE_KICK;
                end
            end

            R_BYTE_KICK: begin
                tx <= 8'h00; // cs stays low, the flash auto increments for us
                start <= 1'b1;
                state <= R_BYTE_WAIT;
            end

            R_BYTE_WAIT: begin
                if (done) begin
                    rbuf[bcount[7:0]] <= rx;
                    rsum <= rsum + rx;
                    bcount <= bcount + 1'd1;
                    state <= R_BYTE_KICK;
                    if (bcount == 9'd255) begin
                        cs <= 1'd1; // done with the read, close the frame
                        state <= C_WREN_KICK;
                    end
                end
            end

            // program that page out to the dest
            C_WREN_KICK: begin
                cs <= 1'b0;
                tx <= 8'h06;
                start <= 1'b1;
                state <= C_WREN_WAIT;
            end

            C_WREN_WAIT: begin
                if (done) begin
                    cs <= 1'd1;
                    state <= P_CMD_KICK;
                end
            end

            P_CMD_KICK: begin
                cs <= 1'b0;
                case (counter)
                    2'd0: tx <= 8'h02; // page program
                    2'd1: tx <= daddr[23:16];
                    2'd2: tx <= daddr[15:8];
                    2'd3: tx <= daddr[7:0];
                endcase
                start <= 1'b1;
                state <= P_CMD_WAIT;
            end

            P_CMD_WAIT: begin
                if (done && counter < 2'd3) begin
                    counter <= counter + 1'd1;
                    state <= P_CMD_KICK;
                end
                if (done && counter == 2'd3) begin
                    counter <= 2'd0;
                    bcount <= 9'd0;
                    state <= P_BYTE_KICK;
                end
            end

            P_BYTE_KICK: begin
                tx <= rbuf[bcount[7:0]]; // data comes back out of the buffer
                start <= 1'b1;
                state <= P_BYTE_WAIT;
            end

            P_BYTE_WAIT: begin
                if (done) begin
                    bcount <= bcount + 1'd1;
                    state <= P_BYTE_KICK;
                    if (bcount == 9'd255) begin
                        cs <= 1'd1; // cs rise starts the program
                        state <= P_POLL_KICK;
                    end
                end
            end

            P_POLL_KICK: begin
                cs <= 1'b0;
                tx <= 8'h05;
                start <= 1'b1;
                state <= P_POLL_WAIT;
            end

            P_POLL_WAIT: begin
                if (done) state <= P_STAT_KICK;
            end

            P_STAT_KICK: begin
                tx <= 8'h00;
                start <= 1'b1;
                state <= P_STAT_WAIT;
            end

            P_STAT_WAIT: begin
                if (done) begin
                    cs <= 1'd1;
                    if (rx[0] == 1) begin
                        state <= P_POLL_KICK; // still busy programming
                    end else if (page < PAGES - 1) begin
                        page <= page + 1'd1;
                        saddr <= saddr + 24'd256;
                        daddr <= daddr + 24'd256;
                        counter <= 2'd0;
                        state <= R_CMD_KICK; // go do the next page
                    end else begin
                        // every page copied, go check our work
                        vaddr <= 24'h000000;
                        vcount <= TOTAL;
                        vsum <= 16'd0;
                        counter <= 2'd0;
                        state <= V_CMD_KICK;
                    end
                end
            end

            //  read the whole dest back in one stream and checksum it 
            V_CMD_KICK: begin
                cs <= 1'b0;
                case (counter)
                    2'd0: tx <= 8'h03;
                    2'd1: tx <= vaddr[23:16];
                    2'd2: tx <= vaddr[15:8];
                    2'd3: tx <= vaddr[7:0];
                endcase
                start <= 1'b1;
                state <= V_CMD_WAIT;
            end

            V_CMD_WAIT: begin
                if (done && counter < 2'd3) begin
                    counter <= counter + 1'd1;
                    state <= V_CMD_KICK;
                end
                if (done && counter == 2'd3) begin
                    counter <= 2'd0;
                    state <= V_BYTE_KICK;
                end
            end

            V_BYTE_KICK: begin
                tx <= 8'h00; // one long read, cs never rises till were done
                start <= 1'b1;
                state <= V_BYTE_WAIT;
            end

            V_BYTE_WAIT: begin
                if (done) begin
                    vsum <= vsum + rx;
                    vcount <= vcount - 1'd1;
                    state <= V_BYTE_KICK;
                    if (vcount == 24'd1) begin
                        cs <= 1'd1; // last byte, close the frame
                        state <= DONE;
                    end
                end
            end

            DONE: begin
                cs <= 1'd1;
                if (rsum == vsum) begin
                    led <= ~6'b010101; // checksums match! LEDs 0,2,4, data has been copied over successfully!
                    recfg_n <= 1'b0; // pulse recfg, rebooting the FPGA from the 0x0 boot address
                    end 
                    else
                    led <= ~6'b101010; // mismatch, LEDs 1,3,5
            end

        endcase
    end

endmodule
