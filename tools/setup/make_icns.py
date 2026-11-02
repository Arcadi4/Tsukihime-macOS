"""Writes the port's macOS icon (assets/icon/tsukihime.icns) from the same drawing as the .ico (tools/setup/make_icon.py).

A .icns is a 4-byte type, a 4-byte big-endian length and an image per entry. The entries macOS reads are PNG based, so the
pictures are drawn at each size by `make_icon.draw` (never enlarged from a smaller one) and stored as PNG.

Run:  python3 tools/setup/make_icns.py [--out DIR]
"""
from __future__ import annotations

import argparse
import io
import struct
from pathlib import Path

from make_icon import draw

# (OSType, pixels) — icp4/icp5 are 16 and 32 px, ic11/ic12 are 16x16@2x and 32x32@2x, ic07..ic10 are 128..1024,
# ic13/ic14 are 128x128@2x and 256x256@2x.
ENTRIES = (
    (b"icp4", 16),
    (b"icp5", 32),
    (b"ic11", 32),
    (b"ic12", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic13", 256),
    (b"ic09", 512),
    (b"ic14", 512),
    (b"ic10", 1024),
)


def write_icns(path: Path) -> None:
    images = {size: draw(size) for _, size in ENTRIES}
    body = bytearray()
    for ostype, size in ENTRIES:
        buffer = io.BytesIO()
        images[size].save(buffer, "PNG", optimize=True)
        data = buffer.getvalue()
        body += ostype + struct.pack(">I", len(data) + 8) + data
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + bytes(body))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(Path(__file__).resolve().parents[2] / "assets" / "icon"))
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    target = out / "tsukihime.icns"
    write_icns(target)
    print(f"{target} ({target.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
