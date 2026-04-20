## `nnlut.sv` 模块说明

### 功能概述
`nnlut` 实现 **NNLUT（Neural Network Lookup Table）分段线性推理**。模块内部存储一组断点 `breakpoints` 以及每段对应的 `slope/intercept`，对输入 `x` 做分段线性计算：

\[
y = slope[seg] \times x + intercept[seg]
\]

其中所有数据均为 **Posit\<16,2\>（默认参数）** 的位表示，乘加运算通过 `rtl/vpu/posit_mac.sv` 完成。

### 参数与存储组织
- **段数**：`N_ENTRIES = 32`
- **断点数**：`N_BREAKPOINTS = 31`（对应 32 段的分界）
- **寄存器数组**：
  - `breakpoints[0..30]`：31 个断点（升序）
  - `slopes[0..31]`：32 个斜率
  - `intercepts[0..31]`：32 个截距

### 配置接口（cfg）
通过 `cfg_*` 端口对内部参数寄存器进行读写。

#### 地址映射（`ADDR_WIDTH=8` 时）
`nnlut.sv` 中固定使用如下地址窗口（写入时按数组下标寻址）：
- **breakpoints**：`0x00` ~ `0x1E`（共 31 个）
- **slopes**：`0x20` ~ `0x3F`（共 32 个）
- **intercepts**：`0x40` ~ `0x5F`（共 32 个）

读操作为组合逻辑：`cfg_en_i=1 && cfg_wr_en_i=0` 时，`cfg_data_o` 输出对应寄存器值。

### 推理接口（infer）
- **输入**：
  - `infer_start_i`：推理启动脉冲（建议 1 个周期）
  - `infer_x_i`：输入 `x`（Posit 位模式）
- **输出**：
  - `infer_done_o`：推理完成（与 `posit_mac` 的 `calc_done_o` 对齐）
  - `infer_y_o`：推理输出 `y`（Posit 位模式）

### 分段查找规则（与 Python `searchsorted(side="right")` 对齐）
模块在 Stage1 计算段号 `seg_idx`，目标等价于 Python：

```python
seg = np.searchsorted(breakpoints, x, side="right")
```

实现方式是从小到大扫描所有断点，统计满足 `x >= breakpoints[i]` 的个数：
- 初值 `seg=0`
- 若 `x >= bp[0]`，则 `seg=1`
- ...
- 若 `x >= bp[30]`，则 `seg=31`

也即 **当 `x` 恰好等于断点时（side="right"）进入右侧区间**。

#### 关于比较方式的约束
当前实现采用 **符号扩展后按有符号整数比较**：
- `x_signed = {x[15], x}`（17-bit signed）
- `bp_signed = {bp[15], bp}`（17-bit signed）
- 比较条件：`x_signed >= bp_signed`

这并不是通用的“按 posit 数值大小比较”的完整实现，而是基于本工程参数集（断点经训练/导出后保持单调）所采用的硬件近似/工程化做法。若未来需要支持更一般的 posit 比较，应替换为真正的 posit 解码比较（例如基于 `posit_decoder` 的有序比较逻辑）。

### 流水线与延迟
`nnlut` 内部由 3 个前级流水 + `posit_mac`（3 拍）构成：
- **Stage0**：捕获 `infer_x_i`，产生 `infer_valid_s0`
- **Stage1**：断点扫描得到 `segment_idx_comb`，并寄存为 `segment_idx_s1`
- **Stage2**：用 `segment_idx_s1` 选出 `selected_slope/intercept`，并将 `infer_valid_s2` 作为 `posit_mac.calc_start_i`
- **MAC**：`posit_mac` 内部 3-cycle latency，输出 `mac_result` 与 `mac_done`

因此从 `infer_start_i` 到 `infer_done_o` 的典型延迟为：
- **约 6 个时钟周期**（3 个 Stage + 3-cycle MAC）

> 备注：验证环境中常在 `wait(infer_done_o); @(posedge clk);` 后采样 `infer_y_o`，以避免边界时序/显示采样造成的“慢一拍”观感差异。

### 调试信号
`nnlut.sv` 顶层内部暴露了（用于 tb 跨层引用）：
- `segment_idx`：Stage1 寄存后的段号（便于 tb 打印对比）

此外，文件中目前还保留了内部调试 wire（不影响功能）：
- `debug_slope_16/debug_intercept_16`
- `debug_slope_0/debug_intercept_0`

如需更干净的综合网表，可在确认无需调试后移除这些信号。

### 与验证（verify）目录的关系

典型验证方式是：
- 从 `nnlut/outputs/<target>_default/lut_params.json` 读取 `posit_params.*_hex`
- 在 TB 中按地址映射写入 `breakpoints/slopes/intercepts`
- 给定一组输入点与 golden 输出（由 `PositLUTInference` 生成）逐点比对

验证流程可参考：`verify/NNLUT_VERIFICATION_GUIDE.md`。

使用已有的tb：

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