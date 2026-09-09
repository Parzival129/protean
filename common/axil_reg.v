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
    reg resp_pending = 0;

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

            s_awready <= 0;
            s_wready <= 0;

            if (s_awvalid && s_wvalid && !resp_pending) begin
                s_awready <= 1; // pulse that the reciever is ready
                s_wready <= 1;
                // write data from each channel based on write_strobe -> mask to lanes for byte and halfword
                if (s_wstrb[0]) data[7:0] <= s_wdata[7:0];
                if (s_wstrb[1]) data[15:8] <= s_wdata[15:8];
                if (s_wstrb[2]) data[23:16] <= s_wdata[23:16];
                if (s_wstrb[3]) data[31:24] <= s_wdata[31:24];

                resp_pending <= 1;
                s_bvalid <= 1;
                s_bresp <= 2'b00;

            end

            if (s_bvalid && s_bready) begin

                s_bvalid <= 0;
                resp_pending <= 0;
                
            end
        end
    end

    // read
    always @(posedge clk) begin
        if (!resetn) begin
            s_arready <= 0;
            s_rvalid <= 0;
        end else begin
            //  the read handshake
            s_arready <= 0; // slave not ready to receive address
            // master ready to send adddress:
            if (s_arvalid && !s_rvalid) begin // guard to not latch new read while master hasn't taken last read yet
                s_arready <= 1; // slave ready to send
                s_rdata <= data; // 
                s_rresp <= 2'b00;
                s_rvalid <= 1;
            end

            if (s_rvalid && s_rready) begin
                s_rvalid <= 0;
            end

        end
    end

endmodule
