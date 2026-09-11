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
    // 金额寄存器采用 8 位，可保存 0～255 元；数码管只显示十位和个位。
    output reg [7:0] total_due,
    output wire [7:0] first_item_total,
    output reg [7:0] paid_amount,
    output reg [7:0] change_due,
    output reg vend_pulse,
    output reg return_coin_pulse,
    output reg selection_full_pulse,
    // 付款不足或投币超过上限时输出一个时钟周期的告警脉冲，供顶层驱动灯光和蜂鸣器。
    output reg payment_insufficient_pulse
);

    // 状态编码同时直接显示在数码管第 1 位，因此保持为固定的 0～6。
    localparam ST_IDLE           = 3'd0;
    localparam ST_SELECT_PRODUCT = 3'd1;
    localparam ST_SELECT_QTY     = 3'd2;
    localparam ST_ORDER_READY    = 3'd3;
    localparam ST_PAY            = 3'd4;
    localparam ST_VEND           = 3'd5;
    localparam ST_CHANGE         = 3'd6;

    // 最多保存两种商品。has_item* 表示对应槽位已经正式计入订单；
    // pending_code 则保存正在选择、尚未提交的商品编号。
    reg has_item1;
    reg has_item2;
    reg [3:0] item1_code;
    reg [3:0] item2_code;
    reg [1:0] item1_qty;
    reg [1:0] item2_qty;
    reg [3:0] pending_code;
    reg [31:0] vend_counter;
    // 以下变量只在时序过程内部用阻塞赋值计算“本拍临时结果”，
    // 真正的状态寄存器仍统一使用非阻塞赋值更新。
    reg [7:0] money_next;
    reg [8:0] money_sum_next;
    reg [1:0] qty_next;

    // 当前价格供顶层或调试观察；第一种商品小计专门供选择页显示。
    assign current_price = price_of(current_product_code);
    assign first_item_total = has_item1 ? line_total(item1_code, item1_qty) : 8'd0;

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
                // 11 没有对应第 4 档，按最大允许数量 3 处理。
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
            // 数量最大为 3，用移位和加法计算，避免引入通用乘法器。
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
            // 付款状态下 SW2、SW1（即 sw[1:0]）选择纸币面额。
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
            // 完全结束交易：商品、付款和余额全部清零。
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

    // 清除未完成订单，但保留 change_due 作为可继续消费的余额。
    // 用户在找零状态按 KEY1 开始新订单时调用此任务。
    task clear_order_keep_balance;
        begin
            // 只清除商品及本次付款，故意不写 change_due。
            has_item1 <= 1'b0;
            has_item2 <= 1'b0;
            item1_code <= 4'd0;
            item2_code <= 4'd0;
            item1_qty <= 2'd0;
            item2_qty <= 2'd0;
            selected_count <= 2'd0;
            total_due <= 8'd0;
            paid_amount <= 8'd0;
            pending_code <= 4'd0;
            current_product_code <= 4'd0;
            current_quantity <= 2'd0;
        end
    endtask

    // KEY2 确认订单后始终进入付款状态。即使余额足够，也必须再按 KEY3
    // 明确确认付款，防止新订单因为已有余额而自动出货。
    task confirm_order;
        begin
            paid_amount <= 8'd0;
            state <= ST_PAY;
        end
    endtask

    // KEY4 取消未完成订单：有余额时进入找零状态，无余额时直接返回空闲状态。
    task cancel_order;
        begin
            if (change_due != 8'd0) begin
                clear_order_keep_balance();
                state <= ST_CHANGE;
            end else begin
                clear_transaction();
                state <= ST_IDLE;
            end
        end
    endtask

    task commit_selection;
        begin
            // qty_next 使用阻塞赋值，保证下方同一拍计算金额时拿到新数量。
            qty_next = qty_from_switch(sw[1:0]);
            current_product_code <= pending_code;
            current_quantity <= qty_next;
            if (!has_item1) begin
                // 订单为空：写入第一个槽位并建立订单总价。
                has_item1 <= 1'b1;
                item1_code <= pending_code;
                item1_qty <= qty_next;
                selected_count <= 2'd1;
                total_due <= line_total(pending_code, qty_next);
            end else if (item1_code == pending_code) begin
                // 新选择与第一种商品相同：修改第一槽数量，不占用第二槽。
                item1_qty <= qty_next;
                total_due <= line_total(pending_code, qty_next) +
                             (has_item2 ? line_total(item2_code, item2_qty) : 8'd0);
            end else if (!has_item2) begin
                // 商品种类不同且第二槽为空：加入第二种商品。
                has_item2 <= 1'b1;
                item2_code <= pending_code;
                item2_qty <= qty_next;
                selected_count <= 2'd2;
                total_due <= line_total(item1_code, item1_qty) +
                             line_total(pending_code, qty_next);
            end else begin
                // 编辑第二种商品后重新提交：覆盖第二槽并重算整单金额。
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
            payment_insufficient_pulse <= 1'b0;
        end else begin
            // 以下四个输出都是事件脉冲，默认每拍清零；状态分支需要时再置 1，
            // 因而不会因为上一次操作而持续保持有效。
            vend_pulse <= 1'b0;
            return_coin_pulse <= 1'b0;
            selection_full_pulse <= 1'b0;
            payment_insufficient_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    // 空闲状态持续保持交易数据为零；KEY1 捕获当前拨码并唤醒机器。
                    clear_transaction();
                    if (key_product_pulse) begin
                        current_product_code <= sw;
                        state <= ST_SELECT_PRODUCT;
                    end
                end

                ST_SELECT_PRODUCT: begin
                    // 商品编号显示实时跟随四位拨码，按 KEY1 后才锁存到 pending_code。
                    current_product_code <= sw;
                    current_quantity <= 2'd0;
                    paid_amount <= 8'd0;

                    // 同一拍出现多个按键时，判断顺序也就是处理优先级：
                    // KEY4（取消）> KEY3（返回）> KEY1（下一步）> KEY2（付款）。
                    if (key_cancel_pulse) begin
                        cancel_order();
                    end else if (key_change_pulse) begin
                        // 选择第一种商品时，KEY3 与 KEY4 一样取消选择；
                        // 选择第二种商品时，KEY3 返回第一种商品的确认页。
                        if (selected_count == 2'd0) begin
                            // 没有已确认商品，继续回退等价于取消交易。
                            cancel_order();
                        end else begin
                            // 已保留第一种商品，说明当前位于第二种商品的选择流程；
                            // 返回时恢复第一种商品的编号、数量和确认状态。
                            pending_code <= item1_code;
                            current_product_code <= item1_code;
                            current_quantity <= item1_qty;
                            state <= ST_ORDER_READY;
                        end
                    end else if (key_product_pulse) begin
                        // KEY1 锁存商品编号，防止进入数量页后拨码变化影响商品种类。
                        pending_code <= sw;
                        current_product_code <= sw;
                        state <= ST_SELECT_QTY;
                    end else if (key_confirm_pulse && (total_due != 8'd0)) begin
                        // 已有订单时允许从商品选择页直接按 KEY2 进入付款。
                        confirm_order();
                    end
                end

                ST_SELECT_QTY: begin
                    // 数量显示实时跟随 sw[1:0]；商品编号使用上一页锁存的 pending_code。
                    current_product_code <= pending_code;
                    current_quantity <= qty_from_switch(sw[1:0]);

                    if (key_cancel_pulse) begin
                        cancel_order();
                    end else if (key_change_pulse) begin
                        // 数量页按 KEY3 返回商品编号选择页，以便重新选择商品。
                        current_product_code <= sw;
                        current_quantity <= 2'd0;
                        state <= ST_SELECT_PRODUCT;
                    end else if (key_product_pulse) begin
                        // KEY1 将当前商品和数量正式写入订单槽位。
                        commit_selection();
                        state <= ST_ORDER_READY;
                    end
                end

                ST_ORDER_READY: begin
                    // 确认页不累计投币，确保进入付款状态前 paid_amount 为零。
                    paid_amount <= 8'd0;

                    if (key_cancel_pulse) begin
                        cancel_order();
                    end else if (key_change_pulse) begin
                        // KEY3 按“后进先退”方式撤销最后确认的商品，再进入其数量页。
                        // 重新按 KEY1 可提交修改；连续按 KEY3 则依次退回第二种商品、
                        // 第一种商品，最后退出到空闲状态，避免 3→2→1→3 的循环。
                        if (has_item2) begin
                            // 两种商品时弹出第二槽，total_due 立即恢复为第一种商品小计。
                            // 非阻塞赋值右侧读取的是本拍更新前的 item2_*，因此可以先把
                            // 原编号和数量保存到 pending/current，再清空第二槽。
                            pending_code <= item2_code;
                            current_product_code <= item2_code;
                            current_quantity <= item2_qty;
                            has_item2 <= 1'b0;
                            item2_code <= 4'd0;
                            item2_qty <= 2'd0;
                            selected_count <= 2'd1;
                            total_due <= line_total(item1_code, item1_qty);
                        end else begin
                            // 只有一种商品时弹出第一槽；数量页的“此前已选金额”为 00。
                            pending_code <= item1_code;
                            current_product_code <= item1_code;
                            current_quantity <= item1_qty;
                            has_item1 <= 1'b0;
                            item1_code <= 4'd0;
                            item1_qty <= 2'd0;
                            selected_count <= 2'd0;
                            total_due <= 8'd0;
                        end
                        state <= ST_SELECT_QTY;
                    end else if (key_product_pulse) begin
                        if (selected_count == 2'd2) begin
                            // 两个槽位均被占用：订单保持不变，只输出一次上限提示脉冲。
                            selection_full_pulse <= 1'b1;
                        end else begin
                            // 尚有空槽，KEY1 开始选择下一种商品。
                            current_product_code <= sw;
                            current_quantity <= 2'd0;
                            state <= ST_SELECT_PRODUCT;
                        end
                    end else if (key_confirm_pulse && (total_due != 8'd0)) begin
                        confirm_order();
                    end
                end

                ST_PAY: begin
                    if (key_cancel_pulse) begin
                        // 取消付款时，把原余额和本次投入合并为待退金额。
                        money_next = change_due + paid_amount;
                        paid_amount <= 8'd0;
                        state <= (money_next == 8'd0) ? ST_IDLE : ST_CHANGE;
                        if (money_next == 8'd0) begin
                            clear_transaction();
                        end else begin
                            change_due <= money_next;
                        end
                    end else if (key_change_pulse) begin
                        // KEY3 是付款确认键。硬币和纸币只负责累计金额，
                        // 即使金额已经足够，也要按 KEY3 后才允许出货。
                        money_next = change_due + paid_amount;
                        if (money_next >= total_due) begin
                            // 一次性扣除订单金额，差额保存到 change_due；vend_pulse
                            // 只提示出货首拍，持续时间由 vend_counter 单独控制。
                            paid_amount <= 8'd0;
                            change_due <= money_next - total_due;
                            vend_counter <= (VEND_TICKS > 0) ? (VEND_TICKS - 1) : 0;
                            vend_pulse <= 1'b1;
                            state <= ST_VEND;
                        end else begin
                            // 金额不足时保留订单和已付款金额，由顶层控制绿灯闪烁两次。
                            payment_insufficient_pulse <= 1'b1;
                        end
                    end else if (key_product_pulse) begin
                        // 使用第 9 位检测加法溢出，禁止总金额超过 8 位上限 255 元。
                        money_sum_next = {1'b0, change_due} +
                                         {1'b0, paid_amount} + 9'd1;
                        if (money_sum_next <= 9'd255) begin
                            // KEY1 在付款状态代表投入 1 元硬币。
                            paid_amount <= paid_amount + 8'd1;
                        end else begin
                            payment_insufficient_pulse <= 1'b1;
                        end
                    end else if (key_confirm_pulse) begin
                        money_sum_next = {1'b0, change_due} +
                                         {1'b0, paid_amount} +
                                         {1'b0, bill_value(sw[1:0])};
                        if (money_sum_next <= 9'd255) begin
                            // KEY2 在付款状态投入由 sw[1:0] 选择面额的纸币。
                            paid_amount <= paid_amount + bill_value(sw[1:0]);
                        end else begin
                            payment_insufficient_pulse <= 1'b1;
                        end
                    end
                end

                ST_VEND: begin
                    // 计数归零后，有找零则转状态 6；否则清空交易并回状态 0。
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
                    end else if (key_product_pulse) begin
                        // 找零状态按 KEY1 开始新订单，剩余零钱保留为可复用余额。
                        clear_order_keep_balance();
                        current_product_code <= sw;
                        state <= ST_SELECT_PRODUCT;
                    end else if (key_change_pulse) begin
                        // 每次 KEY3 只退 1 元，return_coin_pulse 同步维持一个时钟周期。
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
