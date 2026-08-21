// wave_pixel.v — LA waveform renderer: per-pixel decision (combinational).

module wave_pixel #(
    parameter LANE_H = 32,   // pixels per channel lane
    parameter NCH    = 8,    // channels drawn (top lane = channel 0)
    parameter HI_ROW = 8,    // row within a lane where a HIGH level line is drawn
    parameter LO_ROW = 24    // row within a lane where a LOW level line is drawn
)(
    input  wire [9:0] y,           // active-area row, 0..(NCH*LANE_H - 1)
    input  wire [7:0] col_sample,  // captured sample word for this column
    output reg        pix          // 1 = draw a trace pixel here
);

    wire [4:0] channel = y[9:5]; // divide by 32 by grabbing higher order bits
    wire [4:0] row = y[4:0]; // remainder
    wire chan_bit = col_sample[channel];

    always @(*) begin
        pix = 0;
        if (channel < NCH) begin
            if (chan_bit == 1 & row == HI_ROW) pix = 1;
            if (chan_bit == 0 & row == LO_ROW) pix = 1;
        end
    end


endmodule