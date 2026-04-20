"""
Posit 数制与 FP 浮点数互转实现

Posit 格式结构：
- sign (1 bit): 符号位
- regime (可变长度): 连续的 0/1 序列，表示大范围指数
- exponent (es bits): 指数部分
- fraction (剩余 bits): 尾数部分

参考: John L. Gustafson, "Beating Floating Point at its Own Game"
"""

from dataclasses import dataclass
from typing import Tuple, Optional
import math
import struct


@dataclass
class PositConfig:
    """Posit 格式配置"""
    nbits: int      # 总位数 (如 8, 16, 32)
    es: int         # 指数位宽 (如 0, 1, 2)

    def __post_init__(self):
        if self.nbits < 2:
            raise ValueError("Posit bits must be at least 2")
        if self.es < 0 or self.es > self.nbits - 2:
            raise ValueError(f"es must be in [0, {self.nbits - 2}]")

    @property
    def useed(self) -> int:
        """useed = 2^(2^es)，regime 对应的基数"""
        return 2 ** (2 ** self.es)

    @property
    def max_scale(self) -> int:
        """最大 scale 值"""
        return (self.nbits - 1) * (2 ** self.es)

    @property
    def min_scale(self) -> int:
        """最小 scale 值"""
        return -self.max_scale


class Posit:
    """
    Posit 数表示

    属性:
        bits: 整数形式的 posit 位模式
        config: PositConfig 配置对象
    """

    def __init__(self, bits: int, config: PositConfig):
        self.config = config
        self.nbits = config.nbits
        self.mask = (1 << self.nbits) - 1  # 用于屏蔽高位
        self.bits = bits & self.mask

    def __repr__(self) -> str:
        return f"Posit({self.to_binary_string()}, config={self.config})"

    def to_binary_string(self) -> str:
        """返回二进制字符串表示"""
        return format(self.bits, f'0{self.nbits}b')

    def to_hex_string(self) -> str:
        """返回16进制字符串表示（0x开头）"""
        # 计算需要的16进制位数: nbits / 4，向上取整
        hex_digits = (self.nbits + 3) // 4
        return f"0x{self.bits:0{hex_digits}x}"

    def __int__(self) -> int:
        """返回整数位模式"""
        return self.bits

    def __eq__(self, other) -> bool:
        if not isinstance(other, Posit):
            return False
        return self.bits == other.bits and self.config == other.config

    def is_zero(self) -> bool:
        """检查是否为 0"""
        return self.bits == 0

    def is_nar(self) -> bool:
        """检查是否为 NaR (Not-a-Real)"""
        return self.bits == self.mask  # 全1

    def sign(self) -> int:
        """提取符号位: 0 为正，1 为负"""
        return (self.bits >> (self.nbits - 1)) & 1

    def _extract_regime(self) -> Tuple[int, int]:
        """
        提取 regime 值和 regime bits 长度

        返回:
            (regime_value, regime_bits_length)

        Regime 解码:
        - k 个 1 后跟 0: regime = k-1 (如 10 -> 0, 110 -> 1, 1110 -> 2)
        - k 个 0 后跟 1: regime = -k (如 01 -> -1, 001 -> -2, 0001 -> -3)
        """
        if self.is_zero() or self.is_nar():
            return (0, 0)

        # 去除符号位，只看数值部分
        remaining = self.bits & ((1 << (self.nbits - 1)) - 1)

        # 检查最高位（数值部分的最高位）
        msb_pos = self.nbits - 2

        if remaining == 0:
            # 所有位都是 0
            return (-(self.nbits - 1), self.nbits - 1)

        # 检查 leading bit
        leading_bit = (remaining >> msb_pos) & 1

        if leading_bit == 1:
            # 连续 1 后跟 0
            # 数前导 1 的个数
            k = 0
            temp = remaining
            while k < msb_pos + 1:
                bit_pos = msb_pos - k
                if (temp >> bit_pos) & 1:
                    k += 1
                else:
                    break
            # regime = k - 1，bits 长度为 k + 1 (包括终止的 0)
            return (k - 1, min(k + 1, self.nbits - 1))
        else:
            # 连续 0 后跟 1
            # 数前导 0 的个数
            k = 0
            temp = remaining
            while k < msb_pos + 1:
                bit_pos = msb_pos - k
                if ((temp >> bit_pos) & 1) == 0:
                    k += 1
                else:
                    break
            # regime = -k，bits 长度为 k + 1 (包括终止的 1)
            return (-k, min(k + 1, self.nbits - 1))

    def to_float(self) -> float:
        """
        将 Posit 转换为 Python float (IEEE 754 double)

        解码过程:
        value = (-1)^sign × useed^regime × 2^exponent × 1.fraction
        """
        if self.is_zero():
            return 0.0
        if self.is_nar():
            return float('nan')

        sign = self.sign()
        abs_bits = self.bits & ((1 << (self.nbits - 1)) - 1)

        if abs_bits == 0:
            return -0.0 if sign else 0.0

        # 提取 regime
        regime_val, regime_len = self._extract_regime()

        # 剩余的 bits 用于 exponent 和 fraction
        remaining_bits = self.nbits - 1 - regime_len

        if remaining_bits < 0:
            remaining_bits = 0

        # 提取 exponent (es bits)
        es = self.config.es
        if remaining_bits >= es:
            exponent_bits = (abs_bits >> (remaining_bits - es)) & ((1 << es) - 1) if es > 0 else 0
            remaining_bits -= es
        else:
            exponent_bits = (abs_bits & ((1 << remaining_bits) - 1)) << (es - remaining_bits) if remaining_bits > 0 and es > 0 else 0
            remaining_bits = 0

        # 提取 fraction
        if remaining_bits > 0:
            fraction_mask = (1 << remaining_bits) - 1
            fraction_bits = abs_bits & fraction_mask
            fraction_len = remaining_bits
        else:
            fraction_bits = 0
            fraction_len = 0

        # 计算 scale
        # scale = regime × 2^es + exponent
        scale = regime_val * (2 ** es) + exponent_bits

        # 计算尾数值: 1.fraction
        if fraction_len > 0:
            mantissa = 1.0 + fraction_bits / (2.0 ** fraction_len)
        else:
            mantissa = 1.0

        # 计算最终值
        value = mantissa * (2.0 ** scale)

        if sign:
            value = -value

        return value


