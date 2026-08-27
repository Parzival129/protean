// gb_keymap.v — CardKB byte -> Game Boy joypad (boy.key, active-high 1=pressed):

module gb_keymap(
    input  wire       clk,        // 27 MHz
    input  wire [7:0] kbd_byte,   // byte from i2c_master (0 = no key)
    input  wire       kbd_valid,  // 1-clock strobe: kbd_byte updated
    input  wire       kbd_acked,  // slave answered (gate on this)
    output reg  [7:0] joypad
);

    reg [21:0] hold;  // countdown window to hold a key since the cardKB is on-press signal only

    always @(posedge clk) begin
        

        if (kbd_valid && kbd_acked && kbd_byte != 0) begin
            joypad <= 8'b0; // clear old
            case (kbd_byte)
                8'hB7: joypad[4] <= 1; // right
                8'hB4: joypad[5] <= 1; // left
                8'hB5: joypad[6] <= 1; // up
                8'hB6: joypad[7] <= 1; // down
                8'h7A: joypad[0] <= 1; // Z -> A
                8'h78: joypad[1] <= 1; // X -> B
                8'h20: joypad[2] <= 1; // space -> select
                8'h0D: joypad[3] <= 1; // enter -> start
            endcase
            hold <= 22'd3_240_000;
        end
        else if (hold != 0) begin
            hold <= hold - 1;
            if (hold == 1) joypad <= 8'b0; // hold window expired
        end
    end

endmodule
