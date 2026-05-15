# 基于 FPGA 的饮料售货机 —— 系统框架设计文档

## 1. 项目总览

本系统是一个基于 FPGA 的饮料售货机，支持**销售**与**管理**两种工作模式，通过 EGO1 板载外设完成全部人机交互。系统覆盖项目要求的所有基础功能（80 分），并实现全部 Bonus（密码校验+报警、蜂鸣器多音效、PS/2 键盘输入、VGA 输出、滚动 UI、操作音、进度条/变频流水灯等）。

### 1.1 设计哲学

- **三层架构**：硬件驱动层（HAL）—— 中枢调度层 —— 业务逻辑层（销售/管理）。
- **共享寄存器堆**：饮料数据（名称/价格/库存/状态）存放在中央寄存器堆，销售模块只读+扣库存，管理模块可读写，顶层做仲裁。
- **统一事件总线**：所有输入（按键/拨码/PS2 键盘）归一化为 `(ev_pulse, ev_code)`，下游模块只看事件编码，不关心物理来源。
- **统一显示总线**：业务模块输出语义数据，`display_mux` 按模式组装后送给 `seg7_driver`。

### 1.2 全局状态机

```
        ┌──────────────────────┐
        │   S_MAIN_MENU (主菜单)│  ← 上电默认，数码管滚动 HELLO
        └──────────────────────┘
               │           │
        SW[0]=0+确认   SW[0]=1+确认
               ▼           ▼
    ┌──────────────┐  ┌────────────────┐
    │ S_SALES(销售) │  │ S_PWD(密码验证) │
    └──────────────┘  └────────────────┘
               │           │ 密码正确
               │           ▼
               │    ┌────────────────┐
               │    │ S_ADMIN(管理)  │
               │    └────────────────┘
               │           │ 连续错 3 次
               │           ▼
               │    ┌────────────────┐
               │    │ S_ALARM(报警)  │  LED全闪 + 蜂鸣器持续
               │    └────────────────┘
               ▼           ▼
           任意状态按 BTN[1] 返回主菜单（报警态需长按 2s）
```

---

## 2. EGO1 硬件资源分配

### 2.1 输入

| 物理外设 | 顶层端口 | 说明 |
|----------|----------|------|
| 100 MHz 时钟 (P17) | `CLK100MHZ` | 系统时钟 |
| 复位按键 S6 (P15) | `CPU_RESETN` | 低有效全局复位 |
| 按键 S0 (R11) | `BTN[0]` | 确认 / 取货 |
| 按键 S1 (R17) | `BTN[1]` | 返回主菜单 / 上翻 |
| 按键 S2 (R15) | `BTN[2]` | 取消 / 下翻 |
| 按键 S3 (V1)  | `BTN[3]` | 左 / 功能− |
| 按键 S4 (U4)  | `BTN[4]` | 右 / 功能+ |
| 拨码开关 SW0~SW7 (R1~P5) | `SW[7:0]` | 数值输入（金额/价格/密码） |
| DIP 开关 SW8[0~7] (T5~U3) | `SW[15:8]` | 功能选择（模式/饮料号/管理子功能） |
| PS2_CLK (K5) | `PS2_CLK` | PS/2 键盘（Bonus） |
| PS2_DATA (L4) | `PS2_DATA` | PS/2 键盘（Bonus） |

**开关功能约定：**

| 开关位 | 主菜单 | 销售模式 | 管理模式/密码 |
|--------|--------|----------|--------------|
| SW[0] | 模式选（0=销售,1=管理） | — | — |
| SW[3:1] | — | 饮料编号 0~7 | 饮料编号 0~7 |
| SW[7:0] | — | 金额输入（角） | 密码输入（8 bit） |
| SW[11:8] | — | — | 价格/库存增量 |
| SW[14:12] | — | — | 管理子功能（见 §4.7） |

### 2.2 输出

