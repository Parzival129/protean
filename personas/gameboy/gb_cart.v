// gb_cart.v — cartridge ROM readback. Tetris = flat 32 KB (MBC0) from roms/game.hex.

module gb_cart(
    input  wire        clk,
    input  wire [15:0] a,
    input  wire        rd,
    input  wire        wr,
    input  wire [7:0]  data_from_cpu,
    output wire [7:0]  data_to_cpu
);

endmodule
