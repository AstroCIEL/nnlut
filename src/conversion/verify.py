from typing import Tuple

import numpy as np
import torch

from src.conversion.lut import LutParams, lut_eval


def verify_conversion(
    model: torch.nn.Module,
    params: LutParams,
    domain: Tuple[float, float],
    samples: int = 10000,
    tolerance: float = 1e-2,
) -> None:
    x = np.random.uniform(domain[0], domain[1], size=samples).astype(np.float32)
    with torch.no_grad():
        nn_pred = model(torch.from_numpy(x).unsqueeze(1)).squeeze(1).numpy()
    lut_pred = lut_eval(x, params, domain)
    diff = np.max(np.abs(nn_pred - lut_pred))
    if diff > tolerance:
        raise RuntimeError(f"NN->LUT 转换误差超阈值: {diff} > {tolerance}")
