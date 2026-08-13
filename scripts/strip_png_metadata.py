#!/usr/bin/env python3
"""Remove non-rendering metadata chunks from a PNG without changing pixels."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
REMOVED_CHUNKS = {b"tEXt", b"zTXt", b"iTXt", b"eXIf", b"tIME"}


def strip_metadata(path: Path) -> None:
    payload = path.read_bytes()
    if not payload.startswith(PNG_SIGNATURE):
        raise ValueError(f"not a PNG: {path}")

    output = bytearray(PNG_SIGNATURE)
    offset = len(PNG_SIGNATURE)
    saw_end = False
    while offset < len(payload):
        if offset + 12 > len(payload):
            raise ValueError(f"truncated PNG chunk in {path}")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_end = offset + 12 + length
        if chunk_end > len(payload):
            raise ValueError(f"invalid PNG chunk length in {path}")
        chunk_type = payload[offset + 4 : offset + 8]
        if chunk_type not in REMOVED_CHUNKS:
            output.extend(payload[offset:chunk_end])
        offset = chunk_end
        if chunk_type == b"IEND":
            saw_end = True
            break

    if not saw_end or offset != len(payload):
        raise ValueError(f"invalid PNG end marker in {path}")
    path.write_bytes(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("png", type=Path)
    args = parser.parse_args()
    strip_metadata(args.png)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
