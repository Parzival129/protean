// la_top.v — Logic Analyzer persona top: beam-races the 480x272 RGB LCD and draws
// the channel waveforms via wave_pixel.
//
// STEP A (first light): feed wave_pixel a FIXED sample word so you can see the 8
// channel lanes with high/low lines on real hardware — proving the beam timing,
// lane layout, wave_pixel, and color before the capture engine is wired in.
module la_top(
    input  wire       clk,        // 27 MHz onboard oscillator (pin 4)
    output reg        lcd_clk,
    output reg        lcd_den,
    output reg [4:0]  lcd_r,
    output reg [5:0]  lcd_g,
    output reg [4:0]  lcd_b
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

    reg [7:0] counter = 0;
    reg begun = 0;

    wire pix;
    wire [9:0] y = vc - V_BP;
    wire [9:0] x = hc - H_BP;
    wire [7:0] sample_word;

    reg go = 0;

    wave_pixel wave_pixel (
        .y(y),
        .col_sample(sample_word),
        .pix(pix)
    );

    la_engine la_engine (
        .clk(clk),
        .probes(counter),
        .go(go),
        .sel(3'd2),
        .mode(2'b00),
        .capturing(),
        .full(),
        .raddr(x),
        .rdata(sample_word)
    );

    wire active = (hc >= H_BP && hc < H_BP+H_ACT) && (vc >= V_BP && vc < V_BP+V_ACT); // in visible range?

    always @(posedge clk) begin
        if (begun == 0) begin
            go <= 1;
            begun <= 1;
        end 
        else go <= 0;
        counter <= counter + 1;
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
                if (pix) begin
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
