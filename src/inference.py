"""
LUT 推理模块

加载训练好的 LUT 参数，对输入值进行推理：
1. 计算 ground truth (目标函数的真实值)
2. 计算 LUT 拟合网络的输出值
"""

import json
import numpy as np
from pathlib import Path
from typing import List, Tuple, Union, Optional
import argparse

from src.functions import get_function
from src.conversion.lut import LutParams, lut_eval


class LUTInference:
    """LUT 推理器"""

    def __init__(self, lut_json_path: str):
        """
        从 JSON 文件加载 LUT 参数

        参数:
            lut_json_path: LUT 参数 JSON 文件路径
        """
        self.lut_path = Path(lut_json_path)
        if not self.lut_path.exists():
            raise FileNotFoundError(f"LUT 参数文件不存在: {lut_json_path}")

        # 加载参数
        with open(self.lut_path, 'r') as f:
            self.metadata = json.load(f)

        # 提取关键信息
        self.function_name = self.metadata['function_name']
        self.domain = (self.metadata['domain_min'], self.metadata['domain_max'])
        self.num_entries = self.metadata['num_entries']

        # 构建 LutParams
        self.params = LutParams(
            breakpoints=self.metadata['breakpoints'],
            slopes=self.metadata['slopes'],
            intercepts=self.metadata['intercepts']
        )

        # 加载目标函数
        try:
            func_spec = get_function(self.function_name)
            self.target_func = func_spec.func
        except KeyError:
            raise ValueError(f"不支持的目标函数: {self.function_name}")

    def __repr__(self) -> str:
        return f"LUTInference(function='{self.function_name}', domain={self.domain}, entries={self.num_entries})"

    def inference(self, x: Union[float, List[float], np.ndarray]) -> Tuple[np.ndarray, np.ndarray]:
        """
        对输入值进行推理

        参数:
            x: 输入值（单个值、列表或 numpy 数组）

        返回:
            (ground_truth, lut_output): 目标函数值和 LUT 输出值
        """
        # 统一转换为 numpy 数组
        if isinstance(x, (int, float)):
            x = np.array([x], dtype=np.float32)
        elif isinstance(x, list):
            x = np.array(x, dtype=np.float32)
        elif isinstance(x, np.ndarray):
            x = x.astype(np.float32)
        else:
            raise TypeError(f"不支持的输入类型: {type(x)}")

        # 计算 ground truth
        ground_truth = self.target_func(x)

        # 计算 LUT 输出
        lut_output = lut_eval(x, self.params, self.domain)

        return ground_truth, lut_output

    def inference_single(self, x: float) -> Tuple[float, float, float]:
        """
        对单个值进行推理

        参数:
            x: 单个输入值

        返回:
            (input_val, ground_truth, lut_output, error)
        """
        gt, lut = self.inference(x)
        error = abs(gt[0] - lut[0])
        return x, gt[0], lut[0], error

    def batch_inference(self, values: List[float]) -> List[Tuple[float, float, float, float]]:
        """
        批量推理

        参数:
            values: 输入值列表

        返回:
            列表，每个元素为 (input, ground_truth, lut_output, error)
        """
        results = []
        gt, lut = self.inference(values)
        for i, (g, l) in enumerate(zip(gt, lut)):
            results.append((values[i], g, l, abs(g - l)))
        return results

    def get_params_info(self) -> dict:
        """获取参数信息"""
        return {
            'function_name': self.function_name,
            'domain': self.domain,
            'num_entries': self.num_entries,
            'num_segments': len(self.params.slopes),
            'breakpoints': self.params.breakpoints,
            'json_path': str(self.lut_path)
        }


def print_inference_result(input_val: float, ground_truth: float, lut_output: float,
                          error: float, show_details: bool = True):
    """打印推理结果"""
    rel_error = abs(error / ground_truth * 100) if ground_truth != 0 else float('inf')

    if show_details:
        print(f"\n输入值: {input_val:.10f}")
        print(f"  Ground Truth ({'目标函数'}): {ground_truth:.10f}")
        print(f"  LUT Output   (拟合网络): {lut_output:.10f}")
        print(f"  绝对误差:   {error:.2e}")
        if rel_error != float('inf'):
            print(f"  相对误差:   {rel_error:.4f}%")
    else:
        print(f"{input_val:12.6f} | {ground_truth:15.8f} | {lut_output:15.8f} | {error:12.4e}")


