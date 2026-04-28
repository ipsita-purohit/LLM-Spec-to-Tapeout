"""
eda_flow_agent.py  —  Full RTL-to-GDS flow in a single command
================================================================
Usage:
    python3 eda_flow_agent.py <spec.yaml>

Stages (all automatic, one command):
    1. RTL generation   — Codex writes synthesizable SystemVerilog
    2. RTL simulation   — iverilog + vvp verify against testbench
    3. Synthesis        — Yosys (multi-core abc) → mapped netlist
    4. Physical Design  — OpenROAD: floorplan → place → CTS → route
    5. GDS export       — KLayout def2stream.py (separate Docker step; avoids write_gds)

Speed improvements over baseline:
    - Yosys abc uses -fast + ABC_NUM_THREADS for multi-core logic mapping
    - OpenROAD gets -threads <nCPU-1> for parallel placement & routing
    - OMP_NUM_THREADS set in Docker for OpenROAD's internal parallel passes
    - Floorplan die/core auto-sized from Yosys chip area → no GPL-0301
    - Docker stdout streamed live so you see progress without waiting
    - Timeout watchdog kills a hung OpenROAD run after 60 min
"""

import sys
import subprocess
import threading
import time
import math
import os
import re
import shutil
from pathlib import Path
from collections import Counter

import yaml

# ── Tunables ─────────────────────────────────────────────────────────────────
SRC_ROOT          = "."
MAX_SAME_FAILURES = 3
MAX_CODEX_CRASHES = 3
OPENROAD_TIMEOUT  = 3600          # seconds — raise for very large designs
TARGET_UTIL       = 0.60          # floorplan target utilisation (60 %)

DOCKER_IMAGE = "openroad/orfs:latest"
OPENROAD_BIN = "/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad"
TECH_LEF     = "/OpenROAD-flow-scripts/flow/platforms/nangate45/lef/NangateOpenCellLibrary.tech.lef"
MACRO_LEF    = "/OpenROAD-flow-scripts/flow/platforms/nangate45/lef/NangateOpenCellLibrary.macro.mod.lef"
LIBERTY_LIB  = "/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib"
LIBERTY_LOCAL = "NangateOpenCellLibrary_typical.lib"
CELL_GDS     = "/OpenROAD-flow-scripts/flow/platforms/nangate45/gds/NangateOpenCellLibrary.gds"


# ═════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═════════════════════════════════════════════════════════════════════════════

def cpu_count() -> int:
    """All CPU cores minus one (leave one for the OS)."""
    return max(1, (os.cpu_count() or 2) - 1)


def run_cmd(cmd: list):
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def banner(title: str):
    print(f"\n{'='*60}\n  {title}\n{'='*60}")


# ═════════════════════════════════════════════════════════════════════════════
# CLOCK / SDC
# ═════════════════════════════════════════════════════════════════════════════

def parse_clock_period_ns(clock_period) -> float:
    if not clock_period:
        return 10.0
    text = str(clock_period).strip().lower().replace(" ", "")
    m = re.match(r"([0-9]*\.?[0-9]+)", text)
    return float(m.group(1)) if m else 10.0


def classify_ports(ports):
    clock_name = reset_name = None
    input_ports, output_ports = [], []
    for port in (ports or []):
        if not isinstance(port, dict):
            continue
        name      = port.get("name")
        direction = str(port.get("direction", "")).lower()
        if not name:
            continue
        lname = name.lower()
        if direction == "input":
            input_ports.append(name)
            if clock_name is None and "clk" in lname:
                clock_name = name
            if reset_name is None and ("reset" in lname or "rst" in lname):
                reset_name = name
        elif direction == "output":
            output_ports.append(name)
    return clock_name or "clk", reset_name, input_ports, output_ports


def generate_sdc(info: dict) -> str:
    """SDC with create_clock + 30%-period I/O delays."""
    period = parse_clock_period_ns(info.get("clock_period", "10ns"))
    clk, rst, ins, outs = classify_ports(info.get("ports", []))
    io_delay = round(period * 0.30, 3)
    lines = [
        f"# Auto-generated SDC — clock period: {period} ns",
        f"create_clock -name {clk} -period {period} [get_ports {clk}]",
        f"set_clock_uncertainty -setup 0.05 [get_clocks {clk}]",
        f"set_clock_uncertainty -hold  0.02 [get_clocks {clk}]",
        f"set_clock_transition   0.05       [get_clocks {clk}]",
    ]
    constrained_ins = [p for p in ins if p not in (clk, rst)]
    if constrained_ins:
        lines.append(
            f"set_input_delay  {io_delay} -clock {clk} "
            f"[get_ports {{{' '.join(constrained_ins)}}}]"
        )
    if outs:
        lines.append(
            f"set_output_delay {io_delay} -clock {clk} "
            f"[get_ports {{{' '.join(outs)}}}]"
        )
    return "\n".join(lines) + "\n"


