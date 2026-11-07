"""从 WHATWG 官方索引生成离线解码表；输入目录应包含两份原始索引文件。"""

import argparse
import base64
import hashlib
from pathlib import Path
import struct
import textwrap


def read_index(path):
    # 数据与算法分离，不在解码器中维护针对单本书或单个字符的补丁。
    return [
        (int(fields[0]), int(fields[1], 16))
        for line in path.read_text(encoding="utf-8").splitlines()
        if (fields := line.split()) and not line.startswith("#")
    ]


def generate(input_dir, output):
    two_byte = input_dir / "index-gb18030.txt"
    ranges = input_dir / "index-gb18030-ranges.txt"
    date = next(
        line.removeprefix("# Date:").strip()
        for line in two_byte.read_text(encoding="utf-8").splitlines()
        if line.startswith("# Date:")
    )
    rows = read_index(two_byte)
    if [pointer for pointer, _ in rows] != list(range(126 * 190)):
        raise ValueError("双字节索引不完整")
    packed = b"".join(struct.pack("<H", point) for _, point in rows)
    lines = [
        "// GB18030 官方映射的生成产物，请使用 tool/generate_gb18030_data.py 更新。",
        f"// 来源：https://encoding.spec.whatwg.org/（索引日期 {date}）。",
        "// Copyright WHATWG (Apple, Google, Mozilla, Microsoft).",
        "// 源码使用 BSD-3-Clause，完整许可证见 third_party/whatwg_encoding_LICENSE。",
        f"// 双字节索引 SHA-256: {hashlib.sha256(two_byte.read_bytes()).hexdigest()}",
        f"// 四字节索引 SHA-256: {hashlib.sha256(ranges.read_bytes()).hexdigest()}",
        "part of 'gb18030_decoder.dart';",
        "",
        "const _gb18030TwoByteBase64 =",
    ]
    chunks = textwrap.wrap(base64.b64encode(packed).decode("ascii"), 100)
    lines += [f"    '{chunk}'" for chunk in chunks]
    lines[-1] += ";"
    lines += ["", "const _gb18030Ranges = <(int, int)>["]
    lines += [f"  ({pointer}, 0x{point:X})," for pointer, point in read_index(ranges)]
    lines += ["];", ""]
    output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_dir", type=Path)
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).resolve().parents[1] / "lib/core/encoding/gb18030_data.dart",
    )
    args = parser.parse_args()
    generate(args.input_dir, args.output)
