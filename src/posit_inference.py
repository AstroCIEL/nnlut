"""
Posit 格式的 LUT 推理模块

用于硬件部署，所有计算在 posit 域进行：
1. 将 FP 参数转换为 Posit<16,2> 格式并保存
2. 支持读取 Posit 格式的参数文件
3. 输入为 Posit 格式，MAC 操作在 posit 域模拟
4. 同时报告 FP 计算的 ground truth 用于对比
"""

import json
import numpy as np
from pathlib import Path
from typing import List, Tuple, Union, Optional, Dict
import argparse

from src.functions import get_function
from src.conversion.lut import LutParams, lut_eval
from src.utils.posit import (
    fp_to_posit, posit_hex_to_fp,
    PositConverter, PositConfig
)


class PositLUTParams:
    """Posit 格式的 LUT 参数"""

    def __init__(self, nbits: int = 16, es: int = 2):
        self.nbits = nbits
        self.es = es
        self.config = PositConfig(nbits=nbits, es=es)

        # Posit 格式的参数（存储为 hex 字符串）
        self.breakpoints_hex: List[str] = []
        self.slopes_hex: List[str] = []
        self.intercepts_hex: List[str] = []

        # FP 格式的参数（用于 ground truth 计算）
        self.breakpoints_fp: List[float] = []
        self.slopes_fp: List[float] = []
        self.intercepts_fp: List[float] = []

    @classmethod
    def from_fp_params(cls, fp_params: LutParams, nbits: int = 16, es: int = 2) -> 'PositLUTParams':
        """从 FP 格式的 LutParams 创建 PositLUTParams"""
        posit_params = cls(nbits=nbits, es=es)

        # 转换 breakpoints
        for bp in fp_params.breakpoints:
            _, hex_str, posit_val = fp_to_posit(bp, nbits, es)
            posit_params.breakpoints_hex.append(hex_str)
            posit_params.breakpoints_fp.append(posit_val)

        # 转换 slopes
        for s in fp_params.slopes:
            _, hex_str, posit_val = fp_to_posit(s, nbits, es)
            posit_params.slopes_hex.append(hex_str)
            posit_params.slopes_fp.append(posit_val)

        # 转换 intercepts
        for i in fp_params.intercepts:
            _, hex_str, posit_val = fp_to_posit(i, nbits, es)
            posit_params.intercepts_hex.append(hex_str)
            posit_params.intercepts_fp.append(posit_val)

        return posit_params

    @classmethod
    def from_dict(cls, data: Dict, nbits: int = 16, es: int = 2) -> 'PositLUTParams':
        """从字典加载（JSON 格式）"""
        posit_params = cls(nbits=nbits, es=es)

        # 加载 hex 格式的参数
        posit_params.breakpoints_hex = data['breakpoints_hex']
        posit_params.slopes_hex = data['slopes_hex']
        posit_params.intercepts_hex = data['intercepts_hex']

        # 转换回 FP 值用于计算
        posit_params.breakpoints_fp = [
            posit_hex_to_fp(h, nbits, es) for h in posit_params.breakpoints_hex
        ]
        posit_params.slopes_fp = [
            posit_hex_to_fp(h, nbits, es) for h in posit_params.slopes_hex
        ]
        posit_params.intercepts_fp = [
            posit_hex_to_fp(h, nbits, es) for h in posit_params.intercepts_hex
        ]

        return posit_params

    def to_dict(self) -> Dict:
        """转换为字典（用于 JSON 保存）"""
        return {
            'nbits': self.nbits,
            'es': self.es,
            'breakpoints_hex': self.breakpoints_hex,
            'slopes_hex': self.slopes_hex,
            'intercepts_hex': self.intercepts_hex,
        }

    def get_fp_params(self) -> LutParams:
        """获取 FP 格式的 LutParams"""
        return LutParams(
            breakpoints=self.breakpoints_fp,
            slopes=self.slopes_fp,
            intercepts=self.intercepts_fp
        )


