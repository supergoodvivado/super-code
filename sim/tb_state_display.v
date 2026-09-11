`timescale 1ns / 1ps

module tb_state_display;
    reg clk = 0;
    reg reset = 0;
    reg [2:0] state;
    reg [1:0] selected_count;
    reg [7:0] total_due;
    reg [7:0] first_item_total;
    reg [7:0] paid_amount;
    reg [7:0] change_due;
    wire [7:0] seg;
    wire [7:0] sel;
    integer expected_state;

    seven_segment_scan #(.REFRESH_BITS(3)) dut (
        .clk(clk), .reset(reset), .state(state),
        .product_code(4'd0), .quantity(2'd0), .total_due(total_due),
        .selected_count(selected_count),
        .first_item_total(first_item_total),
        .paid_amount(paid_amount), .change_due(change_due), .seg(seg), .sel(sel)
    );

    always #5 clk = ~clk;

    function [7:0] expected_seg;
        input integer value;
        begin
            case (value)
                0: expected_seg = 8'b1100_0000;
                1: expected_seg = 8'b1111_1001;
                2: expected_seg = 8'b1010_0100;
                3: expected_seg = 8'b1011_0000;
                4: expected_seg = 8'b1001_1001;
                5: expected_seg = 8'b1001_0010;
                6: expected_seg = 8'b1000_0010;
                7: expected_seg = 8'b1111_1000;
                8: expected_seg = 8'b1000_0000;
                9: expected_seg = 8'b1001_0000;
                default: expected_seg = 8'b1111_1111;
            endcase
        end
    endfunction

    initial begin
        selected_count = 0;
        total_due = 0;
        first_item_total = 0;
        // Force the first digit of the multiplexed display for direct checking.
        force dut.scan_index = 3'd0;
        for (expected_state = 0; expected_state < 7;
             expected_state = expected_state + 1) begin
            state = expected_state[2:0];
            #1;
            if (seg !== expected_seg(expected_state))
                $fatal(1, "State %0d displayed %b instead of %b", expected_state,
                       seg, expected_seg(expected_state));
        end
        release dut.scan_index;

        // A balance carried from ST_CHANGE remains visible while selecting a
        // new item.  During payment the display is balance plus new coins.
        paid_amount = 8'd0;
        change_due = 8'd4;
        state = 3'd1;
        force dut.scan_index = 3'd6;
        #1;
        if (seg !== expected_seg(0)) $fatal(1, "Balance tens digit missing");
        force dut.scan_index = 3'd7;
        #1;
        if (seg !== expected_seg(4)) $fatal(1, "Balance ones digit missing");
        state = 3'd4;
        paid_amount = 8'd5;
        #1;
        if (seg !== expected_seg(9))
            $fatal(1, "Payment total display incorrect: got %b", seg);
        release dut.scan_index;

        // Digits 5 and 6 are 00 while selecting item 1, then retain the
        // committed item-1 subtotal while choosing item 2.
        state = 3'd1;
        selected_count = 0;
        total_due = 8'd18;
        first_item_total = 8'd18;
        force dut.scan_index = 3'd4;
        #1;
        if (seg !== expected_seg(0)) $fatal(1, "Item-1 selection subtotal should be 00");
        selected_count = 1;
        #1;
        if (seg !== expected_seg(1)) $fatal(1, "Item-2 subtotal tens digit incorrect");
        force dut.scan_index = 3'd5;
        #1;
        if (seg !== expected_seg(8)) $fatal(1, "Item-2 subtotal ones digit incorrect");
        state = 3'd2;
        force dut.scan_index = 3'd4;
        #1;
        if (seg !== expected_seg(1)) $fatal(1, "Item-2 quantity subtotal tens digit incorrect");
        force dut.scan_index = 3'd5;
        #1;
        if (seg !== expected_seg(8)) $fatal(1, "Item-2 quantity subtotal ones digit incorrect");

        // Reopening item 2 pops it from the committed order.  The selection
        // page and the resulting item-1 confirmation both display 18.
        selected_count = 1;
        total_due = 8'd18;
        first_item_total = 8'd18;
        force dut.scan_index = 3'd4;
        #1;
        if (seg !== expected_seg(1)) $fatal(1, "Reopened item-2 subtotal tens digit incorrect");
        force dut.scan_index = 3'd5;
        #1;
        if (seg !== expected_seg(8)) $fatal(1, "Reopened item-2 subtotal ones digit incorrect");

        // Returning to state 3 now confirms only the retained first item.
        state = 3'd3;
        force dut.scan_index = 3'd4;
        #1;
        if (seg !== expected_seg(1)) $fatal(1, "Order total tens digit incorrect after return");
        force dut.scan_index = 3'd5;
        #1;
        if (seg !== expected_seg(8)) $fatal(1, "Order total ones digit incorrect after return");
        release dut.scan_index;
        $display("PASS: state codes and reusable balance display are correct.");
        $finish;
    end
endmodule
