`timescale 1ns / 1ps

module seven_segment_scan #(
    parameter REFRESH_BITS = 16,
    parameter SEG_ACTIVE_LOW = 1,
    parameter SEL_ACTIVE_HIGH = 0
) (
    input wire clk,
    input wire reset,
    input wire [2:0] state,
    input wire [3:0] product_code,
    input wire [1:0] quantity,
    input wire [7:0] total_due,
    input wire [7:0] paid_amount,
    input wire [7:0] change_due,
    output reg [7:0] seg,
    output reg [7:0] sel
);

    reg [REFRESH_BITS-1:0] refresh_count;
    wire [2:0] scan_index;
    reg [3:0] digit;
    reg [7:0] seg_active_low;
    reg [7:0] sel_active_high;
    wire [7:0] aux_amount;

    assign scan_index = refresh_count[REFRESH_BITS-1:REFRESH_BITS-3];
    assign aux_amount = (state == 3'd6) ? change_due : paid_amount;

    function [3:0] tens_digit;
        input [7:0] value;
        begin
            tens_digit = (value / 8'd10) % 8'd10;
        end
    endfunction

    function [3:0] visible_state;
        input [2:0] raw_state;
        begin
            case (raw_state)
                3'd0: visible_state = 4'd0; // Idle.
                3'd1: visible_state = 4'd1; // Select product.
                3'd2: visible_state = 4'd2; // Select quantity.
                3'd3: visible_state = 4'd0; // Order ready, same display style as before.
                3'd4: visible_state = 4'd2; // Pay.
                3'd5: visible_state = 4'd3; // Vend.
                3'd6: visible_state = 4'd4; // Change/refund.
                default: visible_state = 4'd0;
            endcase
        end
    endfunction

    function [3:0] ones_digit;
        input [7:0] value;
        begin
            ones_digit = value % 8'd10;
        end
    endfunction

    function [7:0] seg7;
        input [3:0] value;
        begin
            case (value)
                4'd0: seg7 = 8'b1100_0000;
                4'd1: seg7 = 8'b1111_1001;
                4'd2: seg7 = 8'b1010_0100;
                4'd3: seg7 = 8'b1011_0000;
                4'd4: seg7 = 8'b1001_1001;
                4'd5: seg7 = 8'b1001_0010;
                4'd6: seg7 = 8'b1000_0010;
                4'd7: seg7 = 8'b1111_1000;
                4'd8: seg7 = 8'b1000_0000;
                4'd9: seg7 = 8'b1001_0000;
                default: seg7 = 8'b1111_1111;
            endcase
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            refresh_count <= {REFRESH_BITS{1'b0}};
        end else begin
            refresh_count <= refresh_count + 1'b1;
        end
    end

    always @* begin
        case (scan_index)
            3'd0: begin
                sel_active_high = 8'b0000_0001;
                digit = visible_state(state);
            end
            3'd1: begin
                sel_active_high = 8'b0000_0010;
                digit = (state == 3'd0) ? 4'd0 : ({2'b00, product_code[3:2]} + 4'd1);
            end
            3'd2: begin
                sel_active_high = 8'b0000_0100;
                digit = (state == 3'd0) ? 4'd0 : ({2'b00, product_code[1:0]} + 4'd1);
            end
            3'd3: begin
                sel_active_high = 8'b0000_1000;
                digit = ((state == 3'd2) || (state >= 3'd3)) ? {2'b00, quantity} : 4'd0;
            end
            3'd4: begin
                sel_active_high = 8'b0001_0000;
                digit = (state >= 3'd3) ? tens_digit(total_due) : 4'd0;
            end
            3'd5: begin
                sel_active_high = 8'b0010_0000;
                digit = (state >= 3'd3) ? ones_digit(total_due) : 4'd0;
            end
            3'd6: begin
                sel_active_high = 8'b0100_0000;
                digit = (state >= 3'd3) ? tens_digit(aux_amount) : 4'd0;
            end
            default: begin
                sel_active_high = 8'b1000_0000;
                digit = (state >= 3'd3) ? ones_digit(aux_amount) : 4'd0;
            end
        endcase

        seg_active_low = seg7(digit);
        seg = SEG_ACTIVE_LOW ? seg_active_low : ~seg_active_low;
        sel = SEL_ACTIVE_HIGH ? sel_active_high : ~sel_active_high;
    end

endmodule