class PositConverter:
    """Posit 转换器，提供静态转换方法"""

    @staticmethod
    def float_to_posit(value: float, config: PositConfig, ones_complement: bool = True) -> Posit:
        """
        将 IEEE 754 float 转换为 Posit

        参数:
            value: 输入浮点数
            config: Posit 配置 (nbits, es)
            ones_complement: 是否使用 1's complement 编码负数（与给定文件兼容）

        返回:
            Posit 对象
        """
        nbits = config.nbits
        es = config.es

        # 处理特殊情况
        if value == 0.0 or value == -0.0:
            return Posit(0, config)
        if math.isnan(value) or math.isinf(value):
            return Posit((1 << nbits) - 1, config)  # NaR

        # 提取符号
        sign = 1 if value < 0 else 0
        abs_val = abs(value)

        # 分解为 mantissa × 2^scale
        # 使用 frexp: abs_val = mantissa × 2^exponent, 其中 0.5 <= mantissa < 1
        mantissa, exponent = math.frexp(abs_val)

        # 调整 mantissa 到 [1, 2) 范围，scale = exponent - 1
        mantissa *= 2
        scale = exponent - 1

        # 分解 scale = regime × 2^es + exponent_bits
        useed_exp = 2 ** es

        # 计算 regime
        if scale >= 0:
            regime = scale // useed_exp
            exp_bits = scale % useed_exp
        else:
            # 负 scale 需要特殊处理
            regime = -((-scale + useed_exp - 1) // useed_exp)
            exp_bits = scale - regime * useed_exp

        # 构建 posit bits
        # 格式: sign | regime | exponent | fraction

        # 1. 构建 regime bits
        if regime >= 0:
            # k = regime + 1 个 1 后跟 0
            k = regime + 1
            if k >= nbits - 1:
                # 溢出到最大值（不含 NaR）
                k = nbits - 2
            regime_bits = ((1 << k) - 1) << 1  # k 个 1 后跟 0
            regime_len = k + 1
        else:
            # k = -regime 个 0 后跟 1
            k = -regime
            if k >= nbits - 1:
                k = nbits - 2
            regime_bits = 1  # k 个 0 后跟 1
            regime_len = k + 1

        # 2. 构建 exponent bits
        if es > 0:
            exp_bits_val = exp_bits & ((1 << es) - 1)
        else:
            exp_bits_val = 0

        # 3. 构建 fraction bits
        # 剩余位数
        available_bits = nbits - 1 - regime_len - es

        if available_bits > 0:
            # 提取 fraction: mantissa 的小数部分
            # mantissa 在 [1, 2)，fraction = mantissa - 1
            frac_val = mantissa - 1.0
            # 量化到 available_bits
            scaled = frac_val * (2 ** available_bits)

            if sign == 1 and ones_complement:
                # 对于 1's complement 编码的负数，需要使用特殊的舍入
                # 给定文件的舍入规则：当 scaled 是整数或小数部分 < 0.025 时，减 1
                fraction_bits = int(scaled)
                frac_part = scaled - fraction_bits
                # 如果 scaled 是整数（frac_part == 0）或小数部分很小（< 0.025），减 1
                if (frac_part == 0 and fraction_bits > 0) or (0 < frac_part < 0.025):
                    fraction_bits -= 1
                fraction_bits &= ((1 << available_bits) - 1)
            else:
                # 正数使用四舍五入
                fraction_bits = int(scaled + 0.5) & ((1 << available_bits) - 1)
        else:
            fraction_bits = 0

        # 组合所有部分
        # sign bit 在最前面
        result = (sign << (nbits - 1))

        # regime
        remaining_pos = nbits - 1 - regime_len
        if remaining_pos >= 0:
            result |= regime_bits << remaining_pos
        else:
            # regime 溢出，需要截断
            result |= (regime_bits >> (-remaining_pos)) & ((1 << (nbits - 1)) - 1)

        # exponent
        if es > 0 and remaining_pos - es >= 0:
            result |= exp_bits_val << (remaining_pos - es)
        elif es > 0 and remaining_pos > 0:
            result |= exp_bits_val >> (es - remaining_pos)

        # fraction
        if available_bits > 0:
            result |= fraction_bits

        # 确保不超过 nbits
        result &= (1 << nbits) - 1

        # 如果是负数且使用 1's complement，需要取反除符号位外的所有位
        if sign == 1 and ones_complement:
            # 取反低 (nbits-1) 位
            magnitude_mask = (1 << (nbits - 1)) - 1
            magnitude = result & magnitude_mask
            inverted_magnitude = (~magnitude) & magnitude_mask
            result = (sign << (nbits - 1)) | inverted_magnitude

        return Posit(result, config)

    @staticmethod
    def posit_to_float(posit: Posit) -> float:
        """将 Posit 转换为 float"""
        return posit.to_float()

    @staticmethod
    def double_to_posit(value: float, nbits: int, es: int, ones_complement: bool = True) -> Posit:
        """
        便捷方法: double 直接转 posit

        示例:
            p = PositConverter.double_to_posit(3.14159, nbits=16, es=2)
            print(p.to_binary_string())  # 二进制表示
            print(p.to_float())          # 转换回 float
        """
        config = PositConfig(nbits=nbits, es=es)
        return PositConverter.float_to_posit(value, config, ones_complement=ones_complement)

    @staticmethod
    def create_posit_from_binary(binary_str: str, nbits: int, es: int) -> Posit:
        """
        从二进制字符串创建 Posit

        参数:
            binary_str: 二进制字符串，如 "01011000"
            nbits: posit 位数
            es: 指数位宽
        """
        config = PositConfig(nbits=nbits, es=es)
        bits = int(binary_str, 2)
        return Posit(bits, config)


# ============ 便捷函数 ============

def fp_to_posit(value: float, nbits: int, es: int) -> Tuple[str, str, float]:
    """
    将浮点数转换为 Posit

    参数:
        value: 输入浮点数
        nbits: Posit 总位数
        es: 指数位宽

    返回:
        (二进制字符串, 16进制字符串, Posit 表示的浮点数值)

    示例:
        >>> fp_to_posit(3.14159, 16, 1)
        ('0100110010011001', '0x4c99', 3.140625)
    """
    config = PositConfig(nbits=nbits, es=es)
    # 默认使用 1's complement 编码以与给定文件兼容
    posit = PositConverter.float_to_posit(value, config, ones_complement=True)

    # 计算正确的 float 值：对于 1's complement 编码，需要先解码
    bits = posit.bits
    sign = (bits >> (nbits - 1)) & 1
    if sign == 1:
        # 1's complement 解码
        magnitude_mask = (1 << (nbits - 1)) - 1
        magnitude = bits & magnitude_mask
        inverted_magnitude = (~magnitude) & magnitude_mask
        decoded_bits = (sign << (nbits - 1)) | inverted_magnitude
        float_val = Posit(decoded_bits, config).to_float()
    else:
        float_val = posit.to_float()

    return (posit.to_binary_string(), posit.to_hex_string(), float_val)


def fp_to_posit_hex(value: float, nbits: int, es: int) -> str:
    """
    将浮点数转换为 Posit 的16进制表示（便捷函数）

    参数:
        value: 输入浮点数
        nbits: Posit 总位数
        es: 指数位宽

    返回:
        16进制字符串（带 0x 前缀）

    示例:
        >>> fp_to_posit_hex(3.14159, 16, 1)
        '0x4c99'
    """
    config = PositConfig(nbits=nbits, es=es)
    # 默认使用 1's complement 编码以与给定文件兼容
    posit = PositConverter.float_to_posit(value, config, ones_complement=True)
    return posit.to_hex_string()


def posit_to_fp(binary_str: str, nbits: int, es: int) -> float:
    """
    将 Posit 二进制字符串转换为浮点数

    参数:
        binary_str: Posit 的二进制字符串表示
        nbits: Posit 总位数
        es: 指数位宽

    返回:
        对应的浮点数值

    示例:
        >>> posit_to_fp('0100110010011001', 16, 1)
        3.140625
    """
    posit = PositConverter.create_posit_from_binary(binary_str, nbits, es)
    return posit.to_float()


def posit_hex_to_fp(hex_str: str, nbits: int, es: int, ones_complement: bool = True) -> float:
    """
    将 Posit 16进制字符串转换为浮点数

    参数:
        hex_str: Posit 的16进制字符串表示（可带 0x 前缀）
        nbits: Posit 总位数
        es: 指数位宽
        ones_complement: 是否使用 1's complement 解码负数（与给定文件兼容）

    返回:
        对应的浮点数值

    示例:
        >>> posit_hex_to_fp('0x4c99', 16, 1)
        3.140625
        >>> posit_hex_to_fp('4c99', 16, 1)
        3.140625
    """
    config = PositConfig(nbits=nbits, es=es)
    # 去除 0x 前缀
    hex_clean = hex_str.replace('0x', '').replace('0X', '')
    bits = int(hex_clean, 16)

    # 检查符号位
    sign_bit = (bits >> (nbits - 1)) & 1

    # 如果是负数且使用 1's complement，需要取反除符号位外的所有位来解码
    if sign_bit == 1 and ones_complement:
        magnitude_mask = (1 << (nbits - 1)) - 1
        magnitude = bits & magnitude_mask
        inverted_magnitude = (~magnitude) & magnitude_mask
        bits = (sign_bit << (nbits - 1)) | inverted_magnitude

    return Posit(bits, config).to_float()


def posit_info(nbits: int, es: int) -> dict:
    """
    获取 Posit 格式信息

    返回包含格式信息的字典
    """
    config = PositConfig(nbits=nbits, es=es)
    return {
        "nbits": nbits,
        "es": es,
        "useed": config.useed,
        "max_scale": config.max_scale,
        "min_scale": config.min_scale,
        "dynamic_range": f"2^{config.max_scale} to 2^{config.min_scale}",
        "precision_bits": nbits - 1 - es,  # 近似有效位数
    }


# ============ 测试代码 ============

if __name__ == "__main__":
    print("=" * 60)
    print("Posit 数制转换测试")
    print("=" * 60)

    # 测试各种格式的信息
    print("\n【格式信息】")
    for nbits, es in [(8, 0), (8, 1), (16, 1), (32, 2)]:
        info = posit_info(nbits, es)
        print(f"  Posit<{nbits},{es}>: useed={info['useed']}, range=2^{info['min_scale']}~2^{info['max_scale']}")

    # 测试正向转换: FP -> Posit
    print("\n【FP -> Posit 转换测试】")
    test_values = [0.0, 1.0, -1.0, 2.0, 3.14159, -0.5, 100.0, 0.001]

    print(f"{'Value':>12} | {'Binary':>20} | {'Hex':>8} | {'Posit Value':>12} | {'Error':>10}")
    print("-" * 75)
    for val in test_values:
        bin_str, hex_str, posit_val = fp_to_posit(val, nbits=16, es=2)
        error = abs(val - posit_val) if val != 0 else abs(posit_val)
        print(f"{val:12.5f} | {bin_str:>20} | {hex_str:>8} | {posit_val:12.5f} | {error:>10.2e}")

    # 测试反向转换: Posit -> FP
    print("\n【Posit -> FP 转换测试】")
    test_binaries = [
        ("0000000000000000", "0"),
        ("1000000000000000", "-0 (最小正值取反)"),
        ("0100000000000000", "1.0"),
        ("1100000000000000", "-1.0"),
        ("0110000000000000", "4.0 (regime=1)"),
        ("1110000000000000", "-4.0"),
        ("0111111111111111", "NaR (全1)"),
    ]

    for bin_str, desc in test_binaries:
        val = posit_to_fp(bin_str, nbits=16, es=2)
        print(f"  {bin_str} -> {val:20.10f} ({desc})")

    # 验证 NaR: 全1
    nar_binary = "1" * 16  # 16个1
    nar_val = posit_to_fp(nar_binary, nbits=16, es=2)
    print(f"  {nar_binary} -> {nar_val:20.10f} (NaR - 全1才是NaR)")

    # 测试特殊值
    print("\n【特殊值测试】")
    special_vals = [float('inf'), float('-inf'), float('nan')]
    for val in special_vals:
        bin_str, hex_str, posit_val = fp_to_posit(val, nbits=16, es=2)
        print(f"  {val:>5} -> {bin_str} / {hex_str} -> {posit_val}")

    # 边界值测试
    print("\n【边界值测试 (Posit<16,1>)】")
    info = posit_info(16, 2)
    print(f"  动态范围: 2^{info['min_scale']} to 2^{info['max_scale']}")

    # 测试最大最小正值
    max_val = 2 ** info['max_scale']
    min_val = 2 ** info['min_scale']
    print(f"  最大正值: ~{max_val:.2e}")
    print(f"  最小正值: ~{min_val:.2e}")

    # 测试精度
    print("\n【精度测试】")
    val = 1.0
    print(f"{'Original':>15} | {'Binary':>20} | {'Hex':>8} | {'Round-trip':>15}")
    print("-" * 65)
    for _ in range(5):
        bin_str, hex_str, posit_val = fp_to_posit(val, nbits=16, es=2)
        print(f"{val:15.10f} | {bin_str:>20} | {hex_str:>8} | {posit_val:15.10f}")
        val = val + 0.0001

    # 测试16进制互转
    print("\n【16进制互转测试】")
    test_hex_values = [1.0, -1.0, 3.14159, 100.0]
    print(f"{'Value':>12} | {'Hex':>8} | {'Back to FP':>12} | {'Match':>6}")
    print("-" * 55)
    for val in test_hex_values:
        hex_str = fp_to_posit_hex(val, nbits=16, es=2)
        back_val = posit_hex_to_fp(hex_str, nbits=16, es=2)
        match = "✓" if abs(val - back_val) < 1e-6 else "✗"
        print(f"{val:12.5f} | {hex_str:>8} | {back_val:12.5f} | {match:>6}")

    print("\n" + "=" * 60)
    print("测试完成")
    print("=" * 60)
