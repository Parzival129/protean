// gb_cart.v — cartridge ROM readback. Tetris = flat 32 KB (MBC0) from roms/game.hex.

module gb_cart(
    input  wire        clk,
    input  wire [15:0] a,
    input  wire        rd,
    input  wire        wr,
    input  wire [7:0]  data_from_cpu,
    output reg [7:0]  data_to_cpu
);

    reg [7:0] rom [0:32767]; // 32kb of rom
    initial $readmemh("personas/gameboy/roms/game.hex", rom); // load from hex file

    always @(posedge clk) begin
        data_to_cpu <= rom[a[14:0]]; // address with bottom 15 bits of a 
    end


endmodule
