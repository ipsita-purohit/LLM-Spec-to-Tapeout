# Spec-to-Tapeout Agent

## End-to-End Automated VLSI Flow (Spec → RTL → GDSII)

This project presents a fully automated chip design pipeline that converts high-level specifications into final physical layout (GDSII) using an LLM-driven agentic framework integrated with open-source EDA tools.

## Overview 

Traditional VLSI design involves multiple manual steps across RTL design, verification, synthesis, and physical design.
This project demonstrates how an LLM-guided automation framework can execute the complete RTL-to-GDS flow with minimal human intervention.

## Key Capabilities

- Generate synthesizable RTL from structured specifications
- Perform functional verification using testbenches
- Run synthesis and technology mapping
- Automatically generate OpenROAD scripts
- Execute full Physical Design flow
- Produce routed DEF and final GDSII layout 

## Flow Architecture
```text
YAML Spec
   ↓
LLM Agent
   ↓
RTL Generation
   ↓
Simulation (Icarus Verilog)
   ↓
Synthesis (Yosys + ABC)
   ↓
Post-Synthesis Fixes
   ↓
PD Script Generation (TCL)
   ↓
OpenROAD (PnR)
   ↓
Floorplan → Placement → CTS → Routing
   ↓
DEF → GDSII
```

## Project Structure

```text
spec2gds/
│
.
├── Problems/                  # YAML design specifications (p1–p9)
├── Testbenches/              # RTL simulation testbenches
├── generated/                # Generated RTL + intermediate files
├── outputs/
│   ├── logs/                 # RTL / synthesis / PD logs
│   ├── reports/              # synthesis reports
│   ├── p*_mapped.v           # synthesized netlists
│   ├── p*_routed.def         # routed DEF files
│   └── p*.gds                # final GDSII outputs
├── prompts/                  # LLM prompt templates
├── new_main.py               # main pipeline driver
├─final_─ low_agent.py         # automation + orchestration logic
└── README.md
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
### Yosys (Synthesis)
```bash
sudo apt install yosys

### OpenROAD (PnR)
Use Docker:
```bash
docker pull openroad/openroad

###Environment Setup
```bash 
docker --version
yosys -V
iverilog -V

## 2. Exact Commands to Run the system 

### General Command
python3 final_eda_agent.py <spec_yaml_path> <testbench_path>

### Example Runs
- python3 final_eda_agent.py Problems/p1.yaml Testbenches/iclad_seq_detector_tb.v
- python3 final_eda_agent.py Problems/p5.yaml Testbenches/iclad_dot_product_tb.v
- python3 final_eda_agent.py Problems/p7.yaml Testbenches/iclad_exp_tb.v
- python3 final_eda_agent.py Problems/p8.yaml Testbenches/iclad_fp16_mult_tb.v
- python3 final_eda_agent.py Problems/p9.yaml Testbenches/iclad_fir_tb.v

## 3. Input/Output Description 

### Input

1. YAML Spec (Problems/)

Contains:

* Module name
* Inputs/outputs
* Functionality description
* Constraints

Example:
clock_period: 10ns
ports:
  - clk
  - reset
  - data_in
  - data_out

2. Testbench (Testbenches/)

* Verifies RTL functionality
* Used for simulation before synthesis

### Output
	•	All the log files are stored in output_logs/logs/
	•	All the generated sv files are store in generated/
	•	Mapped netist, routed DEF, SDC, GDS, DRC_rpt, abstract LEF, solution.v for P1,P5,P7 are stored in outputs_P1_P5_P7/ and for P8 and P9 are stored in outputs_P8_P9/  

## 4. Expected results (For Verification)

### For provided testcases, simulation result: PASS
	•	p1 → PASS
	•	p5 → PASS
	•	p7 → PASS
	•	p8 → PASS
	•	p9 → PASS
### The terminal should display: PASS

### For Synthesis
* Netlist generated: outputs/pX_mapped.v

### For Physical Design
* Successful PD flow prints: PD FLOW PASS

### Final Output
* Routed DEF exists: outputs/pX_routed.def
* GDS generated: outputs/pX.gds

## 5. Brief Workflow Description 

### The system follows an automated Spec-to-RTL flow:
1. YAML specification is parsed
2. LLM generates synthesizable RTL
3. RTL is simulated using testbench
4. Yosys performs synthesis + mapping
5. Netlist is cleaned and prepared
6. TCL scripts are auto-generated
7. OpenROAD runs:
    * Floorplan
    * Placement
    * CTS
    * Routing
8. DEF and GDS are generated

## 6. How to Run the Hidden Testcases 
 
### To Run any new/unseen testcase :
python3 final_eda_agent.py <new_spec.yaml> <new_testbench.v>

### Example:
python3 final_eda_agent.py Problems/new_problem.yaml Testbenches/new_tb.v

### No code modification is required
 
