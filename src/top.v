module top #(
    parameter BLINK_BIT = 24    // default = slow blinkA
)(
    input  wire clk,   // 27 MHz onboard oscillator (pin 4)
    output wire led,    // onboard LED0, active-low (pin 15)
    output wire led2,
    output reg recfg_n
);
    reg marker = 1'b0;
    reg [24:0] cnt = 25'd0;

    reg fired = 1'b0;
    initial recfg_n = 1'b1; // make high to begin to avoid reflash

    always @(posedge clk) begin
        if (cnt == 25'h800000) marker <= 1'b1;
        cnt <= cnt + 25'd1;
        if (cnt == {25{1'b1}} && fired == 1'b0) begin
            recfg_n <= 1'b0; // make low to reflash
            fired <= 1'b1;
        end
    end
        
    assign led2 = marker; // LED2 on for first 10M cycles
    assign led = cnt[BLINK_BIT];
endmodule
