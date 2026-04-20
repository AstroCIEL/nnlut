import os
from typing import Dict


def write_report(output_dir: str, metadata: Dict, metrics: Dict) -> None:
    os.makedirs(output_dir, exist_ok=True)
    lines = []
    lines.append("# NN-LUT 评估报告")
    lines.append("")
    lines.append("## 函数信息")
    lines.append(f"- function_name: {metadata['function_name']}")
    lines.append(f"- domain: [{metadata['domain_min']}, {metadata['domain_max']}]")
    lines.append(f"- num_entries: {metadata['num_entries']}")
    lines.append("")
    lines.append("## 训练配置")
    lines.append(f"- optimizer: {metadata['optimizer']}")
    lines.append(f"- learning_rate: {metadata['learning_rate']}")
    lines.append(f"- epochs: {metadata['epochs']}")
    lines.append(f"- loss_type: {metadata['loss_type']}")
    lines.append(f"- seed: {metadata['seed']}")
    lines.append("")
    lines.append("## 全局指标")
    for k, v in metrics["global"].items():
        lines.append(f"- {k}: {v}")
    lines.append("")
    lines.append("## 区域指标")
    for name, region in metrics.get("regions", {}).items():
        lines.append(f"### {name}")
        for k, v in region.items():
            lines.append(f"- {k}: {v}")
    lines.append("")
    lines.append("## 分段误差统计")
    for seg in metrics.get("segments", []):
        lines.append(f"- seg{seg['seg']}: mae={seg['mae']}, maxae={seg['maxae']}")
    lines.append("")
    lines.append("## 风险提示")
    lines.append("- 注意接近边界区域的误差放大")
    lines.append("- 量化后需复验是否出现溢出或区间选择错误")
    lines.append("")
    report_path = os.path.join(output_dir, "report.md")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
