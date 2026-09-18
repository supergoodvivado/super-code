`timescale 1ns / 1ps

// 按键调理模块：把低有效机械按键转换为同步、消抖后的按下电平和单周期事件脉冲。
module button_conditioner #(
    parameter DEBOUNCE_TICKS = 500_000
) (
    input wire clk,
    input wire reset,
    input wire btn_n,
    output wire pressed_level,
    output wire pressed_pulse
);

    // 两级同步器消除按键输入相对 clk 的亚稳态风险。
    reg [1:0] sync_reg;
    // 消抖后的当前/上一拍按下状态，用于检测按下沿。
    reg debounced;
    reg debounced_d;
    // 输入与稳定状态不一致时的持续计数器。
    reg [31:0] count;
    wire pressed_raw;

    // 板上按键低电平表示按下；只在稳定按下的第一拍输出 pulse。
    assign pressed_raw = ~btn_n;
    assign pressed_level = debounced;
    assign pressed_pulse = debounced & ~debounced_d;

    // 同步、消抖和按下沿记录：输入连续保持 DEBOUNCE_TICKS 个周期后才更新状态。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sync_reg <= 2'b00;
            debounced <= 1'b0;
            debounced_d <= 1'b0;
            count <= 32'd0;
        end else begin
            sync_reg <= {sync_reg[0], pressed_raw};
            debounced_d <= debounced;

            if (sync_reg[1] == debounced) begin
                count <= 32'd0;
            end else if (count >= (DEBOUNCE_TICKS - 1)) begin
                debounced <= sync_reg[1];
                count <= 32'd0;
            end else begin
                count <= count + 32'd1;
            end
        end
    end

endmodule