class PositLUTInference:
    """Posit 格式的 LUT 推理器

    所有 MAC 操作在 posit 域模拟：
    - 输入: posit 格式 (16-bit, es=2)
    - 参数: posit 格式
    - 计算: y = slope * x + intercept (在 posit 域)
    """

    def __init__(self, lut_json_path: str, use_posit_params: bool = True):
        """
        加载 LUT 参数（FP 或 Posit 格式）

        参数:
            lut_json_path: LUT 参数 JSON 文件路径
            use_posit_params: 是否使用 posit 格式的参数（如果存在）
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
        self.nbits = self.metadata.get('posit_nbits', 16)
        self.es = self.metadata.get('posit_es', 2)

        # 检查是否存在 posit 格式参数
        if use_posit_params and 'posit_params' in self.metadata:
            # 使用 posit 格式参数
            self.posit_params = PositLUTParams.from_dict(
                self.metadata['posit_params'], self.nbits, self.es
            )
            self.fp_params = self.posit_params.get_fp_params()
            self.using_posit_params = True
        else:
            # 使用 FP 格式参数
            self.fp_params = LutParams(
                breakpoints=self.metadata['breakpoints'],
                slopes=self.metadata['slopes'],
                intercepts=self.metadata['intercepts']
            )
            self.posit_params = None
            self.using_posit_params = False

        # 加载目标函数
        try:
            func_spec = get_function(self.function_name)
            self.target_func = func_spec.func
        except KeyError:
            raise ValueError(f"不支持的目标函数: {self.function_name}")

    def __repr__(self) -> str:
        param_type = "Posit" if self.using_posit_params else "FP"
        return f"PositLUTInference(function='{self.function_name}', domain={self.domain}, entries={self.num_entries}, params={param_type})"

    def _posit_mac(self, x_hex: str, slope_hex: str, intercept_hex: str) -> Tuple[str, float]:
        """
        执行 posit 域的 MAC 操作: y = x * slope + intercept

        参数:
            x_hex: 输入值 (hex 字符串)
            slope_hex: 斜率 (hex 字符串)
            intercept_hex: 截距 (hex 字符串)

        返回:
            (result_hex, result_fp): posit hex 结果和对应的 FP 值
        """
        # 转换为 FP 进行计算（在真实硬件中这是 posit MAC 单元）
        x_fp = posit_hex_to_fp(x_hex, self.nbits, self.es)
        slope_fp = posit_hex_to_fp(slope_hex, self.nbits, self.es)
        intercept_fp = posit_hex_to_fp(intercept_hex, self.nbits, self.es)

        # MAC 操作: y = x * slope + intercept
        # 在真实硬件中，这是 posit 乘法和加法
        y_fp = x_fp * slope_fp + intercept_fp

        # 转换回 posit
        _, y_hex, y_posit_val = fp_to_posit(y_fp, self.nbits, self.es)

        return y_hex, y_posit_val

    def _posit_lut_eval(self, x_hex_list: List[str]) -> Tuple[List[str], np.ndarray]:
        """
        在 posit 域执行 LUT 推理

        参数:
            x_hex_list: posit hex 格式的输入列表

        返回:
            (result_hex_list, result_fp_array): posit hex 结果列表和 FP 值数组
        """
        if self.posit_params is None:
            raise ValueError("Posit 参数未加载")

        result_hex_list = []
        result_fp_list = []

        # 获取 breakpoints 的 FP 值用于索引查找
        breakpoints_fp = np.array(self.posit_params.breakpoints_fp)

        for x_hex in x_hex_list:
            x_fp = posit_hex_to_fp(x_hex, self.nbits, self.es)

            # 确定 segment (在 FP 域进行查找)
            x_clipped = np.clip(x_fp, self.domain[0], self.domain[1])
            seg_idx = np.searchsorted(breakpoints_fp, x_clipped, side="right")
            seg_idx = min(seg_idx, len(self.posit_params.slopes_hex) - 1)

            # 在 posit 域执行 MAC
            slope_hex = self.posit_params.slopes_hex[seg_idx]
            intercept_hex = self.posit_params.intercepts_hex[seg_idx]

            y_hex, y_fp = self._posit_mac(x_hex, slope_hex, intercept_hex)

            result_hex_list.append(y_hex)
            result_fp_list.append(y_fp)

        return result_hex_list, np.array(result_fp_list)

    def inference(self, x: Union[float, List[float], np.ndarray]) -> Tuple[np.ndarray, np.ndarray, np.ndarray, List[str]]:
        """
        对输入值进行 posit 域推理

        参数:
            x: 输入值（单个值、列表或 numpy 数组）- FP 格式

        返回:
            (ground_truth, fp_lut_output, posit_lut_output, posit_hex_outputs):
            - ground_truth: 目标函数的 FP 输出
            - fp_lut_output: FP LUT 的输出（用于对比）
            - posit_lut_output: Posit LUT 的 FP 输出值
            - posit_hex_outputs: Posit LUT 的 hex 输出值列表
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

        # 计算 ground truth (FP)
        ground_truth = self.target_func(x)

        # 计算 FP LUT 输出（用于对比）
        fp_lut_output = lut_eval(x, self.fp_params, self.domain)

        # 将输入转换为 posit hex 格式
        x_hex_list = []
        for val in x:
            _, hex_str, _ = fp_to_posit(val, self.nbits, self.es)
            x_hex_list.append(hex_str)

        # 在 posit 域执行 LUT 推理
        if not self.using_posit_params:
            # 如果没有 posit 参数，自动转换
            self.convert_and_save_params()

        posit_hex_outputs, posit_lut_output = self._posit_lut_eval(x_hex_list)

        return ground_truth, fp_lut_output, posit_lut_output, posit_hex_outputs

    def inference_single(self, x: float) -> Dict:
        """
        对单个值进行推理，返回详细信息

        参数:
            x: 单个输入值 (FP 格式)

        返回:
            字典包含：
            - input_fp: 输入 FP 值
            - input_hex: 输入 posit hex
            - ground_truth: ground truth FP 值
            - fp_lut_output: FP LUT 输出
            - posit_lut_output: Posit LUT FP 输出
            - posit_output_hex: Posit LUT hex 输出
            - error_fp: FP LUT 误差
            - error_posit: Posit LUT 误差
        """
        gt, fp_lut, posit_lut, posit_hex = self.inference(x)

        # 转换输入为 posit hex
        _, x_hex, _ = fp_to_posit(x, self.nbits, self.es)

        return {
            'input_fp': x,
            'input_hex': x_hex,
            'ground_truth': gt[0],
            'fp_lut_output': fp_lut[0],
            'posit_lut_output': posit_lut[0],
            'posit_output_hex': posit_hex[0],
            'error_fp': abs(gt[0] - fp_lut[0]),
            'error_posit': abs(gt[0] - posit_lut[0]),
        }

    def batch_inference(self, values: List[float]) -> List[Dict]:
        """
        批量推理

        参数:
            values: 输入值列表 (FP 格式)

        返回:
            字典列表，每个元素包含详细的推理结果
        """
        results = []
        gt, fp_lut, posit_lut, posit_hex = self.inference(values)

        for i in range(len(values)):
            _, x_hex, _ = fp_to_posit(values[i], self.nbits, self.es)
            results.append({
                'input_fp': values[i],
                'input_hex': x_hex,
                'ground_truth': gt[i],
                'fp_lut_output': fp_lut[i],
                'posit_lut_output': posit_lut[i],
                'posit_output_hex': posit_hex[i],
                'error_fp': abs(gt[i] - fp_lut[i]),
                'error_posit': abs(gt[i] - posit_lut[i]),
            })
        return results

    def convert_and_save_params(self, output_path: Optional[str] = None) -> str:
        """
        将 FP 参数转换为 posit 格式并保存

        参数:
            output_path: 输出文件路径（默认为原文件）

        返回:
            保存的文件路径
        """
        if output_path is None:
            output_path = str(self.lut_path)

        # 转换参数
        self.posit_params = PositLUTParams.from_fp_params(self.fp_params, self.nbits, self.es)
        self.using_posit_params = True

        # 更新 metadata
        self.metadata['posit_nbits'] = self.nbits
        self.metadata['posit_es'] = self.es
        self.metadata['posit_params'] = self.posit_params.to_dict()

        # 保存
        with open(output_path, 'w') as f:
            json.dump(self.metadata, f, indent=2)

        return output_path

    def get_params_info(self) -> dict:
        """获取参数信息"""
        return {
            'function_name': self.function_name,
            'domain': self.domain,
            'num_entries': self.num_entries,
            'posit_config': f"Posit<{self.nbits},{self.es}>",
            'using_posit_params': self.using_posit_params,
            'num_segments': len(self.fp_params.slopes),
            'json_path': str(self.lut_path)
        }


