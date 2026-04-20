from typing import Tuple

import numpy as np

from .registry import FunctionSpec, register


def _stable_softplus(x: np.ndarray) -> np.ndarray:
    return np.log1p(np.exp(-np.abs(x))) + np.maximum(x, 0.0)


def mish(x: np.ndarray) -> np.ndarray:
    return x * np.tanh(_stable_softplus(x))


def mish_derivative(x: np.ndarray) -> np.ndarray:
    """mish函数的导数: mish'(x) = tanh(softplus(x)) + x * sech²(softplus(x)) * sigmoid(x)"""
    sp = _stable_softplus(x)
    tanh_sp = np.tanh(sp)
    # sech²(y) = 1/cosh²(y)
    sech2_sp = 1.0 / (np.cosh(sp) ** 2)
    # sigmoid(x) = 1/(1+exp(-x))
    sigmoid_x = 1.0 / (1.0 + np.exp(-np.abs(x)))
    # 对于负数，sigmoid需要修正
    sigmoid_x = np.where(x >= 0, sigmoid_x, 1.0 - sigmoid_x)

    return tanh_sp + x * sech2_sp * sigmoid_x


def sqrt_neg2_log(x: np.ndarray) -> np.ndarray:
    if np.any(x <= 0):
        raise ValueError("sqrt_neg2_log requires x > 0")
    return np.sqrt(-2.0 * np.log(x))


def _check_mish_domain(domain: Tuple[float, float]) -> None:
    if domain[0] >= domain[1]:
        raise ValueError("mish requires domain_min < domain_max")


def _check_sqrt_neg2_log_domain(domain: Tuple[float, float]) -> None:
    if domain[0] <= 0 or domain[1] > 1.0:
        raise ValueError("sqrt_neg2_log requires 0 < domain <= 1")
    if domain[0] >= domain[1]:
        raise ValueError("sqrt_neg2_log requires domain_min < domain_max")


def _check_mish_derivative_domain(domain: Tuple[float, float]) -> None:
    if domain[0] >= domain[1]:
        raise ValueError("mish_derivative requires domain_min < domain_max")


register(
    FunctionSpec(
        name="mish",
        func=mish,
        domain_check=_check_mish_domain,
        default_domain=(-8.0, 8.0),
    )
)

register(
    FunctionSpec(
        name="sqrt_neg2_log",
        func=sqrt_neg2_log,
        domain_check=_check_sqrt_neg2_log_domain,
        default_domain=(1e-4, 1.0),
    )
)

register(
    FunctionSpec(
        name="mish_derivative",
        func=mish_derivative,
        domain_check=_check_mish_derivative_domain,
        default_domain=(-8.0, 8.0),
    )
)
