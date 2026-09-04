`timescale 1ns / 1ps

module vending_machine_top (
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
    wire [7:0] paid_amount;
    wire [7:0] change_due;
    wire vend_pulse;
    wire return_coin_pulse;
    reg [15:0] buzzer_divider = 16'd0;
    reg [22:0] key_beep_counter = 23'd0;
    wire any_key_pulse;
    wire buzz_enable;
    localparam ST_PAY    = 3'd4;
    localparam ST_VEND   = 3'd5;
    localparam ST_CHANGE = 3'd6;

    assign power_on_reset = power_on_reset_count != 20'hFFFFF;
    assign reset = power_on_reset || ((sw == 4'hF) && cancel_level);
    assign cancel_pulse = cancel_pulse_raw && (sw != 4'hF);
    assign any_key_pulse = product_pulse | confirm_pulse | change_pulse | cancel_pulse_raw;
    assign buzz_enable = (state == ST_VEND) | (key_beep_counter != 23'd0);

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
        .paid_amount(paid_amount),
        .change_due(change_due),
        .vend_pulse(vend_pulse),
        .return_coin_pulse(return_coin_pulse)
    );

    seven_segment_scan display (
        .clk(clk),
        .reset(reset),
        .state(state),
        .product_code(current_product_code),
        .quantity(current_quantity),
        .total_due(total_due),
        .paid_amount(paid_amount),
        .change_due(change_due),
        .seg(seg),
        .sel(sel)
    );

    assign led[0] = (selected_count != 2'd0);
    assign led[1] = (state == ST_PAY);
    assign led[2] = (state == ST_VEND) | vend_pulse;
    assign led[3] = (state == ST_CHANGE) | return_coin_pulse;

    assign buzzer = buzz_enable ? buzzer_divider[15] : 1'b1;

endmodule
