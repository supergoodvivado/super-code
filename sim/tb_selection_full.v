`timescale 1ns / 1ps

module tb_selection_full;
    reg clk = 0;
    reg reset = 1;
    reg [3:0] sw = 0;
    reg product = 0;
    reg confirm = 0;
    reg cancel = 0;
    wire [3:0] led;
    wire [7:0] seg, sel;
    wire buzzer;
    integer i, scan;
    reg [7:0] saved_seg [0:7];

    // 将真实硬件中的 5,000,000 拍缩短为 4 拍，因此四个亮灭相位共 16 拍。
    vending_machine_top #(
        .FULL_BLINK_TICKS(4),
        .PAYMENT_ERROR_BLINK_TICKS(4)
    ) dut (
        .clk(clk), .sw(sw), .key_n(4'hF), .led(led),
        .seg(seg), .sel(sel), .buzzer(buzzer)
    );
    always #5 clk = ~clk;

    task press_product;
        begin
            // 在下降沿改变强制脉冲，保证 DUT 在下一上升沿稳定采样。
            @(negedge clk); product = 1;
            @(negedge clk); product = 0;
        end
    endtask

    task press_confirm;
        begin
            @(negedge clk); confirm = 1;
            @(negedge clk); confirm = 0;
        end
    endtask

    task check_order;
        begin
            // 达到两种商品上限后的拒绝提示不能改写订单核心字段。
            if (dut.state !== 3 || dut.selected_count !== 2 ||
                dut.current_product_code !== 4'hD ||
                dut.current_quantity !== 2 || dut.total_due !== 26)
                $fatal(1, "Full order was modified");
            // 强制选择每一位数码管并逐位比较，避免动态扫描时序影响判断。
            for (scan = 0; scan < 8; scan = scan + 1) begin
                force dut.display.scan_index = scan;
                #0.01;
                if (seg !== saved_seg[scan])
                    $fatal(1, "Display digit %0d changed", scan);
            end
            release dut.display.scan_index;
        end
    endtask

    initial begin
        // 直接注入消抖后的按键脉冲，同时验证真实核心、LED 和显示逻辑。
        // 绕过耗时的物理按键消抖，仅跳过输入前端；顶层其余逻辑仍真实参与测试。
        force dut.reset = reset;
        force dut.product_pulse = product;
        force dut.confirm_pulse = confirm;
        force dut.cancel_pulse = cancel;
        force dut.change_pulse = 0;
        repeat (3) @(negedge clk);
        reset = 0;
        sw = 2;
        press_product(); press_product(); press_product(); // 选择 A13，数量为 3
        sw = 4'hD;
        press_product(); press_product();
        sw = 1;
        press_product(); // 选择 A42，数量为 2，订单总价为 26
        for (scan = 0; scan < 8; scan = scan + 1) begin
            force dut.display.scan_index = scan;
            #0.01; saved_seg[scan] = seg;
        end
        release dut.display.scan_index;
        if (led !== 4'b0001) $fatal(1, "Expected green order LED on");
        sw = 4'hA;
        press_product();
        @(negedge clk); // 等待寄存后的拒绝脉冲传到 LED 控制逻辑
        // 4 相位 × 每相位 4 拍：偶数阶段亮/鸣，奇数阶段灭/静音。
        for (i = 0; i < 16; i = i + 1) begin
            if (led !== ((i / 4) % 2 ? 4'b0000 : 4'b0001))
                $fatal(1, "Selection limit did not flash green at cycle %0d", i);
            if (dut.error_beep_enable !== led[0])
                $fatal(1, "Buzzer enable is not synchronized with green LED");
            check_order();
            @(negedge clk);
        end
        if (led !== 1 || dut.full_blink_phases !== 0)
            $fatal(1, "Green order LED did not return after alert");
        // 提示结束后可再次触发，并确认进入付款的正常流程未受影响。
        press_product();
        @(negedge clk);
        if (led !== 1) $fatal(1, "Repeat rejection did not flash green");
        press_confirm();
        @(negedge clk);
        if (dut.state !== 4 || led !== 3 || dut.full_blink_phases !== 0)
            $fatal(1, "Payment did not clear blink feedback");

        // 将付款金额加到 255 元上限，再投入 1 元应被拒绝，
        // 同时产生与商品上限一致的两次绿灯和蜂鸣提示。
        sw = 4'b0011;
        for (i = 0; i < 5; i = i + 1) press_confirm();
        for (i = 0; i < 5; i = i + 1) press_product();
        if (dut.paid_amount !== 8'd255)
            $fatal(1, "Could not reach the 255-yuan payment limit");
        press_product();
        @(negedge clk);
        // 多观察 4 拍，除告警相位外还验证结束后能恢复“绿灯常亮、蜂鸣关闭”。
        for (i = 0; i < 20; i = i + 1) begin
            if (dut.payment_error_blink_phases != 0 &&
                led !== (dut.payment_error_blink_phases[0] ? 4'b0010 : 4'b0011))
                $fatal(1, "Payment limit green flash has an incorrect phase");
            // 告警结束后订单绿灯恢复常亮，而蜂鸣器保持关闭；
            // 因此只在四个有效告警相位内检查二者是否同步。
            if (dut.payment_error_blink_phases != 0 &&
                dut.error_beep_enable !== led[0])
                $fatal(1, "Payment-limit beep is not synchronized with green LED");
            @(negedge clk);
        end
        if (dut.payment_error_blink_phases !== 0)
            $fatal(1, "Payment limit alert did not finish after two flashes");
        $display("PASS: selection limit preserves display and flashes green twice with synchronized beeps.");
        $finish;
    end
endmodule
