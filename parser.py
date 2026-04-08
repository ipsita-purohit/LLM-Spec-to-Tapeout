import yaml

def load_spec(file_path):
    with open(file_path, "r") as f:
        return yaml.safe_load(f)

def extract_key_info(spec):
    top_key = list(spec.keys())[0]
    design = spec[top_key]

    return {
        "module_name": top_key,
        "description": design.get("description"),
        "clock_period": design.get("clock_period"),
        "ports": design.get("ports"),
        "module_signature": design.get("module_signature"),
        "sequence_to_detect": design.get("sequence_to_detect"),
        "sample_input": design.get("sample_input"),
        "sample_output": design.get("sample_output"),
    }

if __name__ == "__main__":
    spec = load_spec("p1.yaml")
    info = extract_key_info(spec)

    print("\nExtracted Info:\n")
    for k, v in info.items():
        print(f"{k}: {v}\n")
