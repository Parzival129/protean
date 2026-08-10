// picorv32 SoC: cpu + 16KB ram + one memory-mapped LED port.
// map: 0x0000_0000-0x3FFF ram, 0x1000_0000 led

module soc_top (
    input  wire       clk,
    output wire [5:0] led   // active-low
);
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

    picorv32 #(
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR     (32'h0000_4000)   // sp = top of ram
    ) cpu (
        .clk(clk), .resetn(resetn),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0), .irq(32'b0)
    );

    localparam integer RAM_WORDS = 4096;
    reg [31:0] ram [0:RAM_WORDS-1];
    initial $readmemh("src/soc/firmware.hex", ram); // load the firmware hex file into RAM

    reg [5:0] led_reg = 6'b0;
    assign led = ~led_reg;

    wire sel_ram = (mem_addr < RAM_WORDS*4);
    wire sel_led = (mem_addr == 32'h1000_0000);

    always @(posedge clk) begin
        mem_ready <= 1'b0;
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
            else begin
                mem_rdata <= 32'b0;
                mem_ready <= 1'b1;   // ack unknown so cpu can't hang
            end
        end
    end

endmodule
