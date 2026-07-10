module spi #(
    parameter integer N = 13500000 // oscillate every 0.5 seconds on the 27Mhz clock
) (
    input wire clk,
    input wire start,
    input wire [7:0] tx,
    output wire done,
    output wire [7:0] rx,
    output reg sclk = 1'b0,
    output wire mosi,
    output reg led = 1'b0,
    input wire miso
);

reg tick;
reg [23:0] cnt = 10'd0;

always @(posedge clk) begin // clock divider
    
    tick <= 1'b0;

    if (cnt == N-1) begin
        tick <= 1'b1;
        cnt <= 0;
    end
    else begin
        cnt <= cnt + 1'd1;
    end
    if (tick) begin
        led <= ~led; // just for testing
        sclk <= ~sclk;
    end
end

endmodule