// i2c_decode.v — passive I2C bus monitor. Watches SCL/SDA and reconstructs the
// protocol into bytes + events. Never drives the bus (decode only).
//   START (SDA falls while SCL high) -> shift 8 bits on each SCL rising edge ->
//   9th bit = ACK -> STOP (SDA rises while SCL high). First byte after START is
//   the address+R/W; the rest are data.


module i2c_decode(
    input  wire       clk,
    input  wire       scl,          // bus lines to observe (sync before feeding on hw)
    input  wire       sda,
    output reg  [7:0] data,         // last byte decoded (address or data)
    output reg        data_valid,   // 1-clock strobe: a byte + its ack just completed
    output reg        is_addr,      // high with data_valid when that byte was the address
    output reg        ackd,         // ack bit for that byte (0 = acked)
    output reg        start_seen,   // 1-clock strobe: START condition detected
    output reg        stop_seen     // 1-clock strobe: STOP condition detected
);


    localparam IDLE = 1'b0,
                RX = 1'b1;

    reg scl_s, sda_s, scl_s0, sda_s0;
    reg scl_prev = 0;
    reg sda_prev = 0;
    reg [3:0] bit_counter = 0; // to clock 8 bits
    reg [7:0] shifter = 0; // accumulate bits
    reg first_byte = 0; // next byte is address
    reg state = IDLE;


    always @(posedge clk) begin

        data_valid <= 0;
        start_seen <= 0;
        stop_seen <= 0;

        scl_s0 <= scl;
        scl_s <= scl_s0;

        sda_s0 <= sda;
        sda_s <= sda_s0;

        if (scl_s && sda_prev && !sda_s) begin //start condition
            start_seen <= 1;
            bit_counter <= 0;
            first_byte <= 1;
            state <= RX;
        end

        if (scl_s && !sda_prev && sda_s) begin //stop condition
            stop_seen <= 1;
            state <= IDLE;
        end

        if (state == RX) begin
            if (scl_s && !scl_prev) begin // on scl rising edge
                if (bit_counter == 8) begin //finished clocking
                    ackd <= sda_s;
                    data <= shifter; // push finished byte
                    data_valid <= 1;
                    is_addr <= first_byte;
                    first_byte <= 0;
                    bit_counter <= 0;
                end
                if (bit_counter < 8) begin
                    shifter <= {shifter[6:0], sda_s};
                    bit_counter <= bit_counter + 1;
                end
            end
        end


        scl_prev <= scl_s;
        sda_prev <= sda_s;

        
    end

endmodule
