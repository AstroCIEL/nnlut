# NN-LUT 参数训练工程

本工程实现单隐层 ReLU 网络逼近与 NN-LUT 参数导出，支持：

- `sqrt(-2*ln(x))`
- `mish(x) = x * tanh(log(1 + exp(x)))`

## 目录结构

```
configs/
src/
tests/
outputs/
```

## 关键说明

- 训练集由目标函数自动采样生成
- 网络结构固定为单隐层 ReLU，隐层大小 = `num_entries - 1`
- 支持断点排序与 NN→LUT 转换一致性验证
- 支持定点量化仿真与 ASIC 导出格式

## 开始训练

1. 安装依赖：

```bash
pip install numpy pyyaml matplotlib torch pytest
```

2. 使用默认配置运行：

```bash
python -m src.cli --config configs/mish_default.yaml
python -m src.cli --config configs/mish_derivative_default.yaml
python -m src.cli --config configs/sqrt_neg2_log_default.yaml
```

3. 输出目录查看：

每次运行会在 `output_dir` 下生成：
- LUT 参数文件（JSON/CSV/Header）
- 评估报告（Markdown）
- 可视化图像

## 运行推理(fp)

```bash
#Python API 使用示例
python inference_example.py

# 单值推理
python -m src.inference --lut outputs/mish_default/lut_params.json --value 1.5

# 批量推理
python -m src.inference --lut outputs/mish_default/lut_params.json --values 1.0 2.0 3.0

# 范围推理（均匀采样）
python -m src.inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 100

# 导出 CSV 文件
python -m src.inference --lut outputs/mish_default/lut_params.json --value 2.0 --output result.csv
```

## 运行推理（posit）

用于硬件部署的 Posit<16,2> 格式 LUT 推理，所有 MAC 操作在 posit 域进行。

- 将 FP 参数转换为 Posit<16,2> 格式并保存
- 支持读取 Posit 格式的参数文件
- 输入为 Posit 格式，MAC 操作在 posit 域模拟
- 同时报告 FP 计算的 ground truth 用于对比

```bash
# api示例脚本
py posit_inference_example.py

# 单值推理（自动转换参数为 posit 格式）
py -m src.posit_inference --lut outputs/mish_default/lut_params.json --value 1.5

# 批量推理
py -m src.posit_inference --lut outputs/mish_default/lut_params.json --values 1.0 2.0 3.0 4.0

# 范围推理
py -m src.posit_inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 100

# 只转换参数格式
py -m src.posit_inference --lut outputs/mish_default/lut_params.json --convert-only

# 使用已转换的参数文件
py -m src.posit_inference --lut outputs/mish_default/lut_params.json --use-posit-params --value 1.5
```

推理结果包含以下字段：
- `input_fp`: 输入 FP 值
- `input_hex`: 输入 posit hex (如 `0x4400`)
- `ground_truth`: 目标函数的 FP 输出
- `fp_lut_output`: FP LUT 的输出（用于对比）
- `posit_lut_output`: Posit LUT 的 FP 输出值
- `posit_output_hex`: Posit LUT 的 hex 输出值
- `error_fp`: FP LUT 误差
- `error_posit`: Posit LUT 误差

转换后的参数文件包含 posit 格式的参数：

```json
{
  "function_name": "mish",
  "domain_min": -8.0,
  "domain_max": 8.0,
  "num_entries": 32,
  "breakpoints": [...],
  "slopes": [...],
  "intercepts": [...],
  "posit_nbits": 16,
  "posit_es": 2,
  "posit_params": {
    "nbits": 16,
    "es": 2,
    "breakpoints_hex": ["0xa900", "0xa400", ...],
    "slopes_hex": ["0xeaf9", "0xe923", ...],
    "intercepts_hex": ["0xde16", "0xddff", ...]
  }
}
```