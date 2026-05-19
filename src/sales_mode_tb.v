`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_sales_mode
// Description : Testbench for the improved 4-item sales_mode.
//
// Tested scenarios:
// 1. Page navigation by previous/next buttons.
// 2. Normal purchase: select -> pay enough -> pickup.
// 3. Insufficient payment.
// 4. Inactivity timeout during payment.
// 5. Pickup timeout refund.
// 6. Off-sale and no-stock exceptions.
//////////////////////////////////////////////////////////////////////////////////

module tb_sales_mode();

    reg clk;
    reg rst_n;
    reg sales_en;

    reg [7:0] switch_in;
    reg btn_confirm;
    reg btn_prev;
    reg btn_next;
    reg btn_pay;
    reg btn_cancel;

    reg [7:0] price0, price1, price2, price3;
    reg [3:0] stock0, stock1, stock2, stock3;
    reg [3:0] enabled_mask;

    wire [1:0]  drink_id;
    wire        sale_we;
    wire [1:0]  sale_idx;
    wire [7:0]  sale_amount;
    wire        refund_pulse;
    wire [7:0]  refund_amount;
    wire        exit_to_main;
    wire [7:0]  paid_amount;
    wire [7:0]  current_price;
    wire [3:0]  current_stock;
    wire [15:0] led_out;
    wire [39:0] view_data;
    wire [3:0]  state_code;
    wire [3:0]  error_code;
    wire [3:0]  countdown_sec;

    integer fail_count;

    localparam S_IDLE      = 4'd0;
    localparam S_SELECT    = 4'd1;
    localparam S_CHECK     = 4'd2;
    localparam S_PAY       = 4'd3;
    localparam S_DISPENSE  = 4'd4;
    localparam S_WAIT_TAKE = 4'd5;
    localparam S_COMPLETE  = 4'd6;
    localparam S_REFUND    = 4'd7;
    localparam S_ERROR     = 4'd8;

    localparam ERR_OFF_SALE   = 4'd1;
    localparam ERR_NO_STOCK   = 4'd2;
    localparam ERR_NOT_ENOUGH = 4'd3;
    localparam ERR_TIMEOUT    = 4'd5;

    sales_mode #(
        .TAKE_TIMEOUT_CYCLES(50),
        .INACTIVITY_TIMEOUT_CYCLES(40),
        .MESSAGE_TIMEOUT_CYCLES(20),
        .LED_STEP_CYCLES(4)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .sales_en(sales_en),
        .switch_in(switch_in),
        .btn_confirm(btn_confirm),
        .btn_prev(btn_prev),
        .btn_next(btn_next),
        .btn_pay(btn_pay),
        .btn_cancel(btn_cancel),
        .price0(price0),
        .price1(price1),
        .price2(price2),
        .price3(price3),
        .stock0(stock0),
        .stock1(stock1),
        .stock2(stock2),
        .stock3(stock3),
        .enabled_mask(enabled_mask),
        .drink_id(drink_id),
        .sale_we(sale_we),
        .sale_idx(sale_idx),
        .sale_amount(sale_amount),
        .refund_pulse(refund_pulse),
        .refund_amount(refund_amount),
        .exit_to_main(exit_to_main),
        .paid_amount(paid_amount),
        .current_price(current_price),
        .current_stock(current_stock),
        .led_out(led_out),
        .view_data(view_data),
        .state_code(state_code),
        .error_code(error_code),
        .countdown_sec(countdown_sec)
    );

    // 100 MHz clock in simulation: 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Mock register_file update.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Demo-friendly prices within 0~10:
            // 0=COLA price 4, 1=SODA price 5, 2=TEA price 3, 3=H2O price 2
            price0 <= 8'd4; stock0 <= 4'd5;
            price1 <= 8'd5; stock1 <= 4'd6;
            price2 <= 8'd3; stock2 <= 4'd8;
            price3 <= 8'd2; stock3 <= 4'd9;
        end else if (sale_we) begin
            case (sale_idx)
                2'd0: stock0 <= stock0 - 1'b1;
                2'd1: stock1 <= stock1 - 1'b1;
                2'd2: stock2 <= stock2 - 1'b1;
                2'd3: stock3 <= stock3 - 1'b1;
                default: ;
            endcase
        end
    end

    task press_confirm; begin @(posedge clk); btn_confirm = 1; @(posedge clk); btn_confirm = 0; end endtask
    task press_prev;    begin @(posedge clk); btn_prev    = 1; @(posedge clk); btn_prev    = 0; end endtask
    task press_next;    begin @(posedge clk); btn_next    = 1; @(posedge clk); btn_next    = 0; end endtask
    task press_pay;     begin @(posedge clk); btn_pay     = 1; @(posedge clk); btn_pay     = 0; end endtask
    task press_cancel;  begin @(posedge clk); btn_cancel  = 1; @(posedge clk); btn_cancel  = 0; end endtask

    task add_money;
        input [7:0] amount;
        begin
            switch_in = amount;
            press_pay;
            repeat (1) @(posedge clk);
        end
    endtask

    task wait_state;
        input [3:0] target_state;
        integer k;
        begin
            for (k = 0; k < 20 && state_code != target_state; k = k + 1)
                @(posedge clk);
        end
    endtask

    task back_to_select;
        begin
            if (state_code == S_ERROR || state_code == S_COMPLETE || state_code == S_REFUND)
                press_confirm;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0;
        sales_en = 0;
        switch_in = 8'd0;
        btn_confirm = 0;
        btn_prev = 0;
        btn_next = 0;
        btn_pay = 0;
        btn_cancel = 0;
        enabled_mask = 4'b1111;
        fail_count = 0;

        #30;
        rst_n = 1;
        #20;
        sales_en = 1;
        repeat (5) @(posedge clk);

        $display("=== Test 1: page navigation ===");
        if (state_code != S_SELECT || drink_id != 2'd0) begin
            $display("FAIL: should start at SELECT page of item 0.");
            fail_count = fail_count + 1;
        end
        press_next; repeat (2) @(posedge clk);
        press_next; repeat (2) @(posedge clk);
        press_prev; repeat (2) @(posedge clk);
        if (drink_id != 2'd1) begin
            $display("FAIL: next/prev navigation should land on item 1.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: page navigation works.");
        end

        // Return to item 0 for normal purchase.
        press_prev; repeat (2) @(posedge clk);

        $display("=== Test 2: normal purchase ===");
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd1);
        add_money(8'd3);
        press_confirm;
        wait_state(S_WAIT_TAKE);
        if (state_code != S_WAIT_TAKE) begin
            $display("FAIL: enough payment should enter WAIT_TAKE.");
            fail_count = fail_count + 1;
        end
        press_confirm; // S0 means take item in WAIT_TAKE
        repeat (3) @(posedge clk);
        if (state_code != S_COMPLETE || sale_idx != 2'd0 || sale_amount != 8'd4) begin
            $display("FAIL: pickup should complete sale for item 0 amount 4.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: normal purchase completed.");
        end
        back_to_select;

        $display("=== Test 3: insufficient payment ===");
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd1);
        press_confirm;
        repeat (3) @(posedge clk);
        if (state_code != S_PAY || error_code != ERR_NOT_ENOUGH) begin
            $display("FAIL: insufficient payment should stay in PAY with ERR_NOT_ENOUGH.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: insufficient payment detected.");
        end
        press_cancel;
        wait_state(S_REFUND);
        back_to_select;

        $display("=== Test 4: inactivity timeout in PAY ===");
        press_next; repeat (2) @(posedge clk); // item 1, price 5
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd2);
        repeat (50) @(posedge clk);
        if (state_code != S_REFUND || error_code != ERR_TIMEOUT) begin
            $display("FAIL: inactivity in PAY should refund and show timeout.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: inactivity timeout refund works.");
        end
        back_to_select;

        $display("=== Test 5: pickup timeout refund ===");
        press_next; repeat (2) @(posedge clk); // item 2, price 3
        press_next; repeat (2) @(posedge clk); // item 3, price 2
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd2);
        press_confirm;
        wait_state(S_WAIT_TAKE);
        repeat (70) @(posedge clk);
        if (state_code != S_REFUND || error_code != ERR_TIMEOUT) begin
            $display("FAIL: no pickup within timeout should refund.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: pickup timeout refund works.");
        end
        back_to_select;

        $display("=== Test 6: off-sale item ===");
        // previous test leaves us on item 3, so two NEXT pulses wrap to item 1
        press_next; repeat (2) @(posedge clk); // item 0
        press_next; repeat (2) @(posedge clk); // item 1
        enabled_mask = 4'b1101; // item 1 disabled
        press_confirm;
        wait_state(S_ERROR);
        if (state_code != S_ERROR || error_code != ERR_OFF_SALE) begin
            $display("FAIL: disabled item should enter ERROR with ERR_OFF_SALE.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: off-sale item detected.");
        end
        enabled_mask = 4'b1111;
        back_to_select;

        $display("=== Test 7: no stock ===");
        // select item 2 and set stock to 0
        press_next; repeat (2) @(posedge clk); // item 2
        stock2 = 4'd0;
        press_confirm;
        wait_state(S_ERROR);
        if (state_code != S_ERROR || error_code != ERR_NO_STOCK) begin
            $display("FAIL: no-stock item should enter ERROR with ERR_NO_STOCK.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: no-stock item detected.");
        end

        if (fail_count == 0)
            $display("=== ALL IMPROVED SALES_MODE TESTS PASSED ===");
        else
            $display("=== TEST FINISHED WITH %0d FAILURE(S) ===", fail_count);

        #50;
        $stop;
    end

endmodule
