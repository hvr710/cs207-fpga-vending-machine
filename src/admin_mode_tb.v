`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/28 11:36:25
// Design Name: 
// Module Name: admin_mode_tb
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


module tb_admin_mode();
    reg clk;
    reg rst_n;
    reg admin_en;
    
    // 交互输入
    reg [7:0] switch_in;
    reg btn_confirm;
    reg btn_next;
    reg btn_to_view;
    reg btn_to_modify;
    reg btn_price;
    reg btn_stock;
    reg btn_shelf;
    
    // 模拟成员C的存储数据输入
    reg [7:0] current_stock;
    reg [7:0] current_price;
    reg [3:0] sold_out_mask;
    reg [15:0] total_revenue;
    
    wire [1:0] update_type_out;
    wire [7:0] update_data;
    wire [2:0] drink_id;
    wire write_en;
    wire [31:0] view_data;
    wire alarm_trigger;
    wire [3:0] error_code;

    // 实例化
    admin_mode uut (
        .clk(clk),
        .rst_n(rst_n),
        .admin_en(admin_en),
        .switch_in(switch_in),
        .btn_confirm(btn_confirm),
        .btn_next(btn_next),
        .btn_to_view(btn_to_view),
        .btn_to_modify(btn_to_modify),
        .btn_price(btn_price),
        .btn_stock(btn_stock),
        .btn_shelf(btn_shelf),
        .current_stock(current_stock),
        .current_price(current_price),
        .sold_out_mask(sold_out_mask),
        .total_revenue(total_revenue),
        .update_type_out(update_type_out),
        .update_data(update_data),
        .drink_id(drink_id),
        .write_en(write_en),
        .view_data(view_data),
        .alarm_trigger(alarm_trigger),
        .error_code(error_code)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns 周期
    end

    // 定义按键触发任务 (模拟单脉冲)
    // 注意：Verilog-2001 中 task 不能直接传 inout 脉冲，所以针对每个按键写小任务最稳妥
    task press_confirm; begin @(posedge clk); btn_confirm = 1; @(posedge clk); btn_confirm = 0; end endtask
    task press_next;    begin @(posedge clk); btn_next = 1;    @(posedge clk); btn_next = 0;    end endtask
    task press_to_view; begin @(posedge clk); btn_to_view = 1; @(posedge clk); btn_to_view = 0; end endtask
    task press_to_mod;  begin @(posedge clk); btn_to_modify = 1;@(posedge clk); btn_to_modify = 0;end endtask
    task press_price;   begin @(posedge clk); btn_price = 1;   @(posedge clk); btn_price = 0;   end endtask
    task press_stock;   begin @(posedge clk); btn_stock = 1;   @(posedge clk); btn_stock = 0;   end endtask
    task press_shelf;   begin @(posedge clk); btn_shelf = 1;   @(posedge clk); btn_shelf = 0;   end endtask

    // 核心测试流程
    initial begin
        // 初始化
        rst_n = 0;
        admin_en = 0;
        switch_in = 8'd0;
        btn_confirm = 0; btn_next = 0; btn_to_view = 0; btn_to_modify = 0;
        btn_price = 0; btn_stock = 0; btn_shelf = 0;
        
        // 模拟外部数据（成员C提供）
        current_stock = 8'd50;  // 50瓶
        current_price = 8'd12;  // 12元
        sold_out_mask = 4'b0010;// 1号饮料(第2种)停售
        total_revenue = 16'd520;// 收入520
        
        #20 rst_n = 1;
        #20;
        
        $display("仿真开始");

        // 测试一：输错密码触发报警
        $display("1. 测试密码校验与报警机制");
        @(posedge clk); admin_en = 1; // 进入管理模式
        
        switch_in = 8'h00; // 错误密码
        #20 press_confirm(); // 错1次
        #20 press_confirm(); // 错2次
        #20 press_confirm(); // 错3次触发报警 (S_ALARM)
        #40;
        if(alarm_trigger) $display("   -> 报警触发成功！");
        
        // 退出重进，清除报警
        @(posedge clk); admin_en = 0;
        #40;
        @(posedge clk); admin_en = 1; 

        // 测试二：正确密码登录与查看模式
        $display("2. 测试正确密码登录");
        switch_in = 8'hA5; // 正确密码
        #20 press_confirm();
        #40;
        $display("   -> 登录成功，进入 S_SELECT");
        
        $display("3. 进入查看模式 (S_VIEW)");
        #20 press_to_view();
        
        // 拨动开关查看不同信息
        switch_in = 8'b0000_0001; #40; // 看库存
        switch_in = 8'b0000_0010; #40; // 看价格
        
        // 退出查看，回选择界面
        #20 press_confirm();
        #40;

        // 测试三：修改模式 - 改价格
        $display("4. 测试修改价格 (0号饮料)");
        #20 press_to_mod(); // 进修改模式
        #20 press_price();  // 按下价格修改键
        
        switch_in = 8'd15;  // 设新价格为 15
        #40 press_confirm();// 确认保存 (产生 write_en 脉冲)
        #40;
        $display("   -> 检查波形：write_en 应出现脉冲，update_type_out=1, update_data=15");

        // 测试四：修改模式 - 切ID并补货
        $display("5. 测试切换饮料并补货 (1号饮料)");
        #20 press_to_mod(); // 再次进入修改模式
        #20 press_next();   // 切换到 1 号饮料
        #20 press_stock();  // 按下补货键
        
        switch_in = 8'd20;  // 补货 20 瓶
        #40 press_confirm();// 确认保存
        #40;
        $display("   -> 检查波形：write_en 脉冲，update_type_out=2, update_data=20, drink_id=1");

        // 测试五：修改模式 - 停售/恢复
        $display("6. 测试停售状态切换 (1号饮料)");
        #20 press_to_mod(); // 进修改模式
        #20 press_shelf();  // 按下状态切换键
        
        #40 press_confirm();// 确认保存
        #40;
        $display("   -> 检查波形：write_en 脉冲，update_type_out=3, update_data=1");

        // 测试六：退出管理模式测试复位状态
        $display("7. 退出管理模式测试 (全局清零)");
        @(posedge clk); admin_en = 0;
        #60;
        $display("   -> 检查波形：所有关键控制信号应清零");

        $display("=== 仿真结束 ===");
        $stop; // 停止仿真
    end

endmodule