def save_sdc_file(sdc_text: str, output_path: str):
    p = Path(output_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(sdc_text)


# ═════════════════════════════════════════════════════════════════════════════
# SPEC LOADING
# ═════════════════════════════════════════════════════════════════════════════

def sanitize_yaml_text(raw: str) -> str:
    """Quote Python-like list expressions that confuse PyYAML."""
    fixed = []
    for line in raw.splitlines():
        if ":" in line:
            prefix, value = line.split(":", 1)
            vs = value.strip()
            looks_like_expr = (
                ("[" in vs and "]" in vs and "*" in vs) or
                ("[" in vs and "]" in vs and "+" in vs)
            )
            already_quoted = (
                (vs.startswith('"') and vs.endswith('"')) or
                (vs.startswith("'") and vs.endswith("'"))
            )
            if looks_like_expr and not already_quoted:
                indent = line[: len(line) - len(line.lstrip())]
                fixed.append(f'{indent}{prefix.strip()}: "{vs}"')
                continue
        fixed.append(line)
    return "\n".join(fixed)


def load_spec_info(spec_path: str) -> dict:
    raw  = Path(spec_path).read_text(encoding="utf-8")
    safe = sanitize_yaml_text(raw)
    spec = yaml.safe_load(safe)
    top  = list(spec.keys())[0]
    d    = spec[top]
    return {
        "module_name":        top,
        "rtl_path":           f"outputs/{top}.sv",
        "description":        d.get("description"),
        "clock_period":       d.get("clock_period"),
        "parameters":         d.get("parameters"),
        "ports":              d.get("ports"),
        "module_signature":   d.get("module_signature"),
        "sequence_to_detect": d.get("sequence_to_detect"),
        "sample_input":       d.get("sample_input"),
        "sample_output":      d.get("sample_output"),
        "sample_usage":       d.get("sample_usage"),
        "stimulus":           d.get("stimulus"),
        "expected_y_out":     d.get("expected_y_out"),
    }


# ═════════════════════════════════════════════════════════════════════════════
# TESTBENCH DISCOVERY
# ═════════════════════════════════════════════════════════════════════════════

def is_likely_testbench(path: Path) -> bool:
    n = path.stem.lower()
    return "tb" in n or "testbench" in n


def find_testbench(module_name: str, search_root: str) -> str:
    root = Path(search_root)
    if not root.exists():
        raise FileNotFoundError(f"Search folder not found: {search_root}")
    candidates = list(root.rglob("*.v")) + list(root.rglob("*.sv"))
    if not candidates:
        raise FileNotFoundError(f"No Verilog/SV files in {search_root}")
    tb = [p for p in candidates if is_likely_testbench(p)] or candidates
    exact = [p for p in tb if p.stem.lower() == f"{module_name}_tb".lower()]
    if exact:
        return str(exact[0])
    contains = [p for p in tb if module_name.lower() in p.stem.lower()]
    if contains:
        return str(contains[0])
    for p in tb:
        try:
            if module_name in p.read_text(encoding="utf-8", errors="ignore"):
                return str(p)
        except Exception:
            pass
    raise FileNotFoundError(
        f"No matching testbench for '{module_name}' in {search_root}"
    )


# ═════════════════════════════════════════════════════════════════════════════
# CODEX / RTL GENERATION
# ═════════════════════════════════════════════════════════════════════════════

def run_codex(prompt: str):
    return run_cmd(["codex", "exec", "--full-auto", "--skip-git-repo-check", prompt])


def build_initial_prompt(spec_path: str, tb_path: str, info: dict) -> str:
    return f"""
Read the YAML spec file at {spec_path} and generate synthesizable SystemVerilog RTL.

Design info:
- Module name: {info["module_name"]}
- Description: {info["description"]}
- Clock period: {info["clock_period"]}
- Parameters: {info.get("parameters")}
- Ports: {info["ports"]}
- Module signature:
{info["module_signature"]}
- Sequence to detect: {info.get("sequence_to_detect")}
- Sample input: {info.get("sample_input")}
- Sample output: {info.get("sample_output")}
- Sample usage: {info.get("sample_usage")}
- Stimulus: {info.get("stimulus")}
- Expected output: {info.get("expected_y_out")}

Write the RTL to {info["rtl_path"]}.

Requirements:
- Follow module_signature exactly
- Use the exact ports from the spec
- Implement the described behavior exactly
- Use synthesizable SystemVerilog only
- Do not modify the testbench
- Overwrite the RTL file if it exists
- Ensure reset initializes all state and outputs correctly
- Avoid unknown ('x') output values in simulation

After writing the RTL, run:
iverilog -g2012 -o sim.out {info["rtl_path"]} {tb_path}
vvp sim.out

If compilation or simulation fails, fix only the RTL and rerun.
When done, print whether the test passed.
""".strip()


def build_fix_prompt(spec_path: str, tb_path: str, info: dict, failure_output: str) -> str:
    return f"""
The RTL in {info["rtl_path"]} failed verification.

Read the spec again from {spec_path}.

Design info:
- Module name: {info["module_name"]}
- Description: {info["description"]}
- Parameters: {info.get("parameters")}
- Ports: {info["ports"]}
- Module signature:
{info["module_signature"]}
- Stimulus: {info.get("stimulus")}
- Expected output: {info.get("expected_y_out")}

Testbench path: {tb_path}

Failure output:
{failure_output}

Task:
- Fix only the RTL in {info["rtl_path"]}
- Keep the module name and module signature exactly unchanged
- Do not modify the testbench
- Use synthesizable SystemVerilog only
- Fix compile errors, logic bugs, and uninitialized or unknown ('x') outputs
- Ensure reset initializes all state and outputs correctly

After fixing the RTL:
iverilog -g2012 -o sim.out {info["rtl_path"]} {tb_path}
vvp sim.out

Continue fixing until the test passes or you are blocked.
When done, print whether the test passed.
""".strip()


# ═════════════════════════════════════════════════════════════════════════════
# RTL SIMULATION
# ═════════════════════════════════════════════════════════════════════════════

def run_local_check(rtl_path: str, tb_path: str) -> dict:
    rc, out, err = run_cmd(["iverilog", "-g2012", "-o", "sim.out", rtl_path, tb_path])
    if rc != 0:
        return {"compile_ok": False, "sim_ok": False, "output": out + err}
    rc2, out2, err2 = run_cmd(["vvp", "sim.out"])
    full = out2 + err2
    passed = "Test PASSED" in full or "PASS" in full
    return {"compile_ok": True, "sim_ok": passed, "output": full}


def normalize_failure(output: str) -> str:
    return (output or "").strip() or "[empty failure output]"


# ═════════════════════════════════════════════════════════════════════════════
# SYNTHESIS  (Yosys — fast multi-core abc)
# ═════════════════════════════════════════════════════════════════════════════

def run_synthesis(rtl_file: str, module_name: str, output_netlist: str):
    """
    Yosys with speed optimisations:
        • abc -fast          — skips slow iterative resyn passes (3-5× faster)
        • ABC_NUM_THREADS    — abc uses all available CPU cores
        • opt -fast          — lightweight optimisation between passes
    Pass order: proc → opt → fsm → memory → techmap → dfflibmap → abc → clean
    dfflibmap MUST come after techmap so FF primitives are lowered first.
    """
    threads = cpu_count()
    env = os.environ.copy()
    env["ABC_NUM_THREADS"] = str(threads)

    yosys_script = f"""
read_verilog -sv {rtl_file}
hierarchy -check -top {module_name}

# RTL elaboration
proc
opt_expr
opt_clean
check
opt -fast

# FSM & memory
fsm
opt -fast
memory -nomap
opt_clean

# Technology mapping — techmap FIRST, then dfflibmap
techmap
opt -fast
dfflibmap -liberty {LIBERTY_LOCAL}

# abc -fast: skips resyn2 loop; uses ABC_NUM_THREADS cores (set in env)
abc -liberty {LIBERTY_LOCAL} -fast

# Tie-cell insertion for unconnected VDD/GND rails
hilomap -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z

opt_clean -purge
stat

write_verilog -noattr -noexpr {output_netlist}
"""
    with open("synth.ys", "w") as f:
        f.write(yosys_script)

    print(f"[synth] Yosys abc using {threads} thread(s) (ABC_NUM_THREADS={threads})")
    result = subprocess.run(
        ["yosys", "-s", "synth.ys"],
        capture_output=True, text=True, env=env
    )
    log = result.stdout + "\n" + result.stderr
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr)
        return False, log
    return True, log


