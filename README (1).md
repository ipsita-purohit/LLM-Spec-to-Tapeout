# Spec-to-RTL Agent (Phase 2)

## Overview

This project implements an AI-assisted **Spec-to-RTL automation flow**.\
Given a hardware specification in YAML format, the system generates
synthesizable Verilog RTL using a Codex-based agent and verifies
correctness using simulation.

### Workflow

Spec → RTL Generation → Simulation → Debug → Fix → PASS

------------------------------------------------------------------------

## Features

-   Accepts any YAML specification file as input\
-   Generates synthesizable Verilog RTL\
-   Automatically runs simulation using Icarus Verilog\
-   Supports multiple testcases (p1, p5, p7, p8, p9)\
-   Works for unseen/hidden testcases

------------------------------------------------------------------------

## Project Structure

``` text
spec2gds/
│
├── eda_flow_agent.py
├── generator.py
├── parser.py
├── run_sim.py
├── main.py
├── README.md
│
├── Problems/
│   ├── p1.yaml
│   ├── p5.yaml
│   ├── p7.yaml
│   ├── p8.yaml
│   └── p9.yaml
│
├── Testbenches/
│   ├── iclad_seq_detector_tb.v
│   ├── iclad_dot_product_tb.v
│   ├── iclad_exp_tb.v
│   ├── iclad_fp16_mult_tb.v
│   └── iclad_fir_tb.v
│
├── outputs/
│   ├── p1_solution.v
│   ├── p5_solution.v
│   ├── p7_solution.v
│   ├── p8_solution.v
│   ├── p9_solution.v
│   │
│   └── logs/
│       ├── p1_log.txt
│       ├── p5_log.txt
│       ├── p7_log.txt
│       ├── p8_log.txt
│       └── p9_log.txt
```

------------------------------------------------------------------------

## 1. Setup Instructions

### Requirements

-   Python 3.x\
-   Icarus Verilog\
-   Codex CLI

### Install Icarus Verilog (Mac)

``` bash
brew install icarus-verilog
```

### Verify Installation

``` bash
iverilog -v
vvp -V
```

### Install Codex CLI

``` bash
npm install -g @openai/codex
```

### Verify Codex Installation

``` bash
codex --help
```

------------------------------------------------------------------------

## 2. How to Run

``` bash
python3 eda_flow_agent.py <spec_yaml_path> <testbench_path>
```

### Example

``` bash
python3 eda_flow_agent.py Problems/p1.yaml Testbenches/iclad_seq_detector_tb.v
```

------------------------------------------------------------------------

## 3. Input / Output

### Input

-   YAML file
-   Verilog testbench

### Output

-   RTL in outputs/
-   Simulation logs
-   PASS / FAIL

------------------------------------------------------------------------

## 4. Expected Results

All provided testcases should return:

PASS

------------------------------------------------------------------------

## 5. Workflow

1.  Parse YAML\
2.  Generate RTL\
3.  Simulate\
4.  Debug until PASS

------------------------------------------------------------------------

## 6. New Testcases

``` bash
python3 eda_flow_agent.py <new_spec.yaml> <new_testbench.v>
```
