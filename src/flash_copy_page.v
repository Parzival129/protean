// Single-page copy: read a block from a SOURCE address into a fabric buffer,
// then page-program that buffer to a DIFFERENT DEST address, then verify.
// Data moves A->B through rbuf[] instead of being hard-coded in RTL.
//
// Source 0x200000, Dest 0x200800 (a different page in the SAME 4KB sector that
// `make flasherase` blanks to 0xFF, so the dest is already erased). Verify
// reads dest+3 = 0x200803, expecting rbuf[3] = 0x24 -> LEDs 2,5.
//
// Precondition: `make flasherase && make flashcopy` lays {A5,3C,18,24} at
// 0x200000 (and leaves the rest of the sector 0xFF). Then run this WITHOUT
// erasing again.

module flash_copy_page(
    input wire clk,
    output reg cs = 1'b1, // chip select
    output wire sclk,  // form the byte engine
    output wire mosi, // from byte engine
    input wire miso, // to spi byte engine
    output reg [5:0] led = 6'b111111 // for testing
);


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

    // Each logical phase gets its OWN state name (no duplicates -> no dead arms).
    localparam IDLE          = 5'd0,
                SRC_KICK      = 5'd1,   // send 0x03 + source address
                SRC_WAIT      = 5'd2,
                STREAM_KICK   = 5'd3,   // clock dummies, stream bytes into rbuf
                STREAM_WAIT   = 5'd4,
                WRT_KICK      = 5'd5,   // WREN (0x06)
                WRT_WAIT      = 5'd6,
                SEND_KICK     = 5'd7,   // page program 0x02 + dest addr + rbuf[]
                SEND_WAIT     = 5'd8,
                POLL_KICK     = 5'd9,   // status read command (0x05)
                POLL_WAIT     = 5'd10,
                READ_KICK     = 5'd11,  // status byte (WIP poll)
                READ_WAIT     = 5'd12,
                VER_KICK      = 5'd13,  // verify: 0x03 + verify address
                VER_WAIT      = 5'd14,
                VER_READ_KICK = 5'd15,  // verify data byte
                VER_READ_WAIT = 5'd16,
                DONE          = 5'd17;

    reg [4:0] state = IDLE;
    reg [2:0] counter = 3'd0;   // which command byte to send (0..7)
    reg [1:0] ridx = 2'd0;      // which rbuf slot to fill during the stream
    reg [7:0] result;           // byte read back during verify

    reg [23:0] saddr = 24'h200000; // source
    reg [23:0] daddr = 24'h200800; // dest (same erased sector, different page)
    reg [23:0] vaddr = 24'h200803; // verify read = dest + 3

    reg [7:0] rbuf [0:3];

    always @(posedge clk) begin
        start <= 1'b0;              // default: only the KICK states override it

        case (state)
            IDLE: begin
                cs <= 1'b0;
                state <= SRC_KICK;
            end

            // --- Read the source block into rbuf --------------------------
            SRC_KICK: begin
                cs <= 1'b0;
                case (counter)
                    3'd0: tx <= 8'h03;            // read data command
                    3'd1: tx <= saddr[23:16];
                    3'd2: tx <= saddr[15:8];
                    3'd3: tx <= saddr[7:0];
                endcase
                start <= 1'b1;
                state <= SRC_WAIT;
            end

            SRC_WAIT: begin
                if (done && counter < 3'd3) begin
                    counter <= counter + 1'd1;
                    state <= SRC_KICK;
                end
                if (done && counter == 3'd3) begin
                    counter <= 3'd0;
                    state <= STREAM_KICK;
                end
            end

            STREAM_KICK: begin
                // CS stays low -- same frame; flash auto-increments the address
                tx <= 8'h00;
                start <= 1'b1;
                state <= STREAM_WAIT;
            end

            STREAM_WAIT: begin
                if (done) begin
                    rbuf[ridx] <= rx;
                    ridx <= ridx + 1'd1;
                    state <= STREAM_KICK;
                    if (ridx == 2'd3) begin
                        cs <= 1'b1;          // close the read frame
                        state <= WRT_KICK;
                    end
                end
            end

            // --- Arm the write --------------------------------------------
            WRT_KICK: begin
                cs <= 1'b0;                  // fresh frame for WREN
                tx <= 8'h06;
                start <= 1'b1;
                state <= WRT_WAIT;
            end

            WRT_WAIT: begin
                if (done) begin
                    cs <= 1'b1;              // CS rise commits WEL
                    state <= SEND_KICK;
                end
            end

            // --- Page-program rbuf to the dest ----------------------------
            SEND_KICK: begin
                cs <= 1'b0;
                case (counter)
                    3'd0: tx <= 8'h02;           // page program command
                    3'd1: tx <= daddr[23:16];
                    3'd2: tx <= daddr[15:8];
                    3'd3: tx <= daddr[7:0];
                    3'd4: tx <= rbuf[0];         // data comes FROM the buffer
                    3'd5: tx <= rbuf[1];
                    3'd6: tx <= rbuf[2];
                    3'd7: tx <= rbuf[3];
                endcase
                start <= 1'b1;
                state <= SEND_WAIT;
            end

            SEND_WAIT: begin
                if (done && counter < 3'd7) begin
                    counter <= counter + 1'd1;
                    state <= SEND_KICK;
                end
                if (done && counter == 3'd7) begin
                    counter <= 3'd0;
                    cs <= 1'b1;              // CS rise begins the program
                    state <= POLL_KICK;
                end
            end

            // --- Wait for the program to finish (WIP poll) ----------------
            POLL_KICK: begin
                cs <= 1'b0;
                tx <= 8'h05;
                start <= 1'b1;
                state <= POLL_WAIT;
            end

            POLL_WAIT: begin
                if (done) state <= READ_KICK;
            end

            READ_KICK: begin
                tx <= 8'h00;
                start <= 1'b1;
                state <= READ_WAIT;
            end

            READ_WAIT: begin
                if (done) begin
                    cs <= 1'b1;
                    counter <= 3'd0;
                    state <= VER_KICK;
                    if (rx[0] == 1'b1) state <= POLL_KICK;  // still busy: poll again
                end
            end

            // --- Verify the copy landed at the dest -----------------------
            VER_KICK: begin
                cs <= 1'b0;
                case (counter)
                    3'd0: tx <= 8'h03;
                    3'd1: tx <= vaddr[23:16];
                    3'd2: tx <= vaddr[15:8];
                    3'd3: tx <= vaddr[7:0];
                endcase
                start <= 1'b1;
                state <= VER_WAIT;
            end

            VER_WAIT: begin
                if (done && counter < 3'd3) begin
                    counter <= counter + 1'd1;
                    state <= VER_KICK;
                end
                if (done && counter == 3'd3) begin
                    counter <= 3'd0;
                    state <= VER_READ_KICK;
                end
            end

            VER_READ_KICK: begin
                tx <= 8'h00;
                start <= 1'b1;
                state <= VER_READ_WAIT;
            end

            VER_READ_WAIT: begin
                if (done) begin
                    result <= rx;
                    state <= DONE;
                end
            end

            DONE: begin
                cs <= 1'b1;
                led <= ~result[5:0];    // expect 0x24 (LEDs 2,5) = rbuf[3] copied to dest+3
            end

        endcase
    end

endmodule
