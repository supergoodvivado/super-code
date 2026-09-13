`timescale 1ns / 1ps

module seven_segment_scan #(
    parameter REFRESH_BITS = 16,
    parameter SEG_ACTIVE_LOW = 1,
    parameter SEL_ACTIVE_HIGH = 0
) (
    input wire clk,
    input wire reset,
    input wire [3:0] state,
    input wire [3:0] product_code,
    input wire [1:0] quantity,
    input wire [1:0] selected_count,
    input wire [7:0] total_due,
    input wire [7:0] paid_amount,
    input wire [7:0] change_due,
    input wire [3:0] stock_selected,
    input wire [7:0] current_price,
    input wire [3:0] admin_price_input,
    output reg [7:0] seg,
    output reg [7:0] sel
);

    reg [REFRESH_BITS-1:0] refresh_count;
    wire [2:0] scan_index;
    reg [3:0] digit;
    reg [7:0] seg_active_low;
    reg [7:0] sel_active_high;
    wire [7:0] aux_amount;
    wire show_order_total;

    assign scan_index = refresh_count[REFRESH_BITS-1:REFRESH_BITS-3];
    // change_due is also the reusable balance when a new order starts from
    // the change state.  During payment, include newly inserted money.
    assign aux_amount = (state == 4'd4) ? (change_due + paid_amount) : change_due;
    // When item 2 is being selected, item 1 has already been committed.
    // Keep its subtotal visible in digits 5 and 6; the first item's selection
    // still shows 00 until that item has been confirmed.
    assign show_order_total = (state >= 3'd3) ||
                              (((state == 3'd1) || (state == 3'd2)) &&
                               (selected_count == 2'd1));

    function [3:0] tens_digit;
        input [7:0] value;
        begin
            tens_digit = (value / 8'd10) % 8'd10;
        end
    endfunction

    function [3:0] visible_state;
        input [3:0] raw_state;
        begin
            case (raw_state)
                4'd0: visible_state = 4'd0;
                4'd1: visible_state = 4'd1;
                4'd2: visible_state = 4'd2;
                4'd3: visible_state = 4'd3;
                4'd4: visible_state = 4'd4;
                4'd5: visible_state = 4'd5;
                4'd6: visible_state = 4'd6;
                4'd7: visible_state = 4'd7;
                4'd8: visible_state = 4'd8;
                4'd9: visible_state = 4'd9;
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
                digit = (state == 4'd0) ? 4'd0 : ({2'b00, product_code[3:2]} + 4'd1);
            end
            3'd2: begin
                sel_active_high = 8'b0000_0100;
                digit = (state == 4'd0) ? 4'd0 : ({2'b00, product_code[1:0]} + 4'd1);
            end
            3'd3: begin
                sel_active_high = 8'b0000_1000;
                if (state == 4'd7 || state == 4'd8 || state == 4'd9)
                    digit = (state == 4'd9) ? admin_price_input : stock_selected;
                else
                    digit = ((state == 4'd2) || (state >= 4'd3)) ? {2'b00, quantity} : 4'd0;
            end
            3'd4: begin
                sel_active_high = 8'b0001_0000;
                if (state == 4'd7 || state == 4'd8)
                    digit = tens_digit(current_price);
                else if (state == 4'd9)
                    digit = tens_digit({4'd0, admin_price_input});
                else
                    digit = show_order_total ? tens_digit(total_due) : 4'd0;
            end
            3'd5: begin
                sel_active_high = 8'b0010_0000;
                if (state == 4'd7 || state == 4'd8)
                    digit = ones_digit(current_price);
                else if (state == 4'd9)
                    digit = ones_digit({4'd0, admin_price_input});
                else
                    digit = show_order_total ? ones_digit(total_due) : 4'd0;
            end
            3'd6: begin
                sel_active_high = 8'b0100_0000;
                digit = (state == 4'd7 || state == 4'd8 || state == 4'd9) ?
                        4'd0 : ((state != 4'd0) ? tens_digit(aux_amount) : 4'd0);
            end
            default: begin
                sel_active_high = 8'b1000_0000;
                digit = (state == 4'd7 || state == 4'd8 || state == 4'd9) ?
                        stock_selected : ((state != 4'd0) ? ones_digit(aux_amount) : 4'd0);
            end
        endcase

        seg_active_low = seg7(digit);
        seg = SEG_ACTIVE_LOW ? seg_active_low : ~seg_active_low;
        sel = SEL_ACTIVE_HIGH ? sel_active_high : ~sel_active_high;
    end

endmodule
