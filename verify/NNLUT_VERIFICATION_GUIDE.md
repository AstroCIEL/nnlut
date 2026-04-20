# NN LUT Mish 验证指南

## 概述

本文档说明如何验证 `nnlut` 硬件模块的计算结果与软件 Golden Model 的一致性。

## 文件说明

- `nnlut_mish_tb.sv` - 主测试平台（带 Golden Model 比对功能）
- `generate_golden.py` - Golden Model 期望值生成脚本（需要 Python 3）
- `gen_golden_reference.py` - 测试向量模板生成脚本

## 验证流程

### 简易版（使用目前已有的tb和测试点）

```bash
cd /data/home/rh_xu30/Work/DPRL_V3_0401/sim
make all MODULE_NAME=nnlut_sqrt_neg2_log
make all MODULE_NAME=nnlut_mish
make all MODULE_NAME=nnlut_mish_derivative
```

观察终端输出即可。为了更直观的对比与期望值的浮点数域差距，运行

```bash
cd /data/home/rh_xu30/Work/DPRL_V3_0401/verify
python nnlut_decode_results.py --log /data/home/rh_xu30/Work/DPRL_V3_0401/sim/simulation_nnlut_sqrt_neg2_log_tb.log
```

此处log文件请使用最新生成的log文件用于提取。

### 步骤 1: 运行硬件仿真

```bash
cd /data/home/rh_xu30/Work/DPRL_V3_0401/sim
make all  # 或对应的仿真命令
```

查看仿真输出，记录每个测试点的硬件输出值。

### 步骤 2: 获取软件 Golden Model 期望值

在支持 Python 3 的环境中运行：

```bash
cd /data/home/rh_xu30/Work/DPRL_V3_0401/nnlut

# 单个测试点
python3 -m src.posit_inference --lut outputs/mish_default/lut_params.json --value -6.0
python3 -m src.posit_inference --lut outputs/mish_default/lut_params.json --value -4.5
python3 -m src.posit_inference --lut outputs/mish_default/lut_params.json --value 0.0

# 批量测试
python3 -m src.posit_inference --lut outputs/mish_default/lut_params.json --range -8 8 --samples 15
```

### 步骤 3: 更新 testbench

将软件模型输出的 `posit_output_hex` 值填入 `nnlut_mish_tb.sv` 中的 `GOLDEN_VECTORS`：

```systemverilog
localparam golden_vector_t GOLDEN_VECTORS[15] = '{
    '{16'hAC00, 16'hXXXX, -6.0, "x=-6.0 (neg_sat, seg2)"},  // 填入实际的 16'hXXXX
    ...
};
```

### 步骤 4: 重新仿真验证

再次运行仿真，检查是否所有测试点都显示 "MATCH"。

## Testbench 说明

### Golden Model 比对机制

```systemverilog
// 硬件计算结果
hw_result = infer_y_o;

// 与 Golden Model 期望值比对
if (hw_result === test.expected_y_hex) begin
    status = "MATCH";
    pass++;
end else begin
    status = "MISMATCH";
    mismatch++;
end
```

### 测试覆盖

| 区域 | 测试点 | 说明 |
|------|--------|------|
| 负饱和区 | x=-6.0, -4.5 | Mish 函数负值饱和区域 |
| 负过渡区 | x=-2.0, -1.0 | 从负值向零过渡 |
| 零点附近 | x=0.0 | Mish(0) = 0 |
| 正过渡区 | x=0.5~2.5 | 正值增长区域 |
| 正线性区 | x=3.0~7.5 | Mish(x) ≈ x 的线性区域 |

## 参数来源

所有参数来自训练结果 `outputs/mish_default/lut_params.json`：

- **breakpoints**: 31 个断点，定义 32 个区间的边界
- **slopes**: 32 个斜率，每个区间一个
- **intercepts**: 32 个截距，每个区间一个

计算公式（posit 域）：
```
y = x * slope + intercept
```

## 地址映射

```
地址 0x00-0x1E: breakpoints (31 entries)
地址 0x20-0x3F: slopes (32 entries)
地址 0x40-0x5F: intercepts (32 entries)
```

## 调试信息

如果仿真显示 MISMATCH，testbench 会输出：

```
[Mismatch Detail] HW=0xXXXX vs Golden=0xYYYY (diff=Z)
```

这表明硬件计算结果与软件期望值的差异。

## 预期误差

由于硬件使用定点数运算，可能存在微小的精度差异：
- Posit <16,2> 精度限制导致的舍入误差
- MAC 运算中的对齐和舍入

如果差异很小（1-2 LSB），通常是可以接受的。

## 自动化验证（可选）

可以编写脚本自动对比：

```python
# pseudo code
hw_outputs = parse_simulation_log("simulation.log")
sw_outputs = run_python_model(test_points)

for hw, sw in zip(hw_outputs, sw_outputs):
    if hw != sw:
        print(f"Mismatch: HW={hw}, SW={sw}")
```
