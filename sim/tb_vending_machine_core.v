`timescale 1ns / 1ps

module tb_vending_machine_core;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [3:0] sw = 4'd0;
    reg key_product_pulse = 1'b0;
    reg key_confirm_pulse = 1'b0;
    reg key_change_pulse = 1'b0;
    reg key_cancel_pulse = 1'b0;
    reg admin_enter_pulse = 1'b0;
    wire [3:0] state;
    wire [1:0] selected_count;
    wire [3:0] current_product_code;
    wire [1:0] current_quantity;
    wire [7:0] current_price;
    wire [7:0] total_due;
    wire [7:0] paid_amount;
    wire [7:0] change_due;
    wire vend_pulse;
    wire return_coin_pulse;
    wire selection_full_pulse;
    wire sold_out_pulse;
    wire change_unavailable_pulse;
    wire payment_insufficient_pulse;
    wire [3:0] stock_selected;

    localparam ST_IDLE = 4'd0;
    localparam ST_SELECT_PRODUCT = 4'd1;
    localparam ST_SELECT_QTY = 4'd2;
    localparam ST_ORDER_READY = 4'd3;
    localparam ST_PAY = 4'd4;
    localparam ST_VEND = 4'd5;
    localparam ST_ADMIN_SELECT = 4'd7;
    localparam ST_ADMIN_VIEW = 4'd8;
    localparam ST_ADMIN_PRICE = 4'd9;

    vending_machine_core #(.VEND_TICKS(2)) dut (
        .clk(clk), .reset(reset), .sw(sw),
        .key_product_pulse(key_product_pulse),
        .key_confirm_pulse(key_confirm_pulse),
        .key_change_pulse(key_change_pulse),
        .key_cancel_pulse(key_cancel_pulse),
        .admin_enter_pulse(admin_enter_pulse),
        .state(state), .selected_count(selected_count),
        .current_product_code(current_product_code),
        .current_quantity(current_quantity), .current_price(current_price),
        .total_due(total_due), .paid_amount(paid_amount),
        .change_due(change_due), .vend_pulse(vend_pulse),
        .return_coin_pulse(return_coin_pulse),
        .selection_full_pulse(selection_full_pulse),
        .sold_out_pulse(sold_out_pulse),
        .change_unavailable_pulse(change_unavailable_pulse),
        .payment_insufficient_pulse(payment_insufficient_pulse),
        .stock_selected(stock_selected)
    );

    always #5 clk = ~clk;

    task pulse_product;
        begin @(negedge clk); key_product_pulse = 1'b1;
              @(negedge clk); key_product_pulse = 1'b0; end
    endtask
    task pulse_confirm;
        begin @(negedge clk); key_confirm_pulse = 1'b1;
              @(negedge clk); key_confirm_pulse = 1'b0; end
    endtask
    task pulse_change;
        begin @(negedge clk); key_change_pulse = 1'b1;
              @(negedge clk); key_change_pulse = 1'b0; end
    endtask
    task pulse_cancel;
        begin @(negedge clk); key_cancel_pulse = 1'b1;
              @(negedge clk); key_cancel_pulse = 1'b0; end
    endtask
    task expect_state;
        input [3:0] expected;
        begin
            if (state !== expected) $fatal(1, "state=%0d expected=%0d", state, expected);
        end
    endtask
    task wait_cycles;
        input integer count;
        integer i;
        begin for (i = 0; i < count; i = i + 1) @(posedge clk); end
    endtask


    initial begin
        wait_cycles(3);
        reset = 1'b0;
        wait_cycles(1);
        expect_state(ST_IDLE);
        if (stock_selected !== 4'd5) $fatal(1, "initial inventory is not 5");

        // Two different products may each use three of their own five units.
        // This specifically guards against cross-product stock accounting.
        sw = 4'hA; pulse_product(); pulse_product();
        sw = 4'b0010; pulse_product(); expect_state(ST_ORDER_READY);
        sw = 4'h8; pulse_product(); expect_state(ST_SELECT_PRODUCT);
        pulse_product(); expect_state(ST_SELECT_QTY);
        sw = 4'b0010; pulse_product(); expect_state(ST_ORDER_READY);
        if (selected_count !== 2'd2 || total_due !== 8'd57)
            $fatal(1, "different products quantity selection failed");
        pulse_cancel(); expect_state(ST_IDLE);

        // A13 x3 costs 18. Insert 50; the sale reduces stock to 2. Exercise
        // both refund paths: KEY2 returns 20 and 10, then KEY3 returns 1.
        sw = 4'h2; pulse_product(); expect_state(ST_SELECT_PRODUCT);
        pulse_product(); expect_state(ST_SELECT_QTY);
        sw = 4'b0010; pulse_product(); expect_state(ST_ORDER_READY);
        if (total_due !== 8'd18) $fatal(1, "A13 x3 total incorrect");
        pulse_confirm(); expect_state(ST_PAY);
        sw = 4'b0011; pulse_confirm();
        pulse_change(); expect_state(ST_VEND);
        wait_cycles(4); expect_state(4'd6);
        sw = 4'b0010; pulse_confirm();
        sw = 4'b0001; pulse_confirm();
        pulse_change(); pulse_change(); expect_state(ST_IDLE);
        sw = 4'h2; pulse_product(); pulse_product();
        if (stock_selected !== 4'd2) $fatal(1, "inventory did not decrement after vend");
        pulse_cancel(); expect_state(ST_IDLE);

        // Admin entry, view A13, replenish twice, set price to 7.
        admin_enter_pulse = 1'b1; @(negedge clk); admin_enter_pulse = 1'b0;
        expect_state(ST_ADMIN_SELECT);
        sw = 4'h2; pulse_product(); expect_state(ST_ADMIN_VIEW);
        if (stock_selected !== 4'd2 || current_price !== 8'd6)
            $fatal(1, "admin view incorrect");
        pulse_confirm(); pulse_confirm();
        if (stock_selected !== 4'd4) $fatal(1, "replenish failed");
        pulse_change(); expect_state(ST_ADMIN_PRICE);
        sw = 4'd7; pulse_product(); expect_state(ST_ADMIN_VIEW);
        if (current_price !== 8'd7) begin
            $display("DEBUG price=%0d array=%0d code=%0d state=%0d sw=%0d", current_price,
                     dut.prices[2], current_product_code, state, sw);
            $fatal(1, "price update failed");
        end
        pulse_cancel(); expect_state(ST_IDLE);

        // Empty the remaining four A13 units in two orders, then verify the
        // next attempt is rejected with sold_out_pulse.
        sw = 4'h2; pulse_product(); pulse_product(); sw = 4'b0001;
        pulse_product(); pulse_confirm(); sw = 4'b0001; pulse_confirm();
        sw = 4'h2; pulse_product(); pulse_product(); pulse_product(); pulse_product();
        pulse_change(); wait_cycles(4);
        sw = 4'h2; pulse_product(); pulse_product(); sw = 4'b0001;
        pulse_product(); pulse_confirm(); sw = 4'b0001; pulse_confirm();
        sw = 4'h2; pulse_product(); pulse_product(); pulse_product(); pulse_product();
        pulse_change(); wait_cycles(4);
        sw = 4'h2; pulse_product(); pulse_product();
        if (state !== ST_SELECT_PRODUCT || sold_out_pulse !== 1'b1)
            $fatal(1, "sold-out selection was not rejected");

        $display("PASS: inventory, admin and manual change simulation completed.");
        $finish;
    end
endmodule