def main():
    parser = argparse.ArgumentParser(
        description='LUT 推理工具 - 加载训练好的 LUT 参数并进行推理',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 单值推理
  python -m src.inference --lut outputs/mish_default/lut_params.json --value 1.5

  # 批量推理
  python -m src.inference --lut outputs/mish_default/lut_params.json --values 1.0 2.0 3.0 4.0

  # 范围推理（均匀采样）
  python -m src.inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 100

  # 从文件读取输入
  python -m src.inference --lut outputs/mish_default/lut_params.json --file input_values.txt
        """
    )

    parser.add_argument('--lut', type=str, required=True,
                       help='LUT 参数 JSON 文件路径')

    # 输入方式互斥组
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument('--value', type=float,
                            help='单个输入值')
    input_group.add_argument('--values', type=float, nargs='+',
                            help='多个输入值（空格分隔）')
    input_group.add_argument('--range', type=float, nargs=2, metavar=('MIN', 'MAX'),
                            help='范围推理：最小值 最大值')
    input_group.add_argument('--file', type=str,
                            help='从文件读取输入值（每行一个）')

    parser.add_argument('--samples', type=int, default=10,
                       help='范围推理时的采样点数（默认: 10）')
    parser.add_argument('--output', type=str,
                       help='输出结果到文件（CSV 格式）')
    parser.add_argument('--quiet', action='store_true',
                       help='静默模式，只输出结果表格')

    args = parser.parse_args()

    # 加载推理器
    try:
        inferencer = LUTInference(args.lut)
    except Exception as e:
        print(f"错误: 无法加载 LUT 参数: {e}")
        return 1

    if not args.quiet:
        print("=" * 70)
        print("LUT 推理")
        print("=" * 70)
        print(f"目标函数: {inferencer.function_name}")
        print(f"定义域: [{inferencer.domain[0]}, {inferencer.domain[1]}]")
        print(f"LUT 条目数: {inferencer.num_entries}")
        print(f"段数: {len(inferencer.params.slopes)}")
        print("=" * 70)

    # 收集输入值
    if args.value is not None:
        input_values = [args.value]
    elif args.values is not None:
        input_values = args.values
    elif args.range is not None:
        min_val, max_val = args.range
        input_values = np.linspace(min_val, max_val, args.samples).tolist()
        if not args.quiet:
            print(f"\n范围推理: [{min_val}, {max_val}], {args.samples} 个采样点")
    elif args.file is not None:
        try:
            with open(args.file, 'r') as f:
                input_values = [float(line.strip()) for line in f if line.strip()]
        except Exception as e:
            print(f"错误: 无法读取输入文件: {e}")
            return 1

    # 检查输入值是否在定义域内
    domain_min, domain_max = inferencer.domain
    out_of_domain = [v for v in input_values if v < domain_min or v > domain_max]
    if out_of_domain:
        print(f"警告: {len(out_of_domain)} 个输入值超出定义域 [{domain_min}, {domain_max}]")
        print(f"  越界值将被 clip 到定义域边界")

    # 执行推理
    if not args.quiet:
        print("\n" + "=" * 70)

    results = inferencer.batch_inference(input_values)

    # 输出结果
    if args.quiet:
        print(f"{'Input':>12} | {'Ground Truth':>15} | {'LUT Output':>15} | {'Error':>12}")
        print("-" * 70)
    else:
        print(f"\n推理结果 ({len(results)} 个值):")
        print("-" * 70)

    for inp, gt, lut, err in results:
        print_inference_result(inp, gt, lut, err, show_details=not args.quiet)

    # 统计信息
    if len(results) > 1:
        errors = [r[3] for r in results]
        max_error = max(errors)
        mean_error = sum(errors) / len(errors)

        if not args.quiet:
            print("\n" + "=" * 70)
            print("统计信息:")
            print(f"  最大绝对误差: {max_error:.6e}")
            print(f"  平均绝对误差: {mean_error:.6e}")

    # 保存到文件
    if args.output:
        with open(args.output, 'w') as f:
            f.write("input,ground_truth,lut_output,error\n")
            for inp, gt, lut, err in results:
                f.write(f"{inp},{gt},{lut},{err}\n")
        if not args.quiet:
            print(f"\n结果已保存到: {args.output}")

    if not args.quiet:
        print("=" * 70)

    return 0


if __name__ == '__main__':
    exit(main())
