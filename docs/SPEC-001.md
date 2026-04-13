# SPEC-001 Architecture Reference
*FPGA QoS Scheduler and Safety Watchdog — Nexys A7*

---

## Interface Contracts at a Glance

### pkg.sv → Everyone
All modules `import qos_pkg::*;`. Never re-declare constants locally.

```
task_desc_t fields:
  [7:0]  task_type   — TYPE_SAFETY / TYPE_AI_TASK / TYPE_AI_HB
  [31:0] t_enq_ms    — ms timestamp at enqueue
  [31:0] payload0    — SAFETY: {distance_cm[15:0], speed_cm_s[15:0]}
                        AI_TASK: {16'h0, work_cycles[15:0]}
  [31:0] payload1    — reserved / 0
```

---

### Person A → Person B (frame_parser → task_fifo)

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `enq_valid` | A → B | 1 | Assert to push |
| `enq_task` | A → B | task_desc_t | Task to enqueue |
| `enq_ready` | B → A | 1 | FIFO not full |

**Also from frame_parser (to be added by Person A):**

| Signal | Direction | Destination |
|--------|-----------|-------------|
| `ai_heartbeat` | A → D | watchdog |
| `rd_metrics_req` | A → D | metrics |
| `set_param_valid` | A → D | metrics |
| `set_param_id[7:0]` | A → D | metrics |
| `set_param_val[31:0]` | A → D | metrics |

---

### Person B → Person B (task_fifo → scheduler, same owner)

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `peek_valid[FIFO_DEPTH-1:0]` | FIFO→SCHED | 4 | Which slots hold tasks |
| `peek_tasks[FIFO_DEPTH]` | FIFO→SCHED | task_desc_t[] | All slot contents |
| `deq_req` | SCHED→FIFO | 1 | Pop request |
| `deq_idx[FIFO_ADDR_W-1:0]` | SCHED→FIFO | 2 | Which slot to pop |
| `count[FIFO_ADDR_W:0]` | FIFO→SCHED | 3 | Occupancy |

---

### Person B → Person C (scheduler → engines)

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `safety_start` | SCHED→SAFETY | 1 | 1-cycle pulse: begin computation |
| `safety_dist[15:0]` | SCHED→SAFETY | 16 | distance_cm for this task |
| `safety_speed[15:0]` | SCHED→SAFETY | 16 | speed_cm_s for this task |
| `safety_done` | SAFETY→SCHED | 1 | 1-cycle pulse: result ready |
| `emergency_stop` | SAFETY→all | 1 | Latched emergency flag |
| `ai_start` | SCHED→AI | 1 | 1-cycle pulse: begin work |
| `ai_work_cycles[15:0]` | SCHED→AI | 16 | Busy-wait duration |
| `ai_abort` | SCHED→AI | 1 | Preempt AI immediately |
| `ai_busy` | AI→SCHED | 1 | AI executor running |
| `ai_done` | AI→SCHED | 1 | 1-cycle pulse: finished/aborted |

---

### Person B → Person D (scheduler → metrics)

| Signal | Direction | Description |
|--------|-----------|-------------|
| `ev_safety_start` | SCHED→MET | Latency start event |
| `ev_safety_done` | SCHED→MET | Latency end event |
| `ev_ai_start` | SCHED→MET | AI start event |
| `ev_ai_done` | SCHED→MET | AI done event |
| `ev_task_enq_ms[31:0]` | SCHED→MET | t_enq_ms of dispatched task |
| `sched_state` | SCHED→MET | Current state (debug) |

---

### Person D → Everyone (ms_tick → all)

| Signal | Consumers | Description |
|--------|-----------|-------------|
| `ms_tick` | watchdog, metrics | 1-cycle pulse every 1 ms |
| `ms_count[31:0]` | frame_parser, scheduler, metrics | Free-running ms counter |

---

### Person D → Person C (metrics cfg → safety_engine)

| Signal | Width | Description |
|--------|-------|-------------|
| `cfg_stop_dist[15:0]` | 16 | Runtime STOP_DIST_CM |

### Person D → Person D (metrics cfg → watchdog)

| Signal | Width | Description |
|--------|-------|-------------|
| `cfg_wdg_timeout[31:0]` | 32 | Runtime AI_WDG_TIMEOUT_MS |

---

## Safety Decision Formula

```
react_add_cm = speed_cm_s / 10           (REACT_TIME_MS = 100 ms)
threshold    = STOP_DIST_CM + react_add_cm
emergency    = (distance_cm <= threshold)

Implementation (Option A — multiply approximation, no divider):
  react_add ≈ (speed_cm_s * 205) >> 11   (error < 0.1%)
```

---

## Simulation Guide

Run testbenches individually first, then tb_top for integration.

```bash
# Vivado XSim (run from project root)
xvlog -sv rtl/pkg.sv rtl/ms_tick.sv sim/tb_ms_tick.sv
xelab tb_ms_tick -s tb_ms_tick_sim
xsim tb_ms_tick_sim -runall

# All unit tests (bash loop)
for tb in tb_ms_tick tb_uart_rx tb_uart_tx tb_frame_parser \
          tb_task_fifo tb_scheduler tb_safety_engine tb_watchdog; do
  echo "=== Running $tb ==="
  xvlog -sv rtl/pkg.sv rtl/*.sv sim/${tb}.sv
  xelab $tb -s ${tb}_sim
  xsim ${tb}_sim -runall
done

# System test
xvlog -sv rtl/pkg.sv rtl/*.sv sim/*.sv
xelab tb_top -s tb_top_sim
xsim tb_top_sim -t "run 50ms; quit"
```

---

## Milestone Checklist

### Day 1–2: Interface Freeze
- [ ] All team members review `pkg.sv` — no objections
- [ ] `task_desc_t` payload packing agreed
- [ ] frame_parser extra output ports finalized (Person A + all)
- [ ] Latency definition agreed: **enqueue → safety_start** (not done)

### Week 1: Core Bring-Up
- [ ] `uart_rx` loopback test passing (Person A)
- [ ] `uart_tx` byte TX verified (Person A)
- [ ] `frame_parser` unit test passing (Person A)
- [ ] `task_fifo` unit test passing (Person B)
- [ ] `ms_tick` unit test passing (Person D)
- [ ] UART visible on Nexys A7 via PuTTY

### Week 2: Scheduling Demo
- [ ] `scheduler` unit test passing (Person B)
- [ ] `safety_engine` unit test passing (Person C)
- [ ] `ai_executor` implemented and tested (Person C)
- [ ] `outputs` LEDs visible on board
- [ ] tb_top Tests 1–4 passing in simulation

### Week 3: Watchdog + Failsafe
- [ ] `watchdog` unit test passing (Person D)
- [ ] tb_top Test 5 (watchdog) passing in simulation
- [ ] failsafe LED visible on board

### Week 4: Metrics + Demo
- [ ] `metrics` telemetry TX working (Person D)
- [ ] `python_sender.py` all three demos running
- [ ] tb_top all tests passing
- [ ] Bitstream on board, full demo recorded
- [ ] Report: worst-case safety latency under AI flood documented
