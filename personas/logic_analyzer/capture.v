// capture.v - pre-trigger ring buffer.
// records continuously into a circular buffer so the trigger lands mid-buffer.
// on rearm the ring runs, on trig it grabs POST more samples then freezes.

module capture #(
    parameter DEPTH = 1024,
    parameter AW    = 10,        // 2**AW must equal DEPTH so waddr wraps on its own
    parameter POST  = 512        // samples kept after trigger, rest of ring is pre-trigger
)(
    input  wire          clk,
    input  wire [7:0]    sample,
    input  wire          sample_stb,
    input  wire          rearm,      // 1-clock pulse: arm a fresh capture
    input  wire          trig,       // 1-clock pulse: trigger edge seen
    output reg           capturing = 0,  // high while recording
    output reg           full = 0,       // high once frozen on a trigger
    input  wire [AW-1:0] raddr,      // read address (renderer / testbench)
    output wire [7:0]    rdata       // data at raddr, oldest first
);

    reg [7:0] mem [0:DEPTH-1];
    reg [AW-1:0] waddr = 0;      // write pointer, free runs while capturing
    reg triggered = 0;          // seen the trigger, counting out post
    reg [AW-1:0] post_cnt = 0;
    reg [AW-1:0] read_base = 0; // oldest sample, latched when frozen

    always @(posedge clk) begin

        if (rearm) begin // start a fresh capture
            capturing <= 1'd1;
            full <= 1'd0;
            triggered <= 1'd0;
            post_cnt <= 0;
        end
        else if (capturing && sample_stb) begin
            mem[waddr] <= sample; // drop new sample into the ring
            waddr      <= waddr + 1'd1; // wraps at DEPTH on its own
            if (triggered) begin
                if (post_cnt == POST-1) begin // enough post samples, freeze
                    capturing <= 1'd0;
                    full <= 1'd1;
                    read_base <= waddr + 1'd1; // next cell is the oldest sample
                end
                else post_cnt <= post_cnt + 1'd1;
            end
        end

        if (trig & capturing & ~triggered) begin // mark where the trigger hit
            triggered <= 1'd1;
            post_cnt  <= 0;
        end
    end

    // live view scrolls off waddr, frozen view anchors at read_base
    wire [AW-1:0] base = capturing ? waddr : read_base;
    assign rdata = mem[raddr + base]; // raddr+base wraps in AW bits

endmodule
