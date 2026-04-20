from dataclasses import dataclass
from typing import List, Tuple

import numpy as np

from src.config import QuantizationConfig


@dataclass
class QuantizedArray:
    values: List[int]
    overflow: bool


def _quantize_array(arr: np.ndarray, cfg: QuantizationConfig) -> QuantizedArray:
    scale = 2**cfg.frac_bits
    scaled = arr * scale
    if cfg.rounding == "round":
        q = np.round(scaled)
    elif cfg.rounding == "floor":
        q = np.floor(scaled)
    else:
        q = np.round(scaled)
    if cfg.signed:
        min_q = -(2 ** (cfg.total_bits - 1))
        max_q = 2 ** (cfg.total_bits - 1) - 1
    else:
        min_q = 0
        max_q = 2**cfg.total_bits - 1
    overflow = np.any(q < min_q) or np.any(q > max_q)
    if cfg.saturation == "saturate":
        q = np.clip(q, min_q, max_q)
    return QuantizedArray(values=[int(v) for v in q], overflow=bool(overflow))


def dequantize_array(values: List[int], cfg: QuantizationConfig) -> np.ndarray:
    scale = 2**cfg.frac_bits
    return np.array(values, dtype=np.float32) / scale


def quantize_lut(
    breakpoints: List[float],
    slopes: List[float],
    intercepts: List[float],
    cfg: QuantizationConfig,
) -> Tuple[QuantizedArray, QuantizedArray, QuantizedArray]:
    d_q = _quantize_array(np.array(breakpoints, dtype=np.float32), cfg)
    s_q = _quantize_array(np.array(slopes, dtype=np.float32), cfg)
    t_q = _quantize_array(np.array(intercepts, dtype=np.float32), cfg)
    return d_q, s_q, t_q
