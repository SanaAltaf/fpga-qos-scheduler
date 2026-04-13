# FPGA QoS Scheduler and Safety Watchdog

**SPEC-001** | Nexys A7 (Artix-7) | **Verilog** | 100 MHz

A real-time supervisor for an autonomous vehicle edge-AI stack.
The FPGA enforces strict-priority scheduling (safety > AI), detects stale
AI updates via a hardware watchdog, and exports latency metrics over UART.

> **Read [`docs/AI_ARCHITECTURE.md`](docs/AI_ARCHITECTURE.md) first** to
> understand how the AI part works and how to attach a real car.

---

## Team Assignments

| Person | Modules |
|--------|---------|
| **A** | `uart_rx.v`, `uart_tx.v`, `frame_parser.v` |
| **B** | `task_fifo.v`, `scheduler.v` |
| **C** | `safety_engine.v`, `ai_executor.v`, `outputs.v` |
| **D** | `watchdog.v`, `metrics.v`, `ms_tick.v`, `host_tools/` |

---

## Repository Structure

```
fpga-qos-scheduler/
├── rtl/
│   ├── qos_defines.v        # Shared `defines (FREEZE after Day 2)
│   ├── top.v                # Top-level structural wiring
│   ├── uart_rx.v            # [A] UART receiver
│   ├── uart_tx.v            # [A] UART transmitter
│   ├── frame_parser.v       # [A] Binary frame parser FSM
│   ├── task_fifo.v          # [B] Slot-based task queue (depth 4)
│   ├── scheduler.v          # [B] Strict-priority QoS arbiter
│   ├── safety_engine.v      # [C] Distance+speed emergency decision
│   ├── ai_executor.v        # [C] AI workload stub (busy-wait + abort)
│   ├── outputs.v            # [C] LEDs, PWM, brake relay output
│   ├── watchdog.v           # [D] AI heartbeat watchdog
│   ├── metrics.v            # [D] Latency counters + UART telemetry
│   └── ms_tick.v            # [D] 1 ms tick from 100 MHz clock
├── sim/                     # Testbenches (Verilog)
├── constraints/
│   └── nexys_a7.xdc
├── host_tools/
│   └── python_sender.py
└── docs/
    ├── AI_ARCHITECTURE.md   # ← Read this for AI + car integration
    └── SPEC-001.md          # Interface contracts and milestones
```

---

## How to Build (Vivado)

```tcl
# In Vivado TCL console:
create_project qos_scheduler ./vivado -part xc7a100tcsg324-1
add_files [glob rtl/*.v]
set_property top top [current_fileset]
add_files -fileset constrs_1 constraints/nexys_a7.xdc
launch_runs synth_1 -jobs 4
launch_runs impl_1 -to_step write_bitstream -jobs 4
```

## Host Script

```bash
pip install pyserial matplotlib
python host_tools/python_sender.py --port /dev/ttyUSB1 --demo all
```

---

## Protocol (UART 115200 baud, 8N1)

`[0xA5][TYPE][LEN][PAYLOAD...][0x00]`

| Type | Command | Payload |
|------|---------|---------|
| `0x01` | SAFETY_SENSOR_UPDATE | `dist[15:0]` + `speed[15:0]` |
| `0x02` | AI_HEARTBEAT | `seq[7:0]` |
| `0x03` | AI_TASK | `work_cycles[15:0]` |
| `0x10` | READ_METRICS | (none) |
| `0x11` | SET_PARAM | `param_id[7:0]` + `value[31:0]` |

---

## Contributing

1. `git checkout -b feature/your-module`
2. Implement your module, include `qos_defines.v` at top
3. Write a testbench in `sim/tb_<module>.v`
4. Open PR — 1 reviewer minimum, `top.v` and `qos_defines.v` need all 4
