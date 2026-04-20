import csv
import json
import os
from typing import Dict, List


def export_json(path: str, payload: Dict) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def export_csv(path: str, breakpoints: List[float], slopes: List[float], intercepts: List[float]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["type", "index", "value"])
        for i, v in enumerate(breakpoints):
            writer.writerow(["breakpoint", i, v])
        for i, v in enumerate(slopes):
            writer.writerow(["slope", i, v])
        for i, v in enumerate(intercepts):
            writer.writerow(["intercept", i, v])


def export_header(path: str, metadata: Dict) -> None:
    lines = []
    lines.append("// Auto-generated NN-LUT parameters")
    lines.append(f"#define NUM_ENTRIES {metadata['num_entries']}")
    lines.append(f"#define DOMAIN_MIN {metadata['domain_min']}")
    lines.append(f"#define DOMAIN_MAX {metadata['domain_max']}")
    lines.append(f"#define INPUT_FORMAT \"{metadata['input_format']}\"")
    lines.append(f"#define SLOPE_FORMAT \"{metadata['slope_format']}\"")
    lines.append(f"#define INTERCEPT_FORMAT \"{metadata['intercept_format']}\"")
    lines.append(f"#define ROUNDING_MODE \"{metadata['rounding_mode']}\"")
    lines.append(f"#define SATURATION_MODE \"{metadata['saturation_mode']}\"")
    lines.append("")
    lines.append("static const float BREAKPOINTS[] = {")
    lines.append(", ".join(str(v) for v in metadata["breakpoints"]))
    lines.append("};")
    lines.append("static const float SLOPES[] = {")
    lines.append(", ".join(str(v) for v in metadata["slopes"]))
    lines.append("};")
    lines.append("static const float INTERCEPTS[] = {")
    lines.append(", ".join(str(v) for v in metadata["intercepts"]))
    lines.append("};")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def export_all(output_dir: str, formats: List[str], payload: Dict) -> None:
    os.makedirs(output_dir, exist_ok=True)
    if "json" in formats:
        export_json(os.path.join(output_dir, "lut_params.json"), payload)
    if "csv" in formats:
        if all(k in payload for k in ["breakpoints", "slopes", "intercepts"]):
            export_csv(
                os.path.join(output_dir, "lut_params.csv"),
                payload["breakpoints"],
                payload["slopes"],
                payload["intercepts"],
            )
    if "header" in formats:
        required = {
            "num_entries",
            "domain_min",
            "domain_max",
            "input_format",
            "slope_format",
            "intercept_format",
            "rounding_mode",
            "saturation_mode",
            "breakpoints",
            "slopes",
            "intercepts",
        }
        if required.issubset(payload.keys()):
            export_header(os.path.join(output_dir, "lut_params.h"), payload)
