// wave_pixel_tb.v — self-checking testbench for the per-pixel waveform decision.
// Checks the simple 2-level convention: within each channel's lane, a HIGH bit
// draws a line at HI_ROW, a LOW bit draws a line at LO_ROW, everything else is
// background. Verifies the channel<->lane mapping and the bit selection.
//
//   run:  make sim-wave_pixel
`timescale 1ns/1ps
module wave_pixel_tb;
    localparam LANE_H = 32, NCH = 8, HI_ROW = 8, LO_ROW = 24;

    reg  [9:0] y;
    reg  [7:0] col_sample;
    wire       pix;

    wave_pixel #(.LANE_H(LANE_H), .NCH(NCH), .HI_ROW(HI_ROW), .LO_ROW(LO_ROW)) dut (
        .y(y), .col_sample(col_sample), .pix(pix)
    );

    integer errors = 0;

    // check pix for a given (y, sample) against an expected value
    task check(input [9:0] yy, input [7:0] s, input exp, input [127:0] name);
        begin
            y = yy; col_sample = s; #1;
            if (pix !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s: y=%0d sample=%h  pix=%b expected=%b", name, yy, s, pix, exp);
            end else begin
                $display("  ok   %0s: y=%0d sample=%h  pix=%b", name, yy, s, pix);
            end
        end
    endtask

    initial begin
        // channel 0 (lane rows 0..31), bit0 high -> line at HI_ROW, not LO_ROW
        check(HI_ROW,          8'b0000_0001, 1'b1, "ch0 high @HI");
        check(LO_ROW,          8'b0000_0001, 1'b0, "ch0 high @LO");
        check(10'd0,           8'b0000_0001, 1'b0, "ch0 high @top(bg)");
        // channel 0 low -> line at LO_ROW, not HI_ROW
        check(HI_ROW,          8'b0000_0000, 1'b0, "ch0 low @HI");
        check(LO_ROW,          8'b0000_0000, 1'b1, "ch0 low @LO");
        // channel 3 (lane base 96), bit3 high -> line at 96+HI_ROW
        check(3*LANE_H+HI_ROW, 8'b0000_1000, 1'b1, "ch3 high @HI");
        check(3*LANE_H+LO_ROW, 8'b0000_1000, 1'b0, "ch3 high @LO");
        // channel 7 (lane base 224), bit7 low -> line at 224+LO_ROW
        check(7*LANE_H+LO_ROW, 8'b0000_0000, 1'b1, "ch7 low @LO");
        // a non-level row is background regardless
        check(10'd5,           8'hFF,        1'b0, "mid-lane bg");

        $display("----");
        if (errors == 0) $display("PASS  wave_pixel: lane/bit mapping + 2-level trace correct");
        else             $display("FAIL  wave_pixel: %0d error(s)", errors);
        $finish;
    end
endmodule
