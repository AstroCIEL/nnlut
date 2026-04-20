#!/usr/bin/env python3
"""
Posit LUT 推理示例

演示如何使用 PositLUTInference 进行硬件部署格式的推理
"""

import sys
sys.path.insert(0, '/home/jet/Work/nnlut')

import numpy as np
from src.posit_inference import PositLUTInference, print_posit_inference_result


def main():
    # 示例 1: 基本使用（自动转换参数）
    print("=" * 80)
    print("示例 1: Posit LUT 推理基本使用")
    print("=" * 80)

    lut_path = "outputs/mish_default/lut_params.json"

    try:
        # 创建推理器（自动将 FP 参数转换为 posit 格式）
        inferencer = PositLUTInference(lut_path)
        print(f"推理器: {inferencer}")
        print(f"参数格式: {'Posit' if inferencer.using_posit_params else 'FP'}")

        # 单值推理
        test_value = 1.5
        result = inferencer.inference_single(test_value)

        print(f"\n单值推理: x = {test_value}")
        print(f"  输入 FP:     {result['input_fp']:.10f}")
        print(f"  输入 Posit:  {result['input_hex']}")
        print(f"  Ground Truth: {result['ground_truth']:.10f}")
        print(f"  FP LUT:      {result['fp_lut_output']:.10f} (误差: {result['error_fp']:.2e})")
        print(f"  Posit LUT:   {result['posit_lut_output']:.10f} (误差: {result['error_posit']:.2e})")
        print(f"  Posit 输出:  {result['posit_output_hex']}")

    except FileNotFoundError:
        print(f"文件未找到: {lut_path}")
        print("请先训练模型: python -m src.cli --config configs/mish_default.yaml")
        return

    # 示例 2: 批量推理
    print("\n" + "=" * 80)
    print("示例 2: 批量推理")
    print("=" * 80)

    test_values = [-2.0, -1.0, 0.0, 1.0, 2.0]
    results = inferencer.batch_inference(test_values)

    print(f"\n{'Input':>10} | {'Input Hex':>8} | {'Ground Truth':>14} | {'Posit Output':>14} | {'Error':>10}")
    print("-" * 70)
    for r in results:
        print(f"{r['input_fp']:>10.4f} | {r['input_hex']:>8} | "
              f"{r['ground_truth']:>14.6f} | {r['posit_lut_output']:>14.6f} | "
              f"{r['error_posit']:>10.2e}")

    # 示例 3: 统计信息
    print("\n" + "=" * 80)
    print("示例 3: 误差统计")
    print("=" * 80)

    # 生成更多测试点
    test_points = np.linspace(inferencer.domain[0], inferencer.domain[1], 100)
    results = inferencer.batch_inference(test_points.tolist())

    errors_posit = [r['error_posit'] for r in results]
    errors_fp = [r['error_fp'] for r in results]

    print(f"\n测试点数: {len(results)}")
    print(f"定义域: [{inferencer.domain[0]}, {inferencer.domain[1]}]")
    print(f"\nFP LUT 误差:")
    print(f"  最大: {max(errors_fp):.6e}")
    print(f"  平均: {sum(errors_fp)/len(errors_fp):.6e}")
    print(f"  RMSE: {np.sqrt(np.mean(np.array(errors_fp)**2)):.6e}")

    print(f"\nPosit LUT 误差:")
    print(f"  最大: {max(errors_posit):.6e}")
    print(f"  平均: {sum(errors_posit)/len(errors_posit):.6e}")
    print(f"  RMSE: {np.sqrt(np.mean(np.array(errors_posit)**2)):.6e}")

    # Posit vs FP LUT 差异
    posit_vs_fp_errors = [abs(r['fp_lut_output'] - r['posit_lut_output']) for r in results]
    print(f"\nPosit vs FP LUT 差异:")
    print(f"  最大: {max(posit_vs_fp_errors):.6e}")
    print(f"  平均: {sum(posit_vs_fp_errors)/len(posit_vs_fp_errors):.6e}")
    print(f"  (这是量化误差，由 Posit<16,2> 的精度限制导致)")

    # 示例 4: 只转换参数
    print("\n" + "=" * 80)
    print("示例 4: 只转换参数格式")
    print("=" * 80)

    # 创建新的推理器，不自动转换
    inferencer2 = PositLUTInference(lut_path, use_posit_params=False)
    print(f"当前参数格式: {'Posit' if inferencer2.using_posit_params else 'FP'}")

    if not inferencer2.using_posit_params:
        output_path = inferencer2.convert_and_save_params()
        print(f"参数已转换为 Posit<{inferencer2.nbits},{inferencer2.es}> 格式")
        print(f"保存到: {output_path}")

        # 显示转换后的参数示例
        print(f"\n参数转换示例:")
        print(f"  Breakpoint[0]: FP={inferencer2.posit_params.breakpoints_fp[0]:.6f}, "
              f"Hex={inferencer2.posit_params.breakpoints_hex[0]}")
        print(f"  Slope[0]:      FP={inferencer2.posit_params.slopes_fp[0]:.6f}, "
              f"Hex={inferencer2.posit_params.slopes_hex[0]}")
        print(f"  Intercept[0]:  FP={inferencer2.posit_params.intercepts_fp[0]:.6f}, "
              f"Hex={inferencer2.posit_params.intercepts_hex[0]}")

    # 示例 5: 使用已转换的参数
    print("\n" + "=" * 80)
    print("示例 5: 使用已转换的 Posit 参数文件")
    print("=" * 80)

    # 重新加载，使用 posit 参数
    inferencer3 = PositLUTInference(lut_path, use_posit_params=True)
    print(f"参数格式: {'Posit' if inferencer3.using_posit_params else 'FP'}")

    result = inferencer3.inference_single(1.0)
    print(f"\n推理结果 (x=1.0):")
    print(f"  Ground Truth: {result['ground_truth']:.6f}")
    print(f"  Posit LUT:    {result['posit_lut_output']:.6f} ({result['posit_output_hex']})")
    print(f"  误差:         {result['error_posit']:.2e}")

    print("\n" + "=" * 80)
    print("示例完成！")
    print("=" * 80)
    print("\n使用命令行工具:")
    print(f"  python -m src.posit_inference --lut {lut_path} --value 1.5")
    print(f"  python -m src.posit_inference --lut {lut_path} --range -8 8 --samples 100")
    print(f"  python -m src.posit_inference --lut {lut_path} --convert-only")


if __name__ == '__main__':
    main()
