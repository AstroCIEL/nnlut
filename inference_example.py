#!/usr/bin/env python3
"""
LUT 推理示例脚本

展示如何在 Python 代码中使用 LUT 推理功能
"""

import numpy as np
from src.inference import LUTInference


def main():
    # 加载训练好的 LUT 参数
    lut_path = "outputs/mish_default/lut_params.json"
    inferencer = LUTInference(lut_path)

    print("=" * 70)
    print("LUT 推理示例")
    print("=" * 70)
    print(f"加载的 LUT: {inferencer}")
    print(f"目标函数: {inferencer.function_name}")
    print(f"定义域: {inferencer.domain}")
    print()

    # 示例 1: 单值推理
    print("【示例 1】单值推理")
    x = 2.5
    gt, lut = inferencer.inference(x)
    print(f"  输入: x = {x}")
    print(f"  Ground Truth: {gt[0]:.8f}")
    print(f"  LUT Output:   {lut[0]:.8f}")
    print(f"  误差: {abs(gt[0] - lut[0]):.2e}")
    print()

    # 示例 2: 批量推理
    print("【示例 2】批量推理")
    x_values = [-3.0, -1.0, 0.0, 1.0, 3.0]
    results = inferencer.batch_inference(x_values)

    print(f"{'Input':>10} {'Ground Truth':>15} {'LUT Output':>15} {'Error':>12}")
    print("-" * 60)
    for inp, gt, lut, err in results:
        print(f"{inp:10.4f} {gt:15.8f} {lut:15.8f} {err:12.4e}")
    print()

    # 示例 3: 使用 numpy 数组推理
    print("【示例 3】使用 numpy 数组推理")
    x_array = np.linspace(-2, 2, 5)
    gt_array, lut_array = inferencer.inference(x_array)

    print(f"输入数组: {x_array}")
    print(f"Ground Truth: {gt_array}")
    print(f"LUT Output:   {lut_array}")
    print(f"误差: {np.abs(gt_array - lut_array)}")
    print()

    # 示例 4: 获取参数信息
    print("【示例 4】获取参数信息")
    info = inferencer.get_params_info()
    for key, value in info.items():
        if key == 'breakpoints':
            print(f"  {key}: {len(value)} 个断点")
        else:
            print(f"  {key}: {value}")
    print()

    # 示例 5: 计算统计信息
    print("【示例 5】统计信息")
    test_points = np.linspace(inferencer.domain[0], inferencer.domain[1], 1000)
    gt, lut = inferencer.inference(test_points)
    errors = np.abs(gt - lut)

    print(f"  测试点数: {len(test_points)}")
    print(f"  最大误差: {np.max(errors):.6e}")
    print(f"  平均误差: {np.mean(errors):.6e}")
    print(f"  RMSE: {np.sqrt(np.mean(errors**2)):.6e}")

    print("\n" + "=" * 70)
    print("示例完成！")
    print("=" * 70)


if __name__ == "__main__":
    main()