def extract_synthesis_metrics(synth_log: str) -> dict:
    patterns = {
        "Chip area (µm²)":        r"Chip area for (?:module|top module) '.*?':\s*([\d.]+)",
        "Number of cells":        r"Number of cells:\s+(\d+)",
        "Number of wires":        r"Number of wires:\s+(\d+)",
        "Number of public wires": r"Number of public wires:\s+(\d+)",
        "Number of memories":     r"Number of memories:\s+(\d+)",
        "Number of processes":    r"Number of processes:\s+(\d+)",
    }
    metrics = {}
    for key, pat in patterns.items():
        m = re.search(pat, synth_log)
        metrics[key] = m.group(1) if m else "N/A"
    return metrics


# ═════════════════════════════════════════════════════════════════════════════
# NETLIST TB COMPATIBILITY HELPER
# ═════════════════════════════════════════════════════════════════════════════

def make_netlist_compatible_tb(tb_path: str, module_name: str) -> str:
    p = Path(tb_path)
    text = p.read_text()
    pattern = (
        rf'(\b{re.escape(module_name)}\b)\s*#\s*\((.*?)\)\s+'
        rf'([A-Za-z_][A-Za-z0-9_]*)\s*\('
    )
    new_text = re.sub(
        pattern, lambda m: f"{m.group(1)} {m.group(3)}(", text, flags=re.DOTALL
    )
    tmp = p.with_name(p.stem + "_netlist_tmp.v")
    tmp.write_text(new_text)
    return str(tmp)


