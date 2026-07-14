module spi #(
    parameter integer N = 13500000 // oscillate every 0.5 seconds on the 27Mhz clock
) (
    input wire clk,
    input wire start,
    input wire [7:0] tx,
    output reg done,
    output reg [7:0] rx,
    output reg sclk = 1'b0,
    output wire mosi,
    output reg led = 1'b0,
    input wire miso
);

reg tick;
reg [23:0] cnt = 10'd0;
reg busy = 1'b0; // 0 idle, 1 mid-transfer
reg [5:0] edge_cnt;
reg [7:0] tx_shift;

assign mosi = tx_shift[7];

always @(posedge clk) begin // clock divider
    
    tick <= 1'b0;
    done <= 0;

    if (!busy && start) begin
        busy <= 1'd1; // transfer begin
        tx_shift <= tx;

    end
    if (cnt == N-1) begin
        tick <= 1'b1;
        cnt <= 0;
    end
    else begin
        cnt <= cnt + 1'd1;
    end
    if (busy && tick) begin // once transfer begins start edge counting
        
        led <= ~led; // just for testing
        sclk <= ~sclk; // takes effect at end of always block (non blocking)
        
        if (sclk == 1) begin // shifts out each bit of tx to mosi every falling edge by most significant bit at a time.
            tx_shift <= {tx_shift[6:0], 1'b0}; // sclk is checked to be 1 because sclk toggle hasn't taken effect yet.
        end
        if (sclk == 0) begin // shifts data to rx from miso, recieving it bit by bit
            rx <= {rx[6:0], miso};
        end
        
        edge_cnt <= edge_cnt + 1'd1;
    end
    if (edge_cnt == 16) begin // stop when weve toggled the clock 16 times (8 bits)
        edge_cnt <= 0;
        busy <= 0;
        done <= 1;
    end
    
end

endmodule