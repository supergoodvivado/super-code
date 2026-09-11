`timescale 1ns / 1ps

module tb_selection_full;
    reg clk = 0;
    reg reset = 1;
    reg [3:0] sw = 0;
    reg product = 0;
    reg confirm = 0;
    reg cancel = 0;
    wire [3:0] led;
    wire [7:0] seg, sel;
    wire buzzer;
    integer i, scan;
    reg [7:0] saved_seg [0:7];

    vending_machine_top #(
        .FULL_BLINK_TICKS(4),
        .PAYMENT_ERROR_BLINK_TICKS(4)
    ) dut (
        .clk(clk), .sw(sw), .key_n(4'hF), .led(led),
        .seg(seg), .sel(sel), .buzzer(buzzer)
    );
    always #5 clk = ~clk;

    task press_product;
        begin
            @(negedge clk); product = 1;
            @(negedge clk); product = 0;
        end
    endtask

    task press_confirm;
        begin
            @(negedge clk); confirm = 1;
            @(negedge clk); confirm = 0;
        end
    endtask

    task check_order;
        begin
            if (dut.state !== 3 || dut.selected_count !== 2 ||
                dut.current_product_code !== 4'hD ||
                dut.current_quantity !== 2 || dut.total_due !== 26)
                $fatal(1, "Full order was modified");
            // Compare all eight rendered digits, independent of scan timing.
            for (scan = 0; scan < 8; scan = scan + 1) begin
                force dut.display.scan_index = scan;
                #0.01;
                if (seg !== saved_seg[scan])
                    $fatal(1, "Display digit %0d changed", scan);
            end
            release dut.display.scan_index;
        end
    endtask

    initial begin
        // Inject debounced events; exercise the real core, LED logic and display.
        force dut.reset = reset;
        force dut.product_pulse = product;
        force dut.confirm_pulse = confirm;
        force dut.cancel_pulse = cancel;
        force dut.change_pulse = 0;
        repeat (3) @(negedge clk);
        reset = 0;
        sw = 2;
        press_product(); press_product(); press_product(); // A13 x3.
        sw = 4'hD;
        press_product(); press_product();
        sw = 1;
        press_product(); // A42 x2, total 26.
        for (scan = 0; scan < 8; scan = scan + 1) begin
            force dut.display.scan_index = scan;
            #0.01; saved_seg[scan] = seg;
        end
        release dut.display.scan_index;
        if (led !== 4'b0001) $fatal(1, "Expected green order LED on");
        sw = 4'hA;
        press_product();
        @(negedge clk); // Registered rejection reaches LED controller.
        for (i = 0; i < 16; i = i + 1) begin
            if (led !== ((i / 4) % 2 ? 4'b0000 : 4'b0001))
                $fatal(1, "Selection limit did not flash green at cycle %0d", i);
            if (dut.error_beep_enable !== led[0])
                $fatal(1, "Buzzer enable is not synchronized with green LED");
            check_order();
            @(negedge clk);
        end
        if (led !== 1 || dut.full_blink_phases !== 0)
            $fatal(1, "Green order LED did not return after alert");
        // A later press can trigger another sequence; payment still works.
        press_product();
        @(negedge clk);
        if (led !== 1) $fatal(1, "Repeat rejection did not flash green");
        press_confirm();
        @(negedge clk);
        if (dut.state !== 4 || led !== 3 || dut.full_blink_phases !== 0)
            $fatal(1, "Payment did not clear blink feedback");

        // Reach the 255-yuan ceiling, then verify that the rejected extra
        // coin produces the identical green/two-beep alert.
        sw = 4'b0011;
        for (i = 0; i < 5; i = i + 1) press_confirm();
        for (i = 0; i < 5; i = i + 1) press_product();
        if (dut.paid_amount !== 8'd255)
            $fatal(1, "Could not reach the 255-yuan payment limit");
        press_product();
        @(negedge clk);
        for (i = 0; i < 20; i = i + 1) begin
            if (dut.payment_error_blink_phases != 0 &&
                led !== (dut.payment_error_blink_phases[0] ? 4'b0010 : 4'b0011))
                $fatal(1, "Payment limit green flash has an incorrect phase");
            // Once the alert finishes, the order LED returns to steady green
            // while the alert buzzer correctly stays off.  Compare them only
            // during the four active alert phases.
            if (dut.payment_error_blink_phases != 0 &&
                dut.error_beep_enable !== led[0])
                $fatal(1, "Payment-limit beep is not synchronized with green LED");
            @(negedge clk);
        end
        if (dut.payment_error_blink_phases !== 0)
            $fatal(1, "Payment limit alert did not finish after two flashes");
        $display("PASS: selection limit preserves display and flashes green twice with synchronized beeps.");
        $finish;
    end
endmodule
