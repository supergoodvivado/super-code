`timescale 1ns / 1ps

// 顶层集成模块：连接按键、核心状态机、数码管、指示灯和蜂鸣器。
module vending_machine_top #(
    parameter FULL_BLINK_TICKS = 5_000_000, // 100 ms per phase at 50 MHz.
    parameter PAYMENT_ERROR_BLINK_TICKS = 5_000_000, //模型内部可修改常量
    parameter SOLD_OUT_BLINK_TICKS = 5_000_000,  //一次亮灭时间持续多久
    parameter CHANGE_ERROR_BLINK_TICKS = 5_000_000
) (
    input wire clk,
    input wire [3:0] sw,
    input wire [3:0] key_n,
    output wire [3:0] led,
    output wire [7:0] seg,       //八位中哪一位
    output wire [7:0] sel,       //该位显示什么数字
    output wire buzzer
);

    // 复位、按键调理输出，以及核心状态机与显示器之间的连线。
    wire reset;
    reg [19:0] power_on_reset_count = 20'd0;
    wire power_on_reset;
    wire product_level;
    wire confirm_level;       //按键是否一直处于按下状态（1）
    wire change_level;
    wire cancel_level;
    wire product_pulse;
    wire confirm_pulse;       //一次按键动作只产生一个时钟周期的脉冲
    wire change_pulse;
    wire cancel_pulse_raw;
    wire cancel_pulse;
    wire [3:0] state;           //信号线
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
    wire sold_out_pulse;
    wire change_unavailable_pulse;
    wire [3:0] stock_selected;
    // 管理员进入检测、错误闪烁和蜂鸣器定时所需的寄存器。
    reg [27:0] admin_hold_counter;       //在always中保存/更新的变量
    reg admin_enter_pulse;
    reg [31:0] full_blink_counter;
    reg [2:0] full_blink_phases;
    reg [31:0] payment_error_blink_counter;
    reg [2:0] payment_error_blink_phases;
    reg [31:0] sold_out_blink_counter;
    reg [2:0] sold_out_blink_phases;
    reg [31:0] change_error_blink_counter;
    reg [2:0] change_error_blink_phases;
    reg [15:0] buzzer_divider = 16'd0;
    reg [22:0] key_beep_counter = 23'd0;
    wire any_key_pulse;
    wire normal_buzz_enable;
    wire error_alert_active;
    wire error_beep_enable;
    // 顶层需要识别的状态编码，用来驱动灯光、蜂鸣器和错误提示。
    localparam ST_PAY    = 4'd4;                   //只在这个模块内部使用，不能从外部覆盖
    localparam ST_ORDER_READY = 4'd3;
    localparam ST_VEND   = 4'd5;
    localparam ST_CHANGE = 4'd6;
    localparam ST_ADMIN_SELECT = 4'd7;
    localparam ST_ADMIN_VIEW = 4'd8;
    localparam ST_ADMIN_PRICE = 4'd9;

    // 上电自动复位、组合复位和各类提示音控制信号。
    assign power_on_reset = power_on_reset_count != 20'hFFFFF;          //上电计数器还没数满时，power_on_reset=1，系统刚启动时处于自动复位
    assign reset = power_on_reset || ((sw == 4'hF) && cancel_level);    //二选一复位
    assign cancel_pulse = cancel_pulse_raw && (sw != 4'hF);             //
    assign any_key_pulse = product_pulse | confirm_pulse | change_pulse | cancel_pulse_raw;
    // A limit violation flashes the green order LED.  Each alert has four
    // 100-ms phases: green/on, off, green/on, off.  The buzzer uses the same
    // on phases, producing exactly two short synchronized beeps.
    assign error_alert_active = (full_blink_phases != 3'd0) ||
                                (payment_error_blink_phases != 3'd0) ||
                                (sold_out_blink_phases != 3'd0) ||
                                (change_error_blink_phases != 3'd0) ||
                                sold_out_pulse || change_unavailable_pulse;
    assign error_beep_enable = ((full_blink_phases != 3'd0) &&
                                !full_blink_phases[0]) ||
                               ((payment_error_blink_phases != 3'd0) &&
                                !payment_error_blink_phases[0]) ||
                               ((sold_out_blink_phases != 3'd0) &&
                                !sold_out_blink_phases[0]) ||
                               ((change_error_blink_phases != 3'd0) &&
                                !change_error_blink_phases[0]);
    assign normal_buzz_enable = (state == ST_VEND) |
                                (key_beep_counter != 23'd0);

    // SW=1110 且长按 KEY4 两秒，产生一次进入管理员模式的脉冲。
    always @(posedge clk or posedge power_on_reset) begin
        if (power_on_reset) begin
            admin_hold_counter <= 28'd0;
            admin_enter_pulse <= 1'b0;
        end else if ((sw == 4'b1110) && cancel_level) begin
            admin_enter_pulse <= 1'b0;
            if (admin_hold_counter < 28'd100_000_000)
                admin_hold_counter <= admin_hold_counter + 1'b1;
            if (admin_hold_counter == 28'd99_999_999) begin
                admin_enter_pulse <= 1'b1;
                admin_hold_counter <= 28'd0;
            end
        end else begin
            admin_hold_counter <= 28'd0;
            admin_enter_pulse <= 1'b0;
        end
    end

    // 上电复位计数、蜂鸣器分频以及每次按键后的短提示音计时。
    always @(posedge clk) begin
        if (power_on_reset_count != 20'hFFFFF) begin
            power_on_reset_count <= power_on_reset_count + 20'd1;
        end
        buzzer_divider <= buzzer_divider + 16'd1;
        if (reset) begin
            key_beep_counter <= 23'd0;
        end else if (any_key_pulse) begin
            key_beep_counter <= 23'd2_500_000;
        end else if (key_beep_counter != 23'd0) begin
            key_beep_counter <= key_beep_counter - 23'd1;
        end
    end

    // 四路按键分别消抖并转成单周期事件；KEY4 保持可用于组合复位检测。
    button_conditioner key1_cond (            //实例化硬件模块
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
        .reset(1'b0),
        .btn_n(key_n[3]),
        .pressed_level(cancel_level),
        .pressed_pulse(cancel_pulse_raw)
    );

    // 核心状态机负责订单、库存、支付、找零和管理员功能。
    vending_machine_core core (
        .clk(clk),
        .reset(reset),
        .sw(sw),
        .key_product_pulse(product_pulse),
        .key_confirm_pulse(confirm_pulse),
        .key_change_pulse(change_pulse),
        .key_cancel_pulse(cancel_pulse),
        .admin_enter_pulse(admin_enter_pulse),
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
        .payment_insufficient_pulse(payment_insufficient_pulse),
        .sold_out_pulse(sold_out_pulse),
        .change_unavailable_pulse(change_unavailable_pulse),
        .stock_selected(stock_selected)
    );

    // 显示驱动把核心状态及金额转换为八位数码管扫描输出。
    seven_segment_scan display (
        .clk(clk),
        .reset(reset),
        .state(state),
        .product_code(current_product_code),
        .quantity(current_quantity),
        .selected_count(selected_count),
        .total_due(total_due),
        .paid_amount(paid_amount),
        .change_due(change_due),
        .stock_selected(stock_selected),
        .current_price(current_price),
        .admin_price_input(sw),
        .seg(seg),
        .sel(sel)
    );

    // 订单已选两种商品时，绿灯按“亮灭亮灭”闪烁两次提示。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            full_blink_counter <= 32'd0;          //这一阶段还剩多久
            full_blink_phases <= 3'd0;            //还剩几个灯亮/灭阶段
        end else if (state != ST_ORDER_READY) begin
            full_blink_counter <= 32'd0;
            full_blink_phases <= 3'd0;
        end else if (full_blink_phases != 3'd0) begin
            if (full_blink_counter == 32'd0) begin
                full_blink_phases <= full_blink_phases - 3'd1;
                full_blink_counter <= (FULL_BLINK_TICKS > 0) ? FULL_BLINK_TICKS - 1 : 0;
            end else begin
                full_blink_counter <= full_blink_counter - 32'd1;
            end
        end else if (selection_full_pulse) begin
            full_blink_phases <= 3'd4;
            full_blink_counter <= (FULL_BLINK_TICKS > 0) ? FULL_BLINK_TICKS - 1 : 0;
        end
    end

    // 客户确认付款但金额不足时，绿灯按“亮灭亮灭”闪烁两次提示。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            payment_error_blink_counter <= 32'd0;
            payment_error_blink_phases <= 3'd0;
        end else if (state != ST_PAY) begin
            payment_error_blink_counter <= 32'd0;
            payment_error_blink_phases <= 3'd0;
        end else if (payment_error_blink_phases != 3'd0) begin
            if (payment_error_blink_counter == 32'd0) begin
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

    // 商品售罄或所选数量超过库存时，绿灯按“亮灭亮灭”闪烁两次提示。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sold_out_blink_counter <= 32'd0;
            sold_out_blink_phases <= 3'd0;
        end else if (sold_out_blink_phases != 3'd0) begin
            if (sold_out_blink_counter == 32'd0) begin
                sold_out_blink_phases <= sold_out_blink_phases - 3'd1;
                sold_out_blink_counter <= (SOLD_OUT_BLINK_TICKS > 0) ?
                                           SOLD_OUT_BLINK_TICKS - 1 : 0;
            end else begin
                sold_out_blink_counter <= sold_out_blink_counter - 32'd1;
            end
        end else if (sold_out_pulse) begin
            sold_out_blink_phases <= 3'd4;
            sold_out_blink_counter <= (SOLD_OUT_BLINK_TICKS > 0) ?
                                       SOLD_OUT_BLINK_TICKS - 1 : 0;
        end
    end

    // 选择的找零面额大于剩余余额时，绿灯按“亮灭亮灭”闪烁两次提示。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            change_error_blink_counter <= 32'd0;
            change_error_blink_phases <= 3'd0;
        end else if (state != ST_CHANGE) begin
            change_error_blink_counter <= 32'd0;
            change_error_blink_phases <= 3'd0;
        end else if (change_error_blink_phases != 3'd0) begin
            if (change_error_blink_counter == 32'd0) begin
                change_error_blink_phases <= change_error_blink_phases - 3'd1;
                change_error_blink_counter <= (CHANGE_ERROR_BLINK_TICKS > 0) ?
                                              CHANGE_ERROR_BLINK_TICKS - 1 : 0;
            end else begin
                change_error_blink_counter <= change_error_blink_counter - 32'd1;
            end
        end else if (change_unavailable_pulse) begin
            change_error_blink_phases <= 3'd4;
            change_error_blink_counter <= (CHANGE_ERROR_BLINK_TICKS > 0) ?
                                          CHANGE_ERROR_BLINK_TICKS - 1 : 0;
        end
    end

    // LED 映射：绿灯表示订单/错误提示，黄灯表示支付，红灯表示出货，蓝灯表示找零或管理。
    // During an alert the green order LED follows the two beep windows;
    // otherwise it remains steadily on while the order is non-empty.
    assign led[0] = ((selected_count != 2'd0) || error_alert_active) &&
                    (!error_alert_active || error_beep_enable);
    assign led[1] = (state == ST_PAY);        //是否在付款阶段
    assign led[2] = (state == ST_VEND) | vend_pulse;       //是否在出货/刚产生出货pulse
    assign led[3] = (state == ST_CHANGE) | return_coin_pulse |
                    (state == ST_ADMIN_SELECT) |
                    (state == ST_ADMIN_VIEW) |
                    (state == ST_ADMIN_PRICE);

    // 错误提示优先占用蜂鸣器；其余时间由按键短音和出货音控制。
    // While an alert is running it owns the buzzer, preventing the ordinary
    // key-click tone from filling the silent gap between the beeps.
    assign buzzer = (error_alert_active ? error_beep_enable : normal_buzz_enable)
                    ? buzzer_divider[15] : 1'b1;

endmodule