# ═════════════════════════════════════════════════════════════════════════════
# FLOORPLAN AUTO-SIZING  (prevents GPL-0301 utilisation > 100%)
# ═════════════════════════════════════════════════════════════════════════════

def extract_cell_area(synth_log: str) -> float:
    """Try multiple patterns to extract cell area from Yosys log."""
    patterns = [
        r"Chip area for (?:module|top module) '.*?':\s*([\d.]+)",
        r"chip area.*?:\s*([\d.]+)",
        r"ABC: netlist.*?area\s*=\s*([\d.]+)",
    ]
    for pat in patterns:
        m = re.search(pat, synth_log, re.IGNORECASE)
        if m:
            return float(m.group(1))
    # Fallback: estimate from cell count
    m2 = re.search(r"Number of cells:\s+(\d+)", synth_log)
    if m2:
        count = int(m2.group(1))
        area = count * 0.532
        print(f"[floorplan] Using cell count estimate: {count} cells × 0.532 = {area:.1f} µm²")
        return area
    return 0.0


def estimate_die_area(synth_log: str, util: float = None) -> tuple:
    """
    Compute die/core area from Yosys chip area to keep util <= TARGET_UTIL.

    Sources tried in order:
        1. 'Chip area for module' line from abc stat  (most accurate)
        2. Number of cells × 0.532 µm²               (NangateOpenCell avg)
        3. Minimum 400 × 400 µm core                 (safe default for larger designs)
    """
    effective_util = util if util is not None else TARGET_UTIL
    cell_area = extract_cell_area(synth_log)

    # If cell_area is 0 or unreasonably small, use a safe large default
    if cell_area < 1000:
        cell_area = 50000.0
        print(f"[floorplan] WARNING: could not read cell area from synth log — using safe default {cell_area} µm²")

    required_core = cell_area / effective_util
    side   = math.ceil(math.ceil(math.sqrt(required_core)) / 50) * 50
    margin = max(20, int(side * 0.15))
    die    = side + 2 * margin

    print(
        f"[floorplan] cell_area={cell_area:.1f} µm²  util={int(effective_util*100)}% "
        f"-> core={side}x{side} µm, die={die}x{die} µm  "
        f"(target util {int(TARGET_UTIL*100)}%)"
    )
    return f"0 0 {die} {die}", f"{margin} {margin} {margin+side} {margin+side}"


# ═════════════════════════════════════════════════════════════════════════════
# OPENROAD TCL  (PD + GDS in one script)
# ═════════════════════════════════════════════════════════════════════════════

