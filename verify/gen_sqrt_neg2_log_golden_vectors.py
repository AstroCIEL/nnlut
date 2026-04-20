#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 sqrt_neg2_log_default 的 golden vectors（与 nnlut_mish_tb.sv 相同格式）。

注意：该函数定义域是 [0.0001, 1.0]，使用 linspace(domain_min, domain_max, 15)。
"""

import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
NNLUT_ROOT = os.path.abspath(os.path.join(HERE, "..", "nnlut"))
sys.path.insert(0, NNLUT_ROOT)

from src.posit_inference import PositLUTInference


def main():
    lut_path = os.path.join(NNLUT_ROOT, "outputs", "sqrt_neg2_log_default", "lut_params.json")
    inferencer = PositLUTInference(lut_path, use_posit_params=True)
    xs = np.linspace(inferencer.domain[0], inferencer.domain[1], 15).tolist()

    print("localparam golden_vector_t GOLDEN_VECTORS[15] = '{")
    for i, x in enumerate(xs):
        r = inferencer.inference_single(float(x))
        x_hex = r["input_hex"]
        y_hex = r["posit_output_hex"]
        desc = f'x={x:.6f} (sqrt_neg2_log)'
        comma = "," if i != len(xs) - 1 else ""
        print(f"    '{{16'h{x_hex[2:].upper()}, 16'h{y_hex[2:].upper()}, {x:.9f}, \"{desc}\"}}{comma}")
    print("};")


if __name__ == "__main__":
    main()

