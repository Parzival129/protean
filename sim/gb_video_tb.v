// gb_video_tb.v — unit test for the framebuffer writer (Part A). Drives a
// synthetic pixel stream (deterministic pattern, hs at line ends, vs at frame
// end) into gb_video and checks framebuffer[] holds what we wrote.
`timescale 1ns/1ps

module gb_video_tb;
    reg clk_gb = 0, clk_lcd = 0;
    always #10 clk_gb  = ~clk_gb;
    always #18 clk_lcd = ~clk_lcd;

    reg        hs = 0, vs = 0, valid = 0;
    reg  [1:0] pixel = 0;
    wire       lcd_clk, lcd_den;
    wire [4:0] lcd_r, lcd_b;
    wire [5:0] lcd_g;

    gb_video dut (
        .clk_lcd(clk_lcd), .clk_gb(clk_gb),
        .hs(hs), .vs(vs), .cpl(1'b0), .pixel(pixel), .valid(valid),
        .lcd_clk(lcd_clk), .lcd_den(lcd_den),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b)
    );

    integer xx, yy, errors;
    function [1:0] pat(input integer x, input integer y);
        pat = (x[1:0] ^ y[1:0]);
    endfunction

    initial begin
        // frame start
        @(posedge clk_gb) vs <= 1;
        @(posedge clk_gb) vs <= 0;

        for (yy = 0; yy < 4; yy = yy + 1) begin       // a few lines
            for (xx = 0; xx < 160; xx = xx + 1) begin
                @(posedge clk_gb) begin valid <= 1; pixel <= pat(xx, yy); end
            end
            @(posedge clk_gb) begin valid <= 0; hs <= 1; end  // end of line
            @(posedge clk_gb) hs <= 0;
        end
        @(posedge clk_gb);

        // check the written lines
        errors = 0;
        for (yy = 0; yy < 4; yy = yy + 1)
            for (xx = 0; xx < 160; xx = xx + 1)
                if (dut.framebuffer[yy*160 + xx] !== pat(xx, yy)) begin
                    if (errors < 8)
                        $display("MISMATCH @ (%0d,%0d): got %b want %b",
                                 xx, yy, dut.framebuffer[yy*160+xx], pat(xx,yy));
                    errors = errors + 1;
                end

        $display("--- gb_video_tb (Part A) ---");
        if (errors == 0) $display("PASS: framebuffer holds the written frame.");
        else             $display("FAIL: %0d mismatches.", errors);
        $finish;
    end
endmodule
