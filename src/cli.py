import argparse
import os
from typing import Dict

import numpy as np
import torch

from src.config import load_config
from src.conversion.baseline import uniform_baseline
from src.conversion.lut import LutParams, nn_to_lut
from src.conversion.verify import verify_conversion
from src.data.dataset import build_dataset
from src.evaluation.metrics import evaluate
from src.export.exporter import export_all
from src.functions import get_function
from src.models.init import init_parameters
from src.models.relu_net import SingleHiddenReLUNet
from src.quantization.quantize import dequantize_array, quantize_lut
from src.reporting.plots import plot_curves
from src.reporting.report import write_report
from src.utils.logging import setup_logging
from src.utils.seed import set_seed


def _build_metadata(cfg, params: LutParams) -> Dict:
    q_cfg = cfg.quantization
    return {
        "function_name": cfg.function_name,
        "domain_min": cfg.domain[0],
        "domain_max": cfg.domain[1],
        "num_entries": cfg.num_entries,
        "breakpoints": params.breakpoints,
        "slopes": params.slopes,
        "intercepts": params.intercepts,
        "input_format": f"Q{q_cfg.total_bits - q_cfg.frac_bits}.{q_cfg.frac_bits}"
        if q_cfg.enabled
        else "FP32",
        "slope_format": f"Q{q_cfg.total_bits - q_cfg.frac_bits}.{q_cfg.frac_bits}"
        if q_cfg.enabled
        else "FP32",
        "intercept_format": f"Q{q_cfg.total_bits - q_cfg.frac_bits}.{q_cfg.frac_bits}"
        if q_cfg.enabled
        else "FP32",
        "rounding_mode": q_cfg.rounding,
        "saturation_mode": q_cfg.saturation,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Path to YAML config")
    args = parser.parse_args()

    setup_logging()
    cfg = load_config(args.config)
    set_seed(cfg.seed)

    func_spec = get_function(cfg.function_name)
    func_spec.domain_check(cfg.domain)

    x_train, y_train = build_dataset(
        cfg.domain, cfg.train_dataset_size, cfg.sampling, cfg.function_name, func_spec.func
    )
    x_eval, y_eval = build_dataset(
        cfg.domain, cfg.eval_dataset_size, cfg.sampling, cfg.function_name, func_spec.func
    )

    model = SingleHiddenReLUNet(hidden_size=cfg.num_entries - 1)
    init_parameters(model, cfg.init_policy, cfg.domain)

    from src.training.trainer import train

    train_result = train(
        model=model,
        x_train=x_train,
        y_train=y_train,
        function_name=cfg.function_name,
        epochs=cfg.epochs,
        batch_size=cfg.batch_size,
        loss_type=cfg.loss_type,
        lr=cfg.learning_rate,
    )
    model.load_state_dict(train_result.best_state)

    params = nn_to_lut(model, cfg.domain, cfg.num_entries)
    verify_conversion(model, params, cfg.domain, tolerance=cfg.verify_tolerance)

    x_eval_np = x_eval.squeeze(1).numpy()
    y_eval_np = y_eval.squeeze(1).numpy()
    metrics = evaluate(cfg.function_name, x_eval_np, y_eval_np, params, cfg.domain)

    baseline_params = uniform_baseline(func_spec.func, cfg.domain, cfg.num_entries)
    baseline_metrics = evaluate(
        cfg.function_name, x_eval_np, y_eval_np, baseline_params, cfg.domain
    )

    output_dir = cfg.output_dir
    os.makedirs(output_dir, exist_ok=True)

    if cfg.plot_enabled:
        order = np.argsort(x_eval_np)
        plot_curves(
            output_dir,
            x_eval_np[order],
            y_eval_np[order],
            params,
            cfg.domain,
        )

    metadata = _build_metadata(cfg, params)
    metadata.update(
        {
            "optimizer": cfg.optimizer,
            "learning_rate": cfg.learning_rate,
            "epochs": cfg.epochs,
            "loss_type": cfg.loss_type,
            "seed": cfg.seed,
            "best_loss": train_result.best_loss,
            "baseline_metrics": baseline_metrics,
            "metrics": metrics,
        }
    )

    export_all(output_dir, cfg.export_formats, metadata)
    write_report(output_dir, metadata, metrics)

    if cfg.quantization.enabled:
        d_q, s_q, t_q = quantize_lut(
            params.breakpoints, params.slopes, params.intercepts, cfg.quantization
        )
        q_params = LutParams(
            breakpoints=dequantize_array(d_q.values, cfg.quantization).tolist(),
            slopes=dequantize_array(s_q.values, cfg.quantization).tolist(),
            intercepts=dequantize_array(t_q.values, cfg.quantization).tolist(),
        )
        quant_metrics = evaluate(
            cfg.function_name, x_eval_np, y_eval_np, q_params, cfg.domain
        )
        quant_payload = {
            "breakpoints": d_q.values,
            "slopes": s_q.values,
            "intercepts": t_q.values,
            "overflow": {
                "breakpoints": d_q.overflow,
                "slopes": s_q.overflow,
                "intercepts": t_q.overflow,
            },
            "quant_metrics": quant_metrics,
        }
        export_all(os.path.join(output_dir, "quantized"), cfg.export_formats, quant_payload)


if __name__ == "__main__":
    main()
