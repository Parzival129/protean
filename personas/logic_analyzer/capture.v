// capture.v — LA step 2: capture buffer (fill-once).

module capture #(
    parameter DEPTH = 1024,
    parameter AW    = 10          // must satisfy 2**AW >= DEPTH
)(
    input  wire          clk,
    input  wire [7:0]    sample,
    input  wire          sample_stb,
    input  wire          arm,        // 1-clock pulse: begin a fresh capture
    output reg           capturing,  // high while recording
    output reg           full,       // high once DEPTH samples are stored
    input  wire [AW-1:0] raddr,      // read address (renderer / testbench)
    output wire [7:0]    rdata       // data at raddr
);

    reg [7:0] mem [0:DEPTH-1];
    reg [AW-1:0] waddr;

    always @(posedge clk) begin
        if (arm) begin
            capturing <= 1'b1;
            full      <= 1'b0;
            waddr     <= 0;
        end else if (capturing && sample_stb) begin
            mem[waddr] <= sample;
            waddr      <= waddr + 1'b1;
            if (waddr == DEPTH-1) begin
                full      <= 1'b1;
                capturing <= 1'b0;
            end
        end
    end
    
    assign rdata = mem[raddr];

endmodule
