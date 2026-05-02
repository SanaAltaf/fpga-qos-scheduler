// =============================================================================
// FILE: scheduler.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Abinaya
// =============================================================================


`timescale 1ns/1ps
`include "qos_defines.v"

module scheduler (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Task FIFO peek interface (all 4 slots visible simultaneously)
    input  wire [`FIFO_DEPTH-1:0]  peek_valid_i,
    input  wire [`TASK_W-1:0]      peek_task0_i,
    input  wire [`TASK_W-1:0]      peek_task1_i,
    input  wire [`TASK_W-1:0]      peek_task2_i,
    input  wire [`TASK_W-1:0]      peek_task3_i,

    // Watchdog failsafe
    input  wire        failsafe_i,

    // Engine completion signals
    input  wire        safety_done_i,
    input  wire        ai_done_i,
    input  wire        ai_busy_i,

    // Current time (ms)
    input  wire [31:0] ms_count_i,

    // FIFO dequeue
    output reg         deq_req_o,
    output reg  [`FIFO_ADDR_W-1:0] deq_idx_o,

    // Safety engine dispatch
    output reg         safety_start_o,
    output reg  [15:0] safety_dist_o,
    output reg  [15:0] safety_speed_o,

    // AI executor dispatch
    output reg         ai_start_o,
    output reg  [15:0] ai_work_cycles_o,
    output reg         ai_abort_o,

    // Metrics events
    output reg         ev_safety_start_o,
    output reg         ev_safety_done_o,
    output reg         ev_ai_start_o,
    output reg         ev_ai_done_o,
    output reg  [31:0] ev_task_enq_ms_o,

    // Debug state
    output reg  [1:0]  sched_state_o
);

    // -------------------------------------------------------------------------
    // Priority scan (combinational)
    // Find the lowest-indexed slot that holds a SAFETY task, then AI task.
    // -------------------------------------------------------------------------
    wire [`TASK_W-1:0] slots [0:3];
    assign slots[0] = peek_task0_i;
    assign slots[1] = peek_task1_i;
    assign slots[2] = peek_task2_i;
    assign slots[3] = peek_task3_i;

    reg [`FIFO_ADDR_W-1:0] safety_idx, ai_idx;
    reg                     safety_found, ai_found;

    always @(*) begin
        safety_idx   = 2'd0; safety_found = 1'b0;
        ai_idx       = 2'd0; ai_found     = 1'b0;
        if (peek_valid_i[0] && slots[0][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_SAFETY
            && !safety_found) begin safety_idx = 2'd0; safety_found = 1'b1; end
        if (peek_valid_i[1] && slots[1][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_SAFETY
            && !safety_found) begin safety_idx = 2'd1; safety_found = 1'b1; end
        if (peek_valid_i[2] && slots[2][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_SAFETY
            && !safety_found) begin safety_idx = 2'd2; safety_found = 1'b1; end
        if (peek_valid_i[3] && slots[3][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_SAFETY
            && !safety_found) begin safety_idx = 2'd3; safety_found = 1'b1; end

        if (peek_valid_i[0] && slots[0][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_AI_TASK
            && !ai_found) begin ai_idx = 2'd0; ai_found = 1'b1; end
        if (peek_valid_i[1] && slots[1][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_AI_TASK
            && !ai_found) begin ai_idx = 2'd1; ai_found = 1'b1; end
        if (peek_valid_i[2] && slots[2][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_AI_TASK
            && !ai_found) begin ai_idx = 2'd2; ai_found = 1'b1; end
        if (peek_valid_i[3] && slots[3][`TASK_TYPE_HI:`TASK_TYPE_LO] == `TYPE_AI_TASK
            && !ai_found) begin ai_idx = 2'd3; ai_found = 1'b1; end
    end

    // Convenience: selected slot task descriptor
    reg [`TASK_W-1:0] sel_task;
    always @(*) begin
        case (safety_found ? safety_idx : ai_idx)
            2'd0: sel_task = slots[0];
            2'd1: sel_task = slots[1];
            2'd2: sel_task = slots[2];
            2'd3: sel_task = slots[3];
        endcase
    end

    // -------------------------------------------------------------------------
    // Scheduler FSM
    // -------------------------------------------------------------------------
    reg [1:0] state;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            state           <= `SCHED_IDLE;
            sched_state_o   <= `SCHED_IDLE;
            deq_req_o       <= 1'b0;
            deq_idx_o       <= 2'd0;
            safety_start_o  <= 1'b0;
            safety_dist_o   <= 16'd0;
            safety_speed_o  <= 16'd0;
            ai_start_o      <= 1'b0;
            ai_work_cycles_o <= 16'd0;
            ai_abort_o      <= 1'b0;
            ev_safety_start_o <= 1'b0;
            ev_safety_done_o  <= 1'b0;
            ev_ai_start_o     <= 1'b0;
            ev_ai_done_o      <= 1'b0;
            ev_task_enq_ms_o  <= 32'd0;
        end else begin
            // Deassert strobes
            deq_req_o         <= 1'b0;
            safety_start_o    <= 1'b0;
            ai_start_o        <= 1'b0;
            ai_abort_o        <= 1'b0;
            ev_safety_start_o <= 1'b0;
            ev_safety_done_o  <= 1'b0;
            ev_ai_start_o     <= 1'b0;
            ev_ai_done_o      <= 1'b0;

            case (state)
                // --------------------------------------------------------------
                `SCHED_IDLE: begin
                    if (failsafe_i) begin
                        // FAILSAFE mode: only safety tasks
                        if (safety_found) begin
                            deq_req_o         <= 1'b1;
                            deq_idx_o         <= safety_idx;
                            safety_start_o    <= 1'b1;
                            safety_dist_o     <= sel_task[`TASK_P0_HI:`TASK_P0_HI-15];
                            safety_speed_o    <= sel_task[`TASK_P0_HI-16:`TASK_P0_LO];
                            ev_safety_start_o <= 1'b1;
                            ev_task_enq_ms_o  <= sel_task[`TASK_ENQ_HI:`TASK_ENQ_LO];
                            state             <= `SCHED_SAFETY;
                            sched_state_o     <= `SCHED_SAFETY;
                        end else begin
                            state         <= `SCHED_FAILSAFE;
                            sched_state_o <= `SCHED_FAILSAFE;
                        end
                    end else if (safety_found) begin
                        // Normal: dispatch safety first
                        deq_req_o         <= 1'b1;
                        deq_idx_o         <= safety_idx;
                        safety_start_o    <= 1'b1;
                        safety_dist_o     <= sel_task[`TASK_P0_HI:`TASK_P0_HI-15];
                        safety_speed_o    <= sel_task[`TASK_P0_HI-16:`TASK_P0_LO];
                        ev_safety_start_o <= 1'b1;
                        ev_task_enq_ms_o  <= sel_task[`TASK_ENQ_HI:`TASK_ENQ_LO];
                        state             <= `SCHED_SAFETY;
                        sched_state_o     <= `SCHED_SAFETY;
                    end else if (ai_found) begin
                        // Dispatch AI task
                        deq_req_o         <= 1'b1;
                        deq_idx_o         <= ai_idx;
                        ai_start_o        <= 1'b1;
                        ai_work_cycles_o  <= sel_task[`TASK_P0_LO+15:`TASK_P0_LO];
                        ev_ai_start_o     <= 1'b1;
                        ev_task_enq_ms_o  <= sel_task[`TASK_ENQ_HI:`TASK_ENQ_LO];
                        state             <= `SCHED_AI;
                        sched_state_o     <= `SCHED_AI;
                    end
                    // else: stay IDLE
                end

                // --------------------------------------------------------------
                `SCHED_SAFETY: begin
                    if (safety_done_i) begin
                        ev_safety_done_o <= 1'b1;
                        state            <= `SCHED_IDLE;
                        sched_state_o    <= `SCHED_IDLE;
                    end
                end

                // --------------------------------------------------------------
                `SCHED_AI: begin
                    // PREEMPTION: safety task arrived while AI running
                    if (safety_found && ai_busy_i) begin
                        ai_abort_o    <= 1'b1;
                        // Safety will be dispatched next cycle after abort ack
                    end
                    if (ai_done_i) begin
                        ev_ai_done_o  <= 1'b1;
                        // If safety is waiting, dispatch it immediately
                        if (safety_found) begin
                            deq_req_o         <= 1'b1;
                            deq_idx_o         <= safety_idx;
                            safety_start_o    <= 1'b1;
                            safety_dist_o     <= slots[safety_idx][`TASK_P0_HI:`TASK_P0_HI-15];
                            safety_speed_o    <= slots[safety_idx][`TASK_P0_HI-16:`TASK_P0_LO];
                            ev_safety_start_o <= 1'b1;
                            ev_task_enq_ms_o  <= slots[safety_idx][`TASK_ENQ_HI:`TASK_ENQ_LO];
                            state             <= `SCHED_SAFETY;
                            sched_state_o     <= `SCHED_SAFETY;
                        end else begin
                            state         <= `SCHED_IDLE;
                            sched_state_o <= `SCHED_IDLE;
                        end
                    end
                end

                // --------------------------------------------------------------
                `SCHED_FAILSAFE: begin
                    // Stay in failsafe waiting for safety tasks
                    if (safety_found) begin
                        deq_req_o         <= 1'b1;
                        deq_idx_o         <= safety_idx;
                        safety_start_o    <= 1'b1;
                        safety_dist_o     <= sel_task[`TASK_P0_HI:`TASK_P0_HI-15];
                        safety_speed_o    <= sel_task[`TASK_P0_HI-16:`TASK_P0_LO];
                        ev_safety_start_o <= 1'b1;
                        ev_task_enq_ms_o  <= sel_task[`TASK_ENQ_HI:`TASK_ENQ_LO];
                        state             <= `SCHED_SAFETY;
                        sched_state_o     <= `SCHED_SAFETY;
                    end
                    if (!failsafe_i) begin
                        state         <= `SCHED_IDLE;
                        sched_state_o <= `SCHED_IDLE;
                    end
                end

                default: state <= `SCHED_IDLE;
            endcase
        end
    end

endmodule
