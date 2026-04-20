#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 mish_derivative 的 golden vectors（与 nnlut_mish_tb.sv 相同格式）。

输出：
  - SystemVerilog 的 GOLDEN_VECTORS 初始化内容（15 点，linspace(-8,8,15)）
"""

import os
import sys
import numpy as np

# 复用本仓库里的 nnlut Python 代码（DPRL_V3_0401/nnlut/src）
HERE = os.path.dirname(os.path.abspath(__file__))
NNLUT_ROOT = os.path.abspath(os.path.join(HERE, "..", "nnlut"))
sys.path.insert(0, NNLUT_ROOT)

from src.posit_inference import PositLUTInference


def main():
    lut_path = os.path.join(NNLUT_ROOT, "outputs", "mish_derivative_default", "lut_params.json")
    inferencer = PositLUTInference(lut_path, use_posit_params=True)
    xs = np.linspace(inferencer.domain[0], inferencer.domain[1], 15).tolist()

    print("localparam golden_vector_t GOLDEN_VECTORS[15] = '{")
    for i, x in enumerate(xs):
        r = inferencer.inference_single(float(x))
        x_hex = r["input_hex"]  # like 0xa7ff
        y_hex = r["posit_output_hex"]
        # 描述用 2 位小数，和 mish_tb 兼容
        desc = f'x={x:.2f} (mish_derivative)'
        comma = "," if i != len(xs) - 1 else ""
        print(f"    '{{16'h{x_hex[2:].upper()}, 16'h{y_hex[2:].upper()}, {x:.6f}, \"{desc}\"}}{comma}")
    print("};")


if __name__ == "__main__":
    main()