| 物理外设 | 顶层端口 | 说明 |
|----------|----------|------|
| LED D1 组 8个 (K3~K1) | `LED[7:0]` | 进度条/流水灯/状态 |
| LED D2 组 8个 (K2~F6) | `LED[15:8]` | 进度条/流水灯/状态 |
| 数码管 DN0 段线 (B4~B2) | `SEG0[6:0]` | 右侧4位段驱动，**高有效** |
| 数码管 DN1 段线 (D4~D2) | `SEG1[6:0]` | 左侧4位段驱动，**高有效** |
| 小数点 DP0(D5), DP1(H2) | `DP0`, `DP1` | 各组小数点 |
| 位选 BIT1~BIT8 | `AN[7:0]` | 8位位选，**高有效**，AN[0]=最右位 |
| 音频 PWM (T1) | `AUD_PWM` | 蜂鸣器，标准推挽输出 0/1 |
| 音频 SD# (M6) | `AUD_SD` | 音频使能，常输出 1 |
| VGA R[3:0] (F5~B7) | `VGA_R` | VGA 红色 4bit（Bonus） |
| VGA G[3:0] (B6~D8) | `VGA_G` | VGA 绿色 4bit（Bonus） |
| VGA B[3:0] (C7~E7) | `VGA_B` | VGA 蓝色 4bit（Bonus） |
| HSYNC (D7), VSYNC (C4) | `VGA_HS`, `VGA_VS` | VGA 同步（Bonus） |

**数码管关键特性：**
- EGO1 数码管为**共阴极**：段选高电平=点亮，位选高电平=选中该位。
- DN0（右4位）和 DN1（左4位）各有独立段线引脚，`seg7_driver` 扫描到哪组就驱动哪组，另一组段线输出全 0。
- `AN[0]`=最右位（DN0_K1/BIT1），`AN[7]`=最左位（DN1_K4/BIT8）。

---

## 3. 模块层级总览

```
drink_vending_top              [C] 顶层，完成所有 wire 连接
├── clk_rst_gen                [C]
├── debouncer × 5              [C] BTN[4:0] 各一份
├── sw_sync                    [C]
├── ps2_keyboard               [C] (Bonus)
├── event_arbiter              [C]
├── mode_controller            [C]
├── reg_file                   [C]
├── sales_module               [B] ← B 实现此模块
├── admin_module               [A] ← A 实现此模块
├── password_unit              [A] ← A 实现此模块
├── display_mux                [C]
├── seg7_driver                [C]
├── led_driver                 [C]
├── buzzer_driver              [C] (Bonus)
└── vga_driver                 [C] (Bonus)
```

| 负责人 | 文件 |
|--------|------|
| C | `drink_vending_top.v`, `clk_rst_gen.v`, `debouncer.v`, `sw_sync.v`, `ps2_keyboard.v`, `event_arbiter.v`, `mode_controller.v`, `reg_file.v`, `display_mux.v`, `seg7_driver.v`, `led_driver.v`, `buzzer_driver.v`, `vga_driver.v`, `vending_ego1.xdc` |
| B | `sales_module.v` |
| A | `admin_module.v`, `password_unit.v` |

---

## 4. 子模块详细说明

### 4.1 `clk_rst_gen` [C]

```verilog
module clk_rst_gen (
    input  wire clk_in,      // P17, 100 MHz
    input  wire rst_btn_n,   // P15, 低有效
    output wire clk_sys,     // 100 MHz 系统时钟（直通）
    output wire rst_sync     // 同步复位，高有效
);
```

### 4.2 `debouncer` [C]

```verilog
module debouncer #(parameter CNT_MAX = 2_000_000) // 20 ms @ 100 MHz
(
    input  wire clk, rst,
    input  wire btn_in,      // 按下=1
    output reg  btn_level,   // 消抖后电平
    output reg  btn_pulse    // 按下瞬间单周期脉冲
);
```

### 4.3 `sw_sync` [C]

```verilog
module sw_sync (
    input  wire        clk,
    input  wire [15:0] sw_in,   // SW[7:0]=拨码, SW[15:8]=DIP
    output reg  [15:0] sw_out   // 两级FF同步后
);
```

### 4.4 `ps2_keyboard` [C] (Bonus)

```verilog
module ps2_keyboard (
    input  wire       clk, rst,
    input  wire       ps2_clk,   // K5
    input  wire       ps2_data,  // L4
    output reg  [7:0] scancode,
    output reg        key_valid,    // 收到完整扫描码的单周期脉冲
    output reg        key_release   // 是否为 break code（F0 前缀）
);
```

### 4.5 `event_arbiter` [C]

