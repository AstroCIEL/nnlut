from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import yaml


SUPPORTED_EXPORTS = {"json", "csv", "header"}
SUPPORTED_LOSSES = {"L1", "MSE", "weighted_L1", "weighted_MSE"}
SUPPORTED_OPTIMIZERS = {"Adam"}
SUPPORTED_INIT = {"random_unconstrained", "sign_constrained", "breakpoint_oriented"}


@dataclass
class SamplingConfig:
    strategy: str = "uniform"
    dense_ranges: List[Tuple[float, float]] = field(default_factory=list)
    log_dense: bool = False
    log_dense_ratio: float = 0.5


@dataclass
class QuantizationConfig:
    enabled: bool = False
    total_bits: int = 16
    frac_bits: int = 8
    rounding: str = "round"
    saturation: str = "saturate"
    signed: bool = True


@dataclass
class Config:
    function_name: str
    domain: Tuple[float, float]
    num_entries: int
    train_dataset_size: int
    eval_dataset_size: int
    output_dir: str
    seed: int = 42
    optimizer: str = "Adam"
    learning_rate: float = 0.001
    epochs: int = 3000
    batch_size: int = 1024
    loss_type: str = "L1"
    init_policy: str = "random_unconstrained"
    sampling: SamplingConfig = field(default_factory=SamplingConfig)
    quantization: QuantizationConfig = field(default_factory=QuantizationConfig)
    plot_enabled: bool = True
    export_formats: List[str] = field(default_factory=lambda: ["json"])
    verify_tolerance: float = 1e-3  # LUT转换验证阈值

    def validate(self) -> None:
        if self.num_entries < 2:
            raise ValueError("num_entries must be >= 2")
        if len(self.domain) != 2:
            raise ValueError("domain must have two values")
        domain_min, domain_max = self.domain
        if domain_min >= domain_max:
            raise ValueError("domain_min must be < domain_max")
        if self.train_dataset_size <= 0 or self.eval_dataset_size <= 0:
            raise ValueError("dataset sizes must be > 0")
        if self.batch_size <= 0:
            raise ValueError("batch_size must be > 0")
        if self.loss_type not in SUPPORTED_LOSSES:
            raise ValueError(f"loss_type must be one of {sorted(SUPPORTED_LOSSES)}")
        if self.optimizer not in SUPPORTED_OPTIMIZERS:
            raise ValueError(f"optimizer must be one of {sorted(SUPPORTED_OPTIMIZERS)}")
        if self.init_policy not in SUPPORTED_INIT:
            raise ValueError(f"init_policy must be one of {sorted(SUPPORTED_INIT)}")
        if not set(self.export_formats).issubset(SUPPORTED_EXPORTS):
            raise ValueError(f"export_formats must be subset of {sorted(SUPPORTED_EXPORTS)}")
        if self.function_name == "sqrt_neg2_log":
            if not (0.0 < domain_min <= 1.0 and 0.0 < domain_max <= 1.0):
                raise ValueError("sqrt_neg2_log requires 0 < domain <= 1")

    def to_dict(self) -> Dict:
        return {
            "function_name": self.function_name,
            "domain": list(self.domain),
            "num_entries": self.num_entries,
            "train_dataset_size": self.train_dataset_size,
            "eval_dataset_size": self.eval_dataset_size,
            "output_dir": self.output_dir,
            "seed": self.seed,
            "optimizer": self.optimizer,
            "learning_rate": self.learning_rate,
            "epochs": self.epochs,
            "batch_size": self.batch_size,
            "loss_type": self.loss_type,
            "init_policy": self.init_policy,
            "sampling": {
                "strategy": self.sampling.strategy,
                "dense_ranges": [list(r) for r in self.sampling.dense_ranges],
                "log_dense": self.sampling.log_dense,
                "log_dense_ratio": self.sampling.log_dense_ratio,
            },
            "quantization": {
                "enabled": self.quantization.enabled,
                "total_bits": self.quantization.total_bits,
                "frac_bits": self.quantization.frac_bits,
                "rounding": self.quantization.rounding,
                "saturation": self.quantization.saturation,
                "signed": self.quantization.signed,
            },
            "plot_enabled": self.plot_enabled,
            "export_formats": self.export_formats,
            "verify_tolerance": self.verify_tolerance,
        }


def load_config(path: str) -> Config:
    with open(path, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f)
    sampling_raw = raw.get("sampling", {}) or {}
    quant_raw = raw.get("quantization", {}) or {}
    sampling = SamplingConfig(
        strategy=sampling_raw.get("strategy", "uniform"),
        dense_ranges=[tuple(x) for x in sampling_raw.get("dense_ranges", [])],
        log_dense=bool(sampling_raw.get("log_dense", False)),
        log_dense_ratio=float(sampling_raw.get("log_dense_ratio", 0.5)),
    )
    quant = QuantizationConfig(
        enabled=bool(quant_raw.get("enabled", False)),
        total_bits=int(quant_raw.get("total_bits", 16)),
        frac_bits=int(quant_raw.get("frac_bits", 8)),
        rounding=str(quant_raw.get("rounding", "round")),
        saturation=str(quant_raw.get("saturation", "saturate")),
        signed=bool(quant_raw.get("signed", True)),
    )
    cfg = Config(
        function_name=str(raw["function_name"]),
        domain=(float(raw["domain"][0]), float(raw["domain"][1])),
        num_entries=int(raw["num_entries"]),
        train_dataset_size=int(raw["train_dataset_size"]),
        eval_dataset_size=int(raw["eval_dataset_size"]),
        output_dir=str(raw["output_dir"]),
        seed=int(raw.get("seed", 42)),
        optimizer=str(raw.get("optimizer", "Adam")),
        learning_rate=float(raw.get("learning_rate", 0.001)),
        epochs=int(raw.get("epochs", 3000)),
        batch_size=int(raw.get("batch_size", 1024)),
        loss_type=str(raw.get("loss_type", "L1")),
        init_policy=str(raw.get("init_policy", "random_unconstrained")),
        sampling=sampling,
        quantization=quant,
        plot_enabled=bool(raw.get("plot_enabled", True)),
        export_formats=list(raw.get("export_formats", ["json"])),
        verify_tolerance=float(raw.get("verify_tolerance", 1e-3)),
    )
    cfg.validate()
    return cfg
