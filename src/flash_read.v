module flash_read( // check that I can read a byte from a specific address
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

    localparam IDLE = 3'd0, // step up FSM states
                CMD_KICK = 3'd1,
                CMD_WAIT = 3'd2,
                READ_KICK = 3'd3,
                READ_WAIT = 3'd4,
                SEND_KICK = 3'd5,
                SEND_WAIT = 3'd6,
                DONE = 3'd7;
    
    reg [2:0] state = IDLE;
    reg [1:0] counter = 2'd0; // to count which byte to send at a time
    reg [7:0] id0, id1, id2;
    reg [23:0] addr = 24'h000100; // 24 bit address to read from => first address of the flash
    // reg [7:0] cmd [3:0] = {8'h03, addr[23:16], addr[15:8], addr[7:0]}; // package bytes to send into one item

    always @(posedge clk) begin
        start <= 1'b0;              // default: only the KICK states override it

        case (state)
            IDLE: begin
                // cs high; when you decide to go, drop cs and head to CMD_KICK
                cs <= 1'd0;
                state <= SEND_KICK;
            end

            SEND_KICK: begin
                case (counter)
                    2'd0: tx <= 8'h03;
                    2'd1: tx <= addr[23:16];
                    2'd2: tx <= addr[15:8];
                    2'd3: tx <= addr[7:0];
                endcase
                start <= 1'b1;
                state <= SEND_WAIT;
            end

            SEND_WAIT: begin
                if (done && counter < 2'd3) begin
                    counter <= counter + 1'd1;
                    state <= SEND_KICK;
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
                    id0 <= rx;
                    state <= DONE;
                end

            end
            DONE: begin
                cs <= 1'd1;
                led <= ~id0[5:0];
                // cs high; sit here
            end
        endcase
    end


endmodule