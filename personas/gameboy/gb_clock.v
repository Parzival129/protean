// gb_clock.v — 27 MHz -> ~4.19 MHz core clock + power-on/button reset.

module gb_clock(
    input  wire clk_in,    // 27 MHz
    input  wire rst_btn,
    output wire clk_gb,    // ~4.19 MHz
    output reg rst
);

    BUFG bufg_gb(.I(clk_div), .O(clk_gb)); // global buffer to pnr routes clock in global clock tree

    reg [7:0] counter = 0;
    reg [7:0] total = 0;
    reg clk_div = 0;

    always @(posedge clk_in) begin
        clk_div <= 0;
        rst <= 0;
        counter <= counter + 1;
        if (total <= 200) begin // reset at powerup
            rst <= 1;
            total <= total + 1;
        end
        if (rst_btn) rst <= 1;
        if (counter == 5) begin // divide tang nano clock for gb
            clk_div <= 1;
            counter <= 0;
        end
    end

endmodule
