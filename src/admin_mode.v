`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/26 21:04:41
// Design Name: 
// Module Name: admin_mode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// 模块名称: admin_mode
// 描述: 售货机管理模式控制，包含8-bit密码校验（Bonus）、连续错误报警、数据修改指令下发。
// 注意: 所有的 btn 输入默认已经被消抖并且提取了单脉冲（上升沿有效）。
// 目前为4种饮料

module admin_mode(
    input clk,
    input rst_n,
    input admin_en,             // 从主状态机来的使能信号：1表示当前在管理模式
    
    // 交互输入
    input [7:0] switch_in,      // 8个拨码开关:输入密码/输入新价格/输入库存增量
    input btn_confirm,          // 确认按键
    input btn_next,             // 切换按键，用于切换饮料编号
    input btn_to_view,          // 进入查看模式按键
    input btn_to_modify,        // 进入修改模式按键
    
    // 来自寄存器堆（成员C）的输入
    input [7:0] current_stock,    // 当前选中饮料的库存
    input [7:0] current_price,    // 当前选中饮料的单价
    input [3:0] sold_out_mask,    // 停售/售罄列表（每位代表一种饮料）
    input [15:0] total_revenue,   // 总销售额
    
    // 给数据存储模块 (成员C) 的输出
    output reg [7:0] update_data, // 发送给存储模块的具体数值
    output reg [2:0] drink_id,   // 发送给存储模块的地址（哪种饮料）
    output reg write_en,        // 写使能脉冲，1个时钟周期
    output reg [31:0] view_data,  // 发送给成员 C，对应 8 个数码管
    
    // 给外设驱动的输出
    output reg alarm_trigger,   // 触发蜂鸣器报警
    output reg [3:0] error_code // 输出到数码管的错误码 (例如 4'hE 代表密码错)
);

    // 数据预处理
    // 使用 assign 定义组合逻辑，实时计算十进制位
    wire [3:0] st_thou = (current_stock / 1000) % 10; 
    wire [3:0] st_hund = (current_stock / 100) % 10;  
    wire [3:0] st_ten  = (current_stock / 10) % 10;   
    wire [3:0] st_one  = current_stock % 10;          

    wire [3:0] pr_ten  = (current_price / 10) % 10;   
    wire [3:0] pr_one  = current_price % 10;
    
    // 状态机定义
    localparam S_IDLE     = 3'd0; // 闲置
    localparam S_AUTH     = 3'd1; // 密码校验
    localparam S_ALARM    = 3'd2; // 报警
    localparam S_SELECT   = 3'd3; // 模式选择
    localparam S_VIEW     = 3'd4; // 查看模式
    localparam S_MODIFY   = 3'd5; // 修改模式
    localparam S_SAVE     = 3'd6; // 保存数据
    
    reg [2:0] current_state, next_state;
    
    reg [1:0] err_cnt;            // 密码错误计数器
    wire [7:0] CORRECT_PWD = 8'hA5; // 预设密码 10100101 (方便拨码开关测试)

    // 第一段：状态转移时序逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;  
        end else begin
            current_state <= next_state;
        end
    end

    // 第二段：状态转移组合逻辑
    always @(*) begin
        next_state = current_state; // 默认保持当前状态
        
        case(current_state)
            S_IDLE: begin
                if (admin_en) 
                    next_state = S_AUTH; // 开启管理模式，去验密码
            end
            
            S_AUTH: begin
                if (!admin_en) 
                    next_state = S_IDLE; // 中途退出
                else if (err_cnt >= 2'd3)
                    next_state = S_ALARM; // 错3次，报警
                else if (btn_confirm) begin
                    if (switch_in == CORRECT_PWD)
                        next_state = S_SELECT; // 密码正确，进入选择
                end
            end
            
            S_ALARM: begin
                if (!admin_en) 
                    next_state = S_IDLE; // 退出管理模式后解除报警
            end
            
            S_SELECT: begin
                if (!admin_en) 
                    next_state = S_IDLE;
                else if (btn_to_view) 
                    next_state = S_VIEW;      // 进入查看
                else if (btn_to_modify) 
                    next_state = S_MODIFY;    // 进入修改
            end
            
            S_VIEW: begin
                if (!admin_en) 
                    next_state = S_IDLE;
                else if (btn_confirm) 
                    next_state = S_SELECT;
            end
            
            S_MODIFY: begin
                if (!admin_en) 
                    next_state = S_IDLE;
                else if (btn_confirm) 
                    next_state = S_SAVE;
            end
            
            S_SAVE: begin
                next_state = S_SELECT; 
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // 第三段：数据和控制信号输出 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位初始化所有输出
            err_cnt <= 2'd0;
            alarm_trigger <= 1'b0;
            error_code <= 4'h0;
            drink_id <= 3'd0;
            update_data <= 8'd0;
            write_en <= 1'b0;
        end else begin
            // 默认值清零，防止误写
            write_en <= 1'b0; 
            
            case(current_state)
                S_IDLE: begin
                    err_cnt <= 2'd0; // 退出管理模式时清空错误次数
                    alarm_trigger <= 1'b0;
                    error_code <= 4'h0;
                end
                
                S_AUTH: begin
                    if (btn_confirm && switch_in != CORRECT_PWD) begin
                        err_cnt <= err_cnt + 1'b1; // 计数错误次数
                        error_code <= 4'hE; // 数码管显示 E (Error)
                    end
                end
                
                S_ALARM: begin
                    alarm_trigger <= 1'b1; // 触发蜂鸣器
                    error_code <= 4'hA;    // 数码管显示 A (Alarm)
                end
                
                S_SELECT: begin
                    error_code <= 4'h0; // 清除错误码
                    // 显示 "SEL- 01" (0代表View, 1代表Modify，提示用户选)
                    view_data <= 32'h5E1_0001;
                end
                
                 S_VIEW: begin
                    //选择饮料
                    if (btn_next) begin
                        if (drink_id == 3'd3) 
                            drink_id <= 3'd0; 
                        else 
                            drink_id <= drink_id + 1'b1;
                    end
                    // 根据低4位开关的状态决定显示内容
                    casex(switch_in[3:0]) 
                        4'bxxx1: begin // 开关0：查看种类及库存
                            // 显示格式: [ID] [F] [F] [千] [百] [十] [个]
                            view_data <= {4'h0, drink_id, 8'hFF, st_thou, st_hund, st_ten, st_one};
                        end
                
                        4'bxx1x: begin // 开关1：查看单价
                            // 显示格式：[ID] [F] [F] [F] [F] [F] [十] [个] 
                             view_data <= {4'h0, drink_id, 16'hFFFF, pr_ten, pr_one};
                        end
                
                        4'bx1xx: begin // 开关2：查看累计总额
                            // 显示格式：直接显示 8 位金额
                            view_data <= total_revenue;
                        end
                
                        4'b1xxx: begin // 开关3：查看停售列表
                            // 显示格式：[O] [F] [F] [F] [F] [F] [F] [Mask]
                            // 示例：OFF-1010(2、4售罄）
                            view_data <= {12'h0FF, 4'hF, 12'h0, sold_out_mask[3], sold_out_mask[2], sold_out_mask[1], sold_out_mask[0]};
                        end
                
                        default: begin
                            // 如果没拨开关，显示 "READY" 或全灭
                            view_data <= 32'h0EAD1_FFF; 
                        end
                    endcase
                end
                
                S_MODIFY: begin
                    // 读取此时拨码开关的值作为新价格/库存
                    update_data <= switch_in;
                end
                
                S_SAVE: begin
                    // 拉高写使能一个时钟周期，告诉 C 把 update_data 存到 drink_id 对应的寄存器里
                    write_en <= 1'b1; 
                end
            endcase
        end
    end
endmodule
