from typing import Tuple

import numpy as np
import torch

from src.config import SamplingConfig
from src.data.sampling import dense_ranges_sample, log_dense_sample, uniform_sample


def generate_samples(
    domain: Tuple[float, float],
    size: int,
    sampling: SamplingConfig,
    function_name: str,
) -> np.ndarray:
    if sampling.strategy == "uniform":
        return uniform_sample(domain, size)
    if sampling.strategy == "hybrid":
        base_size = size
        if function_name == "sqrt_neg2_log" and sampling.log_dense:
            log_size = int(size * sampling.log_dense_ratio)
            lin_size = size - log_size
            log_part = log_dense_sample(domain, log_size)
            lin_part = uniform_sample(domain, lin_size)
            return np.concatenate([log_part, lin_part])
        if sampling.dense_ranges:
            dense_size = int(size * 0.5)
            uniform_size = size - dense_size
            dense_part = dense_ranges_sample(domain, sampling.dense_ranges, dense_size)
            uniform_part = uniform_sample(domain, uniform_size)
            return np.concatenate([dense_part, uniform_part])[:base_size]
        return uniform_sample(domain, size)
    raise ValueError(f"Unsupported sampling strategy: {sampling.strategy}")


def build_dataset(
    domain: Tuple[float, float],
    size: int,
    sampling: SamplingConfig,
    function_name: str,
    func,
) -> Tuple[torch.Tensor, torch.Tensor]:
    x = generate_samples(domain, size, sampling, function_name)
    y = func(x)
    x_t = torch.from_numpy(x.astype(np.float32)).unsqueeze(1)
    y_t = torch.from_numpy(y.astype(np.float32)).unsqueeze(1)
    return x_t, y_t
