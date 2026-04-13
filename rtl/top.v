// =============================================================================
// FILE: top.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: All (shared — PR requires all 4 approvals)
// =============================================================================
//
// PURPOSE:
//   Top-level structural module. Instantiates all sub-modules and wires them
//   together. Contains zero logic — purely connections.
//
// REAL CAR WIRING (beyond FPGA):
//   uart_rx_i  ← RPi UART TX (GPIO 14) via 3.3V logic-level wire
//   uart_tx_o  → RPi UART RX (GPIO 15)
//   pwm_o      → ESC signal wire (servo PWM, 50 Hz, 1–2 ms pulse)
//   brake_o    → NPN transistor base → relay coil → motor power cut
//   led_o[0]   → Red LED on car chassis (emergency indicator)
//   Ultrasonic sensor (HC-SR04) → RPi → distance packed into SAFETY frame
//
// BOARD: Nexys A7-100T  |  DEVICE: XC7A100TCSG324-1  |  CLOCK: 100 MHz E3
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module top (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,
    output wire [7:0]  led_o,
    output wire        pwm_o,
    output wire        brake_o
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // ms_tick
    wire        ms_tick;
    wire [31:0] ms_count;

    // uart_rx → frame_parser
    wire [7:0]  rx_byte;
    wire        rx_valid;

    // metrics → uart_tx
    wire [7:0]  tx_byte;
    wire        tx_valid;
    wire        tx_ready;

    // frame_parser → task_fifo
    wire        enq_valid;
    wire        enq_ready;
    wire [`TASK_W-1:0] enq_task;

    // frame_parser → watchdog
    wire        ai_heartbeat;

    // frame_parser → metrics
    wire        rd_metrics_req;
    wire        set_param_valid;
    wire [7:0]  set_param_id;
    wire [31:0] set_param_val;

    // frame_parser debug
    wire        frame_err;

    // task_fifo → scheduler
    wire [`FIFO_DEPTH-1:0] peek_valid;
    wire [`TASK_W-1:0]     peek_task0, peek_task1, peek_task2, peek_task3;
    wire [2:0]  fifo_count;
    wire        fifo_full;
    wire        fifo_empty;

    // scheduler → task_fifo
    wire        deq_req;
    wire [`FIFO_ADDR_W-1:0] deq_idx;

    // watchdog → scheduler + metrics
    wire        failsafe;
    wire        wdg_event;
    wire [15:0] wdg_event_count;
    wire [31:0] ms_since_last_ai;

    // scheduler → safety_engine
    wire        safety_start;
    wire [15:0] safety_dist;
    wire [15:0] safety_speed;

    // safety_engine → scheduler + outputs
    wire        safety_done;
    wire        emergency_stop;

    // scheduler → ai_executor
    wire        ai_start;
    wire [15:0] ai_work_cycles;
    wire        ai_abort;

    // ai_executor → scheduler
    wire        ai_busy;
    wire        ai_done;
    wire        ai_aborted;

    // scheduler → metrics
    wire        ev_safety_start;
    wire        ev_safety_done;
    wire        ev_ai_start;
    wire        ev_ai_done;
    wire [31:0] ev_task_enq_ms;
    wire [1:0]  sched_state;

    // outputs → metrics
    wire        emergency_event;

    // metrics → safety_engine + watchdog (runtime config)
    wire [15:0] cfg_stop_dist;
    wire [31:0] cfg_wdg_timeout;
    wire [31:0] cfg_telem_period;

    // =========================================================================
    // Module instantiations
    // =========================================================================

    ms_tick u_ms_tick (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .ms_tick_o  (ms_tick),
        .ms_count_o (ms_count)
    );

    uart_rx u_uart_rx (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .rx_i       (uart_rx_i),
        .rx_byte_o  (rx_byte),
        .rx_valid_o (rx_valid)
    );

    uart_tx u_uart_tx (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .tx_byte_i  (tx_byte),
        .tx_valid_i (tx_valid),
        .tx_o       (uart_tx_o),
        .tx_ready_o (tx_ready)
    );

    frame_parser u_frame_parser (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .rx_byte_i        (rx_byte),
        .rx_valid_i       (rx_valid),
        .enq_ready_i      (enq_ready),
        .enq_valid_o      (enq_valid),
        .enq_task_o       (enq_task),
        .ms_count_i       (ms_count),
        .ai_heartbeat_o   (ai_heartbeat),
        .rd_metrics_req_o (rd_metrics_req),
        .set_param_valid_o(set_param_valid),
        .set_param_id_o   (set_param_id),
        .set_param_val_o  (set_param_val),
        .frame_err_o      (frame_err)
    );

    task_fifo u_task_fifo (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .enq_valid_i  (enq_valid),
        .enq_task_i   (enq_task),
        .enq_ready_o  (enq_ready),
        .deq_req_i    (deq_req),
        .deq_idx_i    (deq_idx),
        .peek_valid_o (peek_valid),
        .peek_task0_o (peek_task0),
        .peek_task1_o (peek_task1),
        .peek_task2_o (peek_task2),
        .peek_task3_o (peek_task3),
        .count_o      (fifo_count),
        .full_o       (fifo_full),
        .empty_o      (fifo_empty)
    );

    watchdog u_watchdog (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .ms_tick_i         (ms_tick),
        .ms_count_i        (ms_count),
        .ai_heartbeat_i    (ai_heartbeat),
        .wdg_timeout_cfg_i (cfg_wdg_timeout),
        .failsafe_o        (failsafe),
        .wdg_event_o       (wdg_event),
        .wdg_event_count_o (wdg_event_count),
        .ms_since_last_ai_o(ms_since_last_ai)
    );

    scheduler u_scheduler (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .peek_valid_i     (peek_valid),
        .peek_task0_i     (peek_task0),
        .peek_task1_i     (peek_task1),
        .peek_task2_i     (peek_task2),
        .peek_task3_i     (peek_task3),
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
        .ai_work_cycles_o (ai_work_cycles),
        .ai_abort_o       (ai_abort),
        .ev_safety_start_o(ev_safety_start),
        .ev_safety_done_o (ev_safety_done),
        .ev_ai_start_o    (ev_ai_start),
        .ev_ai_done_o     (ev_ai_done),
        .ev_task_enq_ms_o (ev_task_enq_ms),
        .sched_state_o    (sched_state)
    );

    safety_engine u_safety_engine (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .start_i         (safety_start),
        .distance_cm_i   (safety_dist),
        .speed_cm_s_i    (safety_speed),
        .stop_dist_cfg_i (cfg_stop_dist),
        .done_o          (safety_done),
        .emergency_o     (emergency_stop)
    );

    ai_executor u_ai_executor (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .start_i       (ai_start),
        .work_cycles_i (ai_work_cycles),
        .abort_i       (ai_abort),
        .busy_o        (ai_busy),
        .done_o        (ai_done),
        .aborted_o     (ai_aborted)
    );

    outputs u_outputs (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .emergency_i     (emergency_stop),
        .failsafe_i      (failsafe),
        .sched_state_i   (sched_state),
        .fifo_count_i    (fifo_count),
        .pwm_duty_i      (8'hC0),          // 75% default; make SET_PARAM in Week 4
        .led_o           (led_o),
        .pwm_o           (pwm_o),
        .brake_o         (brake_o),
        .emergency_event_o(emergency_event)
    );

    metrics u_metrics (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .ms_tick_i         (ms_tick),
        .ms_count_i        (ms_count),
        .ev_safety_start_i (ev_safety_start),
        .ev_safety_done_i  (ev_safety_done),
        .ev_ai_start_i     (ev_ai_start),
        .ev_ai_done_i      (ev_ai_done),
        .ev_task_enq_ms_i  (ev_task_enq_ms),
        .wdg_event_i       (wdg_event),
        .wdg_event_count_i (wdg_event_count),
        .emergency_event_i (emergency_event),
        .fifo_count_i      (fifo_count),
        .rd_metrics_req_i  (rd_metrics_req),
        .set_param_valid_i (set_param_valid),
        .set_param_id_i    (set_param_id),
        .set_param_val_i   (set_param_val),
        .tx_ready_i        (tx_ready),
        .tx_byte_o         (tx_byte),
        .tx_valid_o        (tx_valid),
        .cfg_stop_dist_o   (cfg_stop_dist),
        .cfg_wdg_timeout_o (cfg_wdg_timeout),
        .cfg_telem_period_o(cfg_telem_period)
    );

endmodule