def write_pd_tcl(spec_stem: str, module_name: str,
                 clock_period_ns: float, clock_port: str = "clk",
                 synth_log: str = "", util: float = None) -> str:
    """
    Single OpenROAD TCL that covers:
        floorplan → pin placement → global/detailed placement →
        CTS → timing repair → global/detailed route →
        post-route timing repair → reports → write_def/v/gds/lef

    Fixes baked in:
        1. create_clock BEFORE read_sdc  — avoids virtual-clock / CTS skip
        2. Auto-sized die/core           — avoids GPL-0301 (util > 100%)
        3. set_wire_rc before placement  — accurate timing parasitics
        4. Full CTS buffer list          — TritonCTS can balance the tree
        5. set_propagated_clock          — real (not ideal) clock for STA
        6. repair_timing after routing   — eliminates setup/hold violations
        7. GDS export inline             — no second Docker run needed
    """
    effective_util      = util if util is not None else TARGET_UTIL
    io_delay            = round(clock_period_ns * 0.30, 3)
    die_area, core_area = estimate_die_area(synth_log, util=effective_util)

    tcl = f"""
# ── Technology files ─────────────────────────────────────────────
read_lef     {TECH_LEF}
read_lef     {MACRO_LEF}
read_liberty {LIBERTY_LIB}

# ── Netlist ──────────────────────────────────────────────────────
read_verilog outputs/{spec_stem}_mapped.v
link_design  {module_name}

# ── Clock — define BEFORE read_sdc ───────────────────────────────
# Defining after read_sdc makes OpenROAD treat it as virtual →
# TritonCTS finds 0 clock nets and is skipped entirely.
create_clock -name {clock_port} -period {clock_period_ns} [get_ports {clock_port}]
set_clock_uncertainty -setup 0.05 [get_clocks {clock_port}]
set_clock_uncertainty -hold  0.02 [get_clocks {clock_port}]
set_clock_transition   0.05       [get_clocks {clock_port}]

# ── SDC (I/O delays only — clock already defined above) ──────────
read_sdc outputs/{spec_stem}.sdc

# ── Wire RC model (needed for timing-driven placement) ───────────
set_wire_rc -clock  -layer metal5
set_wire_rc -signal -layer metal3

# ── Floorplan ────────────────────────────────────────────────────
# Auto-sized from Yosys chip area to keep utilisation at ~{int(effective_util*100)}%.
# This prevents GPL-0301 "Utilisation > 100%" errors on larger designs.
initialize_floorplan \\
  -site      FreePDK45_38x28_10R_NP_162NW_34O \\
  -die_area  "{die_area}" \\
  -core_area "{core_area}"

source /OpenROAD-flow-scripts/flow/platforms/nangate45/make_tracks.tcl
place_pins -hor_layers metal3 -ver_layers metal2 -annealing

# ── Global placement ─────────────────────────────────────────────
global_placement -density {effective_util} -timing_driven -routability_driven
estimate_parasitics -placement
repair_design

# ── Detailed placement ───────────────────────────────────────────
detailed_placement
check_placement -verbose

# ── CTS ──────────────────────────────────────────────────────────
# Full buffer list lets TritonCTS choose the right drive strength.
clock_tree_synthesis \\
  -root_buf CLKBUF_X1 \\
  -buf_list {{BUF_X1 BUF_X2 BUF_X4 CLKBUF_X1 CLKBUF_X2 CLKBUF_X3}} \\
  -wire_unit 20

# Propagate clock so OpenSTA uses real (not ideal) skew
set_propagated_clock [all_clocks]
detailed_placement
check_placement -verbose

# Pre-route timing repair
estimate_parasitics -placement
repair_timing -hold -setup

# ── Routing ──────────────────────────────────────────────────────
global_route \\
  -guide_file outputs/{spec_stem}_route.guide
detailed_route \\
  -output_drc outputs/{spec_stem}_drc.rpt

# ── Post-route parasitics + timing repair ────────────────────────
estimate_parasitics -global_routing
repair_timing -hold -setup -max_buffer_percent 20

# ── Timing / power / area reports ────────────────────────────────
puts "\\n=== Timing Report (Setup) ==="
report_checks -path_delay max -format full_clock_expanded \\
  -fields {{slew cap input_pins nets}} -digits 3

puts "\\n=== Timing Report (Hold) ==="
report_checks -path_delay min -format full_clock_expanded -digits 3

puts "\\n=== WNS / TNS ==="
report_wns
report_tns

puts "\\n=== Power ==="
report_power

puts "\\n=== Area ==="
report_design_area

# ── Output files ─────────────────────────────────────────────────
write_def     outputs/{spec_stem}_routed.def
write_verilog outputs/{spec_stem}_final.v

puts "PD complete — DEF ready for GDS export via def2stream.py"
"""
    tcl_path = f"pd_{spec_stem}.tcl"
    Path(tcl_path).write_text(tcl)
    return tcl_path


# ═════════════════════════════════════════════════════════════════════════════
# OPENROAD DOCKER RUNNER  (live streaming + timeout watchdog + multi-thread)
# ═════════════════════════════════════════════════════════════════════════════

def run_openroad_docker(tcl_path: str, timeout_sec: int = OPENROAD_TIMEOUT):
    """
    Run OpenROAD inside Docker.
    Speed improvements:
        -threads N          parallel placement & detailed routing
        OMP_NUM_THREADS=N   OpenROAD's internal OpenMP parallel passes
    Reliability improvements:
        Live streaming      see progress line-by-line, not just at end
        Timeout watchdog    kills container if routing hangs past timeout
    """
    threads = cpu_count()
    print(f"[docker] OpenROAD: {threads} thread(s), timeout {timeout_sec}s")

    cmd = [
        "docker", "run", "--rm",
        "--platform", "linux/amd64",
        "-v", f"{Path.cwd()}:/work",
        "-w", "/work",
        DOCKER_IMAGE,
        "bash", "-lc",
        (
            f"export OMP_NUM_THREADS={threads} && "
            f"{OPENROAD_BIN} -threads {threads} -exit {tcl_path}"
        ),
    ]

    lines = []
    proc  = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )

    timed_out = [False]

    def watchdog():
        deadline = time.time() + timeout_sec
        while proc.poll() is None:
            if time.time() > deadline:
                timed_out[0] = True
                print(f"\n[timeout] OpenROAD exceeded {timeout_sec}s — killing container.")
                proc.kill()
                return
            time.sleep(5)

    wd = threading.Thread(target=watchdog, daemon=True)
    wd.start()

    for line in proc.stdout:
        print(line, end="", flush=True)
        lines.append(line)

    proc.wait()
    wd.join(timeout=2)

    full_log = "".join(lines)
    if timed_out[0]:
        full_log += "\n[AGENT] OpenROAD killed by timeout watchdog.\n"
        return False, full_log

    return proc.returncode == 0, full_log


