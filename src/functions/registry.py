from dataclasses import dataclass
from typing import Callable, Dict, Tuple

import numpy as np


@dataclass
class FunctionSpec:
    name: str
    func: Callable[[np.ndarray], np.ndarray]
    domain_check: Callable[[Tuple[float, float]], None]
    default_domain: Tuple[float, float]


_REGISTRY: Dict[str, FunctionSpec] = {}


def register(spec: FunctionSpec) -> None:
    _REGISTRY[spec.name] = spec


def get_function(name: str) -> FunctionSpec:
    if name not in _REGISTRY:
        raise KeyError(f"Unsupported function: {name}")
    return _REGISTRY[name]


def list_functions() -> Dict[str, FunctionSpec]:
    return dict(_REGISTRY)
