// gb_clock.v — 27 MHz -> ~4.19 MHz core clock + power-on/button reset.

module gb_clock(
    input  wire clk_in,    // 27 MHz
    input  wire rst_btn,
    output reg clk_gb,    // ~4.19 MHz
    output reg rst
);

    reg [7:0] counter = 0;
    reg [7:0] total = 0;


    always @(posedge clk_in) begin
        clk_gb <= 0;
        rst <= 0;
        counter <= counter + 1;
        if (total <= 200) begin // reset at powerup
            rst <= 1;
            total <= total + 1;
        end
        if (rst_btn) rst <= 1;
        if (counter == 5) begin // divide tang nano clock for gb
            clk_gb <= 1;
            counter <= 0;
        end
    end

endmodule
