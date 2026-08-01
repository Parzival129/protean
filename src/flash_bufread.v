module flash_bufread(
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

    localparam IDLE = 4'd0, // step up FSM states
                WRT_KICK = 4'd1,
                WRT_WAIT = 4'd2,
                POLL_KICK = 4'd3,
                POLL_WAIT = 4'd4,
                SEND_KICK = 4'd5,
                SEND_WAIT = 4'd6,
                READ_KICK = 4'd7,
                READ_WAIT = 4'd8,
                VER_KICK = 4'd9,
                VER_WAIT = 4'd10,
                VER_READ_KICK = 4'd11,
                VER_READ_WAIT = 4'd12,
                DONE = 4'd13;
    
    reg [3:0] state = IDLE;
    reg [2:0] counter = 3'd0; // to count which byte to send at a time
    reg [7:0] id0, id1, id2;
    reg [23:0] addr = 24'h200000; // 24 bit address to write to
    reg [23:0] vaddr = 24'h200003; // 24 bit address to read from 

    reg [7:0] rbuf [0:3];
    reg [1:0] ridx = 0;

    always @(posedge clk) begin
        start <= 1'b0;              // default: only the KICK states override it

        case (state)
            IDLE: begin
                // cs high; when you decide to go, drop cs and head to CMD_KICK
                cs <= 1'b0;
                state <= VER_KICK;
            end


            VER_KICK: begin
                cs <= 1'b0;
                case (counter)
                    2'd0: tx <= 8'h03;
                    2'd1: tx <= addr[23:16];
                    2'd2: tx <= addr[15:8];
                    2'd3: tx <= addr[7:0];
                endcase
                start <= 1'b1;
                state <= VER_WAIT;
            end

            VER_WAIT: begin
                if (done && counter < 2'd3) begin
                    counter <= counter + 1'd1;
                    state <= VER_KICK;
                end
                if (done && counter == 2'd3) begin
                    counter <= 1'd0;
                    state <= READ_KICK;
                end
            end

            READ_KICK: begin
                tx <= 8'h00;
                start <= 1'b1;
                state <= READ_WAIT;
            end

            READ_WAIT: begin
                if (done) begin
                    rbuf[ridx] <= rx;
                    ridx <= ridx + 1;
                    state <= READ_KICK;
                    if (ridx == 3) state <= DONE;
                end
            end
        
            DONE: begin
                cs <= 1'd1;
                led <= ~rbuf[3][5:0];  // ALL LEDS are on, the flash sector at 0x200000 is fully erased!
                // cs high; sit here
            end
        
        endcase
    end

endmodule