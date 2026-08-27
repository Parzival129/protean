// gb_scale_tb.v — probe the 2x read path. Fill framebuffer[idx] = idx & 3, force
// the beam-racer to specific (hc,vc), and check fb_shade == (gb_row*160+gb_col)&3.
`timescale 1ns/1ps

module gb_scale_tb;
    reg clk_lcd = 0, clk_gb = 0;
    always #10 clk_lcd = ~clk_lcd;

    reg [1:0] pixel = 0;
    reg hs=0, vs=0, valid=0;
    wire lcd_clk, lcd_den; wire [4:0] lcd_r, lcd_b; wire [5:0] lcd_g;

    gb_video dut (
        .clk_lcd(clk_lcd), .clk_gb(clk_gb), .hs(hs), .vs(vs), .cpl(1'b0),
        .pixel(pixel), .valid(valid), .lcd_clk(lcd_clk), .lcd_den(lcd_den),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b));

    integer i;
    task probe(input [9:0] px, input [9:0] py);
        reg [15:0] addr;
        reg [1:0]  want;
        begin
            force dut.hc = px + 30;   // x = hc - H_BP
            force dut.vc = py + 5;    // y = vc - V_BP
            @(posedge clk_lcd); @(posedge clk_lcd);  // let fb_shade latch
            addr = dut.gb_row*160 + dut.gb_col;
            want = addr & 3;
            $display("px=%0d py=%0d -> gb_col=%0d gb_row=%0d addr=%0d  fb_shade=%b want=%b  %s",
                px, py, dut.gb_col, dut.gb_row, addr, dut.fb_shade, want,
                (dut.fb_shade === want) ? "OK" : "*** MISMATCH");
            release dut.hc; release dut.vc;
        end
    endtask

    initial begin
        for (i = 0; i < 23040; i = i + 1) dut.framebuffer[i] = i & 3;
        @(posedge clk_lcd);
        probe(80, 0);      // window top-left
        probe(100, 20);
        probe(240, 136);   // middle
        probe(398, 270);   // window bottom-right area
        $finish;
    end
endmodule
