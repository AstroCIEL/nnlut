from typing import Dict, List, Tuple

import numpy as np

from src.conversion.lut import LutParams, lut_eval


def _basic_metrics(y_true: np.ndarray, y_pred: np.ndarray) -> Dict[str, float]:
    diff = y_true - y_pred
    mae = float(np.mean(np.abs(diff)))
    rmse = float(np.sqrt(np.mean(diff**2)))
    maxae = float(np.max(np.abs(diff)))
    denom = np.maximum(np.abs(y_true), 1e-6)
    mape = float(np.mean(np.abs(diff) / denom))
    return {"mae": mae, "rmse": rmse, "maxae": maxae, "mape": mape}


def _segment_stats(
    x: np.ndarray, y_true: np.ndarray, y_pred: np.ndarray, breakpoints: List[float]
) -> List[Dict[str, float]]:
    breakpoints_arr = np.array(breakpoints, dtype=np.float32)
    seg_idx = np.searchsorted(breakpoints_arr, x, side="right")
    stats = []
    for i in range(len(breakpoints) + 1):
        mask = seg_idx == i
        if not np.any(mask):
            stats.append({"seg": i, "mae": 0.0, "maxae": 0.0})
            continue
        diff = y_true[mask] - y_pred[mask]
        stats.append(
            {
                "seg": i,
                "mae": float(np.mean(np.abs(diff))),
                "maxae": float(np.max(np.abs(diff))),
            }
        )
    return stats


def _special_regions(function_name: str, domain: Tuple[float, float]) -> List[Tuple[str, Tuple[float, float]]]:
    if function_name == "sqrt_neg2_log":
        x_min = domain[0]
        return [
            ("near_lower", (x_min, min(4 * x_min, domain[1]))),
            ("low", (min(4 * x_min, domain[1]), min(1e-2, domain[1]))),
            ("mid", (min(1e-2, domain[1]), min(1e-1, domain[1]))),
            ("high", (min(1e-1, domain[1]), domain[1])),
        ]
    if function_name == "mish":
        return [
            ("neg_sat", (-8.0, -4.0)),
            ("transition", (-4.0, 4.0)),
            ("pos_linear", (4.0, 8.0)),
        ]
    return []


def evaluate(
    function_name: str,
    x: np.ndarray,
    y_true: np.ndarray,
    params: LutParams,
    domain: Tuple[float, float],
) -> Dict:
    y_pred = lut_eval(x, params, domain)
    results = {"global": _basic_metrics(y_true, y_pred)}
    results["segments"] = _segment_stats(x, y_true, y_pred, params.breakpoints)

    region_stats = {}
    for name, (a, b) in _special_regions(function_name, domain):
        mask = (x >= a) & (x <= b)
        if np.any(mask):
            region_stats[name] = _basic_metrics(y_true[mask], y_pred[mask])
    results["regions"] = region_stats
    return results
