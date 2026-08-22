// la_engine.v — the LA capture engine: sampler + trigger + capture as one unit

module la_engine #(
    parameter DEPTH = 1024,
    parameter AW    = 10,
    parameter POST  = 512,       // post-trigger samples (rest of ring is pre-trigger)
    parameter DIV   = 27
)(
    input  wire          clk,
    input  wire [7:0]    probes,     // async probe inputs
    input  wire          go,         // 1-clock pulse: arm trigger, then wait for the edge
    input  wire [2:0]    sel,        // trigger channel
    input  wire [1:0]    mode,       // trigger edge: 00 rising, 01 falling, 10 any
    output wire          capturing,
    output wire          full,
    output wire          armed,      // high while waiting for the trigger edge
    input  wire [AW-1:0] raddr,      // read the capture back
    output wire [7:0]    rdata
);

    wire [7:0] sample;
    wire sample_stb;
    wire trig;                   // trigger.trig -> capture.trig

    sampler #(.DIV(13500)) sampler (
        .clk(clk),
        .probes(probes),
        .sample(sample),
        .sample_stb(sample_stb)
    );

    capture #(.DEPTH(DEPTH), .AW(AW), .POST(POST))capture (
        .clk(clk),
        .sample(sample),
        .sample_stb(sample_stb),
        .rearm(go),
        .trig(trig),
        .capturing(capturing),
        .full(full),
        .raddr(raddr),
        .rdata(rdata)
    );

    trigger trigger (
        .clk(clk),
        .sample(sample),
        .sample_stb(sample_stb),
        .arm(go),
        .sel(sel),
        .mode(mode),
        .trig(trig),
        .armed(armed)
    );

endmodule
