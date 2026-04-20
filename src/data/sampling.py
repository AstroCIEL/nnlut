from typing import List, Tuple

import numpy as np


def uniform_sample(domain: Tuple[float, float], size: int) -> np.ndarray:
    return np.random.uniform(domain[0], domain[1], size=size)


def log_dense_sample(domain: Tuple[float, float], size: int) -> np.ndarray:
    log_min = np.log(domain[0])
    log_max = np.log(domain[1])
    return np.exp(np.random.uniform(log_min, log_max, size=size))


def dense_ranges_sample(
    domain: Tuple[float, float],
    dense_ranges: List[Tuple[float, float]],
    size: int,
) -> np.ndarray:
    if not dense_ranges:
        return uniform_sample(domain, size)
    samples_per_range = max(1, size // len(dense_ranges))
    samples = []
    for r in dense_ranges:
        r_min = max(domain[0], r[0])
        r_max = min(domain[1], r[1])
        if r_min >= r_max:
            continue
        samples.append(np.random.uniform(r_min, r_max, size=samples_per_range))
    if not samples:
        return uniform_sample(domain, size)
    return np.concatenate(samples)[:size]
