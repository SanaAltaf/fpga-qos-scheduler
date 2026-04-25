`timescale 1ns/1ps
`include "qos_defines.v"

module tb_ai_exec;

    reg  clk=0, rstn=0, start=0, abort=0;
    reg  [15:0] work=0;
    wire busy, done, aborted;

    always #5 clk = ~clk;   // 100 MHz

    ai_executor dut (
        .clk_i        (clk),
        .rst_ni       (rstn),
        .start_i      (start),
        .work_cycles_i(work),
        .abort_i      (abort),
        .busy_o       (busy),
        .done_o       (done),
        .aborted_o    (aborted)
    );

    // ----------------------------------------------------------------
    // Helper: watch for done_o to pulse within max_cycles
    // Sets saw_done=1 if caught, 0 if timeout
    // Also captures aborted_o in saw_aborted at the same moment
    // ----------------------------------------------------------------
    reg saw_done, saw_aborted;

    task wait_for_done;
        input integer max_cycles;
        integer i;
        begin
            saw_done    = 0;
            saw_aborted = 0;
            for (i = 0; i < max_cycles; i = i + 1) begin
                @(posedge clk);
                if (done) begin
                    saw_done    = 1;
                    saw_aborted = aborted;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("tb_ai.vcd");
        $dumpvars(0, tb_ai_exec);

        // Reset
        repeat(5) @(posedge clk);
        rstn = 1;
        repeat(2) @(posedge clk);

        // ------------------------------------------------
        // TEST 1: Normal completion - work_cycles = 10
        // done_o pulses on cycle 11 after start
        // ------------------------------------------------
        work  = 16'd10;
        start = 1; @(posedge clk); #1;
        start = 0;

        // Check busy is HIGH shortly after start
        repeat(2) @(posedge clk);
        if (busy)
            $display("PASS: busy asserted during countdown");
        else
            $display("FAIL: busy should be HIGH during countdown");

        // Now watch for done pulse (give 20 cycles to be safe)
        wait_for_done(20);
        if (saw_done && !busy)
            $display("PASS: done pulsed after 10 cycles, busy cleared");
        else
            $display("FAIL: done never pulsed within 20 cycles (saw_done=%b busy=%b)", saw_done, busy);

        repeat(2) @(posedge clk);

        // ------------------------------------------------
        // TEST 2: Zero-cycle task completes immediately
        // ------------------------------------------------
        work  = 16'd0;
        start = 1; @(posedge clk); #1;
        start = 0;

        // done should pulse within 2 cycles
        wait_for_done(3);
        if (saw_done && !busy)
            $display("PASS: zero-cycle task completes immediately");
        else
            $display("FAIL: zero-cycle task - saw_done=%b busy=%b", saw_done, busy);

        repeat(2) @(posedge clk);

        // ------------------------------------------------
        // TEST 3: Busy stays HIGH during long task
        // ------------------------------------------------
        work  = 16'd1000;
        start = 1; @(posedge clk); #1;
        start = 0;

        repeat(20) @(posedge clk);
        if (busy)
            $display("PASS: still busy mid-task before abort");
        else
            $display("FAIL: should be busy before abort");

        // ------------------------------------------------
 // ------------------------------------------------
        // TEST 4: Abort mid-task
        // ------------------------------------------------
        // abort_i is sampled on the rising edge - done+aborted
        // pulse on THAT SAME edge, so we must read them before
        // the clock advances again
        @(posedge clk); #1;
        abort = 1;
        // Now capture signals BEFORE next clock edge
        saw_done    = done;
        saw_aborted = aborted;
        @(posedge clk); #1;
        abort = 0;
        // Also check the cycle after in case of 1-cycle delay
        if (done) begin saw_done = 1; saw_aborted = aborted; end
        @(posedge clk);
        if (done) begin saw_done = 1; saw_aborted = aborted; end

        if (saw_done && saw_aborted && !busy)
            $display("PASS: abort mid-task - busy cleared, done+aborted pulsed");
        else
            $display("FAIL: abort - saw_done=%b saw_aborted=%b busy=%b", saw_done, saw_aborted, busy);
        // ------------------------------------------------
        // TEST 5: New task works correctly after abort
        // ------------------------------------------------
        work  = 16'd5;
        start = 1; @(posedge clk); #1;
        start = 0;

        wait_for_done(15);
        if (saw_done && !saw_aborted && !busy)
            $display("PASS: new task after abort completes normally");
        else
            $display("FAIL: post-abort task - saw_done=%b saw_aborted=%b busy=%b", saw_done, saw_aborted, busy);

        repeat(2) @(posedge clk);
        $display("ai_executor test done");
        $finish;
    end

endmodule