```verilog
module event_arbiter (
    input  wire        clk, rst,
    input  wire        btn0_p, btn1_p, btn2_p, btn3_p, btn4_p,
    input  wire [15:0] sw,
    input  wire        kbd_valid,
    input  wire [7:0]  kbd_code,
    input  wire        kbd_release,
    output reg         ev_pulse,     // 有效操作的单周期脉冲
    output reg  [3:0]  ev_code,      // 事件编码
    output reg         buzzer_click  // 操作音触发
);
```

**`ev_code` 编码：**
`0=CONFIRM`(BTN0/Enter), `1=UP`(BTN1/Esc), `2=DOWN`(BTN2/BS),
`3=LEFT`(BTN3/←), `4=RIGHT`(BTN4/→), `5~14=NUM0~9`(键盘数字), `15=NONE`

### 4.6 `mode_controller` [C]

```verilog
module mode_controller (
    input  wire        clk, rst,
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,
    input  wire        sales_exit_req,
    input  wire        admin_exit_req,
    input  wire        pwd_ok,
    input  wire        pwd_fail3,
    output reg         mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm,
    output reg         scroll_enable
);
```

### 4.7 `reg_file` [C]

8 种饮料（编号 0~7），每种有 name_id(4b) / price(8b) / stock(4b) / enabled(1b)，外加 total_revenue(16b)。

```verilog
module reg_file #(parameter N = 8) (
    input  wire        clk, rst,
    input  wire [2:0]  rd_idx,
    output wire [3:0]  rd_name_id,
    output wire [7:0]  rd_price,
    output wire [3:0]  rd_stock,
    output wire        rd_enabled,
    output wire [15:0] rd_total_revenue,
    // 销售写
    input  wire        sale_we,
    input  wire [2:0]  sale_idx,
    input  wire [7:0]  sale_amount,
    input  wire        refund_we,
    input  wire [2:0]  refund_idx,
    input  wire [7:0]  refund_amount,
    // 管理写
    input  wire        admin_we_price,
    input  wire [2:0]  admin_price_idx,
    input  wire [7:0]  admin_price_val,
    input  wire        admin_we_restock,
    input  wire [2:0]  admin_restock_idx,
    input  wire [3:0]  admin_restock_amt,
    input  wire        admin_we_toggle,
    input  wire [2:0]  admin_toggle_idx
);
```

上电初始值：COLA/30/5，SPRT/30/5，ORNG/35/4，MILK/40/3，BEER/50/2，H2O/20/8，TEA/25/6，CFEE/60/0。
sales 写优先于 admin 写。

### 4.8 `sales_module` [B] — 接口已冻结，B 实现内部 FSM

```verilog
module sales_module (
    input  wire        clk, rst,
    input  wire        enable,         // = mode_sales
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,
    // reg_file
    output wire [2:0]  rf_rd_idx,
    input  wire [3:0]  rf_rd_name_id,
    input  wire [7:0]  rf_rd_price,
    input  wire [3:0]  rf_rd_stock,
    input  wire        rf_rd_enabled,
    output wire        rf_sale_we,
    output wire [2:0]  rf_sale_idx,
    output wire [7:0]  rf_sale_amount,
    output wire        rf_refund_we,
    output wire [2:0]  rf_refund_idx,
    output wire [7:0]  rf_refund_amount,
    // 显示
    output wire [2:0]  disp_sel_idx,
    output wire [7:0]  disp_balance,
    output wire [7:0]  disp_price,
    output wire [3:0]  disp_countdown,
    output wire [3:0]  disp_err_code,
    output wire [2:0]  sales_state,
    // LED
    output wire [15:0] led_pattern,
    output wire        led_breathing,
    output wire        led_error_blink,
    output wire        exit_req
);
```

B 的子状态：`IDLE→SELECT→PAY→CONFIRM→DISPENSE→PICKUP_WAIT→DONE` 或 `→REFUND`。
饮料编号 = `sw[3:1]`；金额 = `sw[7:0]`；取货超时 5 s（5×10^8 clk）；错误码 1~4。

### 4.9 `admin_module` [A] — 接口已冻结，A 实现内部 FSM