def docker_available() -> bool:
    return shutil.which("docker") is not None


# ═════════════════════════════════════════════════════════════════════════════
# GDS EXPORT  (KLayout def2stream.py — separate Docker step)
# ═════════════════════════════════════════════════════════════════════════════

def _docker_run_bash(bash_cmd: str) -> tuple:
    """Run a bash command inside the ORFS Docker container, stream output, return (rc, log)."""
    cmd = [
        "docker", "run", "--rm",
        "--platform", "linux/amd64",
        "-v", f"{Path.cwd()}:/work",
        "-w", "/work",
        DOCKER_IMAGE,
        "bash", "-lc", bash_cmd,
    ]
    lines = []
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    for line in proc.stdout:
        print(line, end="", flush=True)
        lines.append(line)
    proc.wait()
    return proc.returncode, "".join(lines)


def run_def_to_gds(spec_stem: str) -> bool:
    """
    Convert routed DEF → GDS using gdstk inside Docker.

    Approach: parse component placements from DEF, instantiate each standard
    cell from the NangateOpenCell GDS library at the correct (x, y, orientation),
    then write a merged GDS. This avoids write_gds (not built in ORFS 26Q2) and
    the KLayout macro path (requires KLayout Python bindings not on system PATH).
    """
    def_path = f"outputs/{spec_stem}_routed.def"
    gds_path = f"outputs/{spec_stem}.gds"
    lef_path = f"outputs/{spec_stem}_abstract.lef"

    print(f"\n[def2gds] Converting {def_path} -> {gds_path}")

    def gds_ok() -> bool:
        p = Path(gds_path)
        return p.exists() and p.stat().st_size > 0

    # ── Write the gdstk helper script to a temp file ──────────────────────────
    script_path = f"/tmp/make_gds_{spec_stem}.py"
    script = f"""import gdstk, re

DEF  = "/work/{def_path}"
CGDS = "{CELL_GDS}"
OUT  = "/work/{gds_path}"

cell_lib = gdstk.read_gds(CGDS)
cell_map = {{c.name: c for c in cell_lib.cells}}

text = open(DEF).read()
units_m = re.search("UNITS DISTANCE MICRONS ([0-9]+)", text)
dbu = int(units_m.group(1)) if units_m else 1000

comps = []
in_comps = False
for line in text.splitlines():
    line = line.strip()
    if line.startswith("COMPONENTS"):
        in_comps = True
        continue
    if line == "END COMPONENTS":
        break
    if in_comps and line.startswith("-"):
        m = re.match(r"-\\s+(\\S+)\\s+(\\S+)\\s+\\+\\s+(?:PLACED|FIXED)\\s+\\(\\s+([0-9]+)\\s+([0-9]+)\\s+\\)\\s+(\\S+)", line)
        if m:
            comps.append({{"inst": m.group(1), "cell": m.group(2),
                          "x": int(m.group(3))/dbu, "y": int(m.group(4))/dbu,
                          "orient": m.group(5)}})

print(f"Parsed {{len(comps)}} components")

lib_out = gdstk.Library()
top = gdstk.Cell("{spec_stem}")
lib_out.add(top)

added = set()
def add_cell(name):
    if name in added or name not in cell_map:
        return
    added.add(name)
    lib_out.add(cell_map[name])
    for ref in cell_map[name].references:
        add_cell(ref.cell.name)

rot_map = {{"N":0,"S":180,"E":270,"W":90,"FN":0,"FS":180,"FE":270,"FW":90}}
for comp in comps:
    add_cell(comp["cell"])
    if comp["cell"] in cell_map:
        angle = rot_map.get(comp["orient"], 0)
        x_flip = comp["orient"].startswith("F")
        ref = gdstk.Reference(cell_map[comp["cell"]],
                              origin=(comp["x"], comp["y"]),
                              rotation=angle * 3.14159265 / 180,
                              x_reflection=x_flip)
        top.add(ref)

lib_out.write_gds(OUT)
print(f"SUCCESS: GDS written to {{OUT}}")
print(f"Instances placed: {{len(top.references)}}")
"""
    with open(script_path, "w") as f:
        f.write(script)

    print(f"[def2gds] GDS script -> {script_path}")

    # ── Run inside Docker ─────────────────────────────────────────────────────
    cmd = [
        "docker", "run", "--rm",
        "--platform", "linux/amd64",
        "-v", f"{Path.cwd()}:/work",
        "-v", f"{script_path}:{script_path}",
        DOCKER_IMAGE,
        "bash", "-lc",
        f"pip install gdstk -q && python3 {script_path}",
    ]
    lines = []
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    for line in proc.stdout:
        print(line, end="", flush=True)
        lines.append(line)
    proc.wait()

    if gds_ok():
        print("[def2gds] GDS generation succeeded.")
        _write_abstract_lef(def_path, lef_path)
        _report_gds(gds_path, lef_path)
        return True

    print("[def2gds] gdstk approach failed — GDS not generated.")
    return False


