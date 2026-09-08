`timescale 1ns / 1ps

module vending_machine_core #(
    parameter VEND_TICKS = 50_000_000
) (
    input wire clk,
    input wire reset,
    input wire [3:0] sw,
    input wire key_product_pulse,
    input wire key_confirm_pulse,
    input wire key_change_pulse,
    input wire key_cancel_pulse,
    output reg [2:0] state,
    output reg [1:0] selected_count,
    output reg [3:0] current_product_code,
    output reg [1:0] current_quantity,
    output wire [7:0] current_price,
    output reg [7:0] total_due,
    output reg [7:0] paid_amount,
    output reg [7:0] change_due,
    output reg vend_pulse,
    output reg return_coin_pulse,
    output reg selection_full_pulse
);

    localparam ST_IDLE           = 3'd0;
    localparam ST_SELECT_PRODUCT = 3'd1;
    localparam ST_SELECT_QTY     = 3'd2;
    localparam ST_ORDER_READY    = 3'd3;
    localparam ST_PAY            = 3'd4;
    localparam ST_VEND           = 3'd5;
    localparam ST_CHANGE         = 3'd6;

    reg selection_cleared;
    reg has_item1;
    reg has_item2;
    reg [3:0] item1_code;
    reg [3:0] item2_code;
    reg [1:0] item1_qty;
    reg [1:0] item2_qty;
    reg [3:0] pending_code;
    reg [31:0] vend_counter;
    reg [7:0] money_next;
    reg [1:0] qty_next;

    assign current_price = price_of(current_product_code);

    function [7:0] price_of;
        input [3:0] code;
        begin
            case (code)
                4'h0: price_of = 8'd3;   // A11
                4'h1: price_of = 8'd4;   // A12
                4'h2: price_of = 8'd6;   // A13
                4'h3: price_of = 8'd3;   // A14
                4'h4: price_of = 8'd10;  // A21
                4'h5: price_of = 8'd8;   // A22
                4'h6: price_of = 8'd9;   // A23
                4'h7: price_of = 8'd7;   // A24
                4'h8: price_of = 8'd4;   // A31
                4'h9: price_of = 8'd6;   // A32
                4'hA: price_of = 8'd15;  // A33
                4'hB: price_of = 8'd8;   // A34
                4'hC: price_of = 8'd9;   // A41
                4'hD: price_of = 8'd4;   // A42
                4'hE: price_of = 8'd5;   // A43
                4'hF: price_of = 8'd5;   // A44
                default: price_of = 8'd0;
            endcase
        end
    endfunction

    function [1:0] qty_from_switch;
        input [1:0] code;
        begin
            case (code)
                2'b00: qty_from_switch = 2'd1;
                2'b01: qty_from_switch = 2'd2;
                2'b10: qty_from_switch = 2'd3;
                default: qty_from_switch = 2'd3;
            endcase
        end
    endfunction

    function [7:0] line_total;
        input [3:0] code;
        input [1:0] qty;
        reg [7:0] price;
        begin
            price = price_of(code);
            case (qty)
                2'd1: line_total = price;
                2'd2: line_total = price << 1;
                2'd3: line_total = (price << 1) + price;
                default: line_total = 8'd0;
            endcase
        end
    endfunction

    function [7:0] bill_value;
        input [1:0] code;
        begin
            case (code)
                2'b00: bill_value = 8'd5;
                2'b01: bill_value = 8'd10;
                2'b10: bill_value = 8'd20;
                default: bill_value = 8'd50;
            endcase
        end
    endfunction

    task clear_transaction;
        begin
            selection_cleared <= 1'b0;
            has_item1 <= 1'b0;
            has_item2 <= 1'b0;
            item1_code <= 4'd0;
            item2_code <= 4'd0;
            item1_qty <= 2'd0;
            item2_qty <= 2'd0;
            selected_count <= 2'd0;
            total_due <= 8'd0;
            paid_amount <= 8'd0;
            change_due <= 8'd0;
            pending_code <= 4'd0;
            current_product_code <= 4'd0;
            current_quantity <= 2'd0;
        end
    endtask

    // First KEY4 clears the order; another KEY4 leaves the selection page.
    task cancel_selection;
        begin
            clear_transaction();
            if (selection_cleared) begin
                state <= ST_IDLE;
            end else begin
                selection_cleared <= 1'b1;
                state <= ST_SELECT_PRODUCT;
            end
        end
    endtask

    task commit_selection;
        begin
            qty_next = qty_from_switch(sw[1:0]);
            current_product_code <= pending_code;
            current_quantity <= qty_next;
            if (!has_item1) begin
                has_item1 <= 1'b1;
                item1_code <= pending_code;
                item1_qty <= qty_next;
                selected_count <= 2'd1;
                total_due <= line_total(pending_code, qty_next);
            end else if (item1_code == pending_code) begin
                item1_qty <= qty_next;
                total_due <= line_total(pending_code, qty_next) +
                             (has_item2 ? line_total(item2_code, item2_qty) : 8'd0);
            end else if (!has_item2) begin
                has_item2 <= 1'b1;
                item2_code <= pending_code;
                item2_qty <= qty_next;
                selected_count <= 2'd2;
                total_due <= line_total(item1_code, item1_qty) +
                             line_total(pending_code, qty_next);
            end else begin
                item2_code <= pending_code;
                item2_qty <= qty_next;
                total_due <= line_total(item1_code, item1_qty) +
                             line_total(pending_code, qty_next);
            end
        end
    endtask

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_IDLE;
            selection_cleared <= 1'b0;
            has_item1 <= 1'b0;
            has_item2 <= 1'b0;
            item1_code <= 4'd0;
            item2_code <= 4'd0;
            item1_qty <= 2'd0;
            item2_qty <= 2'd0;
            pending_code <= 4'd0;
            selected_count <= 2'd0;
            current_product_code <= 4'd0;
            current_quantity <= 2'd0;
            total_due <= 8'd0;
            paid_amount <= 8'd0;
            change_due <= 8'd0;
            vend_counter <= 32'd0;
            vend_pulse <= 1'b0;
            return_coin_pulse <= 1'b0;
            selection_full_pulse <= 1'b0;
        end else begin
            vend_pulse <= 1'b0;
            return_coin_pulse <= 1'b0;
            selection_full_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    clear_transaction();
                    if (key_product_pulse) begin
                        current_product_code <= sw;
                        state <= ST_SELECT_PRODUCT;
                    end
                end

                ST_SELECT_PRODUCT: begin
                    current_product_code <= sw;
                    current_quantity <= 2'd0;
                    paid_amount <= 8'd0;
                    change_due <= 8'd0;

                    if (key_cancel_pulse) begin
                        cancel_selection();
                    end else if (key_change_pulse) begin
                        selection_cleared <= 1'b0;
                        if (total_due == 8'd0) begin
                            clear_transaction();
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_ORDER_READY;
                        end
                    end else if (key_product_pulse) begin
                        selection_cleared <= 1'b0;
                        pending_code <= sw;
                        current_product_code <= sw;
                        state <= ST_SELECT_QTY;
                    end else if (key_confirm_pulse && (total_due != 8'd0)) begin
                        state <= ST_PAY;
                    end
                end

                ST_SELECT_QTY: begin
                    current_product_code <= pending_code;
                    current_quantity <= qty_from_switch(sw[1:0]);

                    if (key_cancel_pulse) begin
                        cancel_selection();
                    end else if (key_change_pulse) begin
                        selection_cleared <= 1'b0;
                        state <= (total_due == 8'd0) ? ST_IDLE : ST_ORDER_READY;
                    end else if (key_product_pulse) begin
                        commit_selection();
                        state <= ST_ORDER_READY;
                    end
                end

                ST_ORDER_READY: begin
                    paid_amount <= 8'd0;
                    change_due <= 8'd0;

                    if (key_cancel_pulse) begin
                        clear_transaction();
                        state <= ST_IDLE;
                    end else if (key_product_pulse) begin
                        if (selected_count == 2'd2) begin
                            selection_full_pulse <= 1'b1;
                        end else begin
                            current_product_code <= sw;
                            current_quantity <= 2'd0;
                            state <= ST_SELECT_PRODUCT;
                        end
                    end else if (key_confirm_pulse && (total_due != 8'd0)) begin
                        state <= ST_PAY;
                    end
                end

                ST_PAY: begin
                    if (key_cancel_pulse) begin
                        change_due <= paid_amount;
                        paid_amount <= 8'd0;
                        state <= (paid_amount == 8'd0) ? ST_IDLE : ST_CHANGE;
                        if (paid_amount == 8'd0) begin
                            clear_transaction();
                        end
                    end else if (key_change_pulse && (paid_amount != 8'd0)) begin
                        paid_amount <= paid_amount - 8'd1;
                        return_coin_pulse <= 1'b1;
                    end else if (key_product_pulse) begin
                        money_next = paid_amount + 8'd1;
                        if (money_next >= total_due) begin
                            paid_amount <= 8'd0;
                            change_due <= money_next - total_due;
                            vend_counter <= (VEND_TICKS > 0) ? (VEND_TICKS - 1) : 0;
                            vend_pulse <= 1'b1;
                            state <= ST_VEND;
                        end else begin
                            paid_amount <= money_next;
                        end
                    end else if (key_confirm_pulse) begin
                        money_next = paid_amount + bill_value(sw[1:0]);
                        if (money_next >= total_due) begin
                            paid_amount <= 8'd0;
                            change_due <= money_next - total_due;
                            vend_counter <= (VEND_TICKS > 0) ? (VEND_TICKS - 1) : 0;
                            vend_pulse <= 1'b1;
                            state <= ST_VEND;
                        end else begin
                            paid_amount <= money_next;
                        end
                    end
                end

                ST_VEND: begin
                    if (vend_counter == 32'd0) begin
                        if (change_due != 8'd0) begin
                            state <= ST_CHANGE;
                        end else begin
                            clear_transaction();
                            state <= ST_IDLE;
                        end
                    end else begin
                        vend_counter <= vend_counter - 32'd1;
                    end
                end

                ST_CHANGE: begin
                    if (change_due == 8'd0) begin
                        clear_transaction();
                        state <= ST_IDLE;
                    end else if (key_change_pulse) begin
                        change_due <= change_due - 8'd1;
                        return_coin_pulse <= 1'b1;
                        if (change_due == 8'd1) begin
                            clear_transaction();
                            state <= ST_IDLE;
                        end
                    end
                end

                default: begin
                    clear_transaction();
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
