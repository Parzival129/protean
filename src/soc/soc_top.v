// picorv32 SoC: cpu + 16KB ram + one memory-mapped LED port.
// map: 0x0000_0000-0x3FFF ram, 0x1000_0000 led

module soc_top (
    input  wire clk,
    input  wire btn,        // NEXT (nav)
    input  wire btn2,       // GO (commit the switch)
    output wire [5:0] led,   // active-low
    output wire       lcd_clk,
    output wire       lcd_den,
    output wire [4:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [4:0] lcd_b,
    output wire       cs,    // flash SPI
    output wire       sclk,
    output wire       mosi,
    input  wire       miso,
    output wire       recfg_n
);
    // bitstream size to copy per switch (real persona ~0.6 MB)
    parameter COPY_LEN = 24'd600000;

    // power-on reset, hold low for the first 256 cycles
    reg [7:0] rst_cnt = 8'd0;
    wire resetn = &rst_cnt;
    always @(posedge clk) if (!resetn) rst_cnt <= rst_cnt + 8'd1;

    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;   // 0 = read, else which bytes to write
    reg  [31:0] mem_rdata;

    reg [1:0] sel_reg = 2'd1; // selection register for menu

    picorv32 #(
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR     (32'h0000_4000)   // sp = top of ram
    ) cpu (
        .clk(clk), .resetn(resetn),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0), .irq(32'b0)
    );

    lcd_render lcd_render (
        .clk(clk),
        .sel(sel_reg),
        .lcd_clk(lcd_clk),
        .lcd_den(lcd_den),
        .lcd_r(lcd_r),
        .lcd_g(lcd_g),
        .lcd_b(lcd_b),
        .text_we(text_we),
        .text_waddr(text_waddr),
        .text_wdata(text_wdata)
    );

    localparam integer RAM_WORDS = 4096;
    reg [31:0] ram [0:RAM_WORDS-1];
    initial $readmemh("src/soc/firmware.hex", ram); // load the firmware hex file into RAM

    reg [5:0] led_reg = 6'b0;
    assign led = ~led_reg;

    wire sel_ram = (mem_addr < RAM_WORDS*4);
    wire sel_led = (mem_addr == 32'h1000_0000);

    wire sel_text = (mem_addr >= 32'h3000_0000) && (mem_addr < 32'h3000_0000 + 256);
    wire        text_we    = mem_valid && !mem_ready && sel_text && (|mem_wstrb);
    wire [5:0]  text_waddr = mem_addr[7:2];   // word index 0..63
    wire [7:0]  text_wdata = mem_wdata[7:0];

    // synchronise both buttons into the clock domain
    reg [1:0] btn_sync = 2'b0, btn2_sync = 2'b0;
    always @(posedge clk) begin
        btn_sync  <= {btn_sync[0], btn};
        btn2_sync <= {btn2_sync[0], btn2};
    end
    wire btn_synced  = btn_sync[1];
    wire btn2_synced = btn2_sync[1];

    // flash switcher peripheral: write 0x6000_0000 with the slot -> start a
    // switch; read it back for the busy flag.
    reg  flash_start = 1'b0;
    reg  flash_slot  = 1'b0;
    wire flash_busy;

    flash_ctrl #(.COPY_LEN(COPY_LEN)) u_flash (
        .clk(clk),
        .start(flash_start),
        .slot_in(flash_slot),
        .cs(cs),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .busy(flash_busy),
        .recfg_n(recfg_n)
    );

    always @(posedge clk) begin
        mem_ready   <= 1'b0;
        flash_start <= 1'b0;   // one-cycle pulse, set only on the trigger write
        if (mem_valid && !mem_ready) begin
            if (sel_ram) begin
                if (mem_wstrb[0]) ram[mem_addr[13:2]][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) ram[mem_addr[13:2]][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) ram[mem_addr[13:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) ram[mem_addr[13:2]][31:24] <= mem_wdata[31:24];
                mem_rdata <= ram[mem_addr[13:2]];
                mem_ready <= 1'b1;
            end
            else if (sel_led) begin
                if (|mem_wstrb) led_reg <= mem_wdata[5:0];
                mem_rdata <= {26'b0, led_reg};
                mem_ready <= 1'b1;
            end
            else if (sel_text) begin
               mem_ready <= 1'b1; 
            end
            else if (mem_addr == 32'h4000_0000) begin // buttons: bit0 = NEXT, bit1 = GO
                mem_rdata <= {30'b0, btn2_synced, btn_synced};
                mem_ready <= 1'b1;
            end
            else if (mem_addr == 32'h5000_0000) begin // write the menu selection register
                if (|mem_wstrb) sel_reg <= mem_wdata[1:0];
                mem_ready <= 1'b1;
            end
            else if (mem_addr == 32'h6000_0000) begin // flash: write slot -> switch, read -> busy
                if (|mem_wstrb) begin
                    flash_slot  <= mem_wdata[0];
                    flash_start <= 1'b1;
                end
                mem_rdata <= {31'b0, flash_busy};
                mem_ready <= 1'b1;
            end
            else begin
                mem_rdata <= 32'b0;
                mem_ready <= 1'b1;   // ack unknown so cpu can't hang
            end
        end
    end

endmodule
