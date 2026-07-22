module flash_erase(
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
    reg [1:0] counter = 2'd0; // to count which byte to send at a time
    reg [7:0] id0, id1, id2;
    reg [23:0] addr = 24'h200000; // 24 bit address to read from => first address of the flash

    always @(posedge clk) begin
        start <= 1'b0;              // default: only the KICK states override it

        case (state)
            IDLE: begin
                // cs high; when you decide to go, drop cs and head to CMD_KICK
                cs <= 1'b0;
                state <= WRT_KICK;
            end

            WRT_KICK: begin
                tx <= 8'h06; // write enable command to see something for status
                start <= 1'b1;
                state <= WRT_WAIT;
            end

            WRT_WAIT: begin
                if (done) begin
                    state <= SEND_KICK;
                    cs <= 1'b1;
                end 
            end

            SEND_KICK: begin
                cs <= 1'b0;
                case (counter)
                    2'd0: tx <= 8'h20;
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
                    state <= POLL_KICK;
                    cs <= 1'b1;
                end
            end

           POLL_KICK: begin
                cs <= 1'd0;
                tx <= 8'h05;
                start <= 1'b1;
                state <= POLL_WAIT;
            end

            POLL_WAIT: begin
                if (done) begin 
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
                    state <= VER_KICK;
                    counter <= 2'd0;
                    cs <= 1'b1;
                    if (rx[0] == 1) state <= POLL_KICK;
                end
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
                    id0 <= rx;
                    state <= DONE;
                end
            end
        
            DONE: begin
                cs <= 1'd1;
                led <= ~id0[5:0];  // ALL LEDS are on, the flash sector at 0x200000 is fully erased!
                // cs high; sit here
            end
        
        endcase
    end

endmodule