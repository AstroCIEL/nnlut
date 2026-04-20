import os
from typing import Tuple

import matplotlib.pyplot as plt
import numpy as np

from src.conversion.lut import LutParams, lut_eval


def plot_curves(
    output_dir: str,
    x: np.ndarray,
    y_true: np.ndarray,
    params: LutParams,
    domain: Tuple[float, float],
) -> None:
    os.makedirs(output_dir, exist_ok=True)
    y_pred = lut_eval(x, params, domain)
    plt.figure(figsize=(8, 4))
    plt.plot(x, y_true, label="target")
    plt.plot(x, y_pred, label="lut")
    plt.legend()
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "curve_compare.png"))
    plt.close()

    abs_err = np.abs(y_true - y_pred)
    plt.figure(figsize=(8, 4))
    plt.plot(x, abs_err)
    plt.title("Absolute Error")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "abs_error.png"))
    plt.close()

    rel_err = abs_err / np.maximum(np.abs(y_true), 1e-6)
    plt.figure(figsize=(8, 4))
    plt.plot(x, rel_err)
    plt.title("Relative Error")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "rel_error.png"))
    plt.close()

    plt.figure(figsize=(8, 2))
    for d in params.breakpoints:
        plt.axvline(d, color="red", linewidth=0.5)
    plt.xlim(domain[0], domain[1])
    plt.title("Breakpoints")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "breakpoints.png"))
    plt.close()
import os
from typing import Tuple

import matplotlib.pyplot as plt
import numpy as np

from src.conversion.lut import LutParams, lut_eval


def plot_curves(
    output_dir: str,
    x: np.ndarray,
    y_true: np.ndarray,
    params: LutParams,
    domain: Tuple[float, float],
) -> None:
    os.makedirs(output_dir, exist_ok=True)
    y_pred = lut_eval(x, params, domain)
    plt.figure(figsize=(8, 4))
    plt.plot(x, y_true, label="target")
    plt.plot(x, y_pred, label="lut")
    plt.legend()
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "curve_compare.png"))
    plt.close()

    abs_err = np.abs(y_true - y_pred)
    plt.figure(figsize=(8, 4))
    plt.plot(x, abs_err)
    plt.title("Absolute Error")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "abs_error.png"))
    plt.close()

    rel_err = abs_err / np.maximum(np.abs(y_true), 1e-6)
    plt.figure(figsize=(8, 4))
    plt.plot(x, rel_err)
    plt.title("Relative Error")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "rel_error.png"))
    plt.close()

    plt.figure(figsize=(8, 2))
    for d in params.breakpoints:
        plt.axvline(d, color="red", linewidth=0.5)
    plt.xlim(domain[0], domain[1])
    plt.title("Breakpoints")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "breakpoints.png"))
    plt.close()
