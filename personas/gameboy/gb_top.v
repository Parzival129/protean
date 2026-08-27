// gb_top.v — Game Boy persona top. Wires the VerilogBoy core (core/boy.v) to
// the clock, cartridge, and video blocks.

module gb_top(
    input  wire       clk,        // 27 MHz (pin 4)
    input  wire       btn1,       // reset
    input  wire       btn2,
    inout  wire       scl,        // CardKB I2C (open-drain, 71/72)
    inout  wire       sda,
    output wire       lcd_clk,
    output wire       lcd_den,
    output wire [4:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [4:0] lcd_b
);

    wire clk_gb;   // ~4.19 MHz core clock
    wire rst_gb;

    gb_clock gb_clock (
        .clk_in (clk),
        .rst_btn(btn1),
        .clk_gb (clk_gb),
        .rst    (rst_gb)
    );

    // CardKB over I2C: poll periodically, decode to joypad (reused from LA)
    reg  i2c_start = 0;
    reg  [22:0] poll = 0;
    wire i2c_scl_oe, i2c_sda_oe, i2c_busy, kbd_valid, kbd_acked;
    wire [7:0] kbd_byte;

    i2c_master #(.ADDR(7'h5F), .DIV(4096)) u_kbd (
        .clk(clk), .start(i2c_start),
        .scl_oe(i2c_scl_oe), .sda_oe(i2c_sda_oe), .sda_in(sda),
        .key(kbd_byte), .valid(kbd_valid), .acked(kbd_acked), .busy(i2c_busy)
    );

    assign scl = i2c_scl_oe ? 1'b0 : 1'bz;
    assign sda = i2c_sda_oe ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        i2c_start <= 1'b0;
        if (poll == 23'd2700000) begin
            poll <= 0;
            if (!i2c_busy) i2c_start <= 1'b1;   // ~10 Hz keyboard poll
        end else poll <= poll + 1'b1;
    end

    wire [7:0] joypad;
    gb_keymap gb_keymap (
        .clk      (clk),
        .kbd_byte (kbd_byte),
        .kbd_valid(kbd_valid),
        .kbd_acked(kbd_acked),
        .joypad   (joypad)
    );

    wire [15:0] cart_a;
    wire [7:0]  cart_to_cpu;  // boy.din
    wire [7:0]  cart_fr_cpu;  // boy.dout
    wire        cart_rd, cart_wr;

    wire        gb_hs, gb_vs, gb_cpl, gb_valid;
    wire [1:0]  gb_pixel;
    wire [15:0] gb_left, gb_right;
    wire        gb_done, gb_fault;

    boy boy (
        .rst  (rst_gb),
        .clk  (clk_gb),
        .phi  (),
        .a    (cart_a),
        .dout (cart_fr_cpu),
        .din  (cart_to_cpu),
        .wr   (cart_wr),
        .rd   (cart_rd),
        .key  (joypad),         // CardKB -> joypad (gb_keymap)
        .hs   (gb_hs),
        .vs   (gb_vs),
        .cpl  (gb_cpl),
        .pixel(gb_pixel),
        .valid(gb_valid),
        .left (gb_left),
        .right(gb_right),
        .done (gb_done),
        .fault(gb_fault)
    );

    gb_cart gb_cart (
        .clk          (clk_gb),
        .a            (cart_a),
        .rd           (cart_rd),
        .wr           (cart_wr),
        .data_from_cpu(cart_fr_cpu),
        .data_to_cpu  (cart_to_cpu)
    );

    gb_video gb_video (
        .clk_lcd(clk),
        .clk_gb (clk_gb),
        .hs     (gb_hs),
        .vs     (gb_vs),
        .cpl    (gb_cpl),
        .pixel  (gb_pixel),
        .valid  (gb_valid),
        .lcd_clk(lcd_clk),
        .lcd_den(lcd_den),
        .lcd_r  (lcd_r),
        .lcd_g  (lcd_g),
        .lcd_b  (lcd_b)
    );

endmodule
