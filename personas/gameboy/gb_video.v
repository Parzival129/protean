// gb_video.v — GB pixel stream -> framebuffer -> 480x272 LCD.
// Write pixels in clk_gb, beam-race the panel in clk_lcd (cross via
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

    localparam H_BP = 30, H_ACT = 480, H_TOT = 560;
    localparam V_BP = 5,  V_ACT = 272, V_TOT = 297;

    // frmae
    reg [7:0] xi = 0, yi = 0;
    reg [1:0] framebuffer [0:23039]; // 160x144, 2bpp

    reg hs_prev, vs_prev;

    always @(posedge clk_gb) begin

        vs_prev <= vs;
        hs_prev <= hs;

        if (valid) begin
            framebuffer[yi * 160 + xi] <= pixel;
            xi <= xi + 1;
        end
        if (hs && !hs_prev) begin // new row on rising edge
            xi <= 0; 
            yi <= yi + 1; 
        end 
        if (vs && !vs_prev) yi <= 0; // new frame on rising edge
    end

    // beam-racer ported from common/lcd_render.v
    reg pix_tick = 1'd0;
    reg [1:0] ph = 2'd0;
    reg [9:0] vc = 0;
    reg [9:0] hc = 0;

    wire [9:0] x = hc - H_BP;   // 0-479
    wire [9:0] y = vc - V_BP;   // 0-271
    wire active = (hc >= H_BP && hc < H_BP+H_ACT) && (vc >= V_BP && vc < V_BP+V_ACT);

    // GB row/col, 8-bit to match the writer's yi/xi so the framebuffer infers as one clean dual-port BRAM. 
    // 2x: 320x272, 8-row vertical crop, centered 
    wire [7:0] gb_col = (x - 80) >> 1;   // 0..159
    wire [7:0] gb_row = (y >> 1) + 4;    // 4..139
    // --- 1:1: 160x144, centered (also uncomment the 1:1 window below)
    // wire [7:0] gb_col = x - 160;      // 0..159
    // wire [7:0] gb_row = y - 64;       // 0..143

    reg [1:0] fb_shade;

    always @(posedge clk_lcd) begin
        pix_tick <= 1'd0;
        fb_shade <= framebuffer[gb_row*160 + gb_col];
        lcd_clk <= (ph == 1);

        if (ph == 2) begin
            pix_tick <= 1'b1;   // 9 MHz pixel rate
            ph <= 0;
        end else begin
            ph <= ph + 1'd1;
        end

        if (pix_tick) begin
            lcd_den <= active;
            if (active) begin
                if (x >= 80 && x < 400) begin  // 2x window: 320px wide, thin side borders, full height
                // if (x >= 160 && x < 320 && y >= 64 && y < 208) begin  // 1:1 window (with the 1:1 wires above)
                    case (fb_shade) // map 2bit shade to rgb color
                        2'b00: begin // white
                            lcd_r <= 31;
                            lcd_g <= 63;
                            lcd_b <= 31;
                        end
                        2'b01: begin// light gray
                            lcd_r <= 21;
                            lcd_g <= 42;
                            lcd_b <= 21;
                        end
                        2'b10: begin // dark gray
                            lcd_r <= 10;
                            lcd_g <= 21;
                            lcd_b <= 10;
                        end                    
                        2'b11: begin // black
                            lcd_r <= 0;
                            lcd_g <= 0;
                            lcd_b <= 0;
                        end
                    endcase
                end else begin
                lcd_r <= 0;
                lcd_g <= 0;
                lcd_b <= 0;
            end
            end else begin
                lcd_r <= 0;
                lcd_g <= 0;
                lcd_b <= 0;
            end

            if (hc == H_TOT-1) begin
                hc <= 0;
                if (vc == V_TOT-1) vc <= 0;
                else vc <= vc + 1;
            end else hc <= hc + 1;
        end
    end

endmodule
