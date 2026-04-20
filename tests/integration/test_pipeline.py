import os
import subprocess
import tempfile

import yaml


def _run_config(function_name: str, domain, tmpdir: str) -> None:
    config = {
        "function_name": function_name,
        "domain": list(domain),
        "num_entries": 4,
        "train_dataset_size": 2000,
        "eval_dataset_size": 2000,
        "output_dir": os.path.join(tmpdir, function_name),
        "seed": 123,
        "optimizer": "Adam",
        "learning_rate": 0.01,
        "epochs": 50,
        "batch_size": 256,
        "loss_type": "L1",
        "init_policy": "random_unconstrained",
        "sampling": {"strategy": "uniform"},
        "quantization": {"enabled": False},
        "plot_enabled": False,
        "export_formats": ["json"],
    }
    config_path = os.path.join(tmpdir, f"{function_name}.yaml")
    with open(config_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(config, f)
    subprocess.run(
        ["python", "-m", "src.cli", "--config", config_path],
        check=True,
        cwd=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")),
    )


def test_mish_pipeline():
    with tempfile.TemporaryDirectory() as tmpdir:
        _run_config("mish", [-4.0, 4.0], tmpdir)


def test_sqrt_neg2_log_pipeline():
    with tempfile.TemporaryDirectory() as tmpdir:
        _run_config("sqrt_neg2_log", [0.001, 1.0], tmpdir)
