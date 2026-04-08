import os
import sys

from parser import load_spec, extract_key_info
from generator import generate_rtl_from_spec, save_rtl_to_file
from run_sim import compile_and_run_sim


def main():
    # Check if user provided spec filename
    if len(sys.argv) < 2:
        print("Usage: python3 main.py <spec_file.yaml>")
        sys.exit(1)

    spec_file = sys.argv[1]
    tb_file = "iclad_seq_detector_tb.v"
    output_dir = "outputs"

    print("\n=== Spec-to-RTL Flow Started ===\n")

    # Step 1: Check file exists
    if not os.path.exists(spec_file):
        print(f"ERROR: Spec file '{spec_file}' not found.")
        sys.exit(1)

    # Step 2: Load and parse spec
    print(f"Step 1: Loading spec file '{spec_file}'...")
    spec = load_spec(spec_file)
    info = extract_key_info(spec)

    print("Spec parsed successfully.\n")
    print("Extracted design info:")
    for key, value in info.items():
        print(f"{key}: {value}")
    print()

    # Step 3: Generate RTL
    print("Step 2: Generating RTL...")
    rtl_code = generate_rtl_from_spec(info)

    # Use module name from spec for output filename
    module_name = info["module_name"]
    rtl_file = os.path.join(output_dir, f"{module_name}.v")

    os.makedirs(output_dir, exist_ok=True)
    save_rtl_to_file(rtl_code, rtl_file)
    print(f"RTL saved to {rtl_file}\n")

    # Step 4: Run simulation
    print("Step 3: Running simulation...")
    result = compile_and_run_sim(rtl_file, tb_file)

    # Step 5: Report result
    if not result["compile_success"]:
        print("Compilation FAILED.\n")
        print(result["stderr"])
        sys.exit(1)

    print("\nSimulation output:")
    print(result["stdout"])

    if result["stderr"]:
        print("Simulation stderr:")
        print(result["stderr"])

    if "Test PASSED" in result["stdout"]:
        print("\n=== FINAL RESULT: PASS ===")
    else:
        print("\n=== FINAL RESULT: FAIL ===")


if __name__ == "__main__":
    main()
