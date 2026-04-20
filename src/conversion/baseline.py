from typing import Tuple

import numpy as np

from src.conversion.lut import LutParams


def uniform_baseline(
    func,
    domain: Tuple[float, float],
    num_entries: int,
) -> LutParams:
    breakpoints = np.linspace(domain[0], domain[1], num_entries + 1)[1:-1]
    all_points = [domain[0]] + breakpoints.tolist() + [domain[1]]
    slopes = []
    intercepts = []
    for i in range(len(all_points) - 1):
        x0 = all_points[i]
        x1 = all_points[i + 1]
        y0 = func(np.array([x0]))[0]
        y1 = func(np.array([x1]))[0]
        slope = (y1 - y0) / (x1 - x0 + 1e-12)
        intercept = y0 - slope * x0
        slopes.append(float(slope))
        intercepts.append(float(intercept))
    return LutParams(breakpoints=breakpoints.tolist(), slopes=slopes, intercepts=intercepts)
