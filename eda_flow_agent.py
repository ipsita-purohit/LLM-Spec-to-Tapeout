import sys
import subprocess
from pathlib import Path
from collections import Counter
import yaml

SRC_ROOT = "."
MAX_SAME_FAILURES = 3
MAX_CODEX_CRASHES = 3


def run_cmd(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def sanitize_yaml_text(raw_text: str) -> str:
    """
    Makes certain non-YAML Python-like expressions parseable by quoting them
    in-memory only, without changing the original file.

    Example fixes:
      clk: [0, 1] * 40
      rst: [1] + [0] * 39
      x_in: [1, 2, 3] + [0] * 32
    """
    lines = raw_text.splitlines()
    fixed_lines = []

    for line in lines:
        if ":" in line:
            prefix, value = line.split(":", 1)
            value_stripped = value.strip()

            looks_like_python_expr = (
                ("[" in value_stripped and "]" in value_stripped and "*" in value_stripped)
                or ("[" in value_stripped and "]" in value_stripped and "+" in value_stripped)
            )

            already_quoted = (
                (value_stripped.startswith('"') and value_stripped.endswith('"')) or
                (value_stripped.startswith("'") and value_stripped.endswith("'"))
            )

            if looks_like_python_expr and not already_quoted:
                indent = line[:len(line) - len(line.lstrip())]
                fixed_line = f'{indent}{prefix.strip()}: "{value_stripped}"'
                fixed_lines.append(fixed_line)
                continue

        fixed_lines.append(line)

    return "\n".join(fixed_lines)


def load_spec_info(spec_path: str):
    with open(spec_path, "r", encoding="utf-8") as f:
        raw_text = f.read()

    safe_text = sanitize_yaml_text(raw_text)
    spec = yaml.safe_load(safe_text)

    top_key = list(spec.keys())[0]
    design = spec[top_key]

    module_name = top_key
    rtl_path = f"outputs/{module_name}.sv"

    return {
        "module_name": module_name,
        "rtl_path": rtl_path,
        "description": design.get("description"),
        "clock_period": design.get("clock_period"),
        "parameters": design.get("parameters"),
        "ports": design.get("ports"),
        "module_signature": design.get("module_signature"),
        "sequence_to_detect": design.get("sequence_to_detect"),
        "sample_input": design.get("sample_input"),
        "sample_output": design.get("sample_output"),
        "sample_usage": design.get("sample_usage"),
        "stimulus": design.get("stimulus"),
        "expected_y_out": design.get("expected_y_out"),
    }


def is_likely_testbench(path: Path) -> bool:
    name = path.stem.lower()
    return "tb" in name or "testbench" in name


def find_testbench(module_name: str, search_root: str) -> str:
    root = Path(search_root)
    if not root.exists():
        raise FileNotFoundError(f"Search folder not found: {search_root}")

    candidates = list(root.rglob("*.v")) + list(root.rglob("*.sv"))
    if not candidates:
        raise FileNotFoundError(f"No Verilog/SystemVerilog files found in: {search_root}")

    tb_candidates = [p for p in candidates if is_likely_testbench(p)]
    if not tb_candidates:
        tb_candidates = candidates

    exact_name = [
        p for p in tb_candidates
        if p.stem.lower() == f"{module_name}_tb".lower()
    ]
    if exact_name:
        return str(exact_name[0])

    contains_name = [
        p for p in tb_candidates
        if module_name.lower() in p.stem.lower()
    ]
    if contains_name:
        return str(contains_name[0])

    content_match = []
    for p in tb_candidates:
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
            if module_name in text:
                content_match.append(p)
        except Exception:
            pass

    if content_match:
        return str(content_match[0])

    raise FileNotFoundError(
        f"Could not find a matching testbench for module '{module_name}' in {search_root}"
    )


def run_codex(prompt: str):
    return run_cmd([
        "codex",
        "exec",
        "--full-auto",
        "--skip-git-repo-check",
        prompt,
    ])


def run_local_check(rtl_path: str, tb_path: str):
    compile_rc, compile_out, compile_err = run_cmd(
        ["iverilog", "-g2012", "-o", "sim.out", rtl_path, tb_path]
    )

    if compile_rc != 0:
        return {
            "compile_ok": False,
            "sim_ok": False,
            "output": compile_out + compile_err,
        }

    sim_rc, sim_out, sim_err = run_cmd(["vvp", "sim.out"])
    full_output = sim_out + sim_err
    passed = "Test PASSED" in full_output or "PASS" in full_output

    return {
        "compile_ok": True,
        "sim_ok": passed,
        "output": full_output,
    }


def normalize_failure(output: str) -> str:
    text = (output or "").strip()
    if not text:
        return "[empty failure output]"
    return text


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

If compilation or simulation fails:
- inspect the output
- fix only the RTL in {info["rtl_path"]}
- rerun compile and simulation
- continue until the test passes or you are blocked

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

Testbench path:
{tb_path}

Failure output:
{failure_output}

Task:
- Fix only the RTL in {info["rtl_path"]}
- Keep the module name and module signature exactly unchanged
- Do not modify the testbench
- Use synthesizable SystemVerilog only
- Fix compile errors, logic bugs, and uninitialized or unknown ('x') outputs
- Ensure reset initializes all state and outputs correctly

After fixing the RTL, run:
iverilog -g2012 -o sim.out {info["rtl_path"]} {tb_path}
vvp sim.out

If it still fails, continue fixing until the test passes or you are blocked.

When done, print whether the test passed.
""".strip()


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 agent_loop.py <spec_yaml_path>")
        sys.exit(1)

    spec_path = sys.argv[1]

    if not Path(spec_path).exists():
        print(f"Spec file not found: {spec_path}")
        sys.exit(1)

    Path("outputs").mkdir(exist_ok=True)

    try:
        info = load_spec_info(spec_path)
    except yaml.YAMLError as e:
        print(f"Failed to parse YAML: {spec_path}")
        print(e)
        sys.exit(1)

    try:
        tb_path = find_testbench(info["module_name"], SRC_ROOT)
    except FileNotFoundError as e:
        print(str(e))
        sys.exit(1)

    print(f"Using spec: {spec_path}")
    print(f"Module name: {info['module_name']}")
    print(f"RTL path: {info['rtl_path']}")
    print(f"Matched testbench: {tb_path}")

    failure_counter = Counter()
    codex_crash_count = 0
    iteration = 1
    last_output = ""

    while True:
        print(f"\n=== Iteration {iteration} ===")

        if iteration == 1:
            prompt = build_initial_prompt(spec_path, tb_path, info)
        else:
            prompt = build_fix_prompt(spec_path, tb_path, info, last_output)

        codex_rc, codex_out, codex_err = run_codex(prompt)

        print("\n--- Codex output ---")
        print(codex_out if codex_out.strip() else "[no stdout]")

        if codex_err.strip():
            print("\n--- Codex stderr ---")
            print(codex_err)

        if codex_rc != 0:
            codex_crash_count += 1
            print(f"\nCodex returned non-zero exit code: {codex_rc}")
            if codex_crash_count >= MAX_CODEX_CRASHES:
                print("\nStopping because Codex failed too many times.")
                sys.exit(1)
        else:
            codex_crash_count = 0

        print("\n--- Local verification ---")
        result = run_local_check(info["rtl_path"], tb_path)
        print(result["output"])

        if result["compile_ok"] and result["sim_ok"]:
            print("\nPASS")
            return

        last_output = result["output"]
        signature = normalize_failure(last_output)
        failure_counter[signature] += 1

        if failure_counter[signature] >= MAX_SAME_FAILURES:
            print("\nStopping because the same failure repeated too many times.")
            print("\nRepeated failure was:\n")
            print(signature)
            sys.exit(1)

        print("\nStill failing, retrying...")
        iteration += 1


if __name__ == "__main__":
    main()
