`timescale 1ns / 1ps

module vending_machine_top #(
    parameter FULL_BLINK_TICKS = 5_000_000, // 100 ms per phase at 50 MHz.
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
    reg [31:0] full_blink_counter;
    reg [2:0] full_blink_phases;
    reg [31:0] payment_error_blink_counter;
    reg [2:0] payment_error_blink_phases;
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
    assign reset = power_on_reset || ((sw == 4'hF) && cancel_level);
    assign cancel_pulse = cancel_pulse_raw && (sw != 4'hF);
    assign any_key_pulse = product_pulse | confirm_pulse | change_pulse | cancel_pulse_raw;
    // A limit violation flashes the green order LED.  Each alert has four
    // 100-ms phases: green/on, off, green/on, off.  The buzzer uses the same
    // on phases, producing exactly two short synchronized beeps.
    assign error_alert_active = (full_blink_phases != 3'd0) ||
                                (payment_error_blink_phases != 3'd0);
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
        buzzer_divider <= buzzer_divider + 16'd1;
        if (reset) begin
            key_beep_counter <= 23'd0;
        end else if (any_key_pulse) begin
            key_beep_counter <= 23'd2_500_000;
        end else if (key_beep_counter != 23'd0) begin
            key_beep_counter <= key_beep_counter - 23'd1;
        end
    end

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
        .reset(1'b0),
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

    // More than two product types is a green alert.  Ignore retriggers
    // during a flash sequence; leaving order ready clears it.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            full_blink_counter <= 32'd0;
            full_blink_phases <= 3'd0;
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

    // An insufficient confirmation or an amount above 255 keeps ST_PAY active
    // and produces the same two green flashes.
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

    // During an alert the green order LED follows the two beep windows;
    // otherwise it remains steadily on while the order is non-empty.
    assign led[0] = (selected_count != 2'd0) &&
                    (!error_alert_active || error_beep_enable);
    assign led[1] = (state == ST_PAY);
    assign led[2] = (state == ST_VEND) | vend_pulse;
    assign led[3] = (state == ST_CHANGE) | return_coin_pulse;

    // While an alert is running it owns the buzzer, preventing the ordinary
    // key-click tone from filling the silent gap between the beeps.
    assign buzzer = (error_alert_active ? error_beep_enable : normal_buzz_enable)
                    ? buzzer_divider[15] : 1'b1;

endmodule
