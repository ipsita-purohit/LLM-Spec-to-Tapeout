# Spec-to-RTL Agent (Phase 2)

## Overview

This project implements an AI-assisted Spec-to-RTL automation flow. 
Given a hardware specification in YAML format, the system generates synthesizable Verilog RTL using a Codex-based agent and verifies correctness using simulation. 
The workflow follows an iterative loop:
Spec → RTL generation → Simulation → Debug → Fix → PASS

## Features 

- Accepts any YAML specification file as input
- Generates synthesizable Verilog RTL
- Automatically runs simulation using Icarus Verilog
- Supports multiple testcases (p1, p5, p7, p8, p9)
- Works for unseen/hidden testcases

## Project Structure
```text
spec2gds/
│
├── eda_flow_agent.py        # Main script (single entry point)
├── generator.py             # RTL generation logic
├── parser.py                # YAML parsing
├── run_sim.py               # Simulation execution
├── main.py                  # Supporting script
├── README.md
│
├── Problems/                # Input specifications
│   ├── p1.yaml
│   ├── p5.yaml
│   ├── p7.yaml
│   ├── p8.yaml
│   └── p9.yaml
│
├── Testbenches/             # Verification testbenches
│   ├── iclad_seq_detector_tb.v
│   ├── iclad_dot_product_tb.v
│   ├── iclad_exp_tb.v
│   ├── iclad_fp16_mult_tb.v
│   └── iclad_fir_tb.v
│
├── outputs/                 # Generated RTL outputs
│   ├── p1_solution.v
│   ├── p5_solution.v
│   ├── p7_solution.v
│   ├── p8_solution.v
│   ├── p9_solution.v
│   │
│    └── logs/                # Execution logs
│       ├── p1_log.txt
│       ├── p5_log.txt
│       ├── p7_log.txt
│       ├── p8_log.txt
│       └── p9_log.txt

```

## 1. Setup Instructions (Dependencies, Environment)

### Requirements
- Python 3.x
- Icarus Verilog (for simulation)
- Codex CLI (used for RTL generation)

### Install Icarus Verilog (Mac)
```bash
brew install icarus-verilog

### Verify installation
iverilog -v
vvp -V

### Install Codex CLI
```markdown
If Codex is not installed:
```bash
npm install -g @openai/codex

### Verify Codex installation
```bash
codex --help
```

## 2. Exact Commands to Run the system 

### General Command
python3 eda_flow_agent.py <spec_yaml_path> <testbench_path>

### Example Runs
- python3 eda_flow_agent.py Problems/p1.yaml Testbenches/iclad_seq_detector_tb.v
- python3 eda_flow_agent.py Problems/p5.yaml Testbenches/iclad_dot_product_tb.v
- python3 eda_flow_agent.py Problems/p7.yaml Testbenches/iclad_exp_tb.v
- python3 eda_flow_agent.py Problems/p8.yaml Testbenches/iclad_fp16_mult_tb.v
- python3 eda_flow_agent.py Problems/p9.yaml Testbenches/iclad_fir_tb.v

## 3. Input/Output Description 

### Input
	•	YAML specification file (.yaml) from Problems/
	•	Verilog testbench file (.v) from Testbenches/

### Output
	•	Generated RTL file stored in outputs/
	•	Simulation output printed in terminal
	•	PASS/FAIL status based on verification

## 4. Expected results (For Verification)

### For provided testcases:
	•	p1 → PASS
	•	p5 → PASS
	•	p7 → PASS
	•	p8 → PASS
	•	p9 → PASS
### The terminal should display: PASS

## 5. Brief Workflow Description 

### The system follows an automated Spec-to-RTL flow:
	1.	Parse YAML specification
	2.	Extract design details (module name, ports, functionality)
	3.	Generate Verilog RTL using agent
	4.	Save RTL in outputs/
	5.	Compile using iverilog
	6.	Run simulation using vvp
	7.	Compare output with expected results
	8.	Iterate/debug if needed until PASS

## 6. How to Run the Hidden Testcases 
 
### To Run any new/unseen testcase :
python3 eda_flow_agent.py <new_spec.yaml> <new_testbench.v>

### Example:
python3 eda_flow_agent.py Problems/new_problem.yaml Testbenches/new_tb.v

### No code modification is required
 
