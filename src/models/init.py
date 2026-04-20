from typing import Tuple

import numpy as np
import torch

from src.models.relu_net import SingleHiddenReLUNet


def init_parameters(
    model: SingleHiddenReLUNet,
    policy: str,
    domain: Tuple[float, float],
) -> None:
    with torch.no_grad():
        if policy == "random_unconstrained":
            torch.nn.init.normal_(model.fc1.weight, mean=0.0, std=0.5)
            torch.nn.init.normal_(model.fc1.bias, mean=0.0, std=0.5)
            torch.nn.init.normal_(model.fc2.weight, mean=0.0, std=0.5)
            return
        if policy == "sign_constrained":
            w = torch.randn_like(model.fc1.weight)
            model.fc1.weight.copy_(torch.abs(w))
            b = torch.randn_like(model.fc1.bias)
            model.fc1.bias.copy_(b)
            m = torch.randn_like(model.fc2.weight)
            model.fc2.weight.copy_(m)
            return
        if policy == "breakpoint_oriented":
            hidden = model.fc1.weight.shape[0]
            d_min, d_max = domain
            breakpoints = np.linspace(d_min, d_max, hidden + 2)[1:-1]
            n = torch.ones(hidden, 1)
            b = -torch.from_numpy(breakpoints.astype(np.float32))
            model.fc1.weight.copy_(n)
            model.fc1.bias.copy_(b)
            torch.nn.init.normal_(model.fc2.weight, mean=0.0, std=0.1)
            return
        raise ValueError(f"Unsupported init policy: {policy}")
