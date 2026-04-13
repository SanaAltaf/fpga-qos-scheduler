// =============================================================================
// FILE: ai_executor.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person C
// =============================================================================
//
// ═══════════════════════════════════════════════════════════════════════════
// HOW THE "AI" PART WORKS — READ THIS BEFORE IMPLEMENTING
// ═══════════════════════════════════════════════════════════════════════════
//
// THE BIG PICTURE
// ───────────────
// The FPGA is NOT running a neural network. Instead, it acts as a
// REAL-TIME SUPERVISOR that sits between:
//
//   [Sensors / Host PC]  ←UART→  [FPGA Supervisor]  ←GPIO/PWM→  [Car Actuators]
//
// The "AI workload" is whatever perception code runs on the HOST (laptop/RPi):
//   - Lane detection, obstacle detection, path planning, etc.
//   - These produce results that are sent as AI_TASK frames to the FPGA.
//
// The FPGA's job is to guarantee that even if the AI is slow or crashes,
// the car's SAFETY RESPONSE (brake / stop) always fires within a bounded time.
//
// ───────────────────────────────────────────────────────────────────────────
// WHAT THIS MODULE SIMULATES (MVP)
// ───────────────────────────────────────────────────────────────────────────
// ai_executor is a CONTROLLABLE BUSY-WAIT stub. It:
//   1. Receives work_cycles from the scheduler (how long an AI task takes).
//   2. Counts down that many clock cycles (simulates heavy AI computation).
//   3. Can be ABORTED immediately when a SAFETY task arrives.
//
// This lets us PROVE the scheduling guarantee:
//   "No matter how many AI cycles are queued, a safety task starts
//    within N clock cycles of arrival" — measured by metrics.v.
//
// ───────────────────────────────────────────────────────────────────────────
// IF YOU ATTACH A REAL CAR
// ───────────────────────────────────────────────────────────────────────────
// The AI_TASK frame (TYPE=0x03) carries work_cycles[15:0] from the host.
// For a real car demo, the host sends:
//
//   [Sensor data arrives at RPi]
//      ↓
//   [RPi runs perception (OpenCV / TensorFlow Lite)]
//      ↓  (takes 50–300 ms)
//   [RPi sends AI_TASK frame to FPGA via UART]
//      ↓
//   [FPGA enqueues AI_TASK, runs ai_executor for work_cycles]
//      ↓
//   [FPGA also receives SAFETY_SENSOR_UPDATE from ultrasonic sensor]
//      ↓
//   [Scheduler preempts AI_TASK → runs safety_engine → drives brake output]
//
// The FPGA's outputs.v drives a PWM pin that connects to the car's ESC
// (Electronic Speed Controller) or a servo for steering. On emergency:
//   - PWM duty = 0  →  motor stop
//   - A GPIO pin goes HIGH  →  physical brake relay closes
//
// ───────────────────────────────────────────────────────────────────────────
// FUTURE EXTENSION: TinyML on FPGA (Won't Have for MVP)
// ───────────────────────────────────────────────────────────────────────────
// If you want actual ML inference on the FPGA (not the host), you would:
//   1. Replace this stub with a neural network accelerator (e.g., a simple
//      MLP for distance regression from raw sensor readings).
//   2. Feed it raw ADC samples via a dedicated SPI peripheral.
//   3. The scheduler would dispatch AI_TASK → the ML core, which signals
//      done_o when inference completes.
//   Tools: hls4ml (C++ to FPGA), Xilinx DPU, or hand-written systolic array.
//   This is a full semester project by itself — hence "Won't Have for MVP".
//
// ───────────────────────────────────────────────────────────────────────────
// DEMO SCRIPT SCENARIOS (from python_sender.py)
// ───────────────────────────────────────────────────────────────────────────
//   Scenario A — AI FLOOD:
//     Host sends 100 AI_TASK frames with work_cycles=50000 (500 µs each)
//     simultaneously sends SAFETY frames every 100 ms.
//     METRIC: safety latency stays < 2 ms despite AI flood.
//
//   Scenario B — WATCHDOG:
//     Host stops sending AI_HEARTBEAT frames.
//     After 200 ms: FPGA enters FAILSAFE, LED lights, AI tasks dropped.
//     METRIC: failsafe response time ≤ 201 ms.
//
//   Scenario C — SPEED THRESHOLD:
//     Host sends distance=60cm, speed=0,100,200,500 cm/s.
//     METRIC: emergency toggles at the correct threshold for each speed.
//
// ═══════════════════════════════════════════════════════════════════════════
//
// MODULE INTERFACE
// ─────────────────
// PARAMETERS TO IMPLEMENT:
//   (None — work_cycles provided per-task at runtime)
//
// VERIFICATION CHECKLIST:
//   [ ] work_cycles=10: busy_o HIGH for 10 cycles, done_o pulses on cycle 11.
//   [ ] work_cycles=0: done_o same cycle or next (document choice).
//   [ ] abort_i mid-task: busy_o deasserts, done_o + aborted_o pulse same cycle.
//   [ ] After abort, new start_i works correctly.
//   [ ] busy_o does not glitch.
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module ai_executor (
    input  wire        clk_i,
    input  wire        rst_ni,

    input  wire        start_i,
    input  wire [15:0] work_cycles_i,
    input  wire        abort_i,

    output reg         busy_o,
    output reg         done_o,
    output reg         aborted_o
);

    reg [15:0] cnt;
    reg        running;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            cnt       <= 16'd0;
            running   <= 1'b0;
            busy_o    <= 1'b0;
            done_o    <= 1'b0;
            aborted_o <= 1'b0;
        end else begin
            done_o    <= 1'b0;
            aborted_o <= 1'b0;

            // PREEMPTION: abort overrides everything
            if (abort_i && running) begin
                running   <= 1'b0;
                busy_o    <= 1'b0;
                done_o    <= 1'b1;
                aborted_o <= 1'b1;

            // NEW TASK: accept start only when idle
            end else if (start_i && !running) begin
                if (work_cycles_i == 16'd0) begin
                    // Zero-cycle task: complete immediately
                    done_o  <= 1'b1;
                    busy_o  <= 1'b0;
                end else begin
                    cnt     <= work_cycles_i - 16'd1;
                    running <= 1'b1;
                    busy_o  <= 1'b1;
                end

            // COUNTING: decrement until zero
            end else if (running) begin
                if (cnt == 16'd0) begin
                    running <= 1'b0;
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                end else begin
                    cnt <= cnt - 16'd1;
                end
            end
        end
    end

endmodule
