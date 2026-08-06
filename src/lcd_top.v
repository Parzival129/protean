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

    // Font ROM: 96 printable ASCII glyphs (0x20..0x7F), 16 rows each, 8 px wide.
    reg [7:0] font [0:1535];
    initial $readmemh("src/font.hex", font);

    // Text to display: one row, "PROTEAN" (each cell holds an ASCII code).
    reg [7:0] text [0:6];
    initial begin
        text[0] = "P"; text[1] = "R"; text[2] = "O"; text[3] = "T";
        text[4] = "E"; text[5] = "A"; text[6] = "N";
    end

    wire [9:0] x = hc - H_BP;   // column within the visible area: 0..479
    wire [9:0] y = vc - V_BP;   // row within the visible area:    0..271

    wire [6:0] cell_col = x[9:3];                 // which 8-wide column, 0..59
    wire in_text = (y < 16) && (cell_col < 7);    // row 0, first 7 cells only
    wire [2:0] cx = x[2:0];                       // column within the cell: 0..7
    wire [3:0] cy = y[3:0];                       // row within the cell:    0..15
    wire [7:0] ch = text[cell_col];               // the character in this cell

    wire [10:0] fidx = ((ch - 8'd32) << 4) + cy; // access current character glphy row
    wire [7:0]  grow = font[fidx];                // the 8 dots of this glyph row
    wire pix_on = grow[7 - cx];                   // cx=0 -> leftmost pixel = bit 7

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
                if (in_text && pix_on) begin
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