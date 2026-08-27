// gb_clock.v — 27 MHz -> ~4.19 MHz core clock + power-on/button reset.

module gb_clock(
    input  wire clk_in,    // 27 MHz
    input  wire rst_btn,
    output wire clk_gb,    // ~4.19 MHz
    output wire rst
);

endmodule
