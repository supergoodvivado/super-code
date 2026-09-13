`timescale 1ns / 1ps

module button_conditioner #(
    parameter DEBOUNCE_TICKS = 500_000
) (
    input wire clk,
    input wire reset,
    input wire btn_n,
    output wire pressed_level,
    output wire pressed_pulse
);

    reg [1:0] sync_reg;
    reg debounced;
    reg debounced_d;
    reg [31:0] count;
    wire pressed_raw;

    assign pressed_raw = ~btn_n;
    assign pressed_level = debounced;
    assign pressed_pulse = debounced & ~debounced_d;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sync_reg <= 2'b00;
            debounced <= 1'b0;
            debounced_d <= 1'b0;
            count <= 32'd0;
        end else begin
            sync_reg <= {sync_reg[0], pressed_raw};
            debounced_d <= debounced;

            if (sync_reg[1] == debounced) begin
                count <= 32'd0;
            end else if (count >= (DEBOUNCE_TICKS - 1)) begin
                debounced <= sync_reg[1];
                count <= 32'd0;
            end else begin
                count <= count + 32'd1;
            end
        end
    end

endmodule
