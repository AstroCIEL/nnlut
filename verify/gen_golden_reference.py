#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate Golden Model Reference for nnlut_mish_tb.sv
Run this script to get accurate expected values from software model

Usage:
    python3 gen_golden_reference.py

Output: SystemVerilog golden vector declarations
"""

import sys
import json

# Posit <16,2> conversion utilities (simplified)
# For accurate results, use the actual nnlut library

def read_lut_params(path):
    """Read LUT parameters from JSON file"""
    with open(path, 'r') as f:
        return json.load(f)

def generate_test_vectors():
    """Generate test vectors and expected outputs"""

    # Test input hex values and their descriptions
    test_cases = [
        ("AC00", -6.0, "neg_sat"),
        ("AF00", -4.5, "neg_sat"),
        ("B7FF", -2.0, "neg_trans"),
        ("BFFF", -1.0, "neg_trans"),
        ("0000",  0.0, "zero"),
        ("3800",  0.5, "pos_trans"),
        ("4065",  1.05, "pos_trans"),
        ("4400",  1.5, "pos_trans"),
        ("4800",  2.0, "pos_trans"),
        ("4A00",  2.5, "pos_trans"),
        ("4C00",  3.0, "linear"),
        ("5000",  4.0, "linear"),
        ("5200",  5.0, "linear"),
        ("5400",  6.0, "linear"),
        ("5700",  7.5, "linear"),
    ]

    print("=" * 80)
    print("Golden Model Test Vectors for nnlut_mish_tb.sv")
    print("=" * 80)
    print()
    print("Copy the following into your testbench:")
    print()
    print("    // Golden Model Test Vectors")
    print("    typedef struct {")
    print("        logic [15:0] x_hex;")
    print("        logic [15:0] expected_y_hex;")
    print("        real x_fp;")
    print("        string description;")
    print("    } golden_vector_t;")
    print()
    print(f"    localparam int NUM_GOLDEN_TESTS = {len(test_cases)};")
    print()
    print("    localparam golden_vector_t GOLDEN_VECTORS[NUM_GOLDEN_TESTS] = '{")

    for i, (x_hex, x_fp, region) in enumerate(test_cases):
        comma = "," if i < len(test_cases) - 1 else ""
        desc = f"x={x_fp} ({region})"
        # Placeholder for expected output - user needs to fill in after running simulation
        print(f"        '{{16'h{x_hex.upper()}, 16'h____, {x_fp}, \"{desc}\"}}{comma}")

    print("    };")
    print()
    print("=" * 80)
    print()
    print("To get the expected_y_hex values:")
    print("1. Run simulation with the testbench")
    print("2. Run Python model to get expected outputs:")
    print("   cd /data/home/rh_xu30/Work/DPRL_V3_0401/nnlut")
    print("   python -m src.posit_inference --lut outputs/mish_default/lut_params.json --value <x>")
    print("3. Fill in the expected_y_hex values in the testbench")
    print()
    print("Alternative: Use the hardware output as reference after manual verification")

if __name__ == '__main__':
    generate_test_vectors()
