import subprocess

def compile_and_run_sim(rtl_file, tb_file, out_file="sim.out"):
    compile_cmd = ["iverilog", "-o", out_file, rtl_file, tb_file]
    run_cmd = ["vvp", out_file]

    print("Compiling...")
    compile_result = subprocess.run(compile_cmd, capture_output=True, text=True)

    if compile_result.returncode != 0:
        return {
            "compile_success": False,
            "run_success": False,
            "stdout": compile_result.stdout,
            "stderr": compile_result.stderr,
        }

    print("Compilation successful.\n")
    print("Running simulation...")
    run_result = subprocess.run(run_cmd, capture_output=True, text=True)

    return {
        "compile_success": True,
        "run_success": run_result.returncode == 0,
        "stdout": run_result.stdout,
        "stderr": run_result.stderr,
    }


if __name__ == "__main__":
    result = compile_and_run_sim("outputs/seq_detector_0011.v", "iclad_seq_detector_tb.v")

    if not result["compile_success"]:
        print("Compilation failed:")
        print(result["stderr"])
    else:
        print(result["stdout"])
        if result["stderr"]:
            print(result["stderr"])
