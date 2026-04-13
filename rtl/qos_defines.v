// =============================================================================
// FILE: qos_defines.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// =============================================================================
//
// PURPOSE:
//   Global `define constants shared by every module. Include this file at the
//   top of every .v file with:  `include "qos_defines.v"
//
// *** FREEZE POLICY ***
//   After Day 2, no changes without approval from all four team members.
//
// OWNER: All (shared)
// =============================================================================

`ifndef QOS_DEFINES_V
`define QOS_DEFINES_V

// ---------------------------------------------------------------------------
// Clock and timing
// ---------------------------------------------------------------------------
`define CLK_HZ            100_000_000
`define UART_BAUD         115_200
`define TICK_HZ           1_000

`define CYCLES_PER_BIT    868          // CLK_HZ / UART_BAUD  (integer)
`define CYCLES_PER_TICK   100_000      // CLK_HZ / TICK_HZ

// ---------------------------------------------------------------------------
// FIFO geometry
// ---------------------------------------------------------------------------
`define FIFO_DEPTH        4
`define FIFO_ADDR_W       2            // log2(FIFO_DEPTH)

// ---------------------------------------------------------------------------
// Data widths
// ---------------------------------------------------------------------------
`define DIST_W            16
`define SPEED_W           16
`define PAYLOAD_W         32

// ---------------------------------------------------------------------------
// task_desc_t field widths and bit positions
// A task descriptor is a 104-bit flat vector:
//   [103:96]  task_type  [7:0]
//   [95:64]   t_enq_ms   [31:0]
//   [63:32]   payload0   [31:0]
//   [31:0]    payload1   [31:0]
// ---------------------------------------------------------------------------
`define TASK_W            104
`define TASK_TYPE_HI      103
`define TASK_TYPE_LO      96
`define TASK_ENQ_HI       95
`define TASK_ENQ_LO       64
`define TASK_P0_HI        63
`define TASK_P0_LO        32
`define TASK_P1_HI        31
`define TASK_P1_LO        0

// Helper macros to pack/unpack a task descriptor vector
`define TASK_TYPE(t)      t[`TASK_TYPE_HI:`TASK_TYPE_LO]
`define TASK_ENQ_MS(t)    t[`TASK_ENQ_HI:`TASK_ENQ_LO]
`define TASK_P0(t)        t[`TASK_P0_HI:`TASK_P0_LO]
`define TASK_P1(t)        t[`TASK_P1_HI:`TASK_P1_LO]

// payload0 sub-fields for SAFETY tasks
`define TASK_DIST(t)      t[`TASK_P0_HI:`TASK_P0_HI-15]   // [63:48]
`define TASK_SPEED(t)     t[`TASK_P0_HI-16:`TASK_P0_LO]   // [47:32]

// payload0 sub-field for AI_TASK
`define TASK_WORKCYC(t)   t[`TASK_P0_LO+15:`TASK_P0_LO]   // [47:32]

// ---------------------------------------------------------------------------
// Default runtime parameters
// ---------------------------------------------------------------------------
`define STOP_DIST_CM_DEFAULT    16'd50
`define REACT_TIME_MS_DEFAULT   32'd100
`define AI_WDG_TIMEOUT_MS_DEF  32'd200
`define TELEM_PERIOD_MS_DEF    32'd500

// ---------------------------------------------------------------------------
// UART frame protocol
// ---------------------------------------------------------------------------
`define FRAME_SOF         8'hA5

// Task type IDs
`define TYPE_SAFETY       8'h01
`define TYPE_AI_HB        8'h02
`define TYPE_AI_TASK      8'h03
`define TYPE_RD_MET       8'h10
`define TYPE_SET_PAR      8'h11

// SET_PARAM IDs
`define PARAM_STOP_DIST   8'h00
`define PARAM_REACT_TIME  8'h01
`define PARAM_WDG_TIMEOUT 8'h02
`define PARAM_TELEM_PERIOD 8'h03

// ---------------------------------------------------------------------------
// Scheduler state encoding (2-bit)
// ---------------------------------------------------------------------------
`define SCHED_IDLE        2'b00
`define SCHED_SAFETY      2'b01
`define SCHED_AI          2'b10
`define SCHED_FAILSAFE    2'b11

// ---------------------------------------------------------------------------
// AI executor command types (sent via AI_TASK payload)
// Upper byte of work_cycles used as sub-command for future extensibility
// ---------------------------------------------------------------------------
`define AI_CMD_BUSY_WAIT  8'h00   // Simple busy-wait (MVP)
`define AI_CMD_SENSOR_SIM 8'h01   // Simulate sensor fusion latency

`endif // QOS_DEFINES_V
