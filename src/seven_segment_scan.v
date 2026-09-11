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
    input wire [1:0] selected_count,
    input wire [7:0] total_due,
    input wire [7:0] first_item_total,
    input wire [7:0] paid_amount,
    input wire [7:0] change_due,
    output reg [7:0] seg,
    output reg [7:0] sel
);

    // 八位数码管从左到右依次显示：状态、商品行、商品列、数量、
    // 订单金额十位、订单金额个位、余额十位、余额个位。
    // refresh_count 的最高三位直接作为 0～7 扫描索引；默认 REFRESH_BITS=16
    // 时，每位刷新频率约为 50 MHz/2^16≈763 Hz，肉眼看到的是稳定八位显示。
    reg [REFRESH_BITS-1:0] refresh_count;
    wire [2:0] scan_index;
    reg [3:0] digit;
    reg [7:0] seg_active_low;
    reg [7:0] sel_active_high;
    wire [7:0] aux_amount;
    wire show_order_total;
    wire [7:0] displayed_order_total;

    assign scan_index = refresh_count[REFRESH_BITS-1:REFRESH_BITS-3];
    // change_due 在新订单中也表示可复用余额；付款状态还要加上本次投入金额。
    // 核心已保证 change_due+paid_amount 不超过 255，因此这里的 8 位加法不会回绕。
    assign aux_amount = (state == 3'd4) ? (change_due + paid_amount) : change_due;
    // 商品选择页的第 5、6 位只显示此前已确认的第一种商品小计；
    // 状态 3 及之后显示当前完整订单总价。
    assign show_order_total = (state >= 3'd3) ||
                              (((state == 3'd1) || (state == 3'd2)) &&
                               (selected_count != 2'd0));
    // displayed_order_total 只选择显示来源，不修改核心中的实际订单金额。
    assign displayed_order_total = (state >= 3'd3) ? total_due : first_item_total;

    function [3:0] tens_digit;
        input [7:0] value;
        begin
            // 再取模 10，故金额超过 99 时只显示其十位，不显示百位。
            tens_digit = (value / 8'd10) % 8'd10;
        end
    endfunction

    function [3:0] visible_state;
        input [2:0] raw_state;
        begin
            case (raw_state)
                3'd0: visible_state = 4'd0; // 空闲
                3'd1: visible_state = 4'd1; // 选择商品编号
                3'd2: visible_state = 4'd2; // 选择数量
                3'd3: visible_state = 4'd3; // 订单确认
                3'd4: visible_state = 4'd4; // 付款
                3'd5: visible_state = 4'd5; // 出货
                3'd6: visible_state = 4'd6; // 找零或退款
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
            // 段码按低电平点亮定义，位序与开发板 seg[7:0] 接线一致。
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
        // 每个分支同时给出当前位选和该位数字，覆盖全部 8 种 scan_index，
        // 因而该组合逻辑不会推断锁存器。
        case (scan_index)
            3'd0: begin
                sel_active_high = 8'b0000_0001;
                digit = visible_state(state);
            end
            3'd1: begin
                sel_active_high = 8'b0000_0010;
                // 商品高两位表示行号 0～3，显示时加 1 形成 A1～A4。
                digit = (state == 3'd0) ? 4'd0 : ({2'b00, product_code[3:2]} + 4'd1);
            end
            3'd2: begin
                sel_active_high = 8'b0000_0100;
                // 商品低两位表示列号 0～3，显示时加 1 形成第 1～4 列。
                digit = (state == 3'd0) ? 4'd0 : ({2'b00, product_code[1:0]} + 4'd1);
            end
            3'd3: begin
                sel_active_high = 8'b0000_1000;
                digit = ((state == 3'd2) || (state >= 3'd3)) ? {2'b00, quantity} : 4'd0;
            end
            3'd4: begin
                sel_active_high = 8'b0001_0000;
                digit = show_order_total ? tens_digit(displayed_order_total) : 4'd0;
            end
            3'd5: begin
                sel_active_high = 8'b0010_0000;
                digit = show_order_total ? ones_digit(displayed_order_total) : 4'd0;
            end
            3'd6: begin
                sel_active_high = 8'b0100_0000;
                digit = (state != 3'd0) ? tens_digit(aux_amount) : 4'd0;
            end
            default: begin
                sel_active_high = 8'b1000_0000;
                digit = (state != 3'd0) ? ones_digit(aux_amount) : 4'd0;
            end
        endcase

        seg_active_low = seg7(digit);
        // 参数允许在不改段码表的情况下适配不同有效电平的数码管硬件。
        seg = SEG_ACTIVE_LOW ? seg_active_low : ~seg_active_low;
        sel = SEL_ACTIVE_HIGH ? sel_active_high : ~sel_active_high;
    end

endmodule
