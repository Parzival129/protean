module lcd_render(
    input wire clk,
    input wire [1:0] sel, // persona selection 
    input wire text_we, // to allow CPU to write to display
    input wire [5:0] text_waddr,
    input wire [7:0] text_wdata,
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

    localparam COLS = 16;   // characters per menu row
    localparam ROWS = 4;    // menu rows

    reg pix_tick = 1'd0;
    reg [1:0] ph = 2'd0;
    reg [9:0] vc = 0;
    reg [9:0] hc = 0;

    // Font ROM: 96 printable ASCII glyphs (0x20..0x7F), 16 rows each, 8 px wide.
    reg [7:0] font [0:1535];
    initial $readmemh("common/font.hex", font);

    // Menu text: ROWS x COLS grid of ASCII codes, flattened row-major.
    // Space-padded to COLS per row (see common/menu.hex).
    reg [7:0] text [0:ROWS*COLS-1];
    initial $readmemh("common/menu.hex", text);

    wire selected = (cell_row == sel);
    // per character render logic!
    wire [9:0] x = hc - H_BP;   // column within the visible area: 0..479
    wire [9:0] y = vc - V_BP;   // row within the visible area:    0..271

    wire [6:0] cell_col = x[9:3];                 // which 8-wide column, 0..59
    wire [6:0] cell_row = y[9:4];                 // Drop 4 lowest bits to divide by 16
    wire [11:0] tidx = cell_row * COLS + cell_col; // flatten 2d grid into 1d datastructure
    wire in_text = (cell_row < ROWS) && (cell_col < COLS);  
    wire [2:0] cx = x[2:0];                       // column within the cell: 0..7
    wire [3:0] cy = y[3:0];                       // row within the cell:    0..15
    wire [7:0] ch = text[tidx];               // the character in this cell

    wire [10:0] fidx = ((ch - 8'd32) << 4) + cy; // access current character glphy row
    wire [7:0]  grow = font[fidx];                // the 8 dots of this glyph row
    wire pix_on = grow[7 - cx];                   // cx=0 -> leftmost pixel = bit 7

    wire active = (hc >= H_BP && hc < H_BP+H_ACT) && (vc >= V_BP && vc < V_BP+V_ACT); // in visible range?

    always @(posedge clk) begin

        if (text_we) text[text_waddr] <= text_wdata; // write the character data to the LCD if enabled

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
                if (in_text && (pix_on ^ selected)) begin // invert the menu item if its selected
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
