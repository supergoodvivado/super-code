`timescale 1ns / 1ps

module tb_state_display;
    // 本测试台通过强制 scan_index 固定当前扫描位，直接检查各位段码。
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

    // REFRESH_BITS 缩为 3，便于仿真；多数检查会直接 force 扫描索引。
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
            // 期望表与硬件低电平有效段码一致，用独立函数避免直接读取 DUT 内部函数。
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
        // 固定扫描到第 1 位，逐一检查状态 0～6 的显示编码。
        // scan_index 在设计中是计数器派生 wire；force 可临时覆盖它，
        // 从而稳定观察某一位，检查完成后必须 release 恢复正常扫描。
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

        // 从找零状态保留下来的余额在新订单选择期间仍应显示；
        // 付款状态显示“原有余额 + 本次投入金额”。
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

        // 选择第一种商品时第 5、6 位显示 00；选择第二种商品时，
        // 第 5、6 位继续显示已经确认的第一种商品小计。
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

        // 从确认页回退编辑第二种商品时，第二种商品先从订单中撤销；
        // 选择页及返回后的第一种商品确认页均应显示 18。
        selected_count = 1;
        total_due = 8'd18;
        first_item_total = 8'd18;
        force dut.scan_index = 3'd4;
        #1;
        if (seg !== expected_seg(1)) $fatal(1, "Reopened item-2 subtotal tens digit incorrect");
        force dut.scan_index = 3'd5;
        #1;
        if (seg !== expected_seg(8)) $fatal(1, "Reopened item-2 subtotal ones digit incorrect");

        // 返回状态 3 后，订单只包含保留下来的第一种商品。
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
