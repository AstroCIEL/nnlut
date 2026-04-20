import numpy as np
import pytest

from src.functions import get_function


def test_mish_domain_ok():
    spec = get_function("mish")
    spec.domain_check((-8.0, 8.0))


def test_sqrt_neg2_log_domain_fail():
    spec = get_function("sqrt_neg2_log")
    with pytest.raises(ValueError):
        spec.domain_check((0.0, 1.0))


def test_sqrt_neg2_log_value():
    spec = get_function("sqrt_neg2_log")
    x = np.array([1.0], dtype=np.float32)
    y = spec.func(x)
    assert np.isclose(y[0], 0.0)
