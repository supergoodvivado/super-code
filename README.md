# 自动售货机 Verilog 课程设计提交包

## 工程信息

- 题目：自动售货机
- 开发板：HX7A75C / Artix-7 XC7A75T FGG484-2
- 顶层模块：`vending_machine_top`
- 主要功能：16 种商品、数量选择、最多两种商品、投币、出货、手动找零/退款、数码管显示、LED 状态指示、蜂鸣器提示

## 文件结构

- `src/`：Verilog 源码
  - `vending_machine_top.v`：顶层模块，连接按键、拨码、LED、数码管、蜂鸣器
  - `vending_machine_core.v`：自动售货机核心状态机
  - `seven_segment_scan.v`：8 位数码管动态扫描显示
  - `button_conditioner.v`：按键同步、消抖、单脉冲
- `sim/`：仿真文件
  - `tb_vending_machine_core.v`：核心功能测试平台
- `constraints/`：HX7A75C 开发板约束文件
- `scripts/`：Vivado Tcl 脚本
  - `create_project.tcl`：重新创建 Vivado 工程
  - `run_sim.tcl`：运行行为仿真
  - `run_build.tcl`：综合、实现并生成 bitstream
- `bitstream/`
  - `vending_machine_top.bit`：已生成好的最终下载文件
- `reports/`：Vivado 生成的时序、资源、布线和 DRC 报告
- `docs/`：操作说明和设计报告草稿

## 快速下载到开发板

如果只想直接在板子上运行：

1. 打开 Vivado。
2. Open Hardware Manager。
3. 连接开发板。
4. Program Device。
5. 选择 `bitstream/vending_machine_top.bit`。

## 重新创建工程

在 Vivado 的 Tcl Console 中执行：

```tcl
source <本文件夹路径>/scripts/create_project.tcl
```

例如，如果本文件夹在桌面：

```tcl
source C:/Users/Lenovo/Desktop/提交包_自动售货机_HX7A75C_最终版/scripts/create_project.tcl
```

执行后会在本文件夹内生成 `vivado_project_hx7a75c/` 工程目录。

## 运行仿真

```tcl
source <本文件夹路径>/scripts/run_sim.tcl
```

仿真通过时，Tcl Console 会看到类似信息：

```text
PASS: vending machine core simulation completed.
```

## 重新生成 bitstream

```tcl
source <本文件夹路径>/scripts/run_build.tcl
```

生成后的 bit 文件在：

```text
vivado_project_hx7a75c/vending_machine_hx7a75c.runs/impl_1/vending_machine_top.bit
```

## 板上开关方向

本开发板实测：

- SW1-SW4 向上为 0，向下为 1。
- DIG/LED 拨到数码管模式时，8 位数码管工作。
- BUZ/SW 拨到蜂鸣器模式时，按键提示音和出货提示音工作。

## 当前显示状态机

- 初始显示：`00000000`
- 按 KEY1 一次进入商品选择：只允许第 2、3 位商品编号变化
- 再按 KEY1 进入数量选择：商品编号锁定，只允许第 4 位数量变化
- 再按 KEY1 确认该商品，后续进入原付款/出货/找零流程

