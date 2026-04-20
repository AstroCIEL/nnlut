import numpy as np
import torch

from src.conversion.lut import extract_and_sort_breakpoints
from src.models.relu_net import SingleHiddenReLUNet


def test_breakpoints_sorted():
    model = SingleHiddenReLUNet(hidden_size=2)
    with torch.no_grad():
        model.fc1.weight.copy_(torch.tensor([[1.0], [1.0]]))
        model.fc1.bias.copy_(torch.tensor([-0.8, -0.2]))
    d_sorted, _, _ = extract_and_sort_breakpoints(model, (0.0, 1.0), num_entries=3)
    assert np.allclose(d_sorted, np.array([0.2, 0.8]))
import numpy as np
import torch

from src.conversion.lut import extract_and_sort_breakpoints
from src.models.relu_net import SingleHiddenReLUNet


def test_breakpoints_sorted():
    model = SingleHiddenReLUNet(hidden_size=2)
    with torch.no_grad():
        model.fc1.weight.copy_(torch.tensor([[1.0], [1.0]]))
        model.fc1.bias.copy_(torch.tensor([-0.8, -0.2]))
    d_sorted, _, _ = extract_and_sort_breakpoints(model, (0.0, 1.0), num_entries=3)
    assert np.allclose(d_sorted, np.array([0.2, 0.8]))
