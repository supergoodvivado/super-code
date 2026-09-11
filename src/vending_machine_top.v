`timescale 1ns / 1ps

module vending_machine_top #(
    parameter FULL_BLINK_TICKS = 5_000_000, // 50 MHz 下每个闪烁相位为 100 ms
    parameter PAYMENT_ERROR_BLINK_TICKS = 5_000_000
) (
    input wire clk,
    input wire [3:0] sw,
    input wire [3:0] key_n,
    output wire [3:0] led,
    output wire [7:0] seg,
    output wire [7:0] sel,
    output wire buzzer
);

    // 上电复位计数约 2^20 个时钟，在 50 MHz 下约为 21 ms，
    // 用来保证各子模块在时钟稳定后从确定状态启动。
    wire reset;
    reg [19:0] power_on_reset_count = 20'd0;
    wire power_on_reset;
    wire product_level;
    wire confirm_level;
    wire change_level;
    wire cancel_level;
    wire product_pulse;
    wire confirm_pulse;
    wire change_pulse;
    wire cancel_pulse_raw;
    wire cancel_pulse;
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
    // 两类告警各自保存“当前相位剩余拍数”和“剩余相位数”；
    // phases 从 4 递减到 0，偶数相位亮、奇数相位灭。
    reg [31:0] full_blink_counter;
    reg [2:0] full_blink_phases;
    reg [31:0] payment_error_blink_counter;
    reg [2:0] payment_error_blink_phases;
    // 50 MHz 时钟的第 15 位约产生 763 Hz 方波作为蜂鸣音；
    // key_beep_counter=2_500_000 对应约 50 ms 的普通按键提示音。
    reg [15:0] buzzer_divider = 16'd0;
    reg [22:0] key_beep_counter = 23'd0;
    wire any_key_pulse;
    wire normal_buzz_enable;
    wire error_alert_active;
    wire error_beep_enable;
    localparam ST_PAY    = 3'd4;
    localparam ST_ORDER_READY = 3'd3;
    localparam ST_VEND   = 3'd5;
    localparam ST_CHANGE = 3'd6;

    assign power_on_reset = power_on_reset_count != 20'hFFFFF;
    // SW=F 且按住 KEY4 是人工复位组合。KEY4 的消抖模块本身不接 reset，
    // 否则 reset 一生效就会清掉 cancel_level，造成复位信号自激振荡。
    assign reset = power_on_reset || ((sw == 4'hF) && cancel_level);
    // 人工复位组合下屏蔽普通取消脉冲，但按键音仍使用 raw 脉冲。
    assign cancel_pulse = cancel_pulse_raw && (sw != 4'hF);
    assign any_key_pulse = product_pulse | confirm_pulse | change_pulse | cancel_pulse_raw;
    // 超出选择或付款上限时共执行四个 100 ms 相位：亮、灭、亮、灭。
    // 蜂鸣器只在两个亮灯相位工作，因此形成两次与绿灯同步的短鸣。
    assign error_alert_active = (full_blink_phases != 3'd0) ||
                                (payment_error_blink_phases != 3'd0);
    // phases 初值为 4：4、2 为亮/鸣相位，3、1 为灭/静音相位。
    assign error_beep_enable = ((full_blink_phases != 3'd0) &&
                                !full_blink_phases[0]) ||
                               ((payment_error_blink_phases != 3'd0) &&
                                !payment_error_blink_phases[0]);
    assign normal_buzz_enable = (state == ST_VEND) |
                                (key_beep_counter != 23'd0);

    always @(posedge clk) begin
        if (power_on_reset_count != 20'hFFFFF) begin
            power_on_reset_count <= power_on_reset_count + 20'd1;
        end
        // 分频器自由运行，使每次使能蜂鸣器时无需等待额外起振状态。
        buzzer_divider <= buzzer_divider + 16'd1;
        if (reset) begin
            key_beep_counter <= 23'd0;
        end else if (any_key_pulse) begin
            key_beep_counter <= 23'd2_500_000;
        end else if (key_beep_counter != 23'd0) begin
            key_beep_counter <= key_beep_counter - 23'd1;
        end
    end

    // KEY1：唤醒/下一步/投 1 元；KEY2：确认/投入纸币；
    // KEY3：返回/确认付款/逐元找零；KEY4：取消或配合 SW=F 复位。
    button_conditioner key1_cond (
        .clk(clk),
        .reset(reset),
        .btn_n(key_n[0]),
        .pressed_level(product_level),
        .pressed_pulse(product_pulse)
    );

    button_conditioner key2_cond (
        .clk(clk),
        .reset(reset),
        .btn_n(key_n[1]),
        .pressed_level(confirm_level),
        .pressed_pulse(confirm_pulse)
    );

    button_conditioner key3_cond (
        .clk(clk),
        .reset(reset),
        .btn_n(key_n[2]),
        .pressed_level(change_level),
        .pressed_pulse(change_pulse)
    );

    button_conditioner key4_cond (
        .clk(clk),
        .reset(1'b0), // 保持 KEY4 电平可用于产生并维持人工复位
        .btn_n(key_n[3]),
        .pressed_level(cancel_level),
        .pressed_pulse(cancel_pulse_raw)
    );

    vending_machine_core core (
        .clk(clk),
        .reset(reset),
        .sw(sw),
        .key_product_pulse(product_pulse),
        .key_confirm_pulse(confirm_pulse),
        .key_change_pulse(change_pulse),
        .key_cancel_pulse(cancel_pulse),
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

    seven_segment_scan display (
        .clk(clk),
        .reset(reset),
        .state(state),
        .product_code(current_product_code),
        .quantity(current_quantity),
        .selected_count(selected_count),
        .total_due(total_due),
        .first_item_total(first_item_total),
        .paid_amount(paid_amount),
        .change_due(change_due),
        .seg(seg),
        .sel(sel)
    );

    // 已选择两种商品后再次按 KEY1，绿灯闪烁两次提示达到上限。
    // 闪烁期间忽略重复触发；离开订单确认状态时立即清除提示。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            full_blink_counter <= 32'd0;
            full_blink_phases <= 3'd0;
        end else if (state != ST_ORDER_READY) begin
            full_blink_counter <= 32'd0;
            full_blink_phases <= 3'd0;
        end else if (full_blink_phases != 3'd0) begin
            if (full_blink_counter == 32'd0) begin
                // 当前相位结束：切换亮灭相位，并重新装载下一相位计数。
                full_blink_phases <= full_blink_phases - 3'd1;
                full_blink_counter <= (FULL_BLINK_TICKS > 0) ? FULL_BLINK_TICKS - 1 : 0;
            end else begin
                full_blink_counter <= full_blink_counter - 32'd1;
            end
        end else if (selection_full_pulse) begin
            // 从相位 4 开始，因此提示序列固定为亮、灭、亮、灭。
            full_blink_phases <= 3'd4;
            full_blink_counter <= (FULL_BLINK_TICKS > 0) ? FULL_BLINK_TICKS - 1 : 0;
        end
    end

    // 付款不足或累计金额将超过 255 元时保持付款状态，并触发相同的两次绿灯提示。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            payment_error_blink_counter <= 32'd0;
            payment_error_blink_phases <= 3'd0;
        end else if (state != ST_PAY) begin
            payment_error_blink_counter <= 32'd0;
            payment_error_blink_phases <= 3'd0;
        end else if (payment_error_blink_phases != 3'd0) begin
            if (payment_error_blink_counter == 32'd0) begin
                // 与商品上限提示采用相同相位规则，保证灯光和声音一致。
                payment_error_blink_phases <= payment_error_blink_phases - 3'd1;
                payment_error_blink_counter <= (PAYMENT_ERROR_BLINK_TICKS > 0) ?
                                               PAYMENT_ERROR_BLINK_TICKS - 1 : 0;
            end else begin
                payment_error_blink_counter <= payment_error_blink_counter - 32'd1;
            end
        end else if (payment_insufficient_pulse) begin
            payment_error_blink_phases <= 3'd4;
            payment_error_blink_counter <= (PAYMENT_ERROR_BLINK_TICKS > 0) ?
                                           PAYMENT_ERROR_BLINK_TICKS - 1 : 0;
        end
    end

    // 告警期间订单绿灯与蜂鸣窗口同步；非告警期间，只要订单非空就保持常亮。
    // LED1=订单/绿色告警，LED2=付款，LED3=出货，LED4=找零或退款。
    assign led[0] = (selected_count != 2'd0) &&
                    (!error_alert_active || error_beep_enable);
    assign led[1] = (state == ST_PAY);
    assign led[2] = (state == ST_VEND) | vend_pulse;
    assign led[3] = (state == ST_CHANGE) | return_coin_pulse;

    // 告警期间由告警逻辑独占蜂鸣器，避免普通按键音填满两次短鸣之间的静音间隔。
    assign buzzer = (error_alert_active ? error_beep_enable : normal_buzz_enable)
                    ? buzzer_divider[15] : 1'b1;

endmodule