def _write_abstract_lef(def_path: str, lef_path: str):
    """Generate abstract LEF from routed DEF via a small OpenROAD Tcl script."""
    lef_tcl = (
        f"read_lef {TECH_LEF}\\n"
        f"read_lef {MACRO_LEF}\\n"
        f"read_liberty {LIBERTY_LIB}\\n"
        f"read_def {def_path}\\n"
        f"write_abstract_lef {lef_path}\\n"
    )
    cmd = (
        f"printf '{lef_tcl}' > /tmp/lef_abs.tcl && "
        f"{OPENROAD_BIN} -exit /tmp/lef_abs.tcl"
    )
    _docker_run_bash(cmd)


def _report_gds(gds_path: str, lef_path: str):
    p = Path(gds_path)
    if p.exists():
        print(f"[def2gds] GDS written -> {gds_path}  ({p.stat().st_size // 1024} KB)")
    if Path(lef_path).exists():
        print(f"[def2gds] LEF written -> {lef_path}")


# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("Usage: python3 eda_flow_agent.py <spec_yaml_path>")
        sys.exit(1)

    spec_path = sys.argv[1]
    if not Path(spec_path).exists():
        print(f"Spec file not found: {spec_path}")
        sys.exit(1)

    # ── Output directories ───────────────────────────────────────
    for d in [
        "outputs",
        "outputs/logs/rtl",
        "outputs/logs/synthesis",
        "outputs/logs/pd",
        "outputs/reports/synthesis",
    ]:
        os.makedirs(d, exist_ok=True)

    # ═══════════════════════════════════════════════════════════════
    # STAGE 0 — Load spec & generate SDC
    # ═══════════════════════════════════════════════════════════════
    banner("STAGE 0 — Load spec & generate SDC")
    try:
        info      = load_spec_info(spec_path)
        spec_stem = Path(spec_path).stem
        sdc_text  = generate_sdc(info)
        sdc_path  = f"outputs/{spec_stem}.sdc"
        save_sdc_file(sdc_text, sdc_path)
        print(f"SDC -> {sdc_path}")
    except yaml.YAMLError as e:
        print(f"YAML parse error in {spec_path}:\n{e}")
        sys.exit(1)

    # ── Find testbench ───────────────────────────────────────────
    try:
        tb_path = find_testbench(info["module_name"], SRC_ROOT)
    except FileNotFoundError as e:
        print(str(e))
        sys.exit(1)

    print(f"Spec:        {spec_path}")
    print(f"Module:      {info['module_name']}")
    print(f"RTL target:  {info['rtl_path']}")
    print(f"Testbench:   {tb_path}")
    print(f"Clock:       {info['clock_period']}")
    print(f"CPU cores:   {cpu_count()} (of {os.cpu_count()} total)")

    clock_period_ns = parse_clock_period_ns(info.get("clock_period"))
    clock_port, *_  = classify_ports(info.get("ports", []))

    failure_counter   = Counter()
    codex_crash_count = 0
    iteration         = 1
    last_output       = ""

    # ═══════════════════════════════════════════════════════════════
    # STAGE 1 — RTL generation / fix loop
    # ═══════════════════════════════════════════════════════════════
    while True:
        banner(f"STAGE 1 — RTL generation  (iteration {iteration})")

        prompt = (
            build_initial_prompt(spec_path, tb_path, info)
            if iteration == 1
            else build_fix_prompt(spec_path, tb_path, info, last_output)
        )

        codex_rc, codex_out, codex_err = run_codex(prompt)

        print("\n--- Codex output ---")
        print(codex_out if codex_out.strip() else "[no stdout]")
        if codex_err.strip():
            print("\n--- Codex stderr ---")
            print(codex_err)

        if codex_rc != 0:
            codex_crash_count += 1
            print(f"\nCodex returned non-zero ({codex_rc})")
            if codex_crash_count >= MAX_CODEX_CRASHES:
                print("Stopping: Codex crashed too many times.")
                sys.exit(1)
            iteration += 1
            continue
        codex_crash_count = 0

        # ── STAGE 2: RTL simulation ──────────────────────────────
        banner("STAGE 2 — RTL simulation")
        result = run_local_check(info["rtl_path"], tb_path)
        print(result["output"])

        rtl_log = f"outputs/logs/rtl/{spec_stem}_log.txt"
        Path(rtl_log).write_text(result["output"])
        print(f"RTL log -> {rtl_log}")

        if not (result["compile_ok"] and result["sim_ok"]):
            last_output = result["output"]
            sig = normalize_failure(last_output)
            failure_counter[sig] += 1
            if failure_counter[sig] >= MAX_SAME_FAILURES:
                print("\nStopping: same RTL failure repeated too many times.")
                print(f"\n{sig}")
                sys.exit(1)
            print("\nRTL failing — retrying with fix prompt ...")
            iteration += 1
            continue

        print("\nRTL simulation PASS ✓")
        break  # exit RTL loop

    # ═══════════════════════════════════════════════════════════════
    # STAGE 3 — Synthesis  (Yosys, fast multi-core abc)
    # ═══════════════════════════════════════════════════════════════
    banner("STAGE 3 — Synthesis  (Yosys + fast multi-core abc)")
    module_name  = info["module_name"]
    netlist_path = f"outputs/{spec_stem}_mapped.v"

    synth_ok, synth_log = run_synthesis(info["rtl_path"], module_name, netlist_path)

    synth_log_path = f"outputs/logs/synthesis/{spec_stem}_synth_log.txt"
    Path(synth_log_path).write_text(synth_log)
    print(f"Synth log -> {synth_log_path}")

    metrics = extract_synthesis_metrics(synth_log)
    metrics_path = f"outputs/reports/synthesis/{spec_stem}_metrics.txt"
    with open(metrics_path, "w") as f:
        for k, v in metrics.items():
            f.write(f"{k}: {v}\n")
    print(f"Metrics   -> {metrics_path}")
    for k, v in metrics.items():
        print(f"  {k}: {v}")

    if not synth_ok:
        print("\nSynthesis FAILED — check synth log.")
        sys.exit(1)
    print(f"\nSynthesis PASS ✓  ->  {netlist_path}")

    # ═══════════════════════════════════════════════════════════════
    # STAGE 4 — Physical Design  (OpenROAD, Docker)
    # ═══════════════════════════════════════════════════════════════
    if not docker_available():
        print("\nDocker not found — skipping PD + GDS stages.")
        sys.exit(0)

    banner("STAGE 4 — Physical Design  (OpenROAD in Docker)")

    # Auto-retry with progressively smaller utilization if GPL-0301 occurs
    global TARGET_UTIL
    util_attempts = [TARGET_UTIL, 0.45, 0.35, 0.25]
    pd_ok, pd_log = False, ""
    for attempt_util in util_attempts:
        if attempt_util != TARGET_UTIL:
            print(f"\n[PD] Retrying with lower utilization: {int(attempt_util*100)}% ...")

        TARGET_UTIL = attempt_util

        pd_tcl = write_pd_tcl(
            spec_stem, module_name,
            clock_period_ns=clock_period_ns,
            clock_port=clock_port,
            synth_log=synth_log,
            util=attempt_util,
        )
        print(f"PD TCL -> {pd_tcl}")

        pd_ok, pd_log = run_openroad_docker(pd_tcl)

        pd_log_path = f"outputs/logs/pd/{spec_stem}_pd_log.txt"
        Path(pd_log_path).write_text(pd_log)
        print(f"\nPD log -> {pd_log_path}")

        if pd_ok:
            break

        # Check if failure was specifically GPL-0301 (utilization > 100%)
        if "GPL-0301" in pd_log:
            print(f"[PD] Utilization exceeded 100% at {int(attempt_util*100)}% target — retrying with more area.")
            continue
        else:
            # Different error — no point retrying with more area
            print("\nPD FLOW FAIL — check PD log for details.")
            sys.exit(1)

    if not pd_ok:
        print("\nPD FLOW FAIL — utilization retry exhausted. Check PD log.")
        sys.exit(1)

    print("\nPlace & Route PASS ✓")

    # ═══════════════════════════════════════════════════════════════
    # STAGE 5 — GDS export  (KLayout def2stream.py in Docker)
    # ═══════════════════════════════════════════════════════════════
    banner("STAGE 5 — GDS export  (KLayout def2stream.py in Docker)")
    gds_ok = run_def_to_gds(spec_stem)

    gds_path = Path(f"outputs/{spec_stem}.gds")
    lef_path = Path(f"outputs/{spec_stem}_abstract.lef")

    print("\n" + "="*60)
    print("  ALL STAGES COMPLETE" if gds_ok else "  STAGES 0-4 COMPLETE  (GDS export failed)")
    print("="*60)
    print("  Stage 0 — SDC generation      OK")
    print("  Stage 1 — RTL generation       OK")
    print("  Stage 2 — RTL simulation       OK")
    print("  Stage 3 — Synthesis            OK")
    print("  Stage 4 — Place & Route        OK")
    print(f"  Stage 5 — GDS export           {'OK' if gds_ok else 'FAIL — check output above'}")
    print()
    if gds_path.exists():
        print(f"  GDS  ->  {gds_path}  ({gds_path.stat().st_size // 1024} KB)")
    else:
        print("  GDS  ->  not generated (see Stage 5 output)")
    if lef_path.exists():
        print(f"  LEF  ->  {lef_path}")
    print()
    if gds_ok:
        print("  To view layout:")
        print(f"    klayout outputs/{spec_stem}.gds")

    sys.exit(0 if gds_ok else 1)


if __name__ == "__main__":
    main()
