#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Golden Model 期望值 for nnlut testbench
将软件计算结果输出为 SystemVerilog 格式
"""

import sys
sys.path.insert(0, '/data/home/rh_xu30/Work/DPRL_V3_0401/nnlut')

import numpy as np
from src.posit_inference import PositLUTInference

def generate_golden_vectors():
    lut_path = "/data/home/rh_xu30/Work/DPRL_V3_0401/nnlut/outputs/mish_default/lut_params.json"

    try:
        inferencer = PositLUTInference(lut_path, use_posit_params=True)
    except FileNotFoundError:
        print(f"Error: Cannot find {lut_path}")
        return None

    print("=" * 80)
    print("Generating Golden Model Vectors for nnlut_mish_tb")
    print("=" * 80)
    print(f"Function: {inferencer.function_name}")
    print(f"Domain: {inferencer.domain}")
    print(f"Posit<{inferencer.nbits},{inferencer.es}>")
    print("=" * 80)

    # 测试点：覆盖不同区域
    test_inputs = [
        -6.0,   # neg sat
        -4.5,   # neg edge
        -2.0,   # neg trans
        -1.0,   # neg trans
        0.0,    # zero
        0.5,    # pos trans
        1.0,    # pos trans
        1.5,    # pos trans
        2.0,    # pos trans
        2.5,    # pos trans
        3.0,    # linear
        4.0,    # linear
        5.0,    # linear
        6.0,    # linear
        7.5,    # pos edge
    ]

    vectors = []

    print("\nTest Vectors:")
    print("-" * 80)
    print(f"{'Idx':>4} | {'Input FP':>10} | {'Input Hex':>10} | {'Output Hex':>12} | {'Output FP':>14}")
    print("-" * 80)

    for i, x in enumerate(test_inputs):
        result = inferencer.inference_single(x)

        x_hex = result['input_hex'].replace('0x', '')
        y_hex = result['posit_output_hex'].replace('0x', '')
        y_fp = result['posit_lut_output']

        vectors.append({
            'idx': i,
            'x_fp': x,
            'x_hex': x_hex.upper(),
            'y_hex': y_hex.upper(),
            'y_fp': y_fp,
            'region': get_region(x)
        })

        print(f"{i:>4} | {x:>10.4f} | 0x{x_hex:>8} | 0x{y_hex:>10} | {y_fp:>14.8f}")

    print("-" * 80)

    # 输出 SystemVerilog 代码
    print("\n" + "=" * 80)
    print("SystemVerilog Test Vectors (copy to testbench)")
    print("=" * 80)
    print()
    print("    // Golden Model Test Vectors (generated from Python)")
    print("    // Format: {input_hex, expected_output_hex, input_fp, description}")
    print("    typedef struct {")
    print("        logic [15:0] x_hex;")
    print("        logic [15:0] expected_y_hex;")
    print("        real x_fp;")
    print("        string description;")
    print("    } golden_vector_t;")
    print()
    print(f"    localparam int NUM_GOLDEN_TESTS = {len(vectors)};")
    print()
    print("    localparam golden_vector_t GOLDEN_VECTORS[NUM_GOLDEN_TESTS] = '{")

    for i, v in enumerate(vectors):
        comma = "," if i < len(vectors) - 1 else ""
        desc = f"x={v['x_fp']:.1f} ({v['region']})"
        print(f"        '{{16'h{v['x_hex']}, 16'h{v['y_hex']}, {v['x_fp']:.6f}, \"{desc}\"}}{comma}")

    print("    };")
    print()
    print("=" * 80)

    return vectors

def get_region(x):
    if x < -4.0:
        return "neg_sat"
    elif x < 0:
        return "neg_trans"
    elif x == 0:
        return "zero"
    elif x < 4.0:
        return "pos_trans"
    else:
        return "linear"

if __name__ == '__main__':
    generate_golden_vectors()
