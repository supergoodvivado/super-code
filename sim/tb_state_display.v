`timescale 1ns / 1ps

module tb_state_display;
    reg clk = 0;
    reg reset = 0;
    reg [2:0] state;
    wire [7:0] seg;
    wire [7:0] sel;
    integer expected_state;

    seven_segment_scan #(.REFRESH_BITS(3)) dut (
        .clk(clk), .reset(reset), .state(state),
        .product_code(4'd0), .quantity(2'd0), .total_due(8'd0),
        .paid_amount(8'd0), .change_due(8'd0), .seg(seg), .sel(sel)
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
                default: expected_seg = 8'b1111_1111;
            endcase
        end
    endfunction

    initial begin
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
        $display("PASS: all seven state display codes are correct.");
        $finish;
    end
endmodule