```verilog
module admin_module (
    input  wire        clk, rst,
    input  wire        enable,         // = mode_admin
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,
    // reg_file
    output reg  [2:0]  rf_rd_idx,
    input  wire [3:0]  rf_rd_name_id,
    input  wire [7:0]  rf_rd_price,
    input  wire [3:0]  rf_rd_stock,
    input  wire        rf_rd_enabled,
    input  wire [15:0] rf_rd_total_revenue,
    output reg         rf_admin_we_price,
    output reg  [2:0]  rf_admin_price_idx,
    output reg  [7:0]  rf_admin_price_val,
    output reg         rf_admin_we_restock,
    output reg  [2:0]  rf_admin_restock_idx,
    output reg  [3:0]  rf_admin_restock_amt,
    output reg         rf_admin_we_toggle,
    output reg  [2:0]  rf_admin_toggle_idx,
    // 显示
    output reg  [2:0]  admin_subfn,
    output reg  [2:0]  disp_admin_idx,
    output reg  [7:0]  disp_admin_val,
    output reg  [15:0] disp_total_revenue,
    output reg  [3:0]  disp_admin_err,
    output reg  [15:0] led_admin,
    output reg         exit_req
);
```

子功能由 `sw[14:12]` 选择：`000`查库存，`001`查价格，`010`查累计，`011`查停售，`100`改价，`101`补货，`110`切停售，`111`退出。

### 4.10 `password_unit` [A] (Bonus)

```verilog
module password_unit #(parameter PWD_DEFAULT = 8'hB4)
(
    input  wire        clk, rst,
    input  wire        enable,      // = mode_pwd
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,          // sw[7:0] 为密码
    output reg         pwd_ok,      // 单周期：正确
    output reg         pwd_fail,    // 单周期：错误
    output reg         pwd_fail3,   // 锁存：连续 3 次错误
    output reg  [1:0]  fail_cnt,
    output reg  [3:0]  disp_err_code
);
```

### 4.11 `display_mux` [C]

根据当前模式将语义数据组装为 8 位数码管的字符 ID 数组。

```verilog
module display_mux (
    input  wire        clk, rst,
    input  wire        mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm,
    input  wire        scroll_enable,
    input  wire [2:0]  s_sel_idx,
    input  wire [7:0]  s_balance, s_price,
    input  wire [3:0]  s_countdown, s_err_code,
    input  wire [2:0]  s_state,
    input  wire [3:0]  rf_name_id,
    input  wire [2:0]  a_subfn,
    input  wire [2:0]  a_idx,
    input  wire [7:0]  a_val,
    input  wire [15:0] a_total,
    input  wire [3:0]  a_err,
    input  wire [1:0]  pwd_fail_cnt,
    input  wire [7:0]  pwd_sw_echo,
    input  wire [3:0]  pwd_err,
    output reg  [4:0]  digit [0:7],  // digit[0]=最右位
    output reg  [7:0]  dp_mask
);
```

字符 ID：0~9=数字，10=H，11=E，12=L，13=O，14=P，15=S，16=n，17=r，18=t，19=A，20=b，21=c，22=d，23=F，24=U，25=`-`，26=空白。

**各模式布局（位7为最左，位0为最右）：**

| 模式 | 位7..0 |
|------|--------|
| 主菜单 | 滚动 `HELLO   ` / `  OPEN  ` |
| 销售-SELECT | `[编号]``[N][A][M][E]``空``[P][r][价格]` |
| 销售-PAY | `[b][A][L]``[余额十位][余额个位]``/``[价格十位][价格个位]` |
| 销售-PICKUP | `[P][i][c][k]``空``空``空``[倒计时]` |
| 销售-ERROR | `[E][-][错误码]``空``空``空``空``空` |
| 密码 | `[P][S][错误次数]``空``[sw7~4]``[sw3~0]` |
| 管理-查库存 | `[编号]``[N][A][M][E]``[S][t][库存]` |
| 管理-查价格 | `[编号]``[N][A][M][E]``空``[价格][.][价格]` |
| 管理-查累计 | `[t][o][t][A][L]``空``[金额高][金额低]` |
| 报警 | `[A][L][A][r][M]``空``[次数]` |

### 4.12 `seg7_driver` [C]

EGO1 共阴极双组段线数码管驱动。

```verilog
module seg7_driver (
    input  wire        clk, rst,
    input  wire [4:0]  digit0, digit1, digit2, digit3,  // 右4位 digit[3:0]
    input  wire [4:0]  digit4, digit5, digit6, digit7,  // 左4位 digit[7:4]
    input  wire [7:0]  dp_mask,
    output reg  [6:0]  SEG0,   // DN0 段线 {CG0..CA0}，高有效
    output reg         DP0,
    output reg  [6:0]  SEG1,   // DN1 段线 {CG1..CA1}，高有效
    output reg         DP1,
    output reg  [7:0]  AN      // 位选，高有效，AN[0]=最右位
);
```

