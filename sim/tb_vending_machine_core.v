`timescale 1ns / 1ps

module tb_vending_machine_core;

    reg clk;
    reg reset;
    reg [3:0] sw;
    reg key_product_pulse;
    reg key_confirm_pulse;
    reg key_change_pulse;
    reg key_cancel_pulse;
    wire [2:0] state;
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
    wire payment_insufficient_pulse;

    localparam ST_IDLE           = 3'd0;
    localparam ST_SELECT_PRODUCT = 3'd1;
    localparam ST_SELECT_QTY     = 3'd2;
    localparam ST_ORDER_READY    = 3'd3;
    localparam ST_PAY            = 3'd4;
    localparam ST_VEND           = 3'd5;
    localparam ST_CHANGE         = 3'd6;

    vending_machine_core #(
        .VEND_TICKS(3)
    ) dut (
        .clk(clk),
        .reset(reset),
        .sw(sw),
        .key_product_pulse(key_product_pulse),
        .key_confirm_pulse(key_confirm_pulse),
        .key_change_pulse(key_change_pulse),
        .key_cancel_pulse(key_cancel_pulse),
        .state(state),
        .selected_count(selected_count),
        .current_product_code(current_product_code),
        .current_quantity(current_quantity),
        .current_price(current_price),
        .total_due(total_due),
        .paid_amount(paid_amount),
        .change_due(change_due),
        .vend_pulse(vend_pulse),
        .return_coin_pulse(return_coin_pulse),
        .selection_full_pulse(selection_full_pulse),
        .payment_insufficient_pulse(payment_insufficient_pulse)
    );

    always #5 clk = ~clk;

    task pulse_product;
        begin
            @(negedge clk);
            key_product_pulse = 1'b1;
            @(negedge clk);
            key_product_pulse = 1'b0;
        end
    endtask

    task pulse_confirm;
        begin
            @(negedge clk);
            key_confirm_pulse = 1'b1;
            @(negedge clk);
            key_confirm_pulse = 1'b0;
        end
    endtask

    task pulse_change;
        begin
            @(negedge clk);
            key_change_pulse = 1'b1;
            @(negedge clk);
            key_change_pulse = 1'b0;
        end
    endtask

    task pulse_cancel;
        begin
            @(negedge clk);
            key_cancel_pulse = 1'b1;
            @(negedge clk);
            key_cancel_pulse = 1'b0;
        end
    endtask

    task expect_state;
        input [2:0] expected;
        begin
            if (state !== expected) begin
                $display("ERROR: expected state %0d, got %0d at %0t", expected, state, $time);
                $finish;
            end
        end
    endtask

    task expect_amount;
        input [7:0] expected_due;
        input [7:0] expected_paid;
        input [7:0] expected_change;
        begin
            if ((total_due !== expected_due) ||
                (paid_amount !== expected_paid) ||
                (change_due !== expected_change)) begin
                $display("ERROR: due=%0d paid=%0d change=%0d at %0t",
                         total_due, paid_amount, change_due, $time);
                $display("       expected due=%0d paid=%0d change=%0d",
                         expected_due, expected_paid, expected_change);
                $finish;
            end
        end
    endtask

    task wait_cycles;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    integer phase;
    integer populated;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        sw = 4'd0;
        key_product_pulse = 1'b0;
        key_confirm_pulse = 1'b0;
        key_change_pulse = 1'b0;
        key_cancel_pulse = 1'b0;

        wait_cycles(3);
        reset = 1'b0;
        wait_cycles(1);
        expect_state(ST_IDLE);

        // Wake the machine, then select A13 and quantity 3: 6 * 3 = 18.
        sw = 4'h2;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_product();
        expect_state(ST_SELECT_QTY);
        sw = 4'b0010;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd18, 8'd0, 8'd0);

        // Select A42, then quantity 2: 4 * 2 = 8. Total becomes 26.
        sw = 4'hD;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_product();
        expect_state(ST_SELECT_QTY);
        sw = 4'b0001;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd26, 8'd0, 8'd0);

        // A full order rejects KEY1 without changing the displayed product/order.
        sw = 4'hA;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd26, 8'd0, 8'd0);
        if (selected_count !== 2 || current_product_code !== 4'hD ||
            current_quantity !== 2 || selection_full_pulse !== 1'b1) begin
            $fatal(1, "Full order changed or rejection pulse missing");
        end
        @(negedge clk);
        if (selection_full_pulse !== 1'b0)
            $fatal(1, "Rejection pulse lasted more than one cycle");

        pulse_confirm();
        expect_state(ST_PAY);

        // Insert 20 yuan bill, then press KEY3: payment remains active and
        // emits an insufficient-payment warning.  A later sufficient amount
        // also remains in ST_PAY until KEY3 explicitly confirms payment.
        sw = 4'b0010;
        pulse_confirm();
        expect_amount(8'd26, 8'd20, 8'd0);
        pulse_change();
        expect_state(ST_PAY);
        expect_amount(8'd26, 8'd20, 8'd0);
        if (payment_insufficient_pulse !== 1'b1)
            $fatal(1, "Insufficient KEY3 confirmation did not issue warning");
        sw = 4'b0001;
        pulse_confirm();
        expect_state(ST_PAY);
        expect_amount(8'd26, 8'd30, 8'd0);
        pulse_change();
        expect_state(ST_VEND);
        expect_amount(8'd26, 8'd0, 8'd4);

        wait_cycles(5);
        expect_state(ST_CHANGE);

        pulse_change();
        expect_amount(8'd26, 8'd0, 8'd3);
        pulse_change();
        pulse_change();
        pulse_change();
        expect_state(ST_IDLE);
        expect_amount(8'd0, 8'd0, 8'd0);

        // Start a second transaction and cancel during payment.
        sw = 4'h4;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_amount(8'd10, 8'd0, 8'd0);
        pulse_confirm();
        expect_state(ST_PAY);
        sw = 4'b0000;
        pulse_confirm();
        expect_amount(8'd10, 8'd5, 8'd0);
        pulse_cancel();
        expect_state(ST_CHANGE);
        expect_amount(8'd10, 8'd0, 8'd5);

        pulse_change();
        pulse_change();
        pulse_change();
        pulse_change();
        pulse_change();
        expect_state(ST_IDLE);
        expect_amount(8'd0, 8'd0, 8'd0);

        // Retain 4 yuan change as a balance, then use it for a new order.
        // A13 x1 costs 6 yuan; 10 yuan leaves a 4 yuan balance.
        sw = 4'h2;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        pulse_confirm();
        sw = 4'b0001;
        pulse_confirm();
        pulse_change();
        expect_state(ST_VEND);
        expect_amount(8'd6, 8'd0, 8'd4);
        wait_cycles(5);
        expect_state(ST_CHANGE);

        // KEY1 starts another selection but preserves the 4 yuan balance.
        // A11 x1 costs 3.  Even though the balance is sufficient, KEY2 only
        // enters payment; KEY3 must explicitly apply the balance and vend.
        sw = 4'h0;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        expect_amount(8'd0, 8'd0, 8'd4);
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd3, 8'd0, 8'd4);
        pulse_confirm();
        expect_state(ST_PAY);
        expect_amount(8'd3, 8'd0, 8'd4);
        pulse_change();
        expect_state(ST_VEND);
        expect_amount(8'd3, 8'd0, 8'd1);
        wait_cycles(5);
        expect_state(ST_CHANGE);

        // A12 x1 costs 4.  The retained 1 yuan is insufficient, so three
        // more 1-yuan coins complete the payment.
        sw = 4'h1;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd4, 8'd0, 8'd1);
        pulse_confirm();
        expect_state(ST_PAY);
        expect_amount(8'd4, 8'd0, 8'd1);
        pulse_product();
        expect_amount(8'd4, 8'd1, 8'd1);
        pulse_product();
        expect_amount(8'd4, 8'd2, 8'd1);
        pulse_product();
        expect_state(ST_PAY);
        pulse_change();
        expect_state(ST_VEND);
        expect_amount(8'd4, 8'd0, 8'd0);
        wait_cycles(5);
        expect_state(ST_IDLE);

        // KEY3 returns from first-product selection to idle.
        sw = 4'h4;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_IDLE);

        // Commit A13 x1 as the first item.
        sw = 4'h2;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd6, 8'd0, 8'd0);

        // KEY3 at confirmation reopens item 1 quantity; KEY3 there returns
        // to product selection, and KEY3 while selecting item 1 returns to
        // its original confirmation page.
        pulse_change();
        expect_state(ST_SELECT_QTY);
        if (current_product_code !== 4'h2 || current_quantity !== 1)
            $fatal(1, "KEY3 did not restore item 1 quantity");
        pulse_change();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_ORDER_READY);
        if (current_product_code !== 4'h2 || current_quantity !== 1)
            $fatal(1, "KEY3 did not restore item 1 confirmation");

        // Start choosing item 2, then KEY3 returns to item 1 confirmation.
        sw = 4'hD;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_ORDER_READY);
        if (current_product_code !== 4'h2 || current_quantity !== 1)
            $fatal(1, "KEY3 did not return from item 2 selection");

        // Commit A42 x2, then reopen and replace its quantity with 3.
        sw = 4'hD;
        pulse_product();
        pulse_product();
        sw = 4'b0001;
        pulse_product();
        expect_amount(8'd14, 8'd0, 8'd0);
        pulse_change();
        expect_state(ST_SELECT_QTY);
        if (current_product_code !== 4'hD || current_quantity !== 2)
            $fatal(1, "KEY3 did not restore item 2 quantity");
        sw = 4'b0010;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd18, 8'd0, 8'd0);
        pulse_cancel();
        expect_state(ST_IDLE);

        // KEY4 in all selection states returns idle when no balance exists.
        sw = 4'h4;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_cancel();
        expect_state(ST_IDLE);
        sw = 4'h4;
        pulse_product();
        pulse_product();
        expect_state(ST_SELECT_QTY);
        pulse_cancel();
        expect_state(ST_IDLE);
        sw = 4'h4;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_state(ST_ORDER_READY);
        pulse_cancel();
        expect_state(ST_IDLE);

        // Create a 4 yuan balance, then verify KEY4 in every selection state
        // discards the order and enters the refund state with that balance.
        sw = 4'h2;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        pulse_confirm();
        sw = 4'b0001;
        pulse_confirm();
        pulse_change();
        expect_state(ST_VEND);
        expect_amount(8'd6, 8'd0, 8'd4);
        wait_cycles(5);
        expect_state(ST_CHANGE);

        // In first-product selection, KEY3 matches KEY4 when a balance exists.
        sw = 4'h4;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_CHANGE);
        expect_amount(8'd0, 8'd0, 8'd4);

        sw = 4'h4;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_cancel();
        expect_state(ST_CHANGE);
        expect_amount(8'd0, 8'd0, 8'd4);

        sw = 4'h4;
        pulse_product();
        pulse_product();
        expect_state(ST_SELECT_QTY);
        pulse_cancel();
        expect_state(ST_CHANGE);
        expect_amount(8'd0, 8'd0, 8'd4);

        sw = 4'h4;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_state(ST_ORDER_READY);
        pulse_cancel();
        expect_state(ST_CHANGE);
        expect_amount(8'd0, 8'd0, 8'd4);
        pulse_change();
        pulse_change();
        pulse_change();
        pulse_change();
        expect_state(ST_IDLE);

        // Amount registers retain the hundreds digit even though the display
        // intentionally renders only the tens and ones positions.  Amounts
        // above the 255-yuan limit are rejected without changing the balance.
        sw = 4'h0;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product(); // A11 x1 costs 3.
        pulse_confirm();
        expect_state(ST_PAY);
        sw = 4'b0011; // 50 yuan.
        pulse_confirm();
        pulse_confirm();
        pulse_confirm();
        pulse_confirm();
        pulse_confirm();
        expect_state(ST_PAY);
        expect_amount(8'd3, 8'd250, 8'd0);
        pulse_product();
        pulse_product();
        pulse_product();
        pulse_product();
        pulse_product();
        expect_amount(8'd3, 8'd255, 8'd0);
        pulse_product();
        expect_state(ST_PAY);
        expect_amount(8'd3, 8'd255, 8'd0);
        if (payment_insufficient_pulse !== 1'b1)
            $fatal(1, "Over-limit payment did not issue warning");
        pulse_change();
        expect_state(ST_VEND);
        expect_amount(8'd3, 8'd0, 8'd252);

        $display("PASS: vending machine core simulation completed.");
        $finish;
    end

endmodule
