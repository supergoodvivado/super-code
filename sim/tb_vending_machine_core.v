`timescale 1ns / 1ps

module tb_vending_machine_core;
    // 缩短出货计数周期，便于在仿真中覆盖完整购买流程。

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
    wire [7:0] first_item_total;
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
        .first_item_total(first_item_total),
        .paid_amount(paid_amount),
        .change_due(change_due),
        .vend_pulse(vend_pulse),
        .return_coin_pulse(return_coin_pulse),
        .selection_full_pulse(selection_full_pulse),
        .payment_insufficient_pulse(payment_insufficient_pulse)
    );

    // 10 ns 周期仅用于加快行为仿真；设计逻辑按时钟拍数工作，不依赖此处频率。
    always #5 clk = ~clk;

    // 四个 pulse_* 任务都在下降沿改变输入，使脉冲完整覆盖下一个上升沿，
    // 避免测试激励与 DUT 的 posedge 时序逻辑发生竞争。
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
            // 使用 case inequality（!==），这样 X/Z 未知态也会立即判为失败。
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
            // 每个关键步骤同时检查订单、投入和余额，防止只看状态而漏掉金额错误。
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
        // 所有按键脉冲先置零；复位保持三个周期，再等待一拍后开始检查。
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

        // 唤醒机器，选择 A13、数量 3：6 × 3 = 18 元。
        sw = 4'h2;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_product();
        expect_state(ST_SELECT_QTY);
        sw = 4'b0010;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd18, 8'd0, 8'd0);

        // 再选择 A42、数量 2：4 × 2 = 8 元，订单总价变为 26 元。
        sw = 4'hD;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_product();
        expect_state(ST_SELECT_QTY);
        sw = 4'b0001;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd26, 8'd0, 8'd0);

        // 已选满两种商品后拒绝 KEY1，当前商品和订单内容都不能改变。
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

        // 投入 20 元后按 KEY3，金额不足，应停留在付款状态并发出提示。
        // 后续金额足够时仍不能自动出货，必须再次按 KEY3 明确确认。
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

        // 开始第二笔交易，并验证付款过程中取消会进入退款状态。
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

        // A13 ×1 售价 6 元，投入 10 元后留下 4 元零钱；
        // 不立即取走零钱，将其作为下一笔订单的余额继续使用。
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

        // KEY1 开始新选择时保留 4 元余额。A11 ×1 售价 3 元，
        // 即使余额足够，KEY2 也只进入付款状态，仍需 KEY3 确认后出货。
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

        // A12 ×1 售价 4 元，已有余额 1 元，再投入三个 1 元硬币完成付款。
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

        // 尚未确认第一种商品时，KEY3 从商品选择页返回空闲状态。
        sw = 4'h4;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_IDLE);

        // 将 A13 ×1 确认为第一种商品。
        sw = 4'h2;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd6, 8'd0, 8'd0);

        // 确认页按 KEY3 时先撤销第一种商品，再进入其数量页；
        // 继续从数量页、商品页逐级回退，最终应到达空闲状态。
        pulse_change();
        expect_state(ST_SELECT_QTY);
        expect_amount(8'd0, 8'd0, 8'd0);
        if (selected_count !== 0 || first_item_total !== 0)
            $fatal(1, "KEY3 did not pop item 1 before editing");
        if (current_product_code !== 4'h2 || current_quantity !== 1)
            $fatal(1, "KEY3 did not restore item 1 quantity");
        pulse_change();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_IDLE);

        // 再次确认 A13 ×1，为两种商品的回退测试建立初始订单。
        sw = 4'h2;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd6, 8'd0, 8'd0);

        // 开始选择第二种商品后按 KEY3，应返回第一种商品确认页。
        sw = 4'hD;
        pulse_product();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_ORDER_READY);
        if (current_product_code !== 4'h2 || current_quantity !== 1)
            $fatal(1, "KEY3 did not return from item 2 selection");

        // 确认 A42 ×2。回退编辑时只撤销第二种商品，订单保留 A13 ×1；
        // 再次确认数量后，将修改后的第二种商品重新加入订单。
        sw = 4'hD;
        pulse_product();
        pulse_product();
        sw = 4'b0001;
        pulse_product();
        expect_amount(8'd14, 8'd0, 8'd0);
        pulse_change();
        expect_state(ST_SELECT_QTY);
        expect_amount(8'd6, 8'd0, 8'd0);
        if (selected_count !== 1 || first_item_total !== 6)
            $fatal(1, "KEY3 did not retain only item 1 while editing item 2");
        if (current_product_code !== 4'hD || current_quantity !== 2)
            $fatal(1, "KEY3 did not restore item 2 quantity");
        sw = 4'b0010;
        pulse_product();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd18, 8'd0, 8'd0);

        // 连续按 KEY3 应依次撤销第二种和第一种商品，不能恢复原两件总价，
        // 也不能再次进入 3→2→1 的循环。
        pulse_change();
        expect_state(ST_SELECT_QTY);
        expect_amount(8'd6, 8'd0, 8'd0);
        pulse_change();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_ORDER_READY);
        expect_amount(8'd6, 8'd0, 8'd0);
        if (selected_count !== 1 || current_product_code !== 4'h2)
            $fatal(1, "KEY3 did not return to the item-1 confirmation page");
        pulse_change();
        expect_state(ST_SELECT_QTY);
        expect_amount(8'd0, 8'd0, 8'd0);
        if (current_product_code !== 4'h2 || selected_count !== 0)
            $fatal(1, "KEY3 did not reach the item-1 quantity page");
        pulse_change();
        expect_state(ST_SELECT_PRODUCT);
        pulse_change();
        expect_state(ST_IDLE);

        // 没有余额时，在所有选择状态按 KEY4 都应返回空闲状态。
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

        // 建立 4 元余额，验证各选择状态下 KEY4 都会取消订单，
        // 同时保留余额并进入退款状态。
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

        // 有余额且正在选择第一种商品时，KEY3 与 KEY4 一样进入退款状态。
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

        // 金额寄存器保留百位数据，但数码管只显示十位和个位；
        // 超过 255 元的投入必须被拒绝，且不能改变已有金额。
        sw = 4'h0;
        pulse_product();
        pulse_product();
        sw = 4'b0000;
        pulse_product(); // A11 ×1 售价 3 元
        pulse_confirm();
        expect_state(ST_PAY);
        sw = 4'b0011; // 选择 50 元纸币
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