扫描频率：100 MHz / 100_000 = 1 kHz/位。扫描到位 0~3 时驱动 SEG0，SEG1=0；扫描到位 4~7 时驱动 SEG1，SEG0=0。

**字符→7段编码（高有效，位序 [6:0]={G,F,E,D,C,B,A}）：**
`0→0111111`，`1→0000110`，`2→1011011`，`3→1001111`，`4→1100110`，
`5→1101101`，`6→1111101`，`7→0000111`，`8→1111111`，`9→1101111`，
`H→1110110`，`E→1111001`，`L→0111000`，`O→0111111`，`P→1110011`，
`S→1101101`，`n→1010100`，`r→1010000`，`t→1111000`，`A→1110111`，
`b→1111100`，`c→1011000`，`d→1011110`，`F→1110001`，`U→0111110`，
`-→1000000`，`空白→0000000`

### 4.13 `led_driver` [C]

```verilog
module led_driver (
    input  wire        clk, rst,
    input  wire        mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm,
    input  wire [15:0] sales_led_pattern,
    input  wire        sales_led_breathing,
    input  wire        sales_led_error,
    input  wire [15:0] admin_led_pattern,
    input  wire [7:0]  pwd_sw_echo,   // 密码模式下显示当前输入
    output reg  [15:0] led
);
```

主菜单=跑马灯；销售=透传 pattern（叠加呼吸/报错效果）；密码=LED[7:0]显示 sw[7:0]；管理=透传；报警=全部 5 Hz 闪烁。

### 4.14 `buzzer_driver` [C] (Bonus)

```verilog
module buzzer_driver (
    input  wire clk, rst,
    input  wire click_pulse,   // 每次有效按键触发，播放操作音
    input  wire mode_alarm,    // 报警时持续播放
    output wire AUD_PWM,       // T1，标准推挽 assign AUD_PWM = pwm_out
    output wire AUD_SD         // M6，= 1'b1
);
```

操作音：4 kHz，50 ms。报警音：1 kHz / 2 kHz 每 200 ms 交替。

### 4.15 `vga_driver` [C] (Bonus)

640×480@60 Hz，25 MHz 像素时钟（100 MHz/4）。三区文本布局：顶部模式名、中部商品列表、底部状态行。

```verilog
module vga_driver (
    input  wire        clk_100m, rst,
    input  wire        mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm,
    output reg  [2:0]  rf_rd_idx_vga,
    input  wire [3:0]  rf_name_id,
    input  wire [7:0]  rf_price,
    input  wire [3:0]  rf_stock,
    input  wire        rf_enabled,
    input  wire [2:0]  sales_sel_idx,
    input  wire [7:0]  sales_balance,
    input  wire [15:0] admin_total_revenue,
    output wire        VGA_HS, VGA_VS,
    output wire [3:0]  VGA_R, VGA_G, VGA_B
);
```

---

## 5. 成员 A / B 接口契约速查

**B (sales_module) 必须保证：**
- `rf_sale_we` 在取货成功那周期拉高 1 周期，`rf_sale_amount = price`
- `rf_refund_we` 在超时那周期拉高 1 周期（stock 归还，revenue 回滚）
- `led_pattern` PAY 阶段=进度条，DISPENSE 阶段=变频流水灯
- `exit_req` 在 `EV_UP` 时拉高 1 周期

**A (admin_module + password_unit) 必须保证：**
- 各写使能（`rf_admin_we_*`）仅在 `EV_CONFIRM` 确认时拉高 1 周期
- `password_unit`：连续 3 次错给 `pwd_fail3` 锁存高
- 修改实时生效（下一时钟边沿 sales 模块即可读到新值）

---

## 6. 编译上板

1. Vivado 新建工程，器件选 `xc7a35tcsg324-1`（速度等级 -1C）。
2. 添加所有 `.v` 文件，顶层模块 `drink_vending_top`。
3. 添加 `vending_ego1.xdc`。
4. Synthesis → Implementation → Generate Bitstream → 通过 Type-C 烧录。

---

*文档版本 v2.0 — EGO1 (XC7A35T-1CSG324C)*
