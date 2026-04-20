from dataclasses import dataclass
from typing import Dict

import torch
from torch import nn
from torch.utils.data import DataLoader, TensorDataset

from src.utils.logging import get_logger


LOGGER = get_logger(__name__)


@dataclass
class TrainResult:
    best_loss: float
    best_state: Dict[str, torch.Tensor]
    history: Dict[str, list]


def _build_loss(loss_type: str) -> nn.Module:
    if loss_type in {"L1", "weighted_L1"}:
        return nn.L1Loss(reduction="none")
    if loss_type in {"MSE", "weighted_MSE"}:
        return nn.MSELoss(reduction="none")
    raise ValueError(f"Unsupported loss: {loss_type}")


def _compute_weights(x: torch.Tensor, function_name: str) -> torch.Tensor:
    if function_name == "sqrt_neg2_log":
        x_norm = (x - x.min()) / (x.max() - x.min() + 1e-8)
        return 1.0 + 4.0 * (1.0 - x_norm)
    return torch.ones_like(x)


def train(
    model: nn.Module,
    x_train: torch.Tensor,
    y_train: torch.Tensor,
    function_name: str,
    epochs: int,
    batch_size: int,
    loss_type: str,
    lr: float,
) -> TrainResult:
    dataset = TensorDataset(x_train, y_train)
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="min", patience=200, factor=0.5
    )
    loss_fn = _build_loss(loss_type)

    best_loss = float("inf")
    best_state = None
    history = {"loss": []}
    patience = 500
    patience_counter = 0

    log_interval = max(1, epochs // 20)
    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        for xb, yb in loader:
            optimizer.zero_grad(set_to_none=True)
            pred = model(xb)
            loss_raw = loss_fn(pred, yb)
            if loss_type.startswith("weighted"):
                weights = _compute_weights(xb, function_name)
                loss_raw = loss_raw * weights
            loss = loss_raw.mean()
            if torch.isnan(loss) or torch.isinf(loss):
                raise RuntimeError("NaN/Inf detected in loss")
            loss.backward()
            grad_norm = torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=10.0)
            if torch.isnan(grad_norm) or torch.isinf(grad_norm):
                raise RuntimeError("NaN/Inf detected in gradients")
            optimizer.step()
            epoch_loss += loss.item() * xb.size(0)

        epoch_loss /= len(dataset)
        history["loss"].append(epoch_loss)
        scheduler.step(epoch_loss)

        if epoch_loss + 1e-8 < best_loss:
            best_loss = epoch_loss
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
            patience_counter = 0
        else:
            patience_counter += 1
            if patience_counter >= patience:
                LOGGER.info("Early stopping at epoch %d (best_loss=%.6f)", epoch, best_loss)
                break

        if epoch % log_interval == 0 or epoch == epochs - 1:
            LOGGER.info("Epoch %d/%d | loss=%.6f | best=%.6f | lr=%.6f", epoch, epochs, epoch_loss, best_loss, optimizer.param_groups[0]["lr"])

    if best_state is None:
        raise RuntimeError("Training failed to produce a best state")
    LOGGER.info("Training completed. Best loss: %.6f", best_loss)
    return TrainResult(best_loss=best_loss, best_state=best_state, history=history)
