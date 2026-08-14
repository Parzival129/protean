// sampler.v - synchronous multi-channel sampler.
// The testbench (sim/sampler_tb.v) drives known values and checks each captured sample.
module sampler #(
    parameter DIV = 27  // sample every DIV clocks (real rate = 27MHz/DIV; tb overrides small)
)(
    input  wire       clk,
    input  wire [7:0] probes,      // async raw inputs from the probe header
    output reg  [7:0] sample,      // latched, synchronized sample word
    output reg        sample_stb   // 1-clock strobe: `sample` just updated
);

    reg [7:0] sync1, synced;
    reg [5:0] counter = 5'd0;
    
    always @(posedge clk) begin
        
        sync1 <= probes;
        synced <= sync1; // to resolve metastabilty 
        sample_stb <= 1'd0;

        if (counter == DIV-1) begin
            sample_stb <= 1'd1;
            counter <= 5'd0;
            sample <= synced;
        end
        else begin
            counter <= counter + 5'd1;
        end
    end

endmodule
