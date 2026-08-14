// trigger.v — LA step 3: hardware edge trigger.
// Watches ONE selected channel of the sample stream. Once `arm`ed, it fires a
// single-clock `trig` pulse the instant it sees the selected edge, then disarms.

module trigger(
    input  wire       clk,
    input  wire [7:0] sample,
    input  wire       sample_stb,
    input  wire       arm,        // 1-clock pulse: start watching
    input  wire [2:0] sel,        // which channel, 0..7
    input  wire [1:0] mode,       // 00 rising, 01 falling, 10 any
    output reg        trig,       // 1-clock pulse when the edge is seen
    output reg        armed       // high while watching
);

    wire cur = sample[sel]; //bit being watched
    reg prev;

    always @(posedge clk) begin
        trig <= 1'd0;

        if (arm) begin
            armed <= 1'd1;
        end
        else if (armed & sample_stb) begin
            prev <= cur;
            if ((mode == 2'b00 & (~prev & cur)) 
            || (mode == 2'b01 & (prev & ~cur)) 
            || (mode == 2'b10 & (prev ^ cur))) begin
                trig <= 1'd1;
                armed <= 1'd0;
            end
        end
    end


endmodule
