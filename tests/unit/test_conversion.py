import numpy as np
import torch

from src.conversion.lut import lut_eval, nn_to_lut
from src.models.relu_net import SingleHiddenReLUNet


def test_nn_to_lut_simple():
    model = SingleHiddenReLUNet(hidden_size=1)
    with torch.no_grad():
        model.fc1.weight.copy_(torch.tensor([[1.0]]))
        model.fc1.bias.copy_(torch.tensor([0.0]))
        model.fc2.weight.copy_(torch.tensor([[2.0]]))
    params = nn_to_lut(model, (-1.0, 1.0), num_entries=2)
    x = np.array([-1.0, 0.0, 1.0], dtype=np.float32)
    y = lut_eval(x, params, (-1.0, 1.0))
    assert np.allclose(y, np.array([0.0, 0.0, 2.0]), atol=1e-5)
import numpy as np
import torch

from src.conversion.lut import lut_eval, nn_to_lut
from src.models.relu_net import SingleHiddenReLUNet


def test_nn_to_lut_simple():
    model = SingleHiddenReLUNet(hidden_size=1)
    with torch.no_grad():
        model.fc1.weight.copy_(torch.tensor([[1.0]]))
        model.fc1.bias.copy_(torch.tensor([0.0]))
        model.fc2.weight.copy_(torch.tensor([[2.0]]))
    params = nn_to_lut(model, (-1.0, 1.0), num_entries=2)
    x = np.array([-1.0, 0.0, 1.0], dtype=np.float32)
    y = lut_eval(x, params, (-1.0, 1.0))
    assert np.allclose(y, np.array([0.0, 0.0, 2.0]), atol=1e-5)
