// gb_video.v — GB pixel stream -> framebuffer -> 480x272 LCD.
// Two domains: write pixels in clk_gb, beam-race the panel in clk_lcd (cross via
// dual-port BRAM). Scale/center 160x144 into 480x272.

module gb_video(
    input  wire       clk_lcd,   // 27 MHz
    input  wire       clk_gb,
    input  wire       hs,        // end of 160-px line
    input  wire       vs,        // end of 144-line frame
    input  wire       cpl,
    input  wire [1:0] pixel,     // 2-bit shade
    input  wire       valid,
    output reg        lcd_clk,
    output reg        lcd_den,
    output reg [4:0]  lcd_r,
    output reg [5:0]  lcd_g,
    output reg [4:0]  lcd_b
);

endmodule