def print_posit_inference_result(result: Dict, show_details: bool = True):
    """打印 posit 推理结果"""
    if show_details:
        print(f"\n输入值:")
        print(f"  FP:     {result['input_fp']:.10f}")
        print(f"  Posit:  {result['input_hex']}")
        print(f"\nGround Truth (FP 计算): {result['ground_truth']:.10f}")
        print(f"\nFP LUT 输出:     {result['fp_lut_output']:.10f} (误差: {result['error_fp']:.2e})")
        print(f"Posit LUT 输出:  {result['posit_lut_output']:.10f} (误差: {result['error_posit']:.2e})")
        print(f"  Posit hex:     {result['posit_output_hex']}")

        # 对比
        posit_vs_fp_error = abs(result['fp_lut_output'] - result['posit_lut_output'])
        print(f"\nPosit vs FP LUT 差异: {posit_vs_fp_error:.2e}")
    else:
        print(f"{result['input_fp']:12.6f} | {result['input_hex']:>8} | "
              f"{result['ground_truth']:15.8f} | {result['posit_lut_output']:15.8f} | "
              f"{result['error_posit']:12.4e}")


def main():
    parser = argparse.ArgumentParser(
        description='Posit LUT 推理工具 - 在 Posit 域进行 LUT 推理',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 单值推理（自动转换参数）
  python -m src.posit_inference --lut outputs/mish_default/lut_params.json --value 1.5

  # 批量推理
  python -m src.posit_inference --lut outputs/mish_default/lut_params.json --values 1.0 2.0 3.0 4.0

  # 范围推理
  python -m src.posit_inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 100

  # 只转换参数，不进行推理
  python -m src.posit_inference --lut outputs/mish_default/lut_params.json --convert-only

  # 使用已转换的参数文件
  python -m src.posit_inference --lut outputs/mish_default/lut_params.json --use-posit-params --value 1.5
        """
    )

    parser.add_argument('--lut', type=str, required=True,
                       help='LUT 参数 JSON 文件路径')
    parser.add_argument('--use-posit-params', action='store_true',
                       help='使用已存在的 posit 格式参数（不自动转换）')

    # 输入方式互斥组
    input_group = parser.add_mutually_exclusive_group()
    input_group.add_argument('--value', type=float,
                            help='单个输入值')
    input_group.add_argument('--values', type=float, nargs='+',
                            help='多个输入值（空格分隔）')
    input_group.add_argument('--range', type=float, nargs=2, metavar=('MIN', 'MAX'),
                            help='范围推理：最小值 最大值')
    input_group.add_argument('--file', type=str,
                            help='从文件读取输入值（每行一个）')
    input_group.add_argument('--convert-only', action='store_true',
                            help='只转换参数格式，不进行推理')

    parser.add_argument('--samples', type=int, default=10,
                       help='范围推理时的采样点数（默认: 10）')
    parser.add_argument('--output', type=str,
                       help='输出结果到文件（CSV 格式）')
    parser.add_argument('--quiet', action='store_true',
                       help='静默模式，只输出结果表格')

    args = parser.parse_args()

    # 加载推理器
    try:
        inferencer = PositLUTInference(args.lut, use_posit_params=args.use_posit_params)
    except Exception as e:
        print(f"错误: 无法加载 LUT 参数: {e}")
        return 1

    # 如果只转换参数
    if args.convert_only:
        if inferencer.using_posit_params:
            print(f"参数已经是 posit 格式: {args.lut}")
            return 0

        output_path = inferencer.convert_and_save_params()
        print(f"参数已转换为 Posit<{inferencer.nbits},{inferencer.es}> 格式")
        print(f"保存到: {output_path}")
        print(f"\n参数统计:")
        print(f"  Breakpoints: {len(inferencer.posit_params.breakpoints_hex)} 个")
        print(f"  Slopes: {len(inferencer.posit_params.slopes_hex)} 个")
        print(f"  Intercepts: {len(inferencer.posit_params.intercepts_hex)} 个")
        return 0

    # 如果没有输入参数，显示信息并退出
    if args.value is None and args.values is None and args.range is None and args.file is None:
        print("推理器信息:")
        info = inferencer.get_params_info()
        for key, value in info.items():
            print(f"  {key}: {value}")

        if not inferencer.using_posit_params:
            print("\n提示: 参数为 FP 格式，将自动转换为 posit 格式")
            print("      或使用 --convert-only 只转换参数")
            print("      或使用 --use-posit-params 如果已转换")
        return 0

    # 如果不是使用 posit 参数，先转换
    if not inferencer.using_posit_params:
        if not args.quiet:
            print("转换 FP 参数为 Posit 格式...")
        inferencer.convert_and_save_params()
        if not args.quiet:
            print(f"参数已转换并保存到: {args.lut}")

    if not args.quiet:
        print("=" * 80)
        print("Posit LUT 推理")
        print("=" * 80)
        print(f"目标函数: {inferencer.function_name}")
        print(f"定义域: [{inferencer.domain[0]}, {inferencer.domain[1]}]")
        print(f"LUT 条目数: {inferencer.num_entries}")
        print(f"Posit 格式: Posit<{inferencer.nbits},{inferencer.es}>")
        print(f"参数格式: {'Posit' if inferencer.using_posit_params else 'FP'}")
        print("=" * 80)

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
    else:
        input_values = []

    if not input_values:
        print("错误: 没有输入值")
        return 1

    # 检查输入值是否在定义域内
    domain_min, domain_max = inferencer.domain
    out_of_domain = [v for v in input_values if v < domain_min or v > domain_max]
    if out_of_domain:
        print(f"警告: {len(out_of_domain)} 个输入值超出定义域 [{domain_min}, {domain_max}]")
        print(f"  越界值将被 clip 到定义域边界")

    # 执行推理
    if not args.quiet:
        print("\n" + "=" * 80)

    results = inferencer.batch_inference(input_values)

    # 输出结果
    if args.quiet:
        print(f"{'Input':>12} | {'Posit':>8} | {'Ground Truth':>15} | {'Posit Output':>15} | {'Error':>12}")
        print("-" * 80)
    else:
        print(f"\n推理结果 ({len(results)} 个值):")
        print("-" * 80)

    for result in results:
        print_posit_inference_result(result, show_details=not args.quiet)

    # 统计信息
    if len(results) > 1:
        errors_posit = [r['error_posit'] for r in results]
        errors_fp = [r['error_fp'] for r in results]
        max_error_posit = max(errors_posit)
        mean_error_posit = sum(errors_posit) / len(errors_posit)
        max_error_fp = max(errors_fp)
        mean_error_fp = sum(errors_fp) / len(errors_fp)

        if not args.quiet:
            print("\n" + "=" * 80)
            print("统计信息:")
            print(f"  FP LUT 最大绝对误差: {max_error_fp:.6e}")
            print(f"  FP LUT 平均绝对误差: {mean_error_fp:.6e}")
            print(f"  Posit LUT 最大绝对误差: {max_error_posit:.6e}")
            print(f"  Posit LUT 平均绝对误差: {mean_error_posit:.6e}")

            # 对比
            posit_vs_fp_errors = [abs(r['fp_lut_output'] - r['posit_lut_output']) for r in results]
            print(f"  Posit vs FP LUT 最大差异: {max(posit_vs_fp_errors):.6e}")
            print(f"  Posit vs FP LUT 平均差异: {sum(posit_vs_fp_errors)/len(posit_vs_fp_errors):.6e}")

    # 保存到文件
    if args.output:
        with open(args.output, 'w') as f:
            f.write("input_fp,input_hex,ground_truth,fp_lut_output,posit_lut_output,posit_output_hex,error_fp,error_posit\n")
            for r in results:
                f.write(f"{r['input_fp']},{r['input_hex']},{r['ground_truth']},"
                       f"{r['fp_lut_output']},{r['posit_lut_output']},{r['posit_output_hex']},"
                       f"{r['error_fp']},{r['error_posit']}\n")
        if not args.quiet:
            print(f"\n结果已保存到: {args.output}")

    if not args.quiet:
        print("=" * 80)

    return 0


if __name__ == '__main__':
    exit(main())
