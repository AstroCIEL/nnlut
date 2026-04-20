from dataclasses import dataclass
from typing import List, Tuple, TYPE_CHECKING

import numpy as np

try:
    import torch
    from src.models.relu_net import SingleHiddenReLUNet
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False
    torch = None
    if TYPE_CHECKING:
        from src.models.relu_net import SingleHiddenReLUNet


@dataclass
class LutParams:
    breakpoints: List[float]
    slopes: List[float]
    intercepts: List[float]


def extract_and_sort_breakpoints(
    model, domain: Tuple[float, float], num_entries: int
):
    if not HAS_TORCH:
        raise ImportError("PyTorch is required for extract_and_sort_breakpoints")
    w_all = model.fc1.weight.detach().cpu().numpy().flatten()
    b_all = model.fc1.bias.detach().cpu().numpy().flatten()
    valid = np.isfinite(w_all) & np.isfinite(b_all) & (w_all != 0)
    w = w_all[valid]
    b = b_all[valid]
    d = -b / w
    d = d[np.isfinite(d)]
    # 使用更宽松的边界检查，允许略微超出domain的断点
    eps = (domain[1] - domain[0]) * 0.01
    d = d[(d > domain[0] - eps) & (d < domain[1] + eps)]
    # 将断点clip到domain范围内
    d = np.clip(d, domain[0], domain[1])
    # 去重（避免断点过于接近）
    min_gap = (domain[1] - domain[0]) / (num_entries * 2)
    if len(d) > 1:
        d_sorted_unique = [d[0]]
        for val in d[1:]:
            if val - d_sorted_unique[-1] > min_gap:
                d_sorted_unique.append(val)
        d = np.array(d_sorted_unique)
    # 如果断点不足，插入均匀分布的断点
    needed = num_entries - 1
    if d.size < needed:
        uniform_breaks = np.linspace(domain[0], domain[1], needed + 2)[1:-1]
        # 合并现有断点和均匀断点，保留均匀断点填补空缺
        if d.size == 0:
            d = uniform_breaks
        else:
            # 在现有断点之间插入均匀断点
            combined = list(d)
            for ub in uniform_breaks:
                # 检查是否已有接近的断点
                if not any(abs(ub - existing) < min_gap for existing in combined):
                    combined.append(ub)
            combined.sort()
            # 取最接近domain范围的needed个
            if len(combined) > needed:
                # 保留边界附近的断点
                d = np.array(combined[:needed])
            else:
                d = np.array(combined)
                # 如果还是不够，填充均匀断点
                while len(d) < needed:
                    gaps = []
                    for i in range(len(d) - 1):
                        gaps.append((d[i+1] - d[i], i))
                    if gaps:
                        max_gap, idx = max(gaps)
                        new_bp = (d[idx] + d[idx+1]) / 2
                        d = np.insert(d, idx+1, new_bp)
                    else:
                        break
    # 最终排序并取前needed个
    d = np.sort(d)[:needed]

    order = np.argsort(d)
    d_sorted = d[order]

    # 根据断点位置重新匹配对应的权重（使用最近匹配）
    # 使用所有有效神经元，不限制在d范围内
    w_t = model.fc1.weight.detach().clone()[valid]
    b_t = model.fc1.bias.detach().clone()[valid]
    # 计算所有有效神经元的断点
    all_d = (-b_t.cpu().numpy().flatten() / w_t.cpu().numpy().flatten())
    # 为每个目标断点找到最近的神经元
    matched_indices = []
    for target_d in d_sorted:
        dist = np.abs(all_d - target_d)
        idx = int(np.argmin(dist))
        if idx not in matched_indices:
            matched_indices.append(idx)
    # 如果没有匹配够，再随机选一些
    available = list(range(len(all_d)))
    for idx in matched_indices:
        if idx in available:
            available.remove(idx)
    while len(matched_indices) < needed and available:
        matched_indices.append(available.pop(0))
    order = np.array(matched_indices[:needed])
    w_sorted = w_t[order]
    b_sorted = b_t[order]
    return d_sorted, valid, order, w_sorted, b_sorted


def nn_to_lut(
    model,
    domain: Tuple[float, float],
    num_entries: int,
) -> LutParams:
    if not HAS_TORCH:
        raise ImportError("PyTorch is required for nn_to_lut")
    breakpoints, valid, order, w_sorted, b_sorted = extract_and_sort_breakpoints(
        model, domain, num_entries
    )
    m = model.fc2.weight.detach().clone().squeeze(0)
    m_sorted = m[valid][order]

    all_points = [domain[0]] + breakpoints.tolist() + [domain[1]]
    slopes: List[float] = []
    intercepts: List[float] = []
    # 确保 w_sorted 是一维向量，避免 broadcasting 问题
    w_sorted_1d = w_sorted.squeeze()
    for i in range(len(all_points) - 1):
        x_mid = (all_points[i] + all_points[i + 1]) * 0.5
        z = w_sorted_1d * x_mid + b_sorted
        active = (z > 0).float()
        slope = torch.sum(m_sorted * w_sorted_1d * active).item()
        intercept = torch.sum(m_sorted * b_sorted * active).item()
        slopes.append(float(slope))
        intercepts.append(float(intercept))

    return LutParams(
        breakpoints=breakpoints.tolist(),
        slopes=slopes,
        intercepts=intercepts,
    )


def lut_eval(x: np.ndarray, params: LutParams, domain: Tuple[float, float]) -> np.ndarray:
    breakpoints = np.array(params.breakpoints, dtype=np.float32)
    slopes = np.array(params.slopes, dtype=np.float32)
    intercepts = np.array(params.intercepts, dtype=np.float32)
    x_clipped = np.clip(x, domain[0], domain[1])
    seg_idx = np.searchsorted(breakpoints, x_clipped, side="right")
    return slopes[seg_idx] * x_clipped + intercepts[seg_idx]
