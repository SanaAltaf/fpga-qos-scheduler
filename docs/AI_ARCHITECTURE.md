# AI Architecture — How the "AI" Part Actually Works

## The Core Concept

The FPGA is **not running a neural network**. It is a **real-time supervisor** that sits between your perception software and your car actuators.

```
┌─────────────────────────────────────────────────────────────────┐
│                    FULL SYSTEM DIAGRAM                           │
├──────────────────┬──────────────────┬───────────────────────────┤
│   SENSORS        │   HOST (RPi/PC)  │   FPGA SUPERVISOR         │
│                  │                  │                           │
│ Ultrasonic ──────┤→ distance_cm     │                           │
│ HC-SR04          │                  │ ┌─────────────────────┐   │
│                  │                  │ │   frame_parser      │   │
│ IMU/Encoder ─────┤→ speed_cm_s      │ │   task_fifo         │   │
│                  │                  │ │   scheduler         │←──┤← UART
│                  │ OpenCV /         │ │   safety_engine     │   │
│ Camera ──────────┤→ TF-Lite    ─────┤→│   ai_executor(stub) │   │
│                  │ (lane det.)      │ │   watchdog          │   │
│                  │                  │ │   metrics           │   │
│                  │                  │ └────────┬────────────┘   │
│                  │                  │          │                 │
│              RPi UART TX ────────────→ FPGA RX │                │
│              RPi UART RX ←──────────── FPGA TX │                │
│                  │                  │          ↓                 │
│                  │                  │   PWM ───→ ESC             │
│                  │                  │   Brake ─→ Relay           │
│                  │                  │   LEDs ──→ Indicators      │
└──────────────────┴──────────────────┴───────────────────────────┘
```

---

## What Each "AI" Frame Actually Represents

### TYPE_SAFETY (0x01) — SAFETY_SENSOR_UPDATE
Sent by the RPi after reading the ultrasonic sensor and wheel encoder.

```python
# On RPi (Python):
distance_cm = read_ultrasonic_hcsr04()   # GPIO trigger/echo
speed_cm_s  = read_wheel_encoder()       # pulse counting
uart.write(frame_safety(distance_cm, speed_cm_s))
```

The FPGA safety engine then computes:
```
emergency = (distance_cm <= STOP_DIST + speed/10)
```
And fires the brake output **within 2 clock cycles** — deterministic always.

### TYPE_AI_TASK (0x03) — AI Computation Workload
Sent by the RPi **after** completing a perception inference run.
`work_cycles` represents how long the FPGA should model the AI task as "occupying" the scheduler.

```python
# On RPi (Python):
t0 = time.time()
result = run_lane_detection(frame)        # Could take 50-300 ms
t1 = time.time()
# Report how long it took as "work cycles" to FPGA
work_cycles = int((t1 - t0) * 100_000_000)  # convert to FPGA cycles
uart.write(frame_ai_task(min(work_cycles, 0xFFFF)))
```

### TYPE_AI_HB (0x02) — AI Heartbeat
Proves the RPi (perception stack) is still alive. If it crashes or hangs,
the FPGA watchdog fires and the car enters failsafe mode.

```python
# On RPi: send every 100 ms from a background thread
while True:
    uart.write(frame_heartbeat(seq))
    seq = (seq + 1) & 0xFF
    time.sleep(0.1)
```

---

## What the Scheduler Proves

The whole point of the project is to demonstrate this guarantee:

> **"Even when flooded with 500 µs AI tasks back-to-back, a SAFETY_SENSOR_UPDATE frame always starts execution within ≤ 2 ms of arrival."**

This is measured by:
```
safety_latency = t_safety_start - t_enq_ms   (both in ms)
```
The host laptop's `python_sender.py` plots this latency under load.

---

## Real Car Integration Steps

If you attach a real RC car:

### Hardware connections
```
Nexys A7 Pmod JA pin 1 (pwm_o)   → ESC signal wire (white)
Nexys A7 Pmod JA pin 2 (brake_o) → NPN transistor base → relay NC contact
Nexys A7 USB UART                 → RPi USB port (or GPIO UART)
RPi GPIO 14 (TX)                  → Logic level converter → FPGA RX pin
HC-SR04 TRIG                      → RPi GPIO 23
HC-SR04 ECHO                      → RPi GPIO 24 (through voltage divider)
```

### RPi software
```python
# Real car sender (runs on RPi)
import RPi.GPIO as GPIO
import time, serial, struct

TRIG, ECHO = 23, 24
uart = serial.Serial('/dev/serial0', 115200)

def measure_distance():
    GPIO.output(TRIG, True)
    time.sleep(0.00001)
    GPIO.output(TRIG, False)
    while GPIO.input(ECHO) == 0: start = time.time()
    while GPIO.input(ECHO) == 1: end = time.time()
    return (end - start) * 17150  # distance in cm

def send_safety(dist_cm, speed_cm_s):
    payload = struct.pack('>HH', int(dist_cm), int(speed_cm_s))
    uart.write(bytes([0xA5, 0x01, 4]) + payload + bytes([0x00]))

seq = 0
while True:
    dist = measure_distance()
    send_safety(dist, 0)          # speed=0 for MVP (add encoder later)
    send_heartbeat(seq)
    seq = (seq + 1) & 0xFF
    time.sleep(0.05)              # 20 Hz sensor loop
```

### FPGA side
No changes needed to RTL. The FPGA already:
- Receives SAFETY frames and computes emergency within 2 clock cycles
- Asserts `brake_o` HIGH on emergency
- The relay cuts motor power immediately

---

## Why Not Run ML on the FPGA?

For this project scope, running ML on the FPGA would require:
- A camera input interface (MIPI CSI or HDMI capture — complex)
- A neural network accelerator (systolic array, BRAM weights — full project)
- Training a model small enough to fit in 4.9 MB (100T BRAM capacity)
- Quantization to INT8 (hls4ml or FINN toolchain)

The scheduler demonstration is the real contribution: **proving timing guarantees under AI load**. The actual AI code lives on the host where it belongs for now.

---

## Grading / Demo Talking Points

When presenting, say:

1. **"The FPGA is the real-time safety layer between a perception AI and a physical vehicle."**

2. **"Even if the AI stack hangs for 200 ms, the watchdog detects this and enters failsafe mode — the car would stop or slow down autonomously."**

3. **"We can prove the worst-case safety response time: [X] ms under [Y] concurrent AI tasks — shown by the metrics telemetry and the Python plot."**

4. **"If we attached a real car, the brake_o pin would drive a relay cutting motor power within 2 clock cycles of detecting an obstacle closer than the stopping distance at current speed."**
