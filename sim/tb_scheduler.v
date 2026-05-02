`timescale 1ns/1ps
`include "qos_defines.v"

module tb_scheduler;

    reg clk=0, rstn=0, failsafe=0;
    reg safety_done=0, ai_done=0, ai_busy=0;
    reg [31:0] ms_count=0;

    // FIFO peek inputs
    reg [`FIFO_DEPTH-1:0]  peek_valid=0;
    reg [`TASK_W-1:0]      pt0=0, pt1=0, pt2=0, pt3=0;

    // Scheduler outputs
    wire        deq_req;
    wire [1:0]  deq_idx;
    wire        safety_start, ai_start, ai_abort;
    wire [15:0] safety_dist, safety_speed, ai_work;
    wire        ev_ss, ev_sd, ev_as, ev_ad;
    wire [31:0] ev_enq;
    wire [1:0]  state;

    always #5 clk = ~clk;   // 100 MHz
    always @(posedge clk) ms_count <= ms_count + 1;

    scheduler dut (
        .clk_i            (clk),
        .rst_ni           (rstn),
        .peek_valid_i     (peek_valid),
        .peek_task0_i     (pt0),
        .peek_task1_i     (pt1),
        .peek_task2_i     (pt2),
        .peek_task3_i     (pt3),
        .failsafe_i       (failsafe),
        .safety_done_i    (safety_done),
        .ai_done_i        (ai_done),
        .ai_busy_i        (ai_busy),
        .ms_count_i       (ms_count),
        .deq_req_o        (deq_req),
        .deq_idx_o        (deq_idx),
        .safety_start_o   (safety_start),
        .safety_dist_o    (safety_dist),
        .safety_speed_o   (safety_speed),
        .ai_start_o       (ai_start),
        .ai_work_cycles_o (ai_work),
        .ai_abort_o       (ai_abort),
        .ev_safety_start_o(ev_ss),
        .ev_safety_done_o (ev_sd),
        .ev_ai_start_o    (ev_as),
        .ev_ai_done_o     (ev_ad),
        .ev_task_enq_ms_o (ev_enq),
        .sched_state_o    (state)
    );

    // ----------------------------------------------------------------
    // Helper: wait for a signal to pulse HIGH within 20 cycles
    // Returns 1=seen, 0=timeout
    // ----------------------------------------------------------------
    reg saw_safety_start;
    reg saw_ai_start;

    task wait_for_safety_start;
        integer i;
        begin
            saw_safety_start = 0;
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                if (safety_start) saw_safety_start = 1;
            end
        end
    endtask

    task wait_for_ai_start;
        integer i;
        begin
            saw_ai_start = 0;
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                if (ai_start) saw_ai_start = 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Task descriptors
    // Layout: [103:96]=type  [95:64]=t_enq_ms  [63:32]=payload0  [31:0]=payload1
    // SAFETY payload0: [63:48]=dist_cm  [47:32]=speed_cm_s
    // AI     payload0: [47:32]=work_cycles  (upper 16 bits unused)
    // ----------------------------------------------------------------

    initial begin
        $dumpfile("tb_sched.vcd");
        $dumpvars(0, tb_scheduler);

        // Reset
        repeat(5) @(posedge clk);
        rstn = 1;
        repeat(2) @(posedge clk);

        // ============================================================
        // TEST 1: SAFETY dispatched before AI when both are pending
        // ============================================================
        // Slot 0 = AI task (type=0x03), slot 1 = SAFETY (type=0x01, dist=30)
        pt0 = {`TYPE_AI_TASK, 32'd10, 32'd5000, 32'd0};
        pt1 = {`TYPE_SAFETY,  32'd10, {16'd30, 16'd0}, 32'd0};
        peek_valid = 4'b0011;   // slots 0 and 1 valid

        wait_for_safety_start;

        if (saw_safety_start)
            $display("PASS: SAFETY dispatched before AI");
        else
            $display("FAIL: safety_start never pulsed (expected SAFETY first)");

        // Check AI was NOT started during that window
        if (!ai_start)
            $display("PASS: AI not started while safety pending");
        else
            $display("FAIL: ai_start should be LOW while safety pending");

        // ============================================================
        // TEST 2: AI dispatched after safety completes
        // ============================================================
        // Pulse safety_done to finish the safety task
        @(posedge clk); #1;
        safety_done = 1;
        @(posedge clk); #1;
        safety_done = 0;

        // Only the AI task remains
        peek_valid = 4'b0001;   // slot 0 = AI task only

        wait_for_ai_start;

        if (saw_ai_start)
            $display("PASS: AI dispatched after safety done");
        else
            $display("FAIL: ai_start never pulsed after safety done");

        // ============================================================
        // TEST 3: failsafe blocks AI tasks
        // ============================================================
        // Finish the AI task, then enable failsafe
        @(posedge clk); #1;
        ai_done  = 1;
        ai_busy  = 0;
        @(posedge clk); #1;
        ai_done  = 0;

        // Wait for scheduler to return to IDLE
        repeat(3) @(posedge clk);

        // Now set failsafe=1 with an AI task waiting
        failsafe   = 1;
        peek_valid = 4'b0001;   // AI task in slot 0

        saw_ai_start = 0;
        repeat(10) @(posedge clk);
        // ai_start must never have pulsed
        if (!saw_ai_start)
            $display("PASS: AI blocked in failsafe mode");
        else
            $display("FAIL: AI should be blocked when failsafe=1");

        failsafe   = 0;
        peek_valid = 0;

        // ============================================================
        // TEST 4 (BONUS): Preemption - ai_abort fires when SAFETY
        //                 arrives while AI is running
        // ============================================================
        repeat(2) @(posedge clk);

        // Start an AI task
        pt0 = {`TYPE_AI_TASK, 32'd20, 32'd5000, 32'd0};
        peek_valid = 4'b0001;
        ai_busy    = 0;

        // Wait for scheduler to dispatch it
        wait_for_ai_start;
        // Simulate executor going busy
        ai_busy = 1;
        peek_valid = 0;   // AI dequeued

        repeat(3) @(posedge clk);

        // Now a SAFETY task arrives mid-AI-execution
        pt1 = {`TYPE_SAFETY, 32'd25, {16'd15, 16'd100}, 32'd0};
        peek_valid = 4'b0010;   // slot 1 = SAFETY

        // Check ai_abort fires within 5 cycles
        begin : preempt_check
            integer j;
            reg saw_abort;
            saw_abort = 0;
            for (j = 0; j < 5; j = j + 1) begin
                @(posedge clk);
                if (ai_abort) saw_abort = 1;
            end
            if (saw_abort)
                $display("PASS: ai_abort fired on SAFETY arrival during AI");
            else
                $display("FAIL: ai_abort did not fire (preemption broken)");
        end

        // Clean up
        ai_busy   = 0;
        ai_done   = 1;
        @(posedge clk); #1;
        ai_done   = 0;
        peek_valid = 0;

        repeat(3) @(posedge clk);
        $display("scheduler test done");
        $finish;
    end

endmodule

