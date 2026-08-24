// i2c_master.v — minimal I2C master: read one byte from a fixed-address slave.
// Built for the CardKB (addr 0x5F): on `start`, run one transaction —
//   START -> send {ADDR, read-bit} -> slave ACK -> read 8 data bits -> master NACK -> STOP
// then present the byte on `key` and pulse `valid`. CardKB returns 0 when no key.

module i2c_master #(
    parameter [6:0] ADDR = 7'h5F,   // slave address (CardKB)
    parameter       DIV  = 64       // clocks per I2C quarter-bit (tb overrides small)
)(
    input  wire       clk,
    input  wire       start,        // 1-clock pulse: begin one read transaction
    output reg        scl_oe,       // 1 = pull SCL low, 0 = release (float high)
    output reg        sda_oe,       // 1 = pull SDA low, 0 = release (float high)
    input  wire       sda_in,       // sampled SDA line level
    output reg  [7:0] key,          // last byte read from the slave
    output reg        valid,        // 1-clock pulse: `key` just updated
    output wire       busy          // high while a transaction is running
);

    localparam IDLE  = 4'd1,
                START = 4'd2,
                TXADDR = 4'd3, // shift out {addr, read}
                ACK   = 4'd4, // read slave ack
                DATA  = 4'd5, // shift in the data byte
                NACK  = 4'd6, // master nacks the last byte
                STOP  = 4'd7;


    reg [5:0] counter = 0;
    reg [1:0] phase = 0;
    reg [3:0] bit_counter = 0;
    reg tick;
    reg [3:0] state = IDLE;
    reg pending = 0;
    reg [7:0] send_byte = {ADDR, 1'b1};
    reg [7:0] recv = 0; // data bits shifted in
    reg ackd = 0;         
    reg sda_s0, sda_s1;      

    assign busy = ((state != IDLE) || pending);

    always @(posedge clk) begin

        tick <= 0;
        valid <= 0;
        if (start) pending <= 1;

        sda_s0 <= sda_in;   // synchronize the async sda line
        sda_s1 <= sda_s0;

        counter <= counter + 1; // clock divider
        if (counter == DIV-1) begin
            tick <= 1;
            counter <= 0;
        end
        if (tick) begin // one step per quarter-bit
            phase <= phase + 1;
            if (phase == 3) phase <= 0;

            case (state)
                IDLE: begin // bus released high; on pending -> START
                    scl_oe <= 0;
                    sda_oe <= 0;
                    if (pending) begin
                        state <= START;
                        pending <= 0;
                    end
                end
                START: begin // sda low while scl high, then scl low
                    if (phase == 0) sda_oe <= 1;
                    if (phase == 1) begin 
                        scl_oe <= 1;
                        state <= TXADDR;
                        phase <= 0;
                    end
                    bit_counter <= 0;
                end
                TXADDR: begin // shift out {addr, read}, msb first, then -> ACK
                    if (bit_counter == 7 & phase == 3) begin
                        bit_counter <= 0;
                        state <= ACK;
                    end
                    if (phase == 2'd3) begin
                        bit_counter <= bit_counter + 1;
                    end

                    if (phase == 2'd0 || phase == 2'd3) begin // clock scl properly based off phase
                        scl_oe <= 1;
                    end else scl_oe <= 0;
                    if (phase == 0) sda_oe <= ~send_byte[7 - bit_counter]; // send by most significant bit first
                end
                ACK: begin // release sda, sample slave ack on scl high, then -> DATA
                    sda_oe <= 0;
                    if (phase == 2'd0 || phase == 2'd3) begin // clock scl properly based off phase
                        scl_oe <= 1;
                    end else scl_oe <= 0;
                    if (phase == 2'd2) ackd <= sda_s1;
                    if (phase == 2'd3) begin
                        state <= DATA;
                        bit_counter <= 0;
                    end
                end
                DATA: begin // shift in the data byte msb first, latch key + valid, then -> NACK
                    sda_oe <= 0;
                    if (phase == 2'd0 || phase == 2'd3) begin // clock scl properly based off phase
                        scl_oe <= 1;
                    end else scl_oe <= 0;
                    if (phase == 2'd2) recv <= {recv[6:0], sda_s1};
                    if (phase == 2'd3) begin
                        if (bit_counter == 7) begin
                            key <= recv;
                            valid <= 1;
                            state <= NACK;
                        end else bit_counter <= bit_counter + 1;
                    end

                end
                NACK: begin // leave sda high on the 9th bit = nack, then -> STOP
                    sda_oe <= 0;                          // released high = nack
                    if (phase == 2'd0 || phase == 2'd3) scl_oe <= 1; else scl_oe <= 0;
                    if (phase == 2'd3) state <= STOP;
                end
                STOP: begin // sda low, scl high, then sda high while scl high -> IDLE
                    if (phase == 0) sda_oe <= 1; 
                    if (phase == 1) scl_oe <= 0;
                    if (phase == 2'd2) begin
                        sda_oe <= 0;                      // stop edge: sda high while scl high
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
