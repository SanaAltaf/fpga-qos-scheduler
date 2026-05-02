// =============================================================================
// FILE: task_fifo.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Abinaya
// =============================================================================
=============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module task_fifo (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Enqueue port (from frame_parser)
    input  wire        enq_valid_i,
    input  wire [`TASK_W-1:0] enq_task_i,
    output wire        enq_ready_o,

    // Dequeue port (from scheduler — picks slot index)
    input  wire        deq_req_i,
    input  wire [`FIFO_ADDR_W-1:0] deq_idx_i,

    // Peek: scheduler reads all slots simultaneously (combinational)
    output wire [`FIFO_DEPTH-1:0] peek_valid_o,
    output wire [`TASK_W-1:0]     peek_task0_o,
    output wire [`TASK_W-1:0]     peek_task1_o,
    output wire [`TASK_W-1:0]     peek_task2_o,
    output wire [`TASK_W-1:0]     peek_task3_o,

    // Occupancy
    output wire [`FIFO_ADDR_W:0]  count_o,
    output wire                    full_o,
    output wire                    empty_o
);

    // Slot storage
    reg [`TASK_W-1:0] mem [0:`FIFO_DEPTH-1];
    reg [`FIFO_DEPTH-1:0] valid;

    // -------------------------------------------------------------------------
    // Combinational: find lowest free slot for enqueue
    // -------------------------------------------------------------------------
    reg [`FIFO_ADDR_W-1:0] enq_slot;
    reg                     enq_slot_found;

    always @(*) begin
        enq_slot       = 2'd0;
        enq_slot_found = 1'b0;
        if (!valid[0]) begin enq_slot = 2'd0; enq_slot_found = 1'b1; end
        else if (!valid[1]) begin enq_slot = 2'd1; enq_slot_found = 1'b1; end
        else if (!valid[2]) begin enq_slot = 2'd2; enq_slot_found = 1'b1; end
        else if (!valid[3]) begin enq_slot = 2'd3; enq_slot_found = 1'b1; end
    end

    // -------------------------------------------------------------------------
    // Combinational: popcount for count_o
    // -------------------------------------------------------------------------
    assign count_o = valid[0] + valid[1] + valid[2] + valid[3];
    assign full_o  = (count_o == `FIFO_DEPTH);
    assign empty_o = (count_o == 3'd0);
    assign enq_ready_o = !full_o;

    // -------------------------------------------------------------------------
    // Sequential: enqueue and dequeue
    // -------------------------------------------------------------------------
    integer i;
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            valid <= 4'b0;
            for (i = 0; i < `FIFO_DEPTH; i = i + 1)
                mem[i] <= {`TASK_W{1'b0}};
        end else begin
            // Dequeue: clear the nominated slot
            if (deq_req_i)
                valid[deq_idx_i] <= 1'b0;

            // Enqueue: write to lowest free slot (if not full)
            if (enq_valid_i && enq_slot_found) begin
                mem[enq_slot]   <= enq_task_i;
                valid[enq_slot] <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Peek outputs (combinational, always driven)
    // -------------------------------------------------------------------------
    assign peek_valid_o = valid;
    assign peek_task0_o = mem[0];
    assign peek_task1_o = mem[1];
    assign peek_task2_o = mem[2];
    assign peek_task3_o = mem[3];

endmodule
