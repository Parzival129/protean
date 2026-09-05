// axil_reg: a single 32-bit read/write register behind an AXI4-Lite slave port.

module axil_reg (
    input  wire        clk,
    input  wire        resetn,

    // write address channel
    input  wire [31:0] s_awaddr,
    input  wire        s_awvalid,
    output reg         s_awready,

    // write data channel
    input  wire [31:0] s_wdata,
    input  wire [ 3:0] s_wstrb,
    input  wire        s_wvalid,
    output reg         s_wready,

    // write response channel
    output reg  [ 1:0] s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,

    // read address channel
    input  wire [31:0] s_araddr,
    input  wire        s_arvalid,
    output reg         s_arready,

    // read data channel
    output reg  [31:0] s_rdata,
    output reg  [ 1:0] s_rresp,
    output reg         s_rvalid,
    input  wire        s_rready
);

    // the register this slave holds
    reg [31:0] data = 32'b0;

    // write
    always @(posedge clk) begin
        if (!resetn) begin
            // reset awready / wready / bvalid / bresp
            s_awready <= 0;
            s_wready <= 0;
            s_bvalid <= 0;
            s_bresp <= 0;
        end else begin
            // write handshake
            if (s_awvalid and s_wvalid) begin
                awready <= 1; // pulse that the reciever is ready
                wready <= 1
                data <= s_wdata;
            end
        end
    end

    // read
    always @(posedge clk) begin
        if (!resetn) begin
            //  reset arready / rvalid / rdata / rresp
        end else begin
            //  the read handshake
        end
    end

endmodule
