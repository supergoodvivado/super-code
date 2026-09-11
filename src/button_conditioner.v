`timescale 1ns / 1ps

module button_conditioner #(
    parameter DEBOUNCE_TICKS = 500_000
) (
    input wire clk,
    input wire reset,
    input wire btn_n,
    output wire pressed_level,
    output wire pressed_pulse
);

    // 板上按键为低电平有效，先取反为“1 表示按下”，便于后续判断。
    // 两级同步器用于降低异步按键输入带来的亚稳态风险；sync_reg[1]
    // 是真正送入消抖逻辑的同步后电平。
    // 只有输入连续稳定 DEBOUNCE_TICKS 个时钟后才更新消抖状态。
    reg [1:0] sync_reg;
    reg debounced;
    reg debounced_d;
    reg [31:0] count;
    wire pressed_raw;

    assign pressed_raw = ~btn_n;
    assign pressed_level = debounced;
    // pressed_pulse 仅在按键稳定按下时产生一个时钟周期的高脉冲。
    assign pressed_pulse = debounced & ~debounced_d;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sync_reg <= 2'b00;
            debounced <= 1'b0;
            debounced_d <= 1'b0;
            count <= 32'd0;
        end else begin
            // 非阻塞赋值使新输入依次经过两级寄存器，而不会在同一拍直接穿透。
            sync_reg <= {sync_reg[0], pressed_raw};
            debounced_d <= debounced;

            if (sync_reg[1] == debounced) begin
                // 输入回到当前稳定状态，说明之前的变化只是抖动，重新计数。
                count <= 32'd0;
            end else if (count >= (DEBOUNCE_TICKS - 1)) begin
                // 新电平持续时间达到门限，正式接受这次按下或释放。
                debounced <= sync_reg[1];
                count <= 32'd0;
            end else begin
                // 输入尚未稳定到门限，只累计时间，不改变对外输出。
                count <= count + 32'd1;
            end
        end
    end

endmodule
