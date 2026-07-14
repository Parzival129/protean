module spi_controller(
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
                DONE = 3'd5;
    
    reg [2:0] state = IDLE;
    reg [1:0] counter = 2'd0;
    reg [7:0] id0, id1, id2;

    always @(posedge clk) begin
        start <= 1'b0;              // default: only the KICK states override it

        case (state)
            IDLE: begin
                // cs high; when you decide to go, drop cs and head to CMD_KICK
                cs <= 1'd0;
                state <= CMD_KICK;
            end
            CMD_KICK: begin
                // cs low; tx <= 8'h9F; start <= 1'b1; state <= CMD_WAIT;
                tx <= 8'h9f; // send 0x9F -> gets id for flash module as smoke test
                start <= 1'b1;
                state <= CMD_WAIT;
            end
            CMD_WAIT: begin
                // wait here; if (done) state <= READ_KICK;
                if (done) state <= READ_KICK;
            end
            READ_KICK: begin
                // tx <= 8'h00; start <= 1'b1; state <= READ_WAIT;
                tx <= 8'h00;
                start <= 1'b1;
                state <= READ_WAIT;
            end
            READ_WAIT: begin
                // if (done): store rx by counter, bump counter,
                //            loop to READ_KICK or fall to DONE
                if (done && counter < 2'd3) begin
                    if (counter == 2'd0) id0 <= rx;
                    if (counter == 2'd1) id1 <= rx;
                    if (counter == 2'd2) begin
                        id2 <= rx;
                        state <= DONE;    
                    end 
                    else begin
                        counter <= counter + 2'd1;
                        state <= READ_KICK;
                    end
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