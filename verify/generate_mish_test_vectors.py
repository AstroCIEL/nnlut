#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Mish 函数的测试向量
用于验证 nnlut 硬件模块

运行方式：
    python generate_mish_test_vectors.py

输出：
    1. 打印测试向量的 SystemVerilog 代码
    2. 生成预期的硬件输出对比表
"""

import sys
sys.path.insert(0, '/home/jet/Work/nnlut')

import numpy as np
from src.posit_inference import PositLUTInference

def main():
    # LUT 参数文件路径
    lut_path = "/home/jet/Work/nnlut/outputs/mish_default/lut_params.json"

    try:
        inferencer = PositLUTInference(lut_path, use_posit_params=True)
    except FileNotFoundError:
        print(f"错误: 找不到参数文件 {lut_path}")
        print("请确保已经训练了 mish 模型")
        return 1

    print("=" * 80)
    print("Mish Function Test Vector Generator")
    print("=" * 80)
    print(f"Function: {inferencer.function_name}")
    print(f"Domain: {inferencer.domain}")
    print(f"Entries: {inferencer.num_entries}")
    print(f"Posit: <{inferencer.nbits},{inferencer.es}>")
    print("=" * 80)

    # 生成测试点
    test_points = np.linspace(-8.0, 8.0, 17)  # 17 个点覆盖定义域

    print("\n[测试向量表]")
    print("-" * 80)
    print(f"{'Index':>6} | {'FP Input':>12} | {'Hex Input':>10} | {'Expected Output (hex)':>22} | {'FP Output':>14}")
    print("-" * 80)

    sv_test_vectors = []

    for i, x in enumerate(test_points):
        result = inferencer.inference_single(x)

        x_hex = result['input_hex']
        y_hex = result['posit_output_hex']
        y_fp = result['posit_lut_output']

        # 转换 hex 字符串为整数
        x_val = int(x_hex, 16) if x_hex.startswith('0x') else int(x_hex, 16)
        y_val = int(y_hex, 16) if y_hex.startswith('0x') else int(y_hex, 16)

        print(f"{i:>6} | {x:>12.6f} | {x_hex:>10} | {y_hex:>22} | {y_fp:>14.8f}")

        # 为 SystemVerilog 生成代码
        description = f"x={x:.1f}"
        sv_test_vectors.append({
            'x_hex': f"16'h{x_hex[2:].upper()}",
            'y_hex': f"16'h{y_hex[2:].upper()}",
            'x_fp': x,
            'y_fp': y_fp,
            'desc': description
        })

    print("-" * 80)

    # 生成 SystemVerilog 测试向量代码
    print("\n[SystemVerilog Test Vectors]")
    print("复制以下内容到 testbench 中：")
    print("=" * 80)
    print()
    print("    // 测试向量（从 Python 模型生成）")
    print("    typedef struct {")
    print("        logic [15:0] x_hex;")
    print("        logic [15:0] expected_y_hex;")
    print("        real x_fp;")
    print("        real expected_y_fp;")
    print("        string description;")
    print("    } test_vector_t;")
    print()
    print(f"    localparam int NUM_TESTS = {len(sv_test_vectors)};")
    print()
    print("    localparam test_vector_t TEST_VECTORS [NUM_TESTS] = '{")

    for i, tv in enumerate(sv_test_vectors):
        comma = "," if i < len(sv_test_vectors) - 1 else ""
        print(f"        '{{{tv['x_hex']}, {tv['y_hex']}, {tv['x_fp']:.6f}, {tv['y_fp']:.8f}, \"{tv['desc']}\"}}{comma}")

    print("    };")
    print()
    print("=" * 80)

    # 生成参数初始化代码
    print("\n[Hardware Parameters]")
    print("复制以下内容到 testbench 的参数加载部分：")
    print("=" * 80)
    print()

    # breakpoints
    print("    // Breakpoints (31 entries)")
    print("    localparam logic [15:0] BP_HEX [31] = '{")
    bp_hex_list = inferencer.posit_params.breakpoints_hex
    for i in range(0, len(bp_hex_list), 5):
        line_values = bp_hex_list[i:i+5]
        hex_strs = [f"16'h{h[2:].upper()}" for h in line_values]
        comma = "," if i + 5 < len(bp_hex_list) else ""
        print(f"        {', '.join(hex_strs)}{comma}")
    print("    };")
    print()

    # slopes
    print("    // Slopes (32 entries)")
    print("    localparam logic [15:0] SLOPE_HEX [32] = '{")
    slope_hex_list = inferencer.posit_params.slopes_hex
    for i in range(0, len(slope_hex_list), 4):
        line_values = slope_hex_list[i:i+4]
        hex_strs = [f"16'h{h[2:].upper()}" for h in line_values]
        comma = "," if i + 4 < len(slope_hex_list) else ""
        print(f"        {', '.join(hex_strs)}{comma}")
    print("    };")
    print()

    # intercepts
    print("    // Intercepts (32 entries)")
    print("    localparam logic [15:0] INTERCEPT_HEX [32] = '{")
    intercept_hex_list = inferencer.posit_params.intercepts_hex
    for i in range(0, len(intercept_hex_list), 4):
        line_values = intercept_hex_list[i:i+4]
        hex_strs = [f"16'h{h[2:].upper()}" for h in line_values]
        comma = "," if i + 4 < len(intercept_hex_list) else ""
        print(f"        {', '.join(hex_strs)}{comma}")
    print("    };")
    print()
    print("=" * 80)

    return 0

if __name__ == '__main__':
    exit(main())
