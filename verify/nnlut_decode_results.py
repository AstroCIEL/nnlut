#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 nnlut_mish_tb 的仿真日志里 Posit(hex) 转成浮点，便于看 mismatch 程度。

输入：
  - 默认读取 ../sim/simulation_nnlut_mish_tb.log
输出：
  - 表格：x_hex/x_fp(来自日志描述)、hw_hex/hw_fp、gold_hex/gold_fp、abs_err

依赖：
  - 复用 nnlut 工程里的 posit.py：nnlut/src/utils/posit.py
"""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from typing import Optional, List


def _import_posit_hex_to_fp():
    """
    复用工程里的 posit.py。
    这里不要求安装为包，直接用相对路径加载。
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(here, ".."))
    posit_py = os.path.join(repo_root, "nnlut", "src", "utils", "posit.py")
    if not os.path.exists(posit_py):
        raise FileNotFoundError(f"找不到 posit.py: {posit_py}")

    import importlib.util

    spec = importlib.util.spec_from_file_location("posit_utils", posit_py)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载模块: {posit_py}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[attr-defined]
    return mod.posit_hex_to_fp


POSIT_HEX_TO_FP = _import_posit_hex_to_fp()


@dataclass
class Row:
    idx: int
    desc: str
    x_hex: str
    hw_hex: str
    gold_hex: str
    seg: Optional[int]

    def hw_fp(self) -> float:
        return float(POSIT_HEX_TO_FP(self.hw_hex, 16, 2, ones_complement=True))

    def gold_fp(self) -> float:
        return float(POSIT_HEX_TO_FP(self.gold_hex, 16, 2, ones_complement=True))

    def x_fp(self) -> float:
        # desc 形如 "x=-6.86 (neg_sat)"，尽量解析前面的数
        m = re.search(r"x\s*=\s*([-+]?\d+(?:\.\d+)?)", self.desc)
        if not m:
            return float("nan")
        return float(m.group(1))


LINE_RE = re.compile(
    r"^\s*(?P<idx>\d+)\s+"
    r"(?P<desc>.+?)\s+"
    r"(?P<xhex>0x[0-9a-fA-F]{1,4})\s+"
    r"(?P<hw>0x[0-9a-fA-F]{1,4})\s*\(seg(?P<seg>\d+)\)\s+"
    r"(?P<gold>0x[0-9a-fA-F]{1,4})\s+"
    r"(?P<match>MATCH|MISMATCH)\b"
)


def parse_rows(text: str) -> List[Row]:
    rows: List[Row] = []
    for line in text.splitlines():
        m = LINE_RE.match(line)
        if not m:
            continue
        rows.append(
            Row(
                idx=int(m.group("idx")),
                desc=m.group("desc").strip(),
                x_hex=m.group("xhex").lower(),
                hw_hex=m.group("hw").lower(),
                gold_hex=m.group("gold").lower(),
                seg=int(m.group("seg")),
            )
        )
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--log",
        default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sim", "simulation_nnlut_mish_tb.log")),
        help="VCS 仿真日志路径",
    )
    ap.add_argument("--csv", default="", help="可选：输出 CSV 文件路径")
    args = ap.parse_args()

    with open(args.log, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()

    rows = parse_rows(text)
    if not rows:
        raise SystemExit(f"没在日志里匹配到结果行。log={args.log}")

    # 打印表格
    header = (
        f"{'idx':>3}  {'seg':>3}  {'x_hex':>6}  {'x_fp':>10}  "
        f"{'hw_hex':>6}  {'hw_fp':>12}  {'gold_hex':>8}  {'gold_fp':>12}  {'abs_err':>12}"
    )
    print(header)
    print("-" * len(header))

    csv_lines = ["idx,seg,x_hex,x_fp,hw_hex,hw_fp,gold_hex,gold_fp,abs_err"]
    for r in rows:
        xfp = r.x_fp()
        hwfp = r.hw_fp()
        gfp = r.gold_fp()
        ae = abs(hwfp - gfp)
        print(
            f"{r.idx:>3}  {r.seg:>3}  {r.x_hex:>6}  {xfp:>10.6f}  "
            f"{r.hw_hex:>6}  {hwfp:>12.8f}  {r.gold_hex:>8}  {gfp:>12.8f}  {ae:>12.8f}"
        )
        csv_lines.append(
            f"{r.idx},{r.seg},{r.x_hex},{xfp},{r.hw_hex},{hwfp},{r.gold_hex},{gfp},{ae}"
        )

    if args.csv:
        with open(args.csv, "w", encoding="utf-8") as f:
            f.write("\n".join(csv_lines) + "\n")
        print(f"\n已写出 CSV: {args.csv}")


if __name__ == "__main__":
    main()

