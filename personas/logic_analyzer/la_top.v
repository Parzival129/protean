// la_top.v — Logic Analyzer persona top: beam-races the 480x272 RGB LCD and draws
// the channel waveforms via wave_pixel.

module la_top(
    input  wire       clk,        // 27 MHz onboard oscillator (pin 4)
    input  wire       btn1,
    input  wire       btn2,
    output reg        lcd_clk,
    output reg        lcd_den,
    output reg [4:0]  lcd_r,
    output reg [5:0]  lcd_g,
    output reg [4:0]  lcd_b,
    output wire       recfg_n,     // reboot pin, driven by flash_ctrl
    output wire       cs,          // MSPI flash bus — the persona switcher drives these
    output wire       sclk,
    output wire       mosi,
    input  wire       miso,
    inout  wire       scl,         // CardKB I2C (open-drain, pins 71/72)
    inout  wire       sda
);

    localparam H_BP  = 30;
    localparam H_ACT = 480;
    localparam H_TOT = 560;
    localparam V_BP = 5;
    localparam V_ACT = 272;
    localparam V_TOT = 297;

    reg [1:0] zoom = 1;         // columns per sample = 2**zoom (arrows adjust)
    reg [8:0] pan_offset = 0;   // scroll position into the 512-deep capture ring

    reg pix_tick = 1'd0;
    reg [1:0] ph = 2'd0;
    reg [9:0] vc = 0;
    reg [9:0] hc = 0;

    reg [7:0] probes = 8'd0;
    reg begun = 0;

    wire pix;
    wire [9:0] y = vc - V_BP;
    wire [9:0] x = hc - H_BP;
    wire [7:0] sample_word;
    wire armed;

    reg go = 0;
    reg btn2_prev = 0;
    reg [23:0] both_btn_cnt = 0;
    reg in_xact = 0;   // high from decoder START to STOP — trigger on its rising edge
    reg key_in_xact = 0;   // this transaction carried a nonzero data byte (a keypress)
    reg cap_full_prev = 0;
    wire cap_full;

    // CardKB over I2C: poll periodically; Enter re-arms, arrows pan/zoom
    reg  i2c_start = 0;
    reg  [22:0] poll = 0;
    wire i2c_scl_oe, i2c_sda_oe, i2c_busy, key_valid, kbd_acked;
    wire [7:0] key;

    i2c_master #(.ADDR(7'h5F), .DIV(4096)) u_kbd ( // Needed to increase DIV to allow for weak internal pullups to raise released lines fast enough
        .clk(clk),
        .start(i2c_start),
        .scl_oe(i2c_scl_oe),
        .sda_oe(i2c_sda_oe),
        .sda_in(sda),
        .key(key),
        .valid(key_valid),
        .acked(kbd_acked),
        .busy(i2c_busy)
    );

    // open-drain: pull low when oe, else release to the external pull-up
    assign scl = i2c_scl_oe ? 1'b0 : 1'bz;
    assign sda = i2c_sda_oe ? 1'b0 : 1'bz;

    // Stolen from lcd_render.v:

    // passively decode the CardKB bus + render the bytes as hex text
    wire [7:0] dec_data;
    wire dec_valid, dec_isaddr, dec_ack, dec_start, dec_stop;

    i2c_decode u_dec (
        .clk(clk), .scl(scl), .sda(sda),
        .data(dec_data), .data_valid(dec_valid), .is_addr(dec_isaddr),
        .ackd(dec_ack), .start_seen(dec_start), .stop_seen(dec_stop)
    );

    // font ROM + text row for the decode readout (borrowed from common/lcd_render.v)
    reg [7:0] font [0:1535];
    initial $readmemh("common/font.hex", font);
    reg [7:0] dtext [0:15];      // fixed readout: "A:xx D:xx"
    integer di;
    initial begin
        dtext[0]=8'h41; dtext[1]=8'h3A; dtext[2]=8'h30; dtext[3]=8'h30; dtext[4]=8'h20; // "A:00 "
        dtext[5]=8'h44; dtext[6]=8'h3A; dtext[7]=8'h30; dtext[8]=8'h30;                 // "D:00"
        for (di = 9; di < 16; di = di + 1) dtext[di] = 8'h20;                            // trailing spaces
        dtext[10]=8'h2E;                                                                 // '.' idle marker
    end

    // per-pixel glyph lookup for the top text row (cells are 8x16)
    wire in_dtext = (y < 16) && (x < 128);
    wire [7:0] tch   = dtext[x[6:3]];
    wire [10:0] tfidx = ((tch - 8'd32) << 4) + y[3:0];
    wire [7:0] tgrow = font[tfidx];
    wire tpix  = tgrow[7 - x[2:0]];

    // escape hatch: hold both buttons -> copy the shell back to boot + reconfig
    reg flash_start = 1'b0;
    reg switching = 1'b0;
    wire flash_busy;

    flash_ctrl #(.COPY_LEN(24'd950000)) u_flash (   // shell bitstream is ~907 KB — must cover it fully
        .clk(clk),
        .start(flash_start),
        .slot_in(1'b0),        // shell staged in slot 0 (0x200000)
        .cs(cs),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .busy(flash_busy),
        .recfg_n(recfg_n)
    );

    wave_pixel wave_pixel (
        .y(y),
        .col_sample(sample_word),
        .pix(pix)
    );

    la_engine #(.DEPTH(512), .AW(9), .POST(448), .DIV(1024)) la_engine ( // ~26kHz; POST=448 puts the START near the left
        .clk(clk),
        .probes(probes),
        .go(go),
        .sel(3'd4),  // trigger on the transaction envelope (channel 4)
        .mode(2'b00),  // rising edge = a real I2C START

        .capturing(),
        .full(cap_full),
        .armed(armed),
        // START sits at buffer sample DEPTH-POST=64; show from ~32 so the transaction fills the screen
        .raddr((x >> zoom) + pan_offset + 9'd32),
        .rdata(sample_word)
    );

    wire active = (hc >= H_BP && hc < H_BP+H_ACT) && (vc >= V_BP && vc < V_BP+V_ACT); // in visible range?

    always @(posedge clk) begin
        probes[0] <= btn1;
        probes[1] <= btn2;
        probes[2] <= scl;   // watch the I2C bus we're decoding
        probes[3] <= sda;
        probes[4] <= in_xact;  // transaction envelope (START..STOP), the trigger source

        if (dec_start) in_xact <= 1;
        else if (dec_stop) in_xact <= 0;

        // track whether the current transaction carried a key (nonzero data byte)
        if (dec_start) key_in_xact <= 0;
        else if (dec_valid && !dec_isaddr && dec_data != 8'd0) key_in_xact <= 1;
        cap_full_prev <= cap_full;

        if (begun == 0) begin
            go <= 1;
            begun <= 1;
        end
        else if (btn2 == 1 && btn2_prev == 0) begin
            go <= 1;
        end
        else if (key_valid && kbd_acked && key == 8'h0D) begin // Enter re-arms a fresh capture
            go <= 1;
        end
        else if (cap_full && !cap_full_prev && !key_in_xact) begin // captured an idle transaction -> try again
            go <= 1;
        end
        else go <= 0;
        btn2_prev <= btn2;

        // decoded byte -> hex into the fixed readout (address field or data field)
        if (dec_valid && dec_isaddr) begin
            dtext[2] <= dec_data[7:4] < 4'd10 ? 8'h30 + dec_data[7:4] : 8'h37 + dec_data[7:4];
            dtext[3] <= dec_data[3:0] < 4'd10 ? 8'h30 + dec_data[3:0] : 8'h37 + dec_data[3:0];
        end
        if (dec_valid && !dec_isaddr) begin
            if (dec_data != 8'd0) begin // hold the last real key; ignore the idle 00 stream
                dtext[7] <= dec_data[7:4] < 4'd10 ? 8'h30 + dec_data[7:4] : 8'h37 + dec_data[7:4];
                dtext[8] <= dec_data[3:0] < 4'd10 ? 8'h30 + dec_data[3:0] : 8'h37 + dec_data[3:0];
            end
            dtext[10] <= (dec_data == 8'd0) ? 8'h2E : 8'h2A; // '.' idle, '*' key down
        end

        // arrow keys pan/zoom the view (left/right scroll, up/down zoom)
        if (key_valid && kbd_acked) begin
            case (key)
                8'hB4: pan_offset <= pan_offset - 5'd16; // left (send-once kbd: big step/tap)
                8'hB7: pan_offset <= pan_offset + 5'd16; // right
                8'hB5: if (zoom != 2'd3) zoom <= zoom + 1'b1; // up = zoom in
                8'hB6: if (zoom != 2'd0) zoom <= zoom - 1'b1; // down = zoom out (512 deep -> zoom 0 shows 480)
            endcase
        end

        // poll the keyboard ~10x/sec — the idle gaps let the SDA trigger wait between reads
        i2c_start <= 1'b0;
        if (poll == 23'd2700000) begin
            poll <= 0;
            if (!i2c_busy) i2c_start <= 1'b1;
        end else poll <= poll + 1'b1;

        flash_start <= 1'b0;   // one-cycle kick, set only on the trigger
        if (btn1 == 1 && btn2 == 1) begin
            both_btn_cnt <= both_btn_cnt + 1;
            if (both_btn_cnt == 24'd10000000 && !switching) begin
                flash_start <= 1'b1;   // copy shell -> boot, verify, reconfig
                switching   <= 1'b1;
            end
        end
        else both_btn_cnt <= 0;

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
                if (flash_busy && x < 16 && y < 16) begin
                    lcd_r <= 0;   // blue box top-left = switching back to shell
                    lcd_g <= 0;
                    lcd_b <= 5'h1F;
                end
                else if (x < 16 && y >= V_ACT-16) begin // diag box bottom-left: kbd ack
                    lcd_r <= kbd_acked ? 5'h00 : 5'h1F;  // green = acked, red = no answer
                    lcd_g <= kbd_acked ? 6'h3F : 6'h00;
                    lcd_b <= 0;
                end
                else if (armed && x >= H_ACT-16 && y < 16) begin
                    lcd_r <= 0;   // green box top-right = armed, waiting for trigger
                    lcd_g <= 6'h3F;
                    lcd_b <= 0;
                end
                else if (in_dtext && tpix) begin
                    lcd_r <= 0;   // cyan = decoded I2C hex text
                    lcd_g <= 6'h3F;
                    lcd_b <= 5'h1F;
                end
                else if (pix) begin
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
