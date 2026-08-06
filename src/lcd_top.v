module lcd_top(
    input wire clk,
    output reg lcd_clk,
    output reg lcd_den,
    output reg [4:0] lcd_r,
    output reg [5:0] lcd_g,
    output reg [4:0] lcd_b
);

    localparam H_BP  = 30;
    localparam H_ACT = 480;
    localparam H_TOT = 560;
    localparam V_BP = 5;
    localparam V_ACT = 272;
    localparam V_TOT = 297;

    reg pix_tick = 1'd0;
    reg [1:0] ph = 2'd0;
    reg [9:0] vc = 0;
    reg [9:0] hc = 0;

    reg [7:0] glyph [0:15];
    initial begin // test glyph — 8x8 smiley centered in the 8x16 cell
        glyph[0]  = 8'b00000000;
        glyph[1]  = 8'b00000000;
        glyph[2]  = 8'b00000000;
        glyph[3]  = 8'b00000000;
        glyph[4]  = 8'b00111100;   //  ..####..
        glyph[5]  = 8'b01111110;   //  .######.
        glyph[6]  = 8'b11011011;   //  ##.##.##  eyes
        glyph[7]  = 8'b11111111;   //  ########
        glyph[8]  = 8'b10111101;   //  #.####.#  smile corners
        glyph[9]  = 8'b11000011;   //  ##....##  smile bottom
        glyph[10] = 8'b01111110;   //  .######.
        glyph[11] = 8'b00111100;   //  ..####..
        glyph[12] = 8'b00000000;
        glyph[13] = 8'b00000000;
        glyph[14] = 8'b00000000;
        glyph[15] = 8'b00000000;
    end

    wire in_box = (x < 8) && (y < 16);   // is this pixel inside the glyph's box?
    wire [2:0] cx = x[2:0];              // column within the cell: 0..7
    wire [3:0] cy = y[3:0];              // row within the cell:    0..15
    wire [7:0] grow = glyph[cy];         // the 8 dots of this glyph row
    wire pix_on = grow[7 - cx];          // cx=0 -> leftmost pixel = bit 7

    wire [9:0] x = hc - H_BP;   // column within the visible area: 0..479
    wire [9:0] y = vc - V_BP;   // row within the visible area:    0..271

    wire active = (hc >= H_BP && hc < H_BP+H_ACT) && (vc >= V_BP && vc < V_BP+V_ACT); // in visible range?

    always @(posedge clk) begin

        pix_tick <= 1'd0;
        lcd_clk <= (ph == 1);

        if (ph == 2) begin 
            pix_tick <= 1'b1; // 9Mhz clock rate for LCD
            ph <= 0;
        end
        else begin
            ph <= ph + 1'd1;
        end

        if (pix_tick) begin
            lcd_den <= active; // data enable
            if (active) begin
                if (in_box && pix_on) begin
                    lcd_r <= 5'h1F;
                    lcd_g <= 6'h3F;
                    lcd_b <= 5'h1F;
                end 
                else begin
                    lcd_r <= 0;
                    lcd_g <= 0;
                    lcd_b <= 0;
                end
            end
            else begin
                lcd_r <= 0;
                lcd_g <= 0;
                lcd_b <= 0;
            end
            
            if (hc == H_TOT-1) begin 
                hc <= 0;
                if (vc == V_TOT-1) vc <= 0;
                else vc <= vc + 1;
            end
            else hc <= hc + 1;
        end
        
    end

endmodule